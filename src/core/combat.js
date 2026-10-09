import { DATA } from '../content.js';

const SLOTS = DATA.slots;
const clamp = (value, low, high) => Math.min(high, Math.max(low, value));

export class Rng {
  constructor(seed) {
    this.state = (Number(seed) >>> 0) || 0x6d2b79f5;
  }

  next() {
    let x = this.state >>> 0;
    x = (x ^ (x << 13)) >>> 0;
    x = (x ^ (x >>> 17)) >>> 0;
    x = (x ^ (x << 5)) >>> 0;
    this.state = x >>> 0;
    return this.state;
  }

  bp(threshold) {
    return this.next() % 10000 < threshold;
  }
}

export function makeStats(loadout) {
  if (!Array.isArray(loadout) || loadout.length !== SLOTS.length) {
    throw new TypeError('exactly six item ids required');
  }
  const stats = { ...DATA.base_stats };
  for (let i = 0; i < SLOTS.length; i += 1) {
    const slot = SLOTS[i];
    const itemId = loadout[i];
    const item = DATA.items[itemId];
    if (!item || item.slot !== slot) throw new RangeError(`invalid item for ${slot}: ${itemId}`);
    for (const [key, value] of Object.entries(item.stats)) {
      stats[key] = (stats[key] ?? 0) + value;
    }
  }
  stats.crit_bp = Math.min(stats.crit_bp, 7500);
  stats.block_bp = Math.min(stats.block_bp, 7500);
  stats.attack_interval_ms = Math.max(400, Math.floor(10000000 / (10000 + stats.haste_bp)));
  return stats;
}

export function fight(loadout, bossId, seed = 1, options = {}) {
  const { trace = false, scale_bp = 10000 } = options;
  const stats = makeStats(loadout);
  const boss = DATA.bosses[bossId];
  if (!boss) throw new RangeError(`unknown boss: ${bossId}`);
  const rng = new Rng(seed);
  let hp = stats.hp;
  let bossHp = Math.floor(boss.hp * scale_bp / 10000);
  let time = 0;
  let nextPlayer = stats.attack_interval_ms;
  let nextDot = 1000;
  let bossCycle = 0;
  let bossHit = 0;
  let nextBoss = boss.hit_offsets_ms[0];
  let poisonStacks = 0;
  let poisonUntil = -1;
  const totals = { normal: 0, poison: 0, counter: 0, incoming: 0, attacks: 0, crits: 0, blocks: 0, boss_hits: 0, poison_ticks: 0 };
  const logs = [];
  const log = (kind, damage, extra = {}) => {
    if (trace) logs.push({ t: time, kind, damage, player_hp: Math.max(0, hp), boss_hp: Math.max(0, bossHp), ...extra });
  };
  const limit = DATA.combat.time_limit_ms;

  while (hp > 0 && bossHp > 0) {
    time = Math.min(nextDot, nextPlayer, nextBoss);
    if (time > limit) { time = limit; break; }
    // Simultaneous events resolve in reference order: poison, player, then boss.
    if (time === nextDot) {
      nextDot += 1000;
      if (poisonStacks && time < poisonUntil) {
        const damage = poisonStacks * stats.poison_damage;
        const actual = Math.min(damage, bossHp);
        bossHp -= damage;
        totals.poison += actual;
        totals.poison_ticks += 1;
        log('poison', actual, { stacks: poisonStacks });
        if (bossHp <= 0) break;
      } else if (time >= poisonUntil) poisonStacks = 0;
    }
    if (time === nextPlayer) {
      nextPlayer += stats.attack_interval_ms;
      totals.attacks += 1;
      const critical = rng.bp(stats.crit_bp);
      totals.crits += Number(critical);
      const raw = Math.floor(stats.attack * (critical ? stats.crit_multiplier_bp : 10000) / 10000);
      const damage = Math.max(1, Math.floor(raw * 100 / (100 + boss.armor)));
      const actual = Math.min(bossHp, damage);
      bossHp -= damage;
      totals.normal += actual;
      if (stats.poison_damage > 0) {
        if (time >= poisonUntil) poisonStacks = 0;
        poisonStacks = Math.min(DATA.combat.poison_stack_cap, poisonStacks + 1);
        poisonUntil = time + stats.poison_duration_ms;
      }
      log('normal', actual, { critical });
      if (bossHp <= 0) break;
    }
    if (time === nextBoss) {
      totals.boss_hits += 1;
      const rageElapsed = Math.max(0, time - boss.enrage_start_ms);
      const multiplier = 10000 + Math.floor(rageElapsed * boss.enrage_bp_per_second / 1000);
      const raw = Math.floor(Math.floor(boss.hit_damage * scale_bp / 10000) * multiplier / 10000);
      let damage = Math.max(1, Math.floor(raw * 100 / (100 + stats.armor)));
      const blocked = rng.bp(stats.block_bp);
      totals.blocks += Number(blocked);
      if (blocked) damage = Math.max(1, Math.floor(damage * (10000 - DATA.combat.block_reduction_bp) / 10000));
      const actual = Math.min(damage, hp);
      hp -= damage;
      totals.incoming += actual;
      log('boss_hit', actual, { blocked });
      if (hp <= 0) break;
      if (blocked && stats.counter_bp > 0) {
        const rawCounter = Math.floor(stats.armor * stats.counter_bp / 10000);
        const counterDamage = Math.max(1, Math.floor(rawCounter * 100 / (100 + boss.armor)));
        const counterActual = Math.min(counterDamage, bossHp);
        bossHp -= counterDamage;
        totals.counter += counterActual;
        log('counter', counterActual);
        if (bossHp <= 0) break;
      }
      bossHit += 1;
      if (bossHit >= boss.hit_offsets_ms.length) { bossCycle += 1; bossHit = 0; }
      nextBoss = bossCycle * boss.cycle_ms + boss.hit_offsets_ms[bossHit];
    }
  }

  const result = {
    win: bossHp <= 0 && hp > 0,
    time_ms: time,
    hp_remaining: Math.max(0, hp),
    boss_hp_remaining: Math.max(0, bossHp),
    stats,
    totals,
  };
  if (trace) result.trace = logs;
  return result;
}
