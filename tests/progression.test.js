import test from 'node:test';
import assert from 'node:assert/strict';
import {
  emptyState, initialState, settle, switchRoute, rebaseClock, equip, savePreset, applyPreset,
  renamePreset, setLocked, setAutoDuplicates, dismantle, previewDismantle, craft,
  reclaimOverflow, convertOverflow, recordFight, claimTrialItems, getLoadout,
} from '../src/core/progression.js';

const HOUR = 60 * 60 * 1000;

test('empty settlement fixture matches the eight-hour R2 sample and is idempotent', () => {
  let state = emptyState();
  const [next, receipt] = settle(state, 8 * HOUR, '8h');
  assert.equal(receipt.awarded_steps, 32);
  assert.equal(receipt.new_ids.length, 6);
  assert.equal(receipt.converted, 26);
  assert.equal(next.essence, 212);
  const [retry, duplicate] = settle(next, 8 * HOUR, '8h');
  assert.equal(duplicate.status, 'ALREADY_APPLIED');
  assert.deepEqual(retry, next);
  const [sameTime, zero] = settle(next, 8 * HOUR, 'another-id');
  assert.equal(zero.awarded_steps, 0);
  assert.equal(sameTime.essence, next.essence);
});

test('actual modes separate starter and balance inventory from collection history', () => {
  const experience = initialState(100, 12345);
  assert.equal(experience.equipped.length, 6);
  assert.ok(experience.equipped.every((id) => experience.inventory[id].origin === 'starter'));
  assert.deepEqual(experience.collection_history, {});
  const balance = initialState(100, 12345, 'balance');
  assert.equal(Object.keys(balance.inventory).length, 18);
  assert.equal(balance.equipped.length, 6);
});

test('route changes settle old route first and preserve its fractional time', () => {
  const s = initialState(0);
  const [one, receipt] = switchRoute(s, 10 * 60 * 1000, 'fen', 'route-change');
  assert.equal(receipt.awarded_steps, 0);
  assert.equal(one.remainders_ms.ash, 10 * 60 * 1000);
  assert.equal(one.route, 'fen');
  assert.equal(one.generation, 1);
});

test('clock rollback gives no reward and rebase requires explicit confirmation', () => {
  const s = initialState(1000);
  const [same, result] = settle(s, 500, 'rollback');
  assert.equal(result.status, 'TIME_ANOMALY');
  assert.deepEqual(same, s);
  assert.throws(() => rebaseClock(s, 500, false));
  assert.equal(rebaseClock(s, 500, true).last_ms, 500);
});

test('equipment, presets, locks and final copies are protected in whole-batch dismantle', () => {
  let s = initialState();
  const duplicateId = 'copy:weapon_c';
  s.inventory[duplicateId] = { id: duplicateId, template_id: 'weapon_c', locked: false, origin: 'loot' };
  s = savePreset(s, 'slot1', '初期構成');
  const preview = previewDismantle(s, [s.equipped[0], duplicateId]);
  assert.equal(preview.allowed, false);
  assert.equal(preview.rejected[0].reason, 'equipped_or_preset');
  assert.throws(() => dismantle(s, [duplicateId, 'starter:weapon_c']), /rejected/);
  const [changed] = [setLocked(s, duplicateId, true)];
  assert.equal(previewDismantle(changed, [duplicateId]).rejected[0].reason, 'locked');
  const altered = equip(s, 'starter:weapon_c');
  assert.deepEqual(getLoadout(altered), getLoadout(s));
  const renamed = renamePreset(altered, 'slot1', '新名称');
  assert.equal(renamed.preset_names.slot1, '新名称');
  assert.deepEqual(applyPreset(renamed, 'slot1').equipped, s.equipped);
});

test('craft charges only when valid, and overflow operations preserve the last copy', () => {
  let s = initialState();
  s.essence = 120;
  s = craft(s, 'weapon_p');
  const crafted = Object.values(s.inventory).find((item) => item.template_id === 'weapon_p');
  assert.equal(crafted.origin, 'craft');
  s.overflow.armor_p = 1;
  assert.throws(() => convertOverflow(s, 'armor_p', 1), /final/);
  s.overflow.weapon_p = 3;
  const converted = convertOverflow(s, 'weapon_p', 2);
  assert.equal(converted.essence, s.essence + 4);
  const reclaimed = reclaimOverflow(converted, 'weapon_p', 1);
  assert.equal(Object.values(reclaimed.inventory).filter((item) => item.template_id === 'weapon_p').length, 2);
});

test('first gatekeeper victory unlocks twelve explicitly marked trial items once', () => {
  const s = initialState();
  const won = recordFight(s, 'gatekeeper', { win: true, time_ms: 1234 }, 44);
  assert.equal(won.trial_unlocked, true);
  assert.equal(won.trial_pending.length, 0);
  const trials = Object.values(won.inventory).filter((item) => item.origin === 'trial');
  assert.equal(trials.length, 12);
  assert.equal(Object.keys(won.collection_history).length, 0);
  const repeated = recordFight(won, 'gatekeeper', { win: true, time_ms: 1000 }, 45);
  assert.equal(Object.values(repeated.inventory).filter((item) => item.origin === 'trial').length, 12);
  assert.equal(repeated.boss_history.gatekeeper.wins, 2);
});

test('automation switch is immutable', () => {
  const s = initialState();
  const changed = setAutoDuplicates(s, false);
  assert.equal(s.auto_duplicates, true);
  assert.equal(changed.auto_duplicates, false);
});

test('15-minute boundary accrues only complete steps and keeps the remainder', () => {
  const s = emptyState(0, 12345);
  const [before, pre] = settle(s, 15 * 60 * 1000 - 1, 'pre-step');
  assert.equal(pre.awarded_steps, 0);
  assert.equal(before.remainders_ms.ash, 15 * 60 * 1000 - 1);
  const [at, exact] = settle(before, 15 * 60 * 1000, 'exact-step');
  assert.equal(exact.awarded_steps, 1);
  assert.equal(at.remainders_ms.ash, 0);
  assert.deepEqual(s, emptyState(0, 12345));
});

test('24-hour cap awards 96 steps; 48-hour elapsed time does not allow catch-up past the checkpoint', () => {
  const s = emptyState();
  const [cap, receipt] = settle(s, 24 * HOUR, 'cap24');
  assert.equal(receipt.credited_ms, 24 * HOUR);
  assert.equal(receipt.awarded_steps, 96);
  const [long, longReceipt] = settle(s, 48 * HOUR, 'cap48');
  assert.equal(longReceipt.credited_ms, 24 * HOUR);
  assert.equal(longReceipt.capped_ms, 24 * HOUR);
  assert.equal(longReceipt.awarded_steps, 96);
  const [again, againReceipt] = settle(long, 48 * HOUR, 'after-cap');
  assert.equal(againReceipt.awarded_steps, 0);
  assert.equal(again.essence, long.essence);
  assert.equal(cap.draws.ash, long.draws.ash);
});

test('split settlements preserve the same drops and essence as a single settlement', () => {
  const start = emptyState(0, 7201);
  const [whole] = settle(start, 8 * HOUR, 'whole');
  const [half] = settle(start, 4 * HOUR, 'half-1');
  const [split] = settle(half, 8 * HOUR, 'half-2');
  assert.deepEqual(split.inventory, whole.inventory);
  assert.deepEqual(split.overflow, whole.overflow);
  assert.deepEqual(split.draws, whole.draws);
  assert.deepEqual(split.remainders_ms, whole.remainders_ms);
  assert.equal(split.essence, whole.essence);
});

test('route-local remainder stays with its route through repeated switches', () => {
  let s = initialState(0);
  [s] = switchRoute(s, 10 * 60 * 1000, 'fen', 'to-fen');
  [s] = switchRoute(s, 15 * 60 * 1000, 'ash', 'to-ash');
  assert.equal(s.remainders_ms.ash, 10 * 60 * 1000);
  assert.equal(s.remainders_ms.fen, 5 * 60 * 1000);
  [s] = switchRoute(s, 20 * 60 * 1000, 'ruins', 'to-ruins');
  assert.equal(s.draws.ash, 1);
  assert.equal(s.remainders_ms.ash, 0);
  assert.equal(s.remainders_ms.fen, 5 * 60 * 1000);
});

test('explicit clock rebase awards nothing and subsequent time starts at the new checkpoint', () => {
  const start = emptyState(10 * HOUR);
  const rebased = rebaseClock(start, 2 * HOUR, true);
  assert.equal(rebased.last_ms, 2 * HOUR);
  assert.equal(rebased.essence, 0);
  assert.equal(rebased.last_receipt.status, 'CLOCK_REBASED');
  const [after, receipt] = settle(rebased, 2 * HOUR + 15 * 60 * 1000, 'after-rebase');
  assert.equal(receipt.awarded_steps, 1);
  assert.equal(after.draws.ash, 1);
  assert.throws(() => rebaseClock(start, 0, 1));
});

test('settlement and inventory mutations leave their input objects unchanged', () => {
  const original = initialState();
  const snapshot = structuredClone(original);
  const settled = settle(original, 4 * HOUR, 'immutable')[0];
  const equipped = equip(original, original.equipped[0]);
  const preset = savePreset(original, 'slot1', '保存');
  const locked = setLocked(original, original.equipped[0], true);
  const toggle = setAutoDuplicates(original, false);
  assert.deepEqual(original, snapshot);
  assert.notEqual(settled, original);
  assert.notEqual(equipped, original);
  assert.notEqual(preset, original);
  assert.notEqual(locked, original);
  assert.notEqual(toggle, original);
});

test('lock, equipped, preset reference, and multi-item last-copy protections reject the entire batch', () => {
  let s = initialState();
  const extraWeapon = { id: 'extra:weapon_c', template_id: 'weapon_c', locked: false, origin: 'loot' };
  const extraArmor = { id: 'extra:armor_c', template_id: 'armor_c', locked: false, origin: 'loot' };
  const extraRing = { id: 'extra:ring_c', template_id: 'ring_c', locked: false, origin: 'loot' };
  s.inventory[extraWeapon.id] = extraWeapon;
  s.inventory[extraArmor.id] = extraArmor;
  s.inventory[extraRing.id] = extraRing;
  s = savePreset(s, 'slot1', '守る構成');
  let locked = setLocked(s, extraWeapon.id, true);
  assert.equal(previewDismantle(locked, [extraWeapon.id]).rejected[0].reason, 'locked');
  assert.throws(() => dismantle(locked, [extraWeapon.id, extraArmor.id]), /rejected/);
  assert.ok(s.inventory[extraArmor.id], 'failed batch must not partially dismantle');
  assert.equal(previewDismantle(s, [s.equipped[0]]).rejected[0].reason, 'equipped_or_preset');
  assert.equal(previewDismantle(s, [extraArmor.id]).allowed, true);
  assert.equal(previewDismantle(s, [extraRing.id]).allowed, true);
  const finalOnly = initialState();
  finalOnly.inventory['armor-p:one'] = { id: 'armor-p:one', template_id: 'armor_p', locked: false };
  finalOnly.inventory['armor-p:two'] = { id: 'armor-p:two', template_id: 'armor_p', locked: false };
  assert.equal(previewDismantle(finalOnly, ['armor-p:one']).allowed, true);
  assert.equal(previewDismantle(finalOnly, ['armor-p:one', 'armor-p:two']).allowed, false);
  assert.equal(previewDismantle(finalOnly, ['starter:weapon_c']).allowed, false);
});

test('craft failures for insufficient essence and a full inventory are charge-free', () => {
  const poor = initialState();
  assert.throws(() => craft(poor, 'weapon_p'), /insufficient/);
  assert.equal(poor.essence, 0);
  const full = initialState();
  full.essence = 500;
  for (let i = Object.keys(full.inventory).length; i < 72; i += 1) {
    const id = `filler:${i}`;
    full.inventory[id] = { id, template_id: 'weapon_c', locked: false, origin: 'test' };
  }
  const beforeEssence = full.essence;
  const beforeIds = Object.keys(full.inventory).length;
  assert.throws(() => craft(full, 'weapon_p'), /inventory full/);
  assert.equal(full.essence, beforeEssence);
  assert.equal(Object.keys(full.inventory).length, beforeIds);
});

test('overflow reclaim requires space, retains aggregate count, and uses unique instance IDs', () => {
  const s = initialState();
  s.overflow.weapon_p = 2;
  const full = structuredClone(s);
  for (let i = Object.keys(full.inventory).length; i < 72; i += 1) {
    const id = `filler:${i}`;
    full.inventory[id] = { id, template_id: 'weapon_c', locked: false };
  }
  assert.throws(() => reclaimOverflow(full, 'weapon_p', 1), /inventory full/);
  assert.equal(full.overflow.weapon_p, 2);
  const first = reclaimOverflow(s, 'weapon_p', 1);
  const second = reclaimOverflow(first, 'weapon_p', 1);
  assert.equal(second.overflow.weapon_p, undefined);
  assert.equal(new Set(Object.keys(second.inventory)).size, Object.keys(second.inventory).length);
});

test('overflow conversion preserves final owned copy and rejects invalid counts atomically', () => {
  const s = initialState();
  s.overflow.armor_p = 2;
  assert.throws(() => convertOverflow(s, 'armor_p', 2), /final/);
  assert.throws(() => convertOverflow(s, 'armor_p', 3), /overflow/);
  assert.equal(s.overflow.armor_p, 2);
  s.inventory['armor-p-copy'] = { id: 'armor-p-copy', template_id: 'armor_p', locked: false };
  const converted = convertOverflow(s, 'armor_p', 1);
  assert.equal(converted.overflow.armor_p, 1);
  assert.equal(converted.essence, s.essence + 2);
});

test('trial grant remains individually claimable at full capacity and does not repeat', () => {
  const full = initialState();
  for (let i = Object.keys(full.inventory).length; i < 72; i += 1) {
    const id = `filler:${i}`;
    full.inventory[id] = { id, template_id: 'weapon_c', locked: false, origin: 'test' };
  }
  const unlocked = recordFight(full, 'gatekeeper', { win: true }, 1);
  assert.equal(unlocked.trial_pending.length, 12);
  assert.equal(Object.values(unlocked.inventory).filter((item) => item.origin === 'trial').length, 0);
  for (let i = 60; i < 72; i += 1) delete unlocked.inventory[`filler:${i}`];
  const claimed = claimTrialItems(unlocked);
  assert.equal(claimed.trial_pending.length, 0);
  assert.equal(Object.values(claimed.inventory).filter((item) => item.origin === 'trial').length, 12);
  const repeated = recordFight(claimed, 'gatekeeper', { win: true }, 2);
  assert.equal(Object.values(repeated.inventory).filter((item) => item.origin === 'trial').length, 12);
  assert.equal(repeated.collection_history.weapon_p, undefined);
});

test('all three boss victories persist completion, while losses do not complete the G1 scope', () => {
  let s = initialState();
  s = recordFight(s, 'gatekeeper', { win: false, reason: 'HP_ZERO' }, 1);
  assert.equal(s.g1_scope_complete, false);
  s = recordFight(s, 'gatekeeper', { win: true }, 2);
  assert.equal(s.g1_scope_complete, false);
  s = recordFight(s, 'stonebeast', { win: true }, 3);
  assert.equal(s.g1_scope_complete, false);
  s = recordFight(s, 'sentinels', { win: true }, 4);
  assert.equal(s.g1_scope_complete, true);
  assert.deepEqual(Object.keys(s.boss_history).sort(), ['gatekeeper', 'sentinels', 'stonebeast']);
});

test('reload-equivalent restoration does not duplicate the same settlement or starter grant', () => {
  const started = initialState(1000);
  const [saved] = settle(started, 1000 + 8 * HOUR, 'reload-checkpoint');
  const restored = JSON.parse(JSON.stringify(saved));
  const [retry, receipt] = settle(restored, restored.last_ms, 'reload-checkpoint');
  assert.equal(receipt.status, 'ALREADY_APPLIED');
  assert.deepEqual(retry, restored);
  assert.equal(Object.values(restored.inventory).filter((item) => item.origin === 'starter').length, 6);
});

test('craft and reclaimed-overflow instance IDs avoid collisions in recovered generations', () => {
  const craftedState = initialState();
  craftedState.essence = 120;
  craftedState.inventory['craft:1'] = { id: 'craft:1', template_id: 'armor_c', locked: false, origin: 'test' };
  const crafted = craft(craftedState, 'weapon_p');
  assert.ok(crafted.inventory['craft:1x']);
  assert.equal(crafted.inventory['craft:1'].template_id, 'armor_c');

  const overflowState = initialState();
  overflowState.overflow.weapon_p = 1;
  overflowState.inventory['reclaim:1:weapon_p:0'] = { id: 'reclaim:1:weapon_p:0', template_id: 'armor_c', locked: false, origin: 'test' };
  const reclaimed = reclaimOverflow(overflowState, 'weapon_p', 1);
  assert.ok(reclaimed.inventory['reclaim:1:weapon_p:0x']);
  assert.equal(reclaimed.overflow.weapon_p, undefined);
});

test('normal drop history includes converted and overflowed loot while excluding starter and trial grants', () => {
  let s = initialState(0, 12345);
  assert.deepEqual(s.collection_history, {});
  [s] = settle(s, 8 * HOUR, 'normal-loot');
  const totalRecorded = Object.values(s.collection_history).reduce((sum, n) => sum + n, 0);
  assert.equal(totalRecorded, 32);
  const [emptySettled] = settle(emptyState(0, 12345), 8 * HOUR, 'empty-loot');
  assert.deepEqual(s.collection_history, emptySettled.collection_history);
  s = recordFight(s, 'gatekeeper', { win: true }, 11);
  assert.equal(Object.values(s.collection_history).reduce((sum, n) => sum + n, 0), 32);
});

test('overflow conversion can retain one protected template instance despite repeated preset references', () => {
  let s = initialState();
  const armorId = 'trial-reference:armor_p';
  s.inventory[armorId] = { id: armorId, template_id: 'armor_p', locked: false, origin: 'loot' };
  s.overflow.armor_p = 2;
  const armorIndex = 1;
  s.equipped[armorIndex] = armorId;
  s.presets.slot1 = [...s.equipped];
  s.presets.slot2 = [...s.equipped];
  const converted = convertOverflow(s, 'armor_p', 2);
  assert.equal(converted.overflow.armor_p, undefined);
  assert.equal(converted.inventory[armorId].template_id, 'armor_p');
  assert.equal(converted.essence, s.essence + 4);
});
