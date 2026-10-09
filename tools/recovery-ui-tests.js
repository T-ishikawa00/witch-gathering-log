import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.IDLE_LOOT_PLAYWRIGHT || '/Users/PUBLIC_USER/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs');
const browser=await chromium.launch({executablePath:process.env.IDLE_LOOT_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--disable-background-networking']});
const context=await browser.newContext({viewport:{width:1280,height:900}});
let external=0;const errors=[];const cases=[];
await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'&&u.port==='4173')return route.continue();external++;return route.abort();});
const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
const ready=()=>page.waitForFunction(()=>window.__g1?.game.state&&!window.__g1.game.busy);
try {
 await page.goto('http://127.0.0.1:4173');await ready();
 await page.evaluate(async()=>{
  const g=window.__g1.game;await g.apply('FIXTURE_RECOVERY',s=>{s.essence=50;return s;});
  const tx=g.repo.db.transaction('generations','readwrite');const store=tx.objectStore('generations');
  const req=store.get(`experience\u0000${g.revision}`);
  req.onsuccess=()=>{const row=req.result;row.checksum='damaged';store.put(row);};
  await new Promise((resolve,reject)=>{tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);});
 });
 await page.reload();await ready();
 assert.ok(await page.locator('#app').innerText().then(t=>t.includes('復旧しました')));
 assert.ok(await page.evaluate(()=>window.__g1.game.warnings.length>0));
 cases.push({name:'recovery_warning_survives_startup_settlement',status:'PASS'});
 await page.screenshot({path:'reports/browser-evidence/recovery-warning.png',fullPage:true});
 await page.locator('#nav [data-tab="equipment"]').click();
 assert.ok(await page.locator('#app').innerText().then(t=>t.includes('復旧しました')));
 cases.push({name:'recovery_warning_survives_navigation',status:'PASS'});
 await page.evaluate(async()=>{
  const g=window.__g1.game;
  await g.apply('FIXTURE_OVERFLOW_UI',s=>{s.overflow.weapon_c=2;return s;});
 });
 await page.locator('[data-action="reclaim"][data-template="weapon_c"]').click();await ready();
 assert.equal(await page.evaluate(()=>window.__g1.game.state.overflow.weapon_c),1);
 cases.push({name:'overflow_reclaim_ui_atomic',status:'PASS'});
 await page.reload();await ready();
 assert.equal(await page.evaluate(()=>window.__g1.game.state.overflow.weapon_c),1);
 cases.push({name:'overflow_reclaim_reload_keeps_count',status:'PASS'});
 // Clock rollback is fixture input. The confirmation resets the checkpoint without award.
 await page.evaluate(async()=>{
  const g=window.__g1.game;
  await g.apply('FIXTURE_CLOCK_ANOMALY_UI',s=>{s.last_ms=Date.now()+3600000;return s;});
 });
 await page.reload();await ready();
 await page.screenshot({path:'reports/browser-evidence/clock-anomaly.png',fullPage:true});
 await page.locator('#settings').click();await page.locator('[data-action="rebase"]').click();await page.locator('#dialog [data-action="confirm"]').click();
 await page.waitForFunction(()=>!window.__g1.game.busy&&!document.querySelector('#dialog').open);
 cases.push({name:'clock_rebase_ui_confirmed',status:'PASS'});
 await page.locator('#nav [data-tab="expedition"]').click();await page.locator('[data-action="fight"]').click();
 await page.waitForFunction(()=>window.__g1.battle.time>=2000);
 await page.locator('[data-action="pause"]').click();
 await page.screenshot({path:'reports/browser-evidence/battle-desktop.png',fullPage:true});
 assert.ok(await page.locator('#battle-event').innerText());
 cases.push({name:'live_battle_trace_display',status:'PASS'});
 await page.locator('[data-action="abort"]').click();
 assert.equal(await page.evaluate(()=>window.__g1.game.state.boss_history.gatekeeper?.attempts || 0),0);
 cases.push({name:'battle_abort_has_no_clear_record',status:'PASS'});
 assert.equal(external,0);assert.deepEqual(errors,[]);
 await writeFile('reports/recovery-ui-tests.json',JSON.stringify({date:new Date().toISOString(),overall:'PASS',cases,external_requests:external,page_errors:errors,scope:'Browser fixtures for corruption, overflow and clock rollback; actual UI interaction after setup'},null,2));
 console.log('Recovery/UI checks 7/7 PASS; external requests 0; page errors 0');
} finally {await context.close();await browser.close();}
