import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const playwrightPath = process.env.IDLE_LOOT_PLAYWRIGHT
  || '/Users/PUBLIC_USER/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
const { chromium } = await import(pathToFileURL(playwrightPath).href);

const baseURL = 'http://127.0.0.1:4173';
const executablePath = process.env.IDLE_LOOT_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const database = `idle-loot-storage-test-${randomUUID()}`;
const reportPath = new URL('../reports/storage-tests.json', import.meta.url);
const report = {
  runAt: new Date().toISOString(),
  browser: 'Google Chrome via bundled Playwright',
  browserVersion: null,
  storageAdapterSha256: null,
  baseURL,
  database,
  networkPolicy: 'all requests outside 127.0.0.1:4173 aborted',
  externalRequestsAborted: 0,
  pageErrors: [],
  tests: [],
  limitations: [
    'Abrupt browser/process termination during an active IndexedDB transaction was not deterministically injected; before-commit abort and committed-but-unconfirmed paths were injected.',
    'Corruption of the latest generation intentionally recovers the preceding valid generation; changes present only in the corrupt generation are lost, and the UI must preserve and show the recovery warning.',
  ],
};

let browser;
try {
  const source = await readFile(new URL('../src/platform/storage.js', import.meta.url));
  report.storageAdapterSha256 = createHash('sha256').update(source).digest('hex');
  const response = await fetch(baseURL);
  if (!response.ok) throw new Error(`Local server returned HTTP ${response.status}`);
  browser = await chromium.launch({ headless: true, executablePath, args: ['--no-sandbox', '--disable-background-networking'] });
  report.browserVersion = browser.version();
  const context = await browser.newContext();
  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.hostname === '127.0.0.1' && url.port === '4173') return route.continue();
    report.externalRequestsAborted += 1;
    return route.abort();
  });
  const page = await context.newPage();
  page.on('pageerror', (error) => report.pageErrors.push(error.message));
  await page.goto(baseURL, { waitUntil: 'domcontentloaded' });
  const uiBooted = await page.waitForFunction(
    () => document.querySelector('#app')?.getAttribute('aria-busy') === 'false' && Boolean(window.__g1?.game?.state),
    null,
    { timeout: 8000 },
  ).then(() => true).catch(() => false);
  report.uiBoot = { status: uiBooted ? 'PASS' : 'FAIL', pageErrors: report.pageErrors };
  await page.evaluate(() => { window.__storageRuns = {}; });

  const results = await page.evaluate(async (dbName) => {
    const { SaveRepository, checksum } = await import('/src/platform/storage.js');
    const { DATA } = await import('/src/content.js');
    const { fight } = await import('/src/core/combat.js');
    const { initialState, settle, recordFight, rebaseClock } = await import('/src/core/progression.js');
    const checks = {};
    const errorOf = async (fn) => {
      try { await fn(); return null; }
      catch (error) { return { code: error.code ?? error.name, message: error.message, revision: error.revision ?? null }; }
    };
    const makeRepo = async (profile) => new SaveRepository({ database: dbName, profile }).open();
    const readRaw = async (repo, storeName, key) => {
      const tx = repo.db.transaction(storeName, 'readonly');
      const request = tx.objectStore(storeName).get(key);
      const value = await new Promise((resolve, reject) => {
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      await new Promise((resolve, reject) => { tx.oncomplete = resolve; tx.onabort = () => reject(tx.error); });
      return value;
    };
    const mutateRaw = async (repo, storeName, operation) => {
      const tx = repo.db.transaction(storeName, 'readwrite');
      operation(tx.objectStore(storeName));
      await new Promise((resolve, reject) => { tx.oncomplete = resolve; tx.onabort = () => reject(tx.error); });
    };
    // New profile, create-once, close/reopen persistence, and independent save revision.
    {
      const repo = await makeRepo('basic');
      checks.new_profile_is_null = (await repo.load()) === null;
      const created = await repo.create(initialState(0));
      checks.create_revision_zero = created.revision === 0 && created.state.generation === 0;
      checks.duplicate_create_conflicts = (await errorOf(() => repo.create(initialState(0))))?.code === 'CONFLICT';
      const next = structuredClone(created.state);
      next.essence = 15;
      const committed = await repo.commit(next, created.revision);
      checks.commit_increments_generation = committed.revision === 1 && committed.state.generation === 1;
      repo.db.close();
      const reopened = await makeRepo('basic');
      const loaded = await reopened.load();
      checks.reopen_persists_committed_state = loaded.revision === 1 && loaded.state.essence === 15 && !loaded.recovered;
      checks.profiles_are_separate = (await (await makeRepo('basic-other')).load()) === null;
    }

    // Keep the current and previous two generations only.
    {
      const repo = await makeRepo('retention');
      let stored = await repo.create(initialState(0));
      for (let value = 1; value <= 3; value += 1) {
        const next = structuredClone(stored.state);
        next.essence = value * 10;
        stored = await repo.commit(next, stored.revision);
      }
      const rows = (await new Promise((resolve, reject) => {
        const tx = repo.db.transaction('generations', 'readonly');
        const request = tx.objectStore('generations').getAll();
        request.onsuccess = () => resolve(request.result.filter((row) => row.profile === 'retention').map((row) => row.revision).sort());
        request.onerror = () => reject(request.error);
      }));
      checks.retains_current_and_previous_two = JSON.stringify(rows) === JSON.stringify([1, 2, 3]);
    }

    // CAS between two simultaneous repositories.
    {
      const a = await makeRepo('cas');
      const b = await makeRepo('cas');
      const created = await a.create(initialState(0));
      const stale = await b.load();
      const first = structuredClone(created.state); first.essence = 1;
      await a.commit(first, created.revision);
      const second = structuredClone(stale.state); second.essence = 2;
      const conflict = await errorOf(() => b.commit(second, stale.revision));
      checks.concurrent_stale_revision_conflicts = conflict?.code === 'CONFLICT' && conflict.revision === 1;
    }

    // Abort and quota failures preserve the old durable state; retrying an idempotent settlement credits once.
    {
      const repo = await makeRepo('before-fault');
      const created = await repo.create(initialState(0));
      const [candidate, firstReceipt] = settle(created.state, 8 * 60 * 60 * 1000, 'request-eight-hours');
      repo.fault = 'before_commit';
      const beforeError = await errorOf(() => repo.commit(candidate, created.revision));
      const old = await repo.load();
      checks.before_commit_abort_keeps_old = beforeError?.code === 'SAVE_FAILED' && old.revision === 0 && old.state.essence === 0;
      const retry = await repo.commit(candidate, old.revision);
      const [repeat, repeatReceipt] = settle(retry.state, 8 * 60 * 60 * 1000, 'request-eight-hours');
      checks.before_commit_retry_awards_once = firstReceipt.essence_delta === retry.state.essence
        && repeatReceipt.status === 'ALREADY_APPLIED' && repeat.essence === retry.state.essence;

      const [quotaCandidate] = settle(retry.state, 16 * 60 * 60 * 1000, 'request-sixteen-hours');
      repo.fault = 'quota';
      const quotaError = await errorOf(() => repo.commit(quotaCandidate, retry.revision));
      const afterQuota = await repo.load();
      checks.quota_abort_keeps_old = quotaError?.code === 'SAVE_FAILED' && afterQuota.revision === retry.revision
        && afterQuota.state.essence === retry.state.essence;
      const quotaRetry = await repo.commit(quotaCandidate, afterQuota.revision);
      const [, quotaRepeat] = settle(quotaRetry.state, 16 * 60 * 60 * 1000, 'request-sixteen-hours');
      checks.quota_retry_awards_once = quotaRepeat.status === 'ALREADY_APPLIED';
    }

    // Transaction completed but caller did not receive confirmation. Readback reconciles the outcome.
    {
      const repo = await makeRepo('after-fault');
      const created = await repo.create(initialState(0));
      const [candidate, receipt] = settle(created.state, 8 * 60 * 60 * 1000, 'request-unknown-outcome');
      repo.fault = 'after_commit';
      const error = await errorOf(() => repo.commit(candidate, created.revision));
      const loaded = await repo.load();
      const [, repeated] = settle(loaded.state, 8 * 60 * 60 * 1000, 'request-unknown-outcome');
      checks.after_commit_reports_unknown_revision = error?.code === 'COMMITTED_UNKNOWN' && error.revision === 1;
      checks.after_commit_readback_prevents_duplicate = loaded.revision === 1 && loaded.state.essence === receipt.essence_delta
        && repeated.status === 'ALREADY_APPLIED';
    }

    // Damage latest checksum; recover previous generation without resetting head, then save a new generation.
    {
      const repo = await makeRepo('corrupt-latest');
      let stored = await repo.create(initialState(0));
      for (const value of [10, 20, 30]) {
        const next = structuredClone(stored.state); next.essence = value;
        stored = await repo.commit(next, stored.revision);
      }
      const head = await readRaw(repo, 'heads', 'corrupt-latest');
      // Replace only the latest row checksum, preserving its key and payload.
      await mutateRaw(repo, 'generations', (store) => {
        const request = store.get(`corrupt-latest\u0000${head.revision}`);
        request.onsuccess = () => store.put({ ...request.result, checksum: '0'.repeat(64) });
      });
      const recovered = await repo.load();
      checks.corrupt_latest_falls_back_with_actual_head_revision = recovered.recovered
        && recovered.revision === head.revision && recovered.state.essence === 20 && recovered.warnings.length > 0;
      const resaved = await repo.commit(recovered.state, recovered.revision);
      const loaded = await repo.load();
      checks.recovered_save_can_advance_without_reset = resaved.revision === 4 && loaded.revision === 4
        && loaded.state.essence === 20 && loaded.state.generation === 4;
    }

    // Future schema is retained and never treated as an empty first-run profile.
    {
      const repo = await makeRepo('future-schema');
      const state = initialState(0); state.schema_version = 99;
      const revision = 0;
      const row = {
        key: `future-schema\u00000`, profile: 'future-schema', revision,
        schemaVersion: state.schema_version, state,
        checksum: await checksum({ profile: 'future-schema', revision, state }),
      };
      await mutateRaw(repo, 'generations', (store) => store.add(row));
      await mutateRaw(repo, 'heads', (store) => store.add({ profile: 'future-schema', revision }));
      const error = await errorOf(() => repo.load());
      const retained = await readRaw(repo, 'generations', row.key);
      checks.unsupported_schema_throws_and_preserves_data = error?.code === 'UNSUPPORTED_SCHEMA'
        && retained?.state.schema_version === 99;
      checks.unknown_schema_create_refused = (await errorOf(() => repo.create(state)))?.code === 'UNSUPPORTED_SCHEMA';
    }

    // Missing equipped IDs remain visible to UI recovery; unknown item templates and invalid saves are rejected.
    {
      const repo = await makeRepo('missing-id');
      const state = initialState(0); state.equipped[2] = 'missing:instance-id';
      const created = await repo.create(state);
      checks.missing_equipped_id_allowed = (await repo.load()).state.equipped[2] === 'missing:instance-id';
      const invalid = structuredClone(created.state);
      invalid.inventory['bad:item'] = { id: 'bad:item', template_id: 'unknown_template', locked: false };
      checks.unknown_content_template_rejected = (await errorOf(() => repo.commit(invalid, created.revision)))?.code === 'SAVE_FAILED';
    }

    // Headless-corrupt and orphan records are not interpreted as new saves.
    {
      const repo = await makeRepo('no-valid-save');
      const created = await repo.create(initialState(0));
      await mutateRaw(repo, 'generations', (store) => {
        const request = store.get('no-valid-save\u00000');
        request.onsuccess = () => store.put({ ...request.result, checksum: 'f'.repeat(64) });
      });
      const invalid = await errorOf(() => repo.load());
      checks.corrupt_only_generation_is_not_new_save = invalid?.code === 'NO_VALID_SAVE'
        && (await readRaw(repo, 'heads', 'no-valid-save'))?.revision === created.revision;
    }
    {
      const repo = await makeRepo('orphan-record');
      const state = initialState(0);
      const row = {
        key: 'orphan-record\u00000', profile: 'orphan-record', revision: 0,
        schemaVersion: state.schema_version, state,
        checksum: await checksum({ profile: 'orphan-record', revision: 0, state }),
      };
      await mutateRaw(repo, 'generations', (store) => store.add(row));
      checks.orphan_generation_refuses_first_run = (await errorOf(() => repo.load()))?.code === 'NO_VALID_SAVE';
    }

    // Optional fields absent on schema 1 remain valid; present fields are fully checked.
    {
      const repo = await makeRepo('optional-fields-valid');
      let state = initialState(0, 0xffffffff);
      state.debug_offset_ms = 8 * 60 * 60 * 1000;
      state.operation_ids = Array.from({ length: 64 }, (_, i) => `operation-${i}`);
      state.logs = [{ kind: 'FIRST_START', utc_ms: 1, debug: true, profile: 'experience', detail: { source: 'test' } }];
      state.last_receipt = settle(state, 8 * 60 * 60 * 1000, 'request-valid')[0].last_receipt;
      state.last_receipt.source = 'DEBUG_8_HOURS';
      const result = fight(DATA.presets.critical, 'gatekeeper', 7, { trace: true });
      state = recordFight(state, 'gatekeeper', result, 7);
      state.last_fight = { boss: 'gatekeeper', result, seed: 7, loadout: [...DATA.presets.critical] };
      state.previous_fight = structuredClone(state.last_fight);
      state.g1_scope_complete = false;
      const created = await repo.create(state);
      checks.optional_fields_valid_shapes_accepted = created.revision === 0;
      const oldSchema1 = initialState(0);
      checks.optional_fields_absent_accepted = (await (await makeRepo('old-schema1')).create(oldSchema1)).revision === 0;
      const rebased = rebaseClock(oldSchema1, 0, true);
      checks.clock_rebase_minimal_receipt_accepted = (await (await makeRepo('clock-rebased')).create(rebased)).revision === 0;
    }

    {
      const badCases = [
        ['seed_signed', (s) => { s.seed = -1; }],
        ['seed_overflow', (s) => { s.seed = 0x100000000; }],
        ['debug_offset_negative', (s) => { s.debug_offset_ms = -1; }],
        ['debug_offset_fractional', (s) => { s.debug_offset_ms = 1.5; }],
        ['operation_ids_shape', (s) => { s.operation_ids = 'id'; }],
        ['operation_ids_limit', (s) => { s.operation_ids = Array.from({ length: 65 }, (_, i) => `id-${i}`); }],
        ['operation_ids_element', (s) => { s.operation_ids = [4]; }],
        ['operation_ids_duplicate', (s) => { s.operation_ids = ['same', 'same']; }],
        ['logs_shape', (s) => { s.logs = {}; }],
        ['logs_limit', (s) => { s.logs = Array.from({ length: 301 }, () => ({ kind: 'x', utc_ms: 1, debug: false, profile: 'experience' })); }],
        ['log_entry', (s) => { s.logs = [{ kind: 'x', utc_ms: -1, debug: false, profile: 'experience' }]; }],
        ['log_profile', (s) => { s.logs = [{ kind: 'x', utc_ms: 1, debug: false, profile: 'other' }]; }],
        ['last_fight_boss', (s) => { s.last_fight = { boss: 'unknown', result: {}, seed: 1, loadout: [] }; }],
        ['last_fight_loadout', (s) => { s.last_fight = { boss: 'gatekeeper', result: {}, seed: 1, loadout: ['weapon_c'] }; }],
        ['previous_fight_result', (s) => { s.previous_fight = { boss: 'gatekeeper', result: {}, seed: 1, loadout: [...DATA.presets.critical] }; }],
        ['boss_history_shape', (s) => { s.boss_history = null; }],
        ['boss_history_key', (s) => { s.boss_history.unknown = { attempts: 1, wins: 1, last_result: {}, last_seed: 1 }; }],
        ['boss_history_counts', (s) => { s.boss_history.gatekeeper = { attempts: 0, wins: 1, last_result: {}, last_seed: 1 }; }],
        ['boss_history_result', (s) => { s.boss_history.gatekeeper = { attempts: 1, wins: 0, last_result: {}, last_seed: 1 }; }],
        ['collection_history_key', (s) => { s.collection_history.unknown = 1; }],
        ['collection_history_value', (s) => { s.collection_history.weapon_c = -1; }],
        ['preset_names', (s) => { s.preset_names = { absent_slot: '名前' }; }],
        ['last_receipt_status', (s) => { s.last_receipt = { status: 'TIME_ANOMALY' }; }],
        ['last_receipt_fields', (s) => { s.last_receipt = { status: 'APPLIED', request_id: 'r' }; }],
        ['last_receipt_conflict', (s) => { s.last_receipt = { status: 'APPLIED', request_id: 'r', raw_ms: 1, credited_ms: 2, capped_ms: -1, awarded_steps: 0, converted: 0, overflowed: 0, essence_delta: 0, new_ids: [] }; }],
        ['last_receipt_source', (s) => { s.last_receipt = { status: 'APPLIED', request_id: 'r', raw_ms: 0, credited_ms: 0, capped_ms: 0, awarded_steps: 0, converted: 0, overflowed: 0, essence_delta: 0, new_ids: [], source: 'NETWORK' }; }],
        ['trial_pending_id', (s) => { s.trial_pending = [{ template_id: 'weapon_p', locked: false, origin: 'trial' }]; }],
        ['trial_pending_template', (s) => { s.trial_pending = [{ id: 'x', template_id: 'unknown', locked: false, origin: 'trial' }]; }],
        ['trial_pending_lock', (s) => { s.trial_pending = [{ id: 'x', template_id: 'weapon_p', locked: 0, origin: 'trial' }]; }],
        ['g1_scope_complete', (s) => { s.g1_scope_complete = 'true'; }],
      ];
      let allRejectedAndPreserved = true;
      for (const [name, mutate] of badCases) {
        const profile = `invalid-${name}`;
        const repo = await makeRepo(profile);
        const base = await repo.create(initialState(0));
        const candidate = structuredClone(base.state);
        mutate(candidate);
        const error = await errorOf(() => repo.commit(candidate, base.revision));
        const stillThere = await repo.load();
        if (error?.code !== 'SAVE_FAILED' || stillThere.revision !== 0
            || stillThere.state.schema_version !== base.state.schema_version
            || Object.keys(stillThere.state.inventory).length !== Object.keys(base.state.inventory).length) {
          allRejectedAndPreserved = false;
          checks[`rejects_and_preserves_${name}`] = false;
        }
      }
      checks.invalid_optional_fields_refused_without_overwriting_existing_save = allRejectedAndPreserved;
    }

    checks.game_ui_boots_without_page_error = window.__g1?.game?.state != null
      && document.querySelector('#app')?.getAttribute('aria-busy') === 'false';

    return checks;
  }, database);

  for (const [name, passed] of Object.entries(results)) {
    report.tests.push({ name, status: passed ? 'PASS' : 'FAIL' });
    assert.equal(passed, true, name);
  }
  report.overall = 'PASS';
  report.testCount = report.tests.length;
} catch (error) {
  report.overall = 'FAIL';
  report.error = { name: error.name, message: error.message, stack: error.stack };
} finally {
  if (browser) await browser.close().catch(() => {});
  await mkdir(new URL('../reports/', import.meta.url), { recursive: true });
  await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
}

console.log(JSON.stringify(report, null, 2));
if (report.overall !== 'PASS') process.exitCode = 1;
