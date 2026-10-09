import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
const playwrightModule = process.env.IDLE_LOOT_PLAYWRIGHT ?? '/Users/PUBLIC_USER/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
const { chromium } = await import(playwrightModule);

const baseURL = process.env.IDLE_LOOT_BASE_URL ?? 'http://127.0.0.1:4173';
const baseOrigin = new URL(baseURL);
if (!['127.0.0.1', 'localhost'].includes(baseOrigin.hostname)) throw new Error('Browser tests only accept a local loopback server.');
const chromePath = process.env.IDLE_LOOT_CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const evidenceDir = new URL('../reports/browser-evidence/', import.meta.url);
await mkdir(evidenceDir, { recursive: true });
const checks = [];
const errors = [];
const pages = [];
let externalRequestsAborted = 0;
let externalRequestURLs = [];
let pageErrors = [];
let consoleErrors = [];

function check(name, passed, details = {}) {
  checks.push({ name, status: passed ? 'PASS' : 'FAIL', ...details });
  if (!passed) throw new Error(`${name} failed${details.message ? `: ${details.message}` : ''}`);
}

async function fresh(name, { width = 1280, height = 900, reducedMotion = 'no-preference' } = {}) {
  const context = await browser.newContext({ viewport: { width, height }, reducedMotion });
  const page = await context.newPage();
  await page.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== baseOrigin.origin) {
      externalRequestsAborted += 1;
      externalRequestURLs.push(url.origin);
      await route.abort('blockedbyclient');
    } else await route.continue();
  });
  page.on('pageerror', (error) => pageErrors.push({ run: name, message: String(error) }));
  page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push({ run: name, message: message.text() }); });
  await page.goto(baseURL, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => window.__g1?.game?.state && !window.__g1.game.busy);
  pages.push({ name, page, context });
  return page;
}

const byAction = (page, action) => page.locator(`[data-action="${action}"]`).first();
async function action(page, action) { await byAction(page, action).click(); }
async function nav(page, tab) { await page.locator(`#nav [data-tab="${tab}"]`).click(); }
async function chooseFamily(page, family) {
  await page.locator(`[data-action="family"][data-family="${family}"]`).click();
  await page.locator('#dialog [data-action="confirm"]').click();
  await page.waitForFunction(() => !window.__g1.game.busy && !document.querySelector('#dialog').open);
}
async function fightSkip(page, boss, seed) {
  await nav(page, 'expedition');
  await page.locator(`[data-action="boss"][data-boss="${boss}"]`).click();
  await page.locator('#seed').fill(String(seed));
  await action(page, 'fight');
  await page.waitForFunction(() => window.__g1.battle);
  await action(page, 'skip');
  await page.waitForFunction((expected) => !window.__g1.battle && window.__g1.game.state.last_fight?.seed === expected, seed);
  return page.evaluate(() => window.__g1.game.state.last_fight);
}
async function familyItemId(page, templateId) {
  return page.evaluate((template) => Object.values(window.__g1.game.state.inventory).find((i) => i.template_id === template)?.id, templateId);
}
async function switchSlotTo(page, slot, template) {
  await nav(page, 'equipment');
  await page.locator(`[data-action="choose"][data-slot="${slot}"]`).click();
  const id = await familyItemId(page, template);
  assert.ok(id, `missing ${template}`);
  await page.locator(`#dialog [data-action="compare"][data-id="${id}"]`).click();
  await page.locator('#dialog [data-action="confirm"]').click();
  await page.waitForFunction(() => !window.__g1.game.busy && !document.querySelector('#dialog').open);
}
async function screenshot(page, name) {
  await page.screenshot({ path: new URL(`${name}.png`, evidenceDir).pathname, fullPage: true });
}

const browser = await chromium.launch({ headless: true, executablePath: chromePath });
try {
  // A2.1: first start, initial six, first boss victory, trial access, build change, second boss result.
  {
    const page = await fresh('onboarding');
    check('A2.1_initial_six_starter_items', await page.evaluate(() => {
      const s = window.__g1.game.state;
      return Object.keys(s.inventory).length === 6 && s.equipped.length === 6 && s.equipped.every((id) => s.inventory[id]?.origin === 'starter');
    }));
    await screenshot(page, 'desktop-01-return');
    await nav(page, 'equipment'); await screenshot(page, 'desktop-02-equipment');
    await nav(page, 'expedition'); await screenshot(page, 'desktop-03-expedition');
    const first = await fightSkip(page, 'gatekeeper', 1001);
    check('A2.1_gatekeeper_first_victory', first.result.win === true && first.result.time_ms > 0);
    check('A2.1_trial_12_available', await page.evaluate(() => window.__g1.game.state.trial_unlocked && Object.values(window.__g1.game.state.inventory).filter((i) => i.origin === 'trial').length === 12));
    await nav(page, 'equipment');
    await chooseFamily(page, 'poison');
    check('A2.1_poison_build_equipped', await page.evaluate(() => window.__g1.game.state.equipped.every((id) => window.__g1.game.state.inventory[id]?.template_id.endsWith('_p'))));
    const second = await fightSkip(page, 'stonebeast', 1001);
    check('A2.1_second_boss_comparable_result', second.result.win === true && second.loadout.some((id) => id.endsWith('_p')));
    await screenshot(page, 'desktop-04-result');
    await nav(page, 'equipment'); await chooseFamily(page, 'counter');
    const third = await fightSkip(page, 'sentinels', 1001);
    check('A2.1_third_boss_clear_and_scope_complete', third.result.win === true && await page.evaluate(() => window.__g1.game.state.g1_scope_complete === true));
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForFunction(() => window.__g1?.game?.state && !window.__g1.game.busy);
    check('A2.1_reload_does_not_regrant_trial_items', await page.evaluate(() => Object.values(window.__g1.game.state.inventory).filter(i => i.origin === 'trial').length === 12));
    check('desktop_four_primary_screenshots', true, { paths: ['desktop-01-return.png','desktop-02-equipment.png','desktop-03-expedition.png','desktop-04-result.png'] });
  }

  // A2.2: route switch, explicitly labeled debug time, reload, no repeated award.
  {
    const page = await fresh('offline-idempotence');
    await nav(page, 'expedition');
    await page.locator('[data-action="route"][data-route="fen"]').click();
    await nav(page, 'return');
    const debugLabel = await page.locator('[data-action="debug8"]').innerText();
    assert.match(debugLabel, /開発用.*8時間/);
    await action(page, 'debug8');
    await page.waitForFunction(() => !window.__g1.game.busy);
    const afterFirst = await page.evaluate(() => {
      const s = window.__g1.game.state;
      return { essence:s.essence, inventory:Object.keys(s.inventory).sort(), overflow:s.overflow, draws:s.draws, remainder:s.remainders_ms, receipt:s.last_receipt };
    });
    check('A2.2_debug_8h_award', afterFirst.draws.fen === 32 && afterFirst.receipt.source === 'DEBUG_8_HOURS' && afterFirst.essence >= 160);
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForFunction(() => window.__g1?.game?.state && !window.__g1.game.busy);
    const afterReload = await page.evaluate(() => {
      const s=window.__g1.game.state;
      return { essence:s.essence, inventory:Object.keys(s.inventory).sort(), overflow:s.overflow, draws:s.draws, remainder:s.remainders_ms };
    });
    check('A2.2_reload_no_duplicate_reward', afterReload.draws.fen===afterFirst.draws.fen&&afterReload.essence===afterFirst.essence&&JSON.stringify(afterReload.inventory)===JSON.stringify(afterFirst.inventory)&&JSON.stringify(afterReload.overflow)===JSON.stringify(afterFirst.overflow));
    check('A2.2_debug_marked_after_reload', await page.locator('.debug-note').count() === 1);
    await screenshot(page, 'offline-after-reload');
  }

  // A2.3: controlled fixture for lock/equipment/preset/manual and automatic duplicate protection.
  {
    const page = await fresh('protection');
    await page.evaluate(async () => {
      const g=window.__g1.game;
      await g.apply('FIXTURE_PROTECTION_SETUP',s=>{
        const make=(id,template_id,locked=false)=>({id,template_id,locked,origin:'loot'});
        const pids=[];
        for(const slot of ['weapon','armor','gloves','boots','charm','ring']){
          const id=`fixture:preset:${slot}`;s.inventory[id]=make(id,`${slot}_p`);pids.push(id);
        }
        s.presets.slot1=pids;s.preset_names.slot1='保護テスト';
        const lock=make('fixture:locked:weapon_c','weapon_c',true);s.inventory[lock.id]=lock;
        const free1=make('fixture:free1:weapon_c','weapon_c');s.inventory[free1.id]=free1;
        const free2=make('fixture:free2:weapon_c','weapon_c');s.inventory[free2.id]=free2;
        return s;
      });
    });
    const before = await page.evaluate(() => ({ equipped:[...window.__g1.game.state.equipped], preset:[...window.__g1.game.state.presets.slot1] }));
    await nav(page,'return'); await action(page,'debug8');
    await page.waitForFunction(() => !window.__g1.game.busy);
    check('A2.3_auto_duplicate_keeps_equipped_locked_preset', await page.evaluate(({equipped,preset})=>{
      const s=window.__g1.game.state;
      return equipped.every(id=>Boolean(s.inventory[id]))&&preset.every(id=>Boolean(s.inventory[id]))&&s.inventory['fixture:locked:weapon_c']?.locked===true;
    },before));
    await nav(page,'equipment');
    for (const protectedId of ['fixture:locked:weapon_c', before.equipped[0], before.preset[0]]) {
      await page.locator(`input[data-select="${protectedId}"]`).check();
      await action(page,'bulk');
      check(`A2.3_manual_bulk_rejects_${protectedId}`, await page.locator('#dialog .error').innerText().then(t=>/全体を拒否|ロック|装備中・保存構成/.test(t)));
      await page.locator('#dialog [data-action="cancel"]').click();
      await page.locator(`input[data-select="${protectedId}"]`).uncheck();
    }
    await action(page,'safeBulk');
    await page.locator('#dialog [data-action="confirm"]').click();
      await page.waitForFunction(()=>!window.__g1.game.busy&&!document.querySelector('#dialog').open);
    check('A2.3_safe_bulk_preserves_protection_and_removes_free_dupes',await page.evaluate(({equipped,preset})=>{
      const s=window.__g1.game.state;
      return equipped.every(id=>Boolean(s.inventory[id]))&&preset.every(id=>Boolean(s.inventory[id]))&&s.inventory['fixture:locked:weapon_c']?.locked===true&&!s.inventory['fixture:free1:weapon_c']&&!s.inventory['fixture:free2:weapon_c'];
    },before));
  }

  // A2.4: pre-commit failures keep old save; committed-but-unknown is reconciled once.
  for (const fault of ['quota','before_commit','after_commit']) {
    const page = await fresh(`save-${fault}`);
    const before = await page.evaluate(()=>({essence:window.__g1.game.state.essence,draws:window.__g1.game.state.draws.ash,inventory:Object.keys(window.__g1.game.state.inventory).length}));
    await page.locator('#settings').click();
    await page.locator('#dialog details summary').click();
    await page.locator(`[data-action="fault"][data-fault="${fault}"]`).click();
    await action(page,'debug8');
    await page.waitForFunction(()=>!window.__g1.game.busy&&!document.querySelector('#dialog').open);
    const committed = fault==='after_commit';
    const current = await page.evaluate(()=>({essence:window.__g1.game.state.essence,draws:window.__g1.game.state.draws.ash,inventory:Object.keys(window.__g1.game.state.inventory).length}));
    if (!committed) {
      check(`A2.4_${fault}_preserves_previous_save`, JSON.stringify(current)===JSON.stringify(before));
      await page.reload({waitUntil:'networkidle'});
      await page.waitForFunction(()=>window.__g1?.game?.state&&!window.__g1.game.busy);
      await action(page,'debug8'); await page.waitForFunction(()=>!window.__g1.game.busy);
    } else {
      check('A2.4_after_commit_readback_reconciled',current.draws-before.draws===32&&current.essence-before.essence>=160);
      await page.reload({waitUntil:'networkidle'});
      await page.waitForFunction(()=>window.__g1?.game?.state&&!window.__g1.game.busy);
    }
    const final = await page.evaluate(()=>({essence:window.__g1.game.state.essence,draws:window.__g1.game.state.draws.ash,inventory:Object.keys(window.__g1.game.state.inventory).length}));
    check(`A2.4_${fault}_one_award_after_retry_or_reload`, final.draws-before.draws===32&&final.essence-before.essence>=160);
  }

  // A2.5: poison build loses sentinels; changing to mixed guard gear changes outcome.
  {
    const page=await fresh('loss-change-retry');
    await fightSkip(page,'gatekeeper',1001);
    await nav(page,'equipment'); await chooseFamily(page,'poison');
    const lost=await fightSkip(page,'sentinels',1001);
    check('A2.5_poison_sentinels_loss_reason_and_breakdown',lost.result.win===false&&lost.result.hp_remaining===0&&await page.locator('[data-testid="outcome"]').innerText()==='敗北'&&await page.locator('.damage-bars').count()===1);
    await switchSlotTo(page,'boots','boots_g');
    await switchSlotTo(page,'ring','ring_g');
    const won=await fightSkip(page,'sentinels',1001);
    check('A2.5_changed_build_wins_same_boss_seed',won.result.win===true&&won.result.stats.attack<lost.result.stats.attack&&won.seed===lost.seed);
  }

  // A2.6: same build/seed with actual 1x and 2x playback plus skip has byte-identical result.
  {
    const page=await fresh('speed-invariance');
    const play=async (mode) => {
      await nav(page,'expedition'); await page.locator(`[data-action="boss"][data-boss="gatekeeper"]`).click(); await page.locator('#seed').fill('0'); await action(page,'fight');
      await page.waitForFunction(()=>window.__g1.battle);
      if(mode==='2x') await page.locator('#speed').selectOption('2');
      if(mode==='skip') await action(page,'skip');
      else await page.waitForFunction(()=>!window.__g1.battle&&window.__g1.game.state.last_fight?.seed===0,{timeout:45000});
      return page.evaluate(()=>window.__g1.game.state.last_fight.result);
    };
    const one=await play('1x'); const two=await play('2x'); const skipped=await play('skip');
    check('A2.6_one_two_skip_results_identical',JSON.stringify(one)===JSON.stringify(two)&&JSON.stringify(one)===JSON.stringify(skipped));
  }

  // Mobile widths, focus restoration, dialog apply/cancel, reduced motion and large text.
  for (const size of [{width:375,height:667},{width:390,height:844}]) {
    const page=await fresh(`mobile-${size.width}`,{...size,reducedMotion:'reduce'});
    check(`mobile_${size.width}_no_horizontal_overflow`,await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    check(`mobile_${size.width}_reduced_motion`,await page.evaluate(()=>matchMedia('(prefers-reduced-motion: reduce)').matches));
    await screenshot(page,`mobile-${size.width}-return`);
    await page.locator('#settings').click();
    await page.locator('[data-action="profile"]').click();
    await page.waitForFunction(()=>window.__g1?.game?.state?.mode==='balance');
    await nav(page,'equipment');
    const boots=page.locator('[data-action="choose"][data-slot="boots"]');
    await boots.click();
    const target=await familyItemId(page,'boots_p');
    await page.locator(`#dialog [data-action="compare"][data-id="${target}"]`).click();
    await page.locator('#dialog [data-action="cancel"]').click();
    check(`mobile_${size.width}_cancel_restores_focus`,await page.evaluate(()=>document.activeElement?.matches('[data-action="choose"][data-slot="boots"]')));
    await boots.click();
    await page.locator(`#dialog [data-action="compare"][data-id="${target}"]`).click();
    await page.locator('#dialog [data-action="confirm"]').click();
    await page.waitForFunction(()=>!window.__g1.game.busy&&!document.querySelector('#dialog').open);
    check(`mobile_${size.width}_apply_restores_focus`,await page.evaluate(()=>document.activeElement?.matches('[data-action="choose"][data-slot="boots"]')));
    check(`mobile_${size.width}_after_apply_no_overflow`,await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.route('**/styles.css',async route=>{
      const response=await route.fetch();
      const stylesheet=await response.text();
      const doubled=stylesheet.replace(/font-size:([0-9]+(?:\.[0-9]+)?)px/g,(_,n)=>`font-size:${Number(n)*2}px`);
      await route.fulfill({response,body:`${doubled}\nbody{font-size:200%!important}`});
    });
    await page.reload({waitUntil:'networkidle'});
    await page.waitForFunction(()=>window.__g1?.game?.state&&!window.__g1.game.busy);
    check(`mobile_${size.width}_200pct_text_applied`,await page.evaluate(()=>getComputedStyle(document.body).fontSize==='32px'));
    check(`mobile_${size.width}_200pct_text_no_horizontal_overflow`,await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    check(`mobile_${size.width}_200pct_labels_fit_controls`,await page.evaluate(()=>[...document.querySelectorAll('button,label,p,summary,h1,h2,h3,dt,dd')].filter(e=>e.getClientRects().length&&e.clientWidth>0).every(e=>e.scrollWidth<=e.clientWidth+1&&e.scrollHeight<=e.clientHeight+1)));
    check(`mobile_${size.width}_buttons_at_least_44px`,await page.evaluate(()=>[...document.querySelectorAll('button')].filter(b=>b.getClientRects().length).every(b=>b.getBoundingClientRect().height>=44)));
    await screenshot(page,`mobile-${size.width}-equipment-200pct`);
  }

  // Empty inventory, full inventory and missing-two-slots recovery.
  {
    const page=await fresh('empty-and-full');
    await page.evaluate(async()=>window.__g1.game.apply('FIXTURE_EMPTY',s=>{s.inventory={};s.equipped=Array(6).fill(null);return s;}));
    await nav(page,'equipment');
    check('edge_zero_items_renders_without_exception',await page.locator('.inventory-row').count()===0&&await page.locator('.error').count()>0);
  }
  {
    const page=await fresh('full-inventory');
    await page.evaluate(async()=>window.__g1.game.apply('FIXTURE_FULL',s=>{
      s.essence=120;
      let n=0;for(const id of Object.keys(window.__g1.game.state.inventory)){};
      const templates=Object.keys(window.__g1.game.state.inventory).map(k=>window.__g1.game.state.inventory[k].template_id);
      while(Object.keys(s.inventory).length<72){const id=`fixture:full:${n++}`;const template_id=templates[n%templates.length];s.inventory[id]={id,template_id,locked:false,origin:'loot'};}
      return s;
    }));
    await nav(page,'equipment'); await action(page,'craft'); await page.locator('#dialog [data-action="confirm"]').click();
    await page.waitForFunction(()=>!window.__g1.game.busy);
    check('edge_full_inventory_craft_fails_without_charge',await page.locator('#dialog [role="alert"]').innerText().then(t=>/full|満杯|inventory/i.test(t))&&await page.evaluate(()=>window.__g1.game.state.essence===120&&Object.keys(window.__g1.game.state.inventory).length===72));
  }
  {
    const page=await fresh('missing-equipment');
    await page.evaluate(async()=>window.__g1.game.apply('FIXTURE_MISSING_TWO',s=>{s.equipped[0]='missing:weapon';s.equipped[3]='missing:boots';return s;}));
    await nav(page,'equipment');
    for(const [slot,template] of [['weapon','weapon_c'],['boots','boots_c']]){
      await page.locator(`[data-action="choose"][data-slot="${slot}"]`).click();
      const id=await familyItemId(page,template);
      await page.locator(`#dialog [data-action="compare"][data-id="${id}"]`).click();
      await page.locator('#dialog [data-action="confirm"]').click();await page.waitForFunction(()=>!window.__g1.game.busy);
    }
    check('edge_missing_two_slots_repairable',await page.evaluate(()=>window.__g1.game.state.equipped.every(id=>Boolean(window.__g1.game.state.inventory[id]))));
  }
  {
    const page=await fresh('clock-anomaly');
    await page.evaluate(async()=>window.__g1.game.apply('FIXTURE_CLOCK_ANOMALY',s=>{s.last_ms=Date.now()+3600000;return s;}));
    await page.reload({waitUntil:'networkidle'});await page.waitForFunction(()=>window.__g1?.game?.state&&!window.__g1.game.busy);
    check('edge_clock_anomaly_no_rewards',await page.locator('#app').innerText().then(t=>t.includes('TIME_ANOMALY'))&&await page.evaluate(()=>window.__g1.game.state.essence===0));
    await page.locator('#settings').click();await page.locator('[data-action="rebase"]').click();await page.locator('#dialog [data-action="confirm"]').click();await page.waitForFunction(()=>!window.__g1.game.busy);
    check('edge_clock_rebase_requires_and_accepts_confirmation',await page.evaluate(()=>!window.__g1.game.timeAnomaly));
  }

  check('external_requests_blocked_and_none_attempted', externalRequestsAborted===0, { externalRequestsAborted, externalRequestOrigins:externalRequestURLs });
  check('no_browser_page_errors',pageErrors.length===0,{pageErrors});
  check('no_browser_console_errors',consoleErrors.length===0,{consoleErrors});
} catch (error) {
  errors.push({ message: String(error), stack: error?.stack });
  console.error(error);
} finally {
  for(const entry of pages) await entry.context.close().catch(()=>{});
  await browser.close();
}

const sourceFiles=['src/ui.js','src/game.js','src/core/combat.js','src/core/progression.js','src/platform/storage.js','styles.css','index.html'];
const sourceFingerprint={};
for(const file of sourceFiles){const data=await readFile(new URL(`../${file}`,import.meta.url));sourceFingerprint[file]=createHash('sha256').update(data).digest('hex');}
const report={
  date:new Date().toISOString(), baseURL, browser:'Google Chrome via bundled Playwright',
  scenarios:checks, passCount:checks.filter(c=>c.status==='PASS').length, failCount:checks.filter(c=>c.status==='FAIL').length,
  externalRequestsAborted, externalRequestOrigins:[...new Set(externalRequestURLs)], pageErrors, consoleErrors, errors, sourceFingerprint,
};
report.screenshots=(await (await import('node:fs/promises')).readdir(evidenceDir)).filter(name=>name.endsWith('.png')).sort().map(name=>`reports/browser-evidence/${name}`);
report.overall=errors.length===0&&checks.every(c=>c.status==='PASS')?'PASS':'FAIL';
await writeFile(new URL('../reports/browser-tests.json',import.meta.url),`${JSON.stringify(report,null,2)}\n`);
console.log(`browser scenarios ${report.overall}: ${report.passCount} passed, ${report.failCount} failed; external requests aborted ${externalRequestsAborted}`);
if(report.overall!=='PASS')process.exitCode=1;
