import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { DATA } from '../src/content.js';
import { Rng, fight, makeStats } from '../src/core/combat.js';

const reference = new URL('../reference/Idle_Loot_RPG_Design_R2_20261008/validation/', import.meta.url);
const readJson = async (name) => JSON.parse(await readFile(new URL(name, reference), 'utf8'));

test('golden_fights reference results match exactly', async () => {
  const cases = await readJson('golden_fights.json');
  assert.equal(cases.length, 28);
  for (const row of cases) {
    assert.deepStrictEqual(fight(row.items, row.boss, row.seed), row.expected,
      `${row.preset} vs ${row.boss}, seed ${row.seed}`);
  }
});

test('seed zero uses the specified xorshift32 replacement and unsigned outputs', () => {
  const zero = new Rng(0);
  const fallback = new Rng(0x6d2b79f5);
  for (let i = 0; i < 16; i += 1) {
    assert.equal(zero.next(), fallback.next());
    assert.ok(zero.state >= 0 && zero.state <= 0xffffffff);
  }
});

test('rejects wrong slot and unknown boss inputs', () => {
  assert.throws(() => makeStats(Array(6).fill('weapon_c')), /invalid item for armor/);
  assert.throws(() => makeStats(['weapon_c']), /exactly six/);
  assert.throws(() => fight(DATA.presets.critical, 'missing'), /unknown boss/);
});

test('all 729 family loadouts preserve damage and incoming HP accounting', () => {
  const families = ['c', 'p', 'g'];
  const slots = DATA.slots;
  let tested = 0;
  for (let encoded = 0; encoded < 3 ** slots.length; encoded += 1) {
    let n = encoded;
    const loadout = slots.map((slot) => {
      const family = families[n % 3];
      n = Math.floor(n / 3);
      return `${slot}_${family}`;
    });
    for (const bossId of Object.keys(DATA.bosses)) {
      const result = fight(loadout, bossId, 137);
      const startingBossHp = Math.floor(DATA.bosses[bossId].hp);
      assert.equal(result.totals.normal + result.totals.poison + result.totals.counter,
        startingBossHp - result.boss_hp_remaining, `${loadout.join(',')} vs ${bossId}`);
      assert.equal(result.totals.incoming, result.stats.hp - result.hp_remaining);
      tested += 1;
    }
  }
  assert.equal(tested, 2187);
});

test('mixed poison-defense loadout reproduces the reference complete event trace', async () => {
  const example = await readJson('example_traces.json');
  const mixed = ['weapon_p', 'armor_p', 'gloves_p', 'boots_g', 'charm_p', 'ring_g'];
  assert.deepStrictEqual(fight(mixed, 'sentinels', 1001, { trace: true }), example.after);
});

test('a lower-attack mixed loadout wins sentinels across the reference seed interval', () => {
  const poison = DATA.presets.poison;
  const mixed = [...poison];
  mixed[3] = 'boots_g';
  mixed[5] = 'ring_g';
  assert.ok(makeStats(mixed).attack < makeStats(poison).attack);
  for (let seed = 1001; seed <= 1100; seed += 1) {
    assert.equal(fight(poison, 'sentinels', seed).win, false, `poison seed ${seed}`);
    assert.equal(fight(mixed, 'sentinels', seed).win, true, `mixed seed ${seed}`);
  }
});

test('trace stops immediately on player death without postmortem events', () => {
  const result = fight(DATA.presets.critical, 'sentinels', 1, { trace: true });
  assert.equal(result.win, false);
  assert.equal(result.trace.at(-1).player_hp, 0);
  assert.equal(result.trace.at(-1).kind, 'boss_hit');
});

test('zero boss scale is an immediate zero-time victory with no combat events', () => {
  const result = fight(DATA.presets.critical, 'gatekeeper', 1, { trace: true, scale_bp: 0 });
  assert.equal(result.win, true);
  assert.equal(result.time_ms, 0);
  assert.equal(result.boss_hp_remaining, 0);
  assert.deepStrictEqual(result.trace, []);
  assert.deepStrictEqual(result.totals, {
    normal: 0, poison: 0, counter: 0, incoming: 0,
    attacks: 0, crits: 0, blocks: 0, boss_hits: 0, poison_ticks: 0,
  });
});
