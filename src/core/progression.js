import { DATA } from '../content.js';
import { Rng } from './combat.js';

const CFG = DATA.offline;
const SLOTS = DATA.slots;
const ROUTES = Object.keys(CFG.route_families);
const clone = (value) => structuredClone(value);
const assertInt = (n, label) => {
  if (!Number.isSafeInteger(n)) throw new TypeError(`${label} must be an integer`);
};
const makeInstance = (id, template_id, origin = 'loot') => ({ id, template_id, locked: false, origin });
const freeInstanceId = (inventory, base) => {
  let id = base;
  while (Object.hasOwn(inventory, id)) id += 'x';
  return id;
};
const bump = (s) => { s.generation += 1; return s; };
const empty = (now, seed) => ({
  schema_version: 1, generation: 0, last_ms: now, seed,
  route: 'ash', remainders_ms: Object.fromEntries(ROUTES.map((route) => [route, 0])),
  draws: Object.fromEntries(ROUTES.map((route) => [route, 0])), inventory: {}, essence: 0, overflow: {},
  auto_duplicates: true, equipped: [], presets: {}, preset_names: {}, processed: [], last_receipt: null,
  mode: 'experience', boss_history: {}, g1_scope_complete: false, trial_unlocked: false, trial_pending: [], collection_history: {},
  debugSimulated: false,
});

/** Empty report fixture, corresponding to validation/progression.py initial_state(). */
export function emptyState(now = 0, seed = 12345) {
  assertInt(now, 'now');
  return empty(now, seed);
}

/** Start an actual G1 save. The starter equipment is explicitly not collected loot. */
export function initialState(now = 0, seed = 12345, mode = 'experience') {
  assertInt(now, 'now');
  if (!['experience', 'balance'].includes(mode)) throw new RangeError(`unknown mode: ${mode}`);
  const s = empty(now, seed);
  s.mode = mode;
  const starters = DATA.presets.critical;
  for (const template_id of starters) {
    const id = `starter:${template_id}`;
    s.inventory[id] = makeInstance(id, template_id, 'starter');
    s.equipped.push(id);
  }
  if (mode === 'balance') {
    for (const template_id of Object.keys(DATA.items)) {
      if (starters.includes(template_id)) continue;
      const id = `balance:${template_id}`;
      s.inventory[id] = makeInstance(id, template_id, 'balance');
    }
    s.presets.critical = [...s.equipped];
    s.presets.poison = SLOTS.map((slot) => `balance:${slot}_p`);
    s.presets.counter = SLOTS.map((slot) => `balance:${slot}_g`);
    s.preset_names = { critical: '会心', poison: '毒', counter: '防御反撃' };
  }
  return s;
}

function loot(state, route, index) {
  const routeIndex = ROUTES.indexOf(route);
  const seed = (state.seed ^ (((index + 1) * 0x9e3779b9) >>> 0) ^ (((routeIndex + 1) * 0x85ebca6b) >>> 0)) >>> 0;
  const rng = new Rng(seed);
  const slot = SLOTS[rng.next() % SLOTS.length];
  return { id: `${route}:${index}`, template_id: `${slot}_${CFG.route_families[route]}`, locked: false, origin: 'loot' };
}

function ownedTemplate(s, templateId) {
  return Object.values(s.inventory).some((item) => item.template_id === templateId)
    || (s.overflow[templateId] ?? 0) > 0
    || s.trial_pending.some((item) => item.template_id === templateId);
}

export function settle(state, now, requestId) {
  assertInt(now, 'now');
  if (!requestId) throw new TypeError('requestId is required');
  if (state.processed.includes(requestId)) return [clone(state), { status: 'ALREADY_APPLIED', request_id: requestId }];
  if (now < state.last_ms) return [clone(state), { status: 'TIME_ANOMALY', request_id: requestId, awarded_steps: 0 }];
  const s = clone(state);
  const raw = now - s.last_ms;
  const accepted = Math.min(raw, CFG.cap_ms);
  const route = s.route;
  const [steps, remainder] = [
    Math.floor((s.remainders_ms[route] + accepted) / CFG.step_ms),
    (s.remainders_ms[route] + accepted) % CFG.step_ms,
  ];
  const receipt = {
    status: 'APPLIED', request_id: requestId, raw_ms: raw, credited_ms: accepted, capped_ms: raw - accepted,
    awarded_steps: steps, new_ids: [], converted: 0, overflowed: 0,
    essence_delta: steps * CFG.essence_per_step,
  };
  const family = s.draws[route];
  for (let i = family; i < family + steps; i += 1) {
    const item = loot(s, route, i);
    // This is the normal loot ledger: record every generated loot item, including
    // duplicates converted automatically and items held in overflow.
    s.collection_history[item.template_id] = (s.collection_history[item.template_id] ?? 0) + 1;
    if (s.auto_duplicates && ownedTemplate(s, item.template_id)) {
      receipt.converted += 1;
      receipt.essence_delta += 2;
    } else if (Object.keys(s.inventory).length < CFG.inventory_capacity) {
      s.inventory[item.id] = item;
      receipt.new_ids.push(item.id);
    } else {
      s.overflow[item.template_id] = (s.overflow[item.template_id] ?? 0) + 1;
      receipt.overflowed += 1;
    }
  }
  s.essence += receipt.essence_delta;
  s.draws[route] += steps;
  s.remainders_ms[route] = remainder;
  s.last_ms = now;
  s.generation += 1;
  s.last_receipt = receipt;
  s.processed = [...s.processed, requestId].slice(-32);
  return [s, receipt];
}

export function switchRoute(state, now, route, requestId) {
  if (!Object.hasOwn(CFG.route_families, route)) throw new RangeError(`unknown route: ${route}`);
  const [s, receipt] = settle(state, now, requestId);
  if (receipt.status !== 'APPLIED') return [s, receipt];
  if (s.route !== route) s.route = route;
  return [s, receipt];
}

export function rebaseClock(state, now, explicitUserConfirmation) {
  if (explicitUserConfirmation !== true) throw new Error('clock rebase requires explicit confirmation');
  assertInt(now, 'now');
  const s = clone(state);
  s.last_ms = now;
  s.generation += 1;
  s.last_receipt = { status: 'CLOCK_REBASED', awarded_steps: 0 };
  return s;
}

export function equip(state, instanceId) {
  const item = state.inventory[instanceId];
  if (!item) throw new RangeError(`unknown instance: ${instanceId}`);
  const slot = DATA.items[item.template_id]?.slot;
  if (!slot) throw new RangeError(`unknown template: ${item.template_id}`);
  const s = clone(state);
  const next = [...s.equipped];
  const at = SLOTS.indexOf(slot);
  while (next.length < SLOTS.length) next.push(null);
  next[at] = instanceId;
  s.equipped = next;
  return bump(s);
}

function validatePreset(state, ids) {
  if (!Array.isArray(ids) || ids.length !== SLOTS.length || ids.some((id) => !state.inventory[id])) {
    throw new TypeError('preset must contain six owned item instance IDs');
  }
  const templates = ids.map((id) => DATA.items[state.inventory[id].template_id]);
  if (templates.some((item, i) => !item || item.slot !== SLOTS[i])) throw new TypeError('preset items must match slot order');
}

export function savePreset(state, key, name, overwrite = false) {
  if (!['slot1', 'slot2', 'slot3'].includes(key)) throw new RangeError('preset key must be slot1, slot2, or slot3');
  if (state.presets[key] && !overwrite) throw new Error('preset already exists; overwrite must be explicit');
  validatePreset(state, state.equipped);
  const s = clone(state);
  s.presets[key] = [...s.equipped];
  s.preset_names[key] = String(name || key);
  return bump(s);
}

export function applyPreset(state, key) {
  const ids = state.presets[key];
  validatePreset(state, ids);
  const s = clone(state);
  s.equipped = [...ids];
  return bump(s);
}

export function renamePreset(state, key, name) {
  if (!state.presets[key]) throw new RangeError(`unknown preset: ${key}`);
  const s = clone(state);
  s.preset_names[key] = String(name);
  return bump(s);
}

export function setLocked(state, instanceId, locked) {
  if (!state.inventory[instanceId]) throw new RangeError(`unknown instance: ${instanceId}`);
  const s = clone(state);
  s.inventory[instanceId].locked = Boolean(locked);
  return bump(s);
}

export function setAutoDuplicates(state, enabled) {
  const s = clone(state);
  s.auto_duplicates = Boolean(enabled);
  return bump(s);
}

export function getLoadout(state) {
  validatePreset(state, state.equipped);
  return state.equipped.map((id) => state.inventory[id].template_id);
}

export function dismantle(state, ids) {
  if (!Array.isArray(ids) || ids.length !== new Set(ids).size || ids.some((id) => !state.inventory[id])) throw new TypeError('invalid item IDs');
  const protectedIds = new Set([...state.equipped, ...Object.values(state.presets).flat()]);
  const reasons = [];
  const removedPerTemplate = {};
  for (const id of ids) removedPerTemplate[state.inventory[id].template_id] = (removedPerTemplate[state.inventory[id].template_id] ?? 0) + 1;
  for (const id of ids) {
    const item = state.inventory[id];
    const remainingCopies = Object.values(state.inventory).filter((other) => other.template_id === item.template_id).length
      - removedPerTemplate[item.template_id] + (state.overflow[item.template_id] ?? 0)
      + state.trial_pending.filter((other) => other.template_id === item.template_id).length;
    const reason = item.locked ? 'locked' : protectedIds.has(id) ? 'equipped_or_preset'
      : remainingCopies < 1 ? 'final_copy' : null;
    if (reason) reasons.push({ id, reason });
  }
  if (reasons.length) {
    const error = new Error('dismantle rejected: protected items included');
    error.details = reasons;
    throw error;
  }
  const s = clone(state);
  for (const id of ids) delete s.inventory[id];
  s.essence += 2 * ids.length;
  return bump(s);
}

export function previewDismantle(state, ids) {
  try {
    dismantle(state, ids);
    return { allowed: true, rejected: [], dismantle_ids: [...ids], essence_delta: 2 * ids.length };
  } catch (error) {
    return { allowed: false, rejected: error.details ?? [], dismantle_ids: [], essence_delta: 0, reason: error.message };
  }
}

export function craft(state, templateId) {
  if (!Object.hasOwn(DATA.items, templateId)) throw new RangeError(`unknown template: ${templateId}`);
  if (state.essence < CFG.craft_cost) throw new Error('insufficient essence');
  if (Object.keys(state.inventory).length >= CFG.inventory_capacity) throw new Error('inventory full; nothing charged');
  const s = clone(state);
  const id = freeInstanceId(s.inventory, `craft:${s.generation + 1}`);
  s.inventory[id] = makeInstance(id, templateId, 'craft');
  s.essence -= CFG.craft_cost;
  s.collection_history[templateId] = (s.collection_history[templateId] ?? 0) + 1;
  return bump(s);
}

export function reclaimOverflow(state, templateId, count = 1) {
  if (!Object.hasOwn(DATA.items, templateId)) throw new RangeError(`unknown template: ${templateId}`);
  assertInt(count, 'count');
  if (count < 1 || (state.overflow[templateId] ?? 0) < count) throw new RangeError('insufficient overflow copies');
  if (Object.keys(state.inventory).length + count > CFG.inventory_capacity) throw new Error('inventory full; nothing reclaimed');
  const s = clone(state);
  for (let n = 0; n < count; n += 1) {
    const id = freeInstanceId(s.inventory, `reclaim:${s.generation + 1}:${templateId}:${n}`);
    s.inventory[id] = makeInstance(id, templateId, 'loot');
  }
  s.overflow[templateId] -= count;
  if (!s.overflow[templateId]) delete s.overflow[templateId];
  return bump(s);
}

export function claimTrialItems(state) {
  const space = Math.max(0, CFG.inventory_capacity - Object.keys(state.inventory).length);
  if (!space || !state.trial_pending.length) return clone(state);
  const s = clone(state);
  const claimed = s.trial_pending.splice(0, space);
  for (const item of claimed) s.inventory[item.id] = item;
  return bump(s);
}

export function convertOverflow(state, templateId, count = 1) {
  if (!Object.hasOwn(DATA.items, templateId)) throw new RangeError(`unknown template: ${templateId}`);
  assertInt(count, 'count');
  if (count < 1 || (state.overflow[templateId] ?? 0) < count) throw new RangeError('insufficient overflow copies');
  const ownedCount = Object.values(state.inventory).filter((item) => item.template_id === templateId).length
    + (state.overflow[templateId] ?? 0) + state.trial_pending.filter((item) => item.template_id === templateId).length;
  if (ownedCount - count < 1) throw new Error('cannot convert final or protected copy');
  const s = clone(state);
  s.overflow[templateId] -= count;
  if (!s.overflow[templateId]) delete s.overflow[templateId];
  s.essence += count * 2;
  return bump(s);
}

export function recordFight(state, bossId, result, seed) {
  if (!Object.hasOwn(DATA.bosses, bossId)) throw new RangeError(`unknown boss: ${bossId}`);
  if (!result || typeof result.win !== 'boolean') throw new TypeError('fight result with win boolean required');
  const s = clone(state);
  s.boss_history[bossId] = {
    attempts: (s.boss_history[bossId]?.attempts ?? 0) + 1,
    wins: (s.boss_history[bossId]?.wins ?? 0) + Number(result.win),
    last_result: clone(result), last_seed: seed,
  };
  s.g1_scope_complete = Object.keys(DATA.bosses).every((id) => (s.boss_history[id]?.wins ?? 0) > 0);
  if (bossId === 'gatekeeper' && result.win && !s.trial_unlocked) {
    s.trial_unlocked = true;
    for (const templateId of Object.keys(DATA.items).filter((id) => ['p', 'g'].includes(DATA.items[id].family))) {
      const id = `trial:${templateId}`;
      const item = makeInstance(id, templateId, 'trial');
      if (Object.keys(s.inventory).length < CFG.inventory_capacity) s.inventory[id] = item;
      else s.trial_pending.push(item); // Preserve the gift as claimable, individually addressable instances.
    }
  }
  return bump(s);
}

export function debugSimulated(state) {
  const s = clone(state);
  s.debugSimulated = true;
  return bump(s);
}
