import test from 'node:test';
import assert from 'node:assert/strict';
import { DATA } from '../src/content.js';
import { Rng, fight } from '../src/core/combat.js';

const LOADOUT = ['weapon_p', 'armor_p', 'gloves_p', 'boots_p', 'charm_p', 'ring_p'];

// Synthetic boundary fixtures are temporary mutations of the imported content object.
// Restore all keys in finally so these cases cannot alter any other test in this worker.
function withSyntheticData({ base = {}, boss = {}, poisonDamage = 1 }, run) {
  const snapshot = structuredClone(DATA);
  try {
    for (const templateId of LOADOUT) DATA.items[templateId].stats = {};
    DATA.items.weapon_p.stats.poison_damage = poisonDamage;
    DATA.base_stats = {
      ...DATA.base_stats,
      hp: 900, attack: 1, armor: 0, crit_bp: 0, crit_multiplier_bp: 10000,
      haste_bp: 0, block_bp: 0, counter_bp: 0, poison_damage: 0,
      poison_duration_ms: 6000,
      ...base,
    };
    DATA.items.boots_p.stats.haste_bp = 0;
    DATA.bosses.gatekeeper = {
      ...DATA.bosses.gatekeeper,
      hp: 10000, armor: 0, cycle_ms: 4000, hit_offsets_ms: [1000], hit_damage: 1,
      enrage_start_ms: 1000000, enrage_bp_per_second: 0,
      ...boss,
    };
    run();
  } finally {
    for (const key of Object.keys(DATA)) delete DATA[key];
    Object.assign(DATA, snapshot);
  }
}

function kindsAt(trace, t) {
  return trace.filter((event) => event.t === t).map((event) => event.kind);
}

function seedForSecondRoll(threshold) {
  for (let seed = 1; seed < 100000; seed += 1) {
    const rng = new Rng(seed);
    rng.next(); // Player's critical roll occurs before a simultaneous enemy hit.
    if (rng.next() % 10000 < threshold) return seed;
  }
  throw new Error('could not find deterministic seed for synthetic guard fixture');
}

test('poison tick, player attack, and boss hit resolve in reference order at one timestamp', () => {
  withSyntheticData({
    base: { poison_duration_ms: 2000 },
    boss: { hp: 100000, cycle_ms: 4000, hit_offsets_ms: [1000, 2000, 3000] },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', 7, { trace: true });
    assert.deepEqual(kindsAt(result.trace, 2000), ['poison', 'normal', 'boss_hit']);
    assert.equal(result.trace.find((event) => event.t === 2000 && event.kind === 'poison').stacks, 1);
  });
});

test('poison expiry at the exact tick/attack/boss timestamp excludes that tick', () => {
  withSyntheticData({
    base: { poison_duration_ms: 1000 },
    boss: { hp: 100000, cycle_ms: 4000, hit_offsets_ms: [1000, 2000] },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', 7, { trace: true });
    assert.deepEqual(kindsAt(result.trace, 1000), ['normal', 'boss_hit']);
    assert.deepEqual(kindsAt(result.trace, 2000), ['normal', 'boss_hit']);
    assert.equal(result.trace.some((event) => event.t === 2000 && event.kind === 'poison'), false);
  });
});

test('a poison tick that kills the boss suppresses same-time player and boss events', () => {
  withSyntheticData({
    poisonDamage: 1,
    base: { attack: 1, poison_damage: 0, poison_duration_ms: 5000 },
    boss: { hp: 2, cycle_ms: 4000, hit_offsets_ms: [1000, 2000], hit_damage: 1 },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', 7, { trace: true });
    assert.equal(result.win, true);
    assert.deepEqual(kindsAt(result.trace, 1000), ['normal', 'boss_hit']);
    assert.deepEqual(kindsAt(result.trace, 2000), ['poison']);
    assert.equal(result.totals.attacks, 1);
    assert.equal(result.totals.boss_hits, 1);
  });
});

test('a player attack that kills the boss suppresses a same-time enemy hit', () => {
  withSyntheticData({
    poisonDamage: 0,
    base: { attack: 1, poison_damage: 0 },
    boss: { hp: 1, cycle_ms: 4000, hit_offsets_ms: [1000], hit_damage: 10 },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', 7, { trace: true });
    assert.equal(result.win, true);
    assert.deepEqual(kindsAt(result.trace, 1000), ['normal']);
    assert.equal(result.totals.boss_hits, 0);
  });
});

test('the first event beyond 90 seconds becomes a time-limit loss with remaining HP', () => {
  withSyntheticData({
    poisonDamage: 0,
    base: { haste_bp: -9990, attack: 1, poison_damage: 0 },
    boss: { hp: 100000, cycle_ms: 100000, hit_offsets_ms: [95000], hit_damage: 1 },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', 7, { trace: true });
    assert.equal(result.time_ms, DATA.combat.time_limit_ms);
    assert.equal(result.win, false);
    assert.ok(result.hp_remaining > 0);
    assert.ok(result.boss_hp_remaining > 0);
    assert.equal(result.totals.attacks, 0);
    assert.equal(result.totals.boss_hits, 0);
  });
});

test('a lethal guarded enemy hit does not trigger a counterattack', () => {
  const seed = seedForSecondRoll(7500);
  withSyntheticData({
    poisonDamage: 0,
    base: { hp: 1, attack: 1, crit_bp: 0, block_bp: 7500, counter_bp: 10000, armor: 0, poison_damage: 0 },
    boss: { hp: 100000, cycle_ms: 4000, hit_offsets_ms: [1000], hit_damage: 100 },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', seed, { trace: true });
    const hit = result.trace.find((event) => event.kind === 'boss_hit');
    assert.equal(hit.blocked, true);
    assert.equal(result.hp_remaining, 0);
    assert.equal(result.totals.counter, 0);
    assert.equal(result.trace.some((event) => event.kind === 'counter'), false);
  });
});

test('counter damage neither crits nor applies poison stacks recursively', () => {
  const seed = seedForSecondRoll(7500);
  withSyntheticData({
    base: { hp: 1000, attack: 1, armor: 100, crit_bp: 7500, block_bp: 7500, counter_bp: 10000, poison_duration_ms: 5000 },
    boss: { hp: 100000, armor: 0, cycle_ms: 5000, hit_offsets_ms: [1000], hit_damage: 10 },
  }, () => {
    const result = fight(LOADOUT, 'gatekeeper', seed, { trace: true });
    assert.deepEqual(kindsAt(result.trace, 1000), ['normal', 'boss_hit', 'counter']);
    const counter = result.trace.find((event) => event.kind === 'counter');
    assert.equal(Object.hasOwn(counter, 'critical'), false);
    assert.equal(result.trace.filter((event) => event.kind === 'counter' && event.t === 1000).length, 1);
    const firstPoison = result.trace.find((event) => event.kind === 'poison');
    assert.equal(firstPoison.stacks, 1);
  });
});
