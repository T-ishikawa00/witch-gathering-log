import { DATA } from '../content.js';

const STORE_HEADS = 'heads';
const STORE_GENERATIONS = 'generations';
const clone = (value) => structuredClone(value);

export class SaveError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'SaveError';
    this.code = code;
    Object.assign(this, details);
  }
}

const fail = (code, message, details) => new SaveError(code, message, details);
const idbRequest = (request) => new Promise((resolve, reject) => {
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error ?? new Error('IndexedDB request failed'));
});
const transactionDone = (transaction) => new Promise((resolve, reject) => {
  transaction.oncomplete = () => resolve();
  transaction.onabort = () => reject(transaction.error ?? new Error('IndexedDB transaction aborted'));
  transaction.onerror = () => reject(transaction.error ?? new Error('IndexedDB transaction failed'));
});
const observedTransactionDone = (transaction) => {
  const done = transactionDone(transaction);
  // Attach a rejection observer immediately. Callers still await this same
  // promise on success paths, while a request failure cannot leave it unhandled.
  done.catch(() => {});
  return done;
};
const compositeKey = (profile, revision) => `${profile}\u0000${revision}`;
const isMap = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
const isUInt = (value) => Number.isSafeInteger(value) && value >= 0 && value <= 0xffffffff;
const isCount = (value) => Number.isSafeInteger(value) && value >= 0;

function validateCombatResult(result, bossId, label) {
  const invalid = (detail) => { throw fail('SAVE_FAILED', `Save state is invalid: ${label} ${detail}`); };
  const boss = DATA.bosses[bossId];
  if (!boss || !isMap(result) || typeof result.win !== 'boolean') invalid('is malformed');
  if (!Number.isSafeInteger(result.time_ms) || result.time_ms < 0 || result.time_ms > DATA.combat.time_limit_ms) invalid('time_ms is invalid');
  if (!isMap(result.stats) || !isMap(result.totals)) invalid('stats or totals are missing');
  const statKeys = ['hp', 'attack', 'armor', 'crit_bp', 'crit_multiplier_bp', 'haste_bp', 'block_bp', 'counter_bp', 'poison_damage', 'poison_duration_ms', 'attack_interval_ms'];
  for (const key of statKeys) if (!isCount(result.stats[key])) invalid(`stat ${key} is invalid`);
  if (result.stats.hp < 1 || result.stats.attack < 1 || result.stats.crit_bp > 7500
      || result.stats.block_bp > 7500 || result.stats.attack_interval_ms < 400) invalid('stats are outside valid bounds');
  if (!isCount(result.hp_remaining) || result.hp_remaining > result.stats.hp
      || !isCount(result.boss_hp_remaining) || result.boss_hp_remaining > boss.hp) invalid('remaining HP is invalid');
  if ((result.win && (result.hp_remaining < 1 || result.boss_hp_remaining !== 0))
      || (!result.win && result.boss_hp_remaining === 0)) invalid('win state conflicts with remaining HP');
  for (const key of ['normal', 'poison', 'counter', 'incoming', 'attacks', 'crits', 'blocks', 'boss_hits', 'poison_ticks']) {
    if (!isCount(result.totals[key])) invalid(`total ${key} is invalid`);
  }
  if (result.totals.incoming !== result.stats.hp - result.hp_remaining
      || result.totals.normal + result.totals.poison + result.totals.counter !== boss.hp - result.boss_hp_remaining) invalid('damage totals do not reconcile');
  if (result.trace !== undefined) {
    if (!Array.isArray(result.trace) || result.trace.length > 2000) invalid('trace is malformed or too long');
    for (const event of result.trace) {
      if (!isMap(event) || !Number.isSafeInteger(event.t) || event.t < 0 || event.t > result.time_ms
          || !['normal', 'poison', 'boss_hit', 'counter'].includes(event.kind)
          || !isCount(event.damage) || !isCount(event.player_hp) || event.player_hp > result.stats.hp
          || !isCount(event.boss_hp) || event.boss_hp > boss.hp) invalid('trace event is malformed');
      if (event.critical !== undefined && typeof event.critical !== 'boolean') invalid('trace critical flag is invalid');
      if (event.blocked !== undefined && typeof event.blocked !== 'boolean') invalid('trace blocked flag is invalid');
      if (event.stacks !== undefined && (!Number.isSafeInteger(event.stacks) || event.stacks < 1 || event.stacks > DATA.combat.poison_stack_cap)) invalid('trace poison stacks are invalid');
    }
  }
}

function validateFightRecord(record, label) {
  if (!isMap(record) || !Object.hasOwn(DATA.bosses, record.boss) || !isUInt(record.seed)
      || !Array.isArray(record.loadout) || record.loadout.length !== DATA.slots.length) {
    throw fail('SAVE_FAILED', `Save state is invalid: ${label} is malformed.`);
  }
  for (let index = 0; index < DATA.slots.length; index += 1) {
    const item = DATA.items[record.loadout[index]];
    if (!item || item.slot !== DATA.slots[index]) throw fail('SAVE_FAILED', `Save state is invalid: ${label} loadout does not match content slots.`);
  }
  validateCombatResult(record.result, record.boss, `${label} result`);
}

function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export async function checksum(value, cryptoObject = globalThis.crypto) {
  if (!cryptoObject?.subtle || typeof TextEncoder === 'undefined') {
    throw fail('SAVE_FAILED', 'Web Crypto SHA-256 is unavailable in this browser context.');
  }
  const bytes = new TextEncoder().encode(stable(value));
  const digest = await cryptoObject.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function validateState(state) {
  const invalid = (message) => { throw fail('SAVE_FAILED', `Save state is invalid: ${message}`); };
  if (!state || typeof state !== 'object' || Array.isArray(state)) invalid('expected an object');
  if (!Number.isSafeInteger(state.schema_version)) invalid('schema_version must be an integer');
  if (state.schema_version !== DATA.schema_version) {
    throw fail('UNSUPPORTED_SCHEMA', `Save schema ${state.schema_version} is not supported.`, { schemaVersion: state.schema_version });
  }
  for (const field of ['generation', 'last_ms', 'essence']) {
    if (!Number.isSafeInteger(state[field]) || state[field] < 0) invalid(`${field} must be a non-negative safe integer`);
  }
  if (!isUInt(state.seed)) invalid('seed must be an unsigned 32-bit integer');
  if (!['experience', 'balance'].includes(state.mode)) invalid('mode is unknown');
  if (!Object.hasOwn(DATA.offline.route_families, state.route)) invalid('route is unknown');
  if (!state.remainders_ms || !state.draws || !state.inventory || !state.overflow
      || typeof state.remainders_ms !== 'object' || typeof state.draws !== 'object'
      || typeof state.inventory !== 'object' || typeof state.overflow !== 'object'
      || Array.isArray(state.inventory) || Array.isArray(state.overflow)) invalid('progression maps are missing');

  for (const route of Object.keys(DATA.offline.route_families)) {
    if (!Number.isSafeInteger(state.remainders_ms[route]) || state.remainders_ms[route] < 0
        || state.remainders_ms[route] >= DATA.offline.step_ms) invalid(`remainder for ${route} is invalid`);
    if (!Number.isSafeInteger(state.draws[route]) || state.draws[route] < 0) invalid(`draw count for ${route} is invalid`);
  }
  if (Object.keys(state.inventory).length > DATA.offline.inventory_capacity) invalid('inventory exceeds capacity');
  for (const [key, item] of Object.entries(state.inventory)) {
    if (!item || typeof item !== 'object' || item.id !== key || typeof item.id !== 'string'
        || typeof item.template_id !== 'string' || typeof item.locked !== 'boolean') invalid(`inventory item ${key} is malformed`);
    if (!Object.hasOwn(DATA.items, item.template_id)) invalid(`inventory item ${key} has unknown template ${item.template_id}`);
    if (item.origin !== undefined && typeof item.origin !== 'string') invalid(`inventory item ${key} has invalid origin`);
  }
  for (const [templateId, count] of Object.entries(state.overflow)) {
    if (!Object.hasOwn(DATA.items, templateId) || !Number.isSafeInteger(count) || count < 1) invalid(`overflow entry ${templateId} is invalid`);
  }
  if (!Array.isArray(state.equipped) || state.equipped.length !== DATA.slots.length
      || state.equipped.some((id) => id !== null && typeof id !== 'string')) invalid('equipped must contain six IDs or null slots');
  // Missing instance IDs are retained for the UI to explain, not silently replaced.
  if (!state.presets || typeof state.presets !== 'object' || Array.isArray(state.presets)) invalid('presets must be an object');
  for (const [name, ids] of Object.entries(state.presets)) {
    if (typeof name !== 'string' || !Array.isArray(ids) || ids.length !== DATA.slots.length
        || ids.some((id) => id !== null && typeof id !== 'string')) invalid(`preset ${name} is malformed`);
  }
  if (!Array.isArray(state.processed) || state.processed.some((id) => typeof id !== 'string')) invalid('processed request IDs are malformed');
  if (state.processed.length > 32 || new Set(state.processed).size !== state.processed.length) invalid('processed request IDs exceed limit or repeat');
  if (state.operation_ids !== undefined && (!Array.isArray(state.operation_ids) || state.operation_ids.length > 64
      || state.operation_ids.some((id) => typeof id !== 'string' || !id) || new Set(state.operation_ids).size !== state.operation_ids.length)) invalid('operation_ids are malformed');
  if (state.logs !== undefined && (!Array.isArray(state.logs) || state.logs.length > 300
      || state.logs.some((entry) => !isMap(entry) || typeof entry.kind !== 'string' || !entry.kind
        || !Number.isSafeInteger(entry.utc_ms) || entry.utc_ms < 0 || typeof entry.debug !== 'boolean'
        || !['experience', 'balance'].includes(entry.profile)))) invalid('logs are malformed or exceed limit');
  if (state.debug_offset_ms !== undefined && (!Number.isSafeInteger(state.debug_offset_ms) || state.debug_offset_ms < 0)) invalid('debug_offset_ms must be a non-negative safe integer');
  if (state.preset_names !== undefined && (!isMap(state.preset_names)
      || Object.entries(state.preset_names).some(([key, name]) => !Object.hasOwn(state.presets, key) || typeof name !== 'string'))) invalid('preset_names are malformed');
  if (!Array.isArray(state.trial_pending) || state.trial_pending.length > DATA.offline.inventory_capacity
      || state.trial_pending.some((item) => !isMap(item) || typeof item.id !== 'string' || !item.id
        || typeof item.template_id !== 'string' || !Object.hasOwn(DATA.items, item.template_id)
        || typeof item.locked !== 'boolean' || typeof item.origin !== 'string')) invalid('trial pending items are malformed');
  if (typeof state.auto_duplicates !== 'boolean' || typeof state.debugSimulated !== 'boolean'
      || typeof state.trial_unlocked !== 'boolean' || !isMap(state.boss_history)
      || !isMap(state.collection_history)) invalid('progression flags or histories are malformed');
  if (state.g1_scope_complete !== undefined && typeof state.g1_scope_complete !== 'boolean') invalid('g1_scope_complete must be boolean');
  if (state.last_receipt !== undefined && state.last_receipt !== null) {
    const receipt = state.last_receipt;
    if (!isMap(receipt) || typeof receipt.status !== 'string') invalid('last_receipt is malformed');
    if (receipt.status === 'CLOCK_REBASED') {
      if (receipt.awarded_steps !== 0) invalid('clock rebase receipt must award zero steps');
    } else if (receipt.status === 'APPLIED') {
      for (const key of ['raw_ms', 'credited_ms', 'capped_ms', 'awarded_steps', 'converted', 'overflowed', 'essence_delta']) {
        if (!isCount(receipt[key])) invalid(`last_receipt ${key} is invalid`);
      }
      if (typeof receipt.request_id !== 'string' || !receipt.request_id
          || !Array.isArray(receipt.new_ids) || receipt.new_ids.some((id) => typeof id !== 'string')
          || (receipt.source !== undefined && !['REAL_TIME', 'REAL_TIME_RESUME', 'DEBUG_8_HOURS'].includes(receipt.source))) invalid('last_receipt fields are malformed');
      if (receipt.credited_ms > DATA.offline.cap_ms || receipt.capped_ms !== receipt.raw_ms - receipt.credited_ms
          || receipt.awarded_steps > Math.ceil(DATA.offline.cap_ms / DATA.offline.step_ms)) invalid('last_receipt time values conflict');
    } else invalid(`last_receipt status ${receipt.status} is unsupported`);
  }
  for (const [templateId, count] of Object.entries(state.collection_history)) {
    if (!Object.hasOwn(DATA.items, templateId) || !Number.isSafeInteger(count) || count < 0) invalid(`collection history ${templateId} is invalid`);
  }
  for (const [bossId, entry] of Object.entries(state.boss_history)) {
    if (!Object.hasOwn(DATA.bosses, bossId) || !isMap(entry) || !isCount(entry.attempts)
        || !isCount(entry.wins) || entry.wins > entry.attempts || !isUInt(entry.last_seed)) invalid(`boss history ${bossId} is malformed`);
    validateCombatResult(entry.last_result, bossId, `boss history ${bossId} result`);
  }
  for (const field of ['last_fight', 'previous_fight']) {
    if (state[field] !== undefined && state[field] !== null) validateFightRecord(state[field], field);
  }
  return true;
}

async function hashRecord(profile, revision, state, cryptoObject) {
  return checksum({ profile, revision, state }, cryptoObject);
}

export class SaveRepository {
  constructor({ database = 'idle-loot-g1', profile = 'experience', indexedDB = globalThis.indexedDB } = {}) {
    if (!indexedDB) throw fail('SAVE_FAILED', 'IndexedDB is unavailable.');
    if (typeof profile !== 'string' || !profile) throw new TypeError('profile must be a non-empty string');
    this.databaseName = database;
    this.profile = profile;
    this.indexedDB = indexedDB;
    this.db = null;
    this.fault = null;
  }

  async open() {
    if (this.db) return this;
    this.db = await new Promise((resolve, reject) => {
      const request = this.indexedDB.open(this.databaseName, 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(STORE_HEADS)) db.createObjectStore(STORE_HEADS, { keyPath: 'profile' });
        if (!db.objectStoreNames.contains(STORE_GENERATIONS)) db.createObjectStore(STORE_GENERATIONS, { keyPath: 'key' });
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error ?? new Error('Could not open IndexedDB'));
      request.onblocked = () => reject(new Error('IndexedDB upgrade is blocked by another open tab'));
    });
    this.db.onversionchange = () => { this.db.close(); this.db = null; };
    return this;
  }

  _requireOpen() {
    if (!this.db) throw fail('SAVE_FAILED', 'Call open() before using the save repository.');
  }

  async _getHeadAndRecords() {
    this._requireOpen();
    const tx = this.db.transaction([STORE_HEADS, STORE_GENERATIONS], 'readonly');
    const done = observedTransactionDone(tx);
    const head = await idbRequest(tx.objectStore(STORE_HEADS).get(this.profile));
    const all = await idbRequest(tx.objectStore(STORE_GENERATIONS).getAll());
    await done;
    return { head: head ?? null, records: all.filter((row) => row.profile === this.profile) };
  }

  async load() {
    const { head, records } = await this._getHeadAndRecords();
    if (!head) {
      if (records.length) throw fail('NO_VALID_SAVE', 'Generation records exist without a save head; refusing to initialize over them.');
      return null;
    }
    const byRevision = new Map(records.map((row) => [row.revision, row]));
    const candidates = [head.revision, head.revision - 1, head.revision - 2]
      .map((revision) => byRevision.get(revision)).filter(Boolean)
      .sort((a, b) => b.revision - a.revision);
    if (!candidates.length) throw fail('NO_VALID_SAVE', 'Save head exists, but no retained generation is available.', { revision: head.revision });

    let sawCorruption = false;
    for (const row of candidates) {
      if (row.schemaVersion !== DATA.schema_version) {
        throw fail('UNSUPPORTED_SCHEMA', `Save schema ${row.schemaVersion} is not supported.`, { schemaVersion: row.schemaVersion, revision: row.revision });
      }
      let expected;
      try { expected = await hashRecord(this.profile, row.revision, row.state); }
      catch (error) { if (error instanceof SaveError) throw error; throw fail('SAVE_FAILED', 'Could not verify save checksum.', { cause: error }); }
      if (expected !== row.checksum) { sawCorruption = true; continue; }
      try { validateState(row.state); }
      catch (error) {
        if (error.code === 'UNSUPPORTED_SCHEMA') throw error;
        sawCorruption = true;
        continue;
      }
      return {
        state: clone(row.state),
        revision: head.revision,
        recovered: row.revision !== head.revision,
        warnings: [
          ...(row.revision !== head.revision ? [`最新の保存世代 ${head.revision} を読み取れず、世代 ${row.revision} から復旧しました。`] : []),
          ...(sawCorruption ? ['保存世代のチェックサムまたは内容検証に失敗しました。'] : []),
        ],
      };
    }
    throw fail('NO_VALID_SAVE', 'No retained save generation passed checksum and schema validation.', { revision: head.revision });
  }

  async create(state) {
    this._requireOpen();
    validateState(state);
    const row = await this._makeRow(state, 0);
    const tx = this.db.transaction([STORE_HEADS, STORE_GENERATIONS], 'readwrite');
    const done = observedTransactionDone(tx);
    try {
      const heads = tx.objectStore(STORE_HEADS);
      const generations = tx.objectStore(STORE_GENERATIONS);
      const current = await idbRequest(heads.get(this.profile));
      if (current) {
        tx.abort();
        await done.catch(() => {});
        throw fail('CONFLICT', 'A save already exists for this profile.', { revision: current.revision });
      }
      await this._injectBeforeWrite(tx, done);
      generations.add(row);
      heads.add({ profile: this.profile, revision: 0 });
      await done;
      await this._verifyReadback(row);
      return { state: clone(row.state), revision: 0, recovered: false, warnings: [] };
    } catch (error) {
      if (error instanceof SaveError) throw error;
      throw this._mapWriteError(error);
    }
  }

  async commit(state, expectedRevision) {
    this._requireOpen();
    validateState(state);
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new TypeError('expectedRevision must be a non-negative safe integer');
    const revision = expectedRevision + 1;
    const row = await this._makeRow(state, revision);
    const tx = this.db.transaction([STORE_HEADS, STORE_GENERATIONS], 'readwrite');
    const done = observedTransactionDone(tx);
    try {
      const heads = tx.objectStore(STORE_HEADS);
      const generations = tx.objectStore(STORE_GENERATIONS);
      const current = await idbRequest(heads.get(this.profile));
      if (!current || current.revision !== expectedRevision) {
        tx.abort();
        await done.catch(() => {});
        throw fail('CONFLICT', 'The save changed in another tab. Reload before applying this change.', { revision: current?.revision ?? null });
      }
      await this._injectBeforeWrite(tx, done);
      generations.put(row);
      heads.put({ profile: this.profile, revision });
      const all = await idbRequest(generations.getAll());
      for (const old of all) {
        if (old.profile === this.profile && old.revision < revision - 2) generations.delete(old.key);
      }
      await done;
      if (this.fault === 'after_commit') {
        this.fault = null;
        throw fail('COMMITTED_UNKNOWN', 'The save committed, but confirmation was interrupted. Reload before retrying.', { revision });
      }
      await this._verifyReadback(row);
      return { state: clone(row.state), revision, recovered: false, warnings: [] };
    } catch (error) {
      if (error instanceof SaveError) throw error;
      throw this._mapWriteError(error, revision);
    }
  }

  async _makeRow(state, revision) {
    const normalized = clone(state);
    normalized.generation = revision;
    const schemaVersion = normalized.schema_version;
    const digest = await hashRecord(this.profile, revision, normalized);
    return { key: compositeKey(this.profile, revision), profile: this.profile, revision, schemaVersion, state: normalized, checksum: digest };
  }

  async _injectBeforeWrite(tx, done) {
    if (this.fault === 'before_commit' || this.fault === 'quota') {
      const fault = this.fault;
      this.fault = null;
      tx.abort();
      await done.catch(() => {});
      if (fault === 'quota') throw new DOMException('Injected quota failure', 'QuotaExceededError');
      throw fail('SAVE_FAILED', 'Injected failure before save commit.');
    }
  }

  async _verifyReadback(expectedRow) {
    try {
      const tx = this.db.transaction(STORE_GENERATIONS, 'readonly');
      const done = observedTransactionDone(tx);
      const actual = await idbRequest(tx.objectStore(STORE_GENERATIONS).get(expectedRow.key));
      await done;
      if (!actual || actual.revision !== expectedRow.revision || actual.checksum !== expectedRow.checksum
          || stable(actual.state) !== stable(expectedRow.state)) {
        throw fail('COMMITTED_UNKNOWN', 'The save transaction committed, but its stored row could not be confirmed. Reload before retrying.', { revision: expectedRow.revision });
      }
      if (this.fault === 'after_commit') {
        this.fault = null;
        throw fail('COMMITTED_UNKNOWN', 'The save committed, but confirmation was interrupted. Reload before retrying.', { revision: expectedRow.revision });
      }
    } catch (error) {
      if (error instanceof SaveError && error.code === 'COMMITTED_UNKNOWN') throw error;
      throw fail('COMMITTED_UNKNOWN', 'The save may have committed, but readback failed. Reload before retrying.', { revision: expectedRow.revision, cause: error });
    }
  }

  _mapWriteError(error, revision) {
    if (error instanceof SaveError) return error;
    if (error?.name === 'QuotaExceededError') return fail('SAVE_FAILED', 'Browser storage is full; the previous save remains available.', { cause: error, revision });
    return fail('SAVE_FAILED', 'Could not save progress; the previous generation remains available.', { cause: error, revision });
  }
}
