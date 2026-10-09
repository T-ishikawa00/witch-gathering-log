import { DATA } from './content.js';
import { fight, makeStats } from './core/combat.js';
import * as P from './core/progression.js';
import { Game } from './game.js';

const $ = s => document.querySelector(s);
const escape = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const slotNames = { weapon:'武器', armor:'鎧', gloves:'手', boots:'靴', charm:'護符', ring:'指輪' };
const familyNames = { c:'会心', p:'毒', g:'防御反撃' };
const routeNames = { ash:'灰の街道', fen:'苔の湿原', ruins:'旧城の回廊' };
const bossTips = {
  gatekeeper:'2.5秒ごとに一撃。24秒から激昂し、毎秒25ポイントずつ攻撃倍率が上がります。',
  stonebeast:'防御160の硬い殻。3秒ごとに一撃。55秒から毎秒16ポイントずつ激昂します。',
  sentinels:'4秒周期で4連撃。周期内1.6 / 2.2 / 2.8 / 3.4秒に攻撃。55秒から毎秒12ポイントずつ激昂します。'
};
const effectLabels = { hp:'HP', attack:'攻撃', armor:'防御', crit_bp:'会心率', crit_multiplier_bp:'会心倍率', haste_bp:'加速', block_bp:'ガード率', counter_bp:'反撃係数', poison_damage:'毒／層・秒', poison_duration_ms:'毒持続' };
const origins = { starter:'初期付与', trial:'初回クリア試用', balance:'検証用', loot:'探索入手', craft:'制作' };
const statKeys = ['hp','attack','armor','crit_bp','crit_multiplier_bp','block_bp','counter_bp','poison_damage','poison_duration_ms','attack_interval_ms'];
const formatStat = (k,v) => k==='crit_multiplier_bp'||k==='counter_bp' ? `${v/10000}倍` : k.endsWith('_bp') ? `${(v / 100).toFixed(v % 100 ? 2 : 0)}%` : k.endsWith('_ms') ? `${(v/1000).toFixed(3)}秒` : String(v);
const duration = ms => ms >= 3600000 ? `${(ms/3600000).toFixed(2)}時間` : `${Math.floor(ms/60000)}分${Math.floor(ms%60000/1000)}秒`;
const effectText = item => Object.entries(item.stats).map(([k,v]) => `${effectLabels[k]}＋${formatStat(k,v)}`).join(' / ');
const btn = (label, action, data = '', cls = 'secondary', disabled = false) => `<button class="${cls}" data-action="${action}" ${data} ${disabled?'disabled':''}>${label}</button>`;
let game, tab = 'return', boss = 'gatekeeper', battle = null, alert = '', selected = new Set(), dialogOpener, dialogOpenerSelector, focusAnchor;
let seed = 1001;
let speed = 1;
let currentProfile = 'experience';
const missing = state => state.equipped.filter(id => !state.inventory[id]);
const safeStats = () => { try { return makeStats(P.getLoadout(game.state)); } catch { return null; } };
function goal() {
  const h = game.state.boss_history;
  const remaining = Object.keys(DATA.bosses).filter(id => !(h[id]?.wins > 0));
  if (!remaining.length) return 'G1試作の確認範囲を完了';
  if (!h.gatekeeper?.wins) return '崩門の番人を倒す';
  return `${DATA.bosses[remaining[0]].name}に挑戦する`;
}
function goalBox() {
  return `<section class="goal"><span class="eyebrow">NEXT OBJECTIVE</span><h2>${goal()}</h2><p>${game.state.trial_unlocked?'毒・防御の試用12点を比較して、攻略の違いを確かめましょう。':'会心系6点を装備済み。まず番人の特性を読んで挑戦しましょう。'}</p><div class="milestones">${Object.entries(DATA.bosses).map(([id,b]) => `<span class="${game.state.boss_history[id]?.wins?'cleared':''}">${game.state.boss_history[id]?.wins?'✓':'○'} ${b.name}</span>`).join('')}</div>${game.state.g1_scope_complete?'<p class="small">G1の確認終了です。本編のエンディングではありません。装備変更と再戦を続けられます。</p>':''}</section>`;
}
function status() {
  const s = game.state;
  return `<div class="status-strip"><span>${currentProfile==='balance'?'バランス検証用の別セーブ':'導入付き体験モード'}</span><span>素材 <b data-testid="essence">${s.essence}</b> · 所持 ${Object.keys(s.inventory).length}/72 · 保留 ${Object.values(s.overflow).reduce((a,b)=>a+b,0)}</span></div>${s.debugSimulated?'<div class="debug-note">開発用の時間送りを使用したセーブです。実時間の放置検証と区別します。</div>':''}`;
}
function statsBlock(s) {
  if (!s) return '<div class="error">装備に欠損があります。欠損枠に所持装備を選び直してください。自動補完は行いません。</div>';
  return `<div class="stat-grid">${[['attack','攻撃'],['armor','防御'],['hp','HP'],['crit_bp','会心率'],['block_bp','ガード率'],['attack_interval_ms','攻撃間隔']].map(([k,label]) => `<div><small>${label}</small><strong>${formatStat(k,s[k])}</strong></div>`).join('')}</div>`;
}
function returnScreen() {
  const s = game.state, r = s.last_receipt;
  const focus = (r?.new_ids||[]).map(id=>s.inventory[id]).filter(Boolean).sort((a,b)=>DATA.slots.indexOf(DATA.items[a.template_id].slot)-DATA.slots.indexOf(DATA.items[b.template_id].slot)).slice(0,3);
  const remaining = DATA.offline.step_ms - s.remainders_ms[s.route];
  return `<div class="screen-head"><span class="eyebrow">01 / RETURN</span><h2>${r?.awarded_steps?'探索者の帰還':'次の戦利品を待つ間に'}</h2><p>現在の探索先 · ${routeNames[s.route]}</p></div>
  <section class="panel"><div class="row"><h3>探索の成果</h3><span class="save-badge">${game.busy?'保存中…':'保存済み · 世代 '+game.revision}</span></div>
  ${r?.status==='APPLIED'?`<p class="small">${r.source==='DEBUG_8_HOURS'?'開発用8時間送り':'実時間の精算'} · 経過 ${duration(r.raw_ms)} / 有効 ${duration(r.credited_ms)}${r.capped_ms?` / 上限超過 ${duration(r.capped_ms)}`:''}</p><div class="receipt-grid"><div><strong>${r.awarded_steps}</strong><span>抽選</span></div><div><strong>${r.new_ids.length}</strong><span>所持へ追加</span></div><div><strong>＋${r.essence_delta}</strong><span>素材</span></div></div><p class="small muted">同一固定装備の重複 ${r.converted}点を素材化 · 保留へ ${r.overflowed}点</p>`:'<p>初期装備6点は一度だけ付与されます。通常ドロップではありません。</p>'}
  ${!r?.awarded_steps?`<p>次の15分工程まで、有効探索時間があと ${duration(remaining)}必要です。</p>`:''}
  ${focus.length?`<div class="focus-items">${focus.map(i=>`<div><span>初入手・効果の比較候補</span><b>${DATA.items[i.template_id].name}</b></div>`).join('')}</div>`:''}
  ${btn('今の装備を確認','nav','data-tab="equipment"','primary')}
  </section><section class="panel"><h3>閉じている間も探索は進みます</h3><p>15分ごとに装備1点と素材5。1回の離席は24時間まで、端数は地域ごとに持ち越します。ボス再戦から追加の装備抽選は発生しません。</p>${btn('実時間の成果を精算','settle')}${btn('開発用：8時間分を計算','debug8','','debug-button')}<p class="small muted">開発操作です。実際に8時間待った記録にはなりません。</p></section>`;
}
function equipmentScreen() {
  const s = game.state, stats = safeStats();
  const names = s.equipped.map(id=>DATA.items[s.inventory[id]?.template_id]?.name||`欠損: ${id}`);
  return `<div class="screen-head"><span class="eyebrow">02 / EQUIPMENT</span><h2>組み替える、突破する。</h2><p>6枠を自由に変更できます。隠しセットボーナスはありません。</p></div>${statsBlock(stats)}
  <div class="equipment-grid">${DATA.slots.map((slot,i)=>btn(`<span class="item-icon">${['剣','鎧','手','靴','符','環'][i]}</span><span><small>${slotNames[slot]}</small><b>${escape(names[i])}</b><em>比較して変更 →</em></span>`,'choose',`data-slot="${slot}"`,'equipment-card')).join('')}</div>
  ${stats?`<details class="panel"><summary>現在の効果・発動条件</summary><p>通常攻撃時の会心 ${formatStat('crit_bp',stats.crit_bp)}、会心ダメージ ${stats.crit_multiplier_bp/10000}倍。${stats.poison_damage>0?`通常攻撃で毒1層、最大6層。構成全体で1層につき毎秒${stats.poison_damage}、防御無視。共有持続${stats.poison_duration_ms/1000}秒。`:'毒ダメージはありません。'} ガード時は被ダメージを55%軽減。${stats.counter_bp>0?`生存したガード時、防御の${stats.counter_bp/10000}倍を素ダメージとして反撃。敵防御で軽減し、会心・毒を追加発動しません。`:'反撃効果はありません。'}</p></details>`:''}
  <section class="panel"><h3>試用構成をまとめて比較</h3><p class="small">固定構成は比較の出発点です。各枠から混成に編集できます。</p><div class="button-row">${Object.entries(DATA.presets).map(([key,ids])=>btn({critical:'会心6点',poison:'毒6点',counter:'防御6点'}[key],'family',`data-family="${key}"`,'secondary',ids.some(t=>!Object.values(s.inventory).some(i=>i.template_id===t)))).join('')}</div></section>
  <section class="panel"><h3>保存構成 · 無料3枠</h3>${['slot1','slot2','slot3'].map((key,i)=>`<div class="preset-row"><label>${i+1}<input id="name-${key}" aria-label="構成${i+1}の名前" maxlength="32" value="${escape(s.preset_names[key]||'構成'+(i+1))}"></label><div class="button-row">${btn('現在を保存','savePreset',`data-key="${key}"`)}${btn('適用','applyPreset',`data-key="${key}"`,'secondary',!s.presets[key])}${btn('名前変更','renamePreset',`data-key="${key}"`,'quiet',!s.presets[key])}</div>${s.presets[key]?.some(id=>!s.inventory[id])?`<p class="error">欠損ID: ${s.presets[key].filter(id=>!s.inventory[id]).map(escape).join(', ')}</p>`:''}</div>`).join('')}</section>
  <section class="panel"><div class="row"><h3>所持品の保護・選別</h3><span>${Object.keys(s.inventory).length}/72</span></div><label class="toggle"><input type="checkbox" id="auto-duplicates" ${s.auto_duplicates?'checked':''}>新しく入手する同一固定装備の重複を自動で素材2へ</label><p class="small muted">初入手・装備中・ロック・保存構成参照・最後の1点を保持。既存の所持品を自動で分解しません。</p><div class="inventory-list">${Object.values(s.inventory).map(i=>{
    const t=DATA.items[i.template_id];
    const refs=s.equipped.includes(i.id)?'装備中':Object.values(s.presets).some(p=>p.includes(i.id))?'保存参照':'';
    return `<div class="inventory-row"><label><input type="checkbox" data-select="${escape(i.id)}" ${selected.has(i.id)?'checked':''}><span><b>${t.name}</b><small>${origins[i.origin]||'探索入手'} ${refs}${i.locked?' · ロック':''}</small></span></label>${btn(i.locked?'解除':'保護','lock',`data-id="${escape(i.id)}"`,'quiet')}${btn('比較','compare',`data-id="${escape(i.id)}"`,'quiet')}</div>`;
  }).join('')}</div><div class="button-row">${btn('選択品の分解を確認','bulk','','secondary',!selected.size)}${btn('保護を除く重複を確認','safeBulk')}</div></section>
  ${overflowSection()}
  <section class="panel"><h3>装備制作</h3><p>好きな固定装備1点を素材120で制作。素材不足・満杯なら消費しません。</p><label>制作する装備<select id="craft-template">${Object.entries(DATA.items).map(([id,i])=>`<option value="${id}">${slotNames[i.slot]} · ${i.name}</option>`).join('')}</select></label>${btn('素材120で制作を確認','craft')}</section>
  ${btn('ボスを選んで試す','nav','data-tab="expedition"','primary')}`;
}
function overflowSection() {
  const s=game.state;
  if (!Object.keys(s.overflow).length && !s.trial_pending.length) return '';
  return `<section class="panel"><h3>保留装備 · 消失していません</h3>${s.trial_pending.length?`<p>初回クリア試用 ${s.trial_pending.length}点を別枠で保全しています。</p>${btn('空き枠へ試用装備を受取','trialClaim')}`:''}${Object.entries(s.overflow).map(([t,n])=>`<div class="overflow-row"><b>${DATA.items[t].name} ×${n}</b><div class="button-row">${btn('1点取り出す','reclaim',`data-template="${t}"`)}${btn('1点を素材2へ','convert',`data-template="${t}"`)}</div></div>`).join('')}</section>`;
}
function expeditionScreen() {
  const s=game.state;
  return `<div class="screen-head"><span class="eyebrow">03 / EXPEDITION</span><h2>次に狙う装備は？</h2><p>探索先の変更時に旧地域を精算します。端数は元の地域に残ります。</p></div><div class="routes">${Object.entries(routeNames).map(([id,name])=>btn(`<span class="route-number">0${Object.keys(routeNames).indexOf(id)+1}</span><span><b>${name}</b><small>${familyNames[DATA.offline.route_families[id]]}系6種 · 15分で1点＋素材5</small><small>端数 ${duration(s.remainders_ms[id])}</small></span><span>${s.route===id?'探索中':'選択 →'}</span>`,'route',`data-route="${id}" aria-pressed="${s.route===id}"`,'route')).join('')}</div><details class="panel"><summary>現在の地域の候補6点</summary><ul>${DATA.slots.map(slot=>`<li>${DATA.items[slot+'_'+DATA.offline.route_families[s.route]].name}</li>`).join('')}</ul></details>
  <section class="panel"><h3>ボスを選ぶ</h3><p>敗北・中断による装備や素材の消費はありません。</p><div class="bosses">${Object.entries(DATA.bosses).map(([id,b])=>btn(`<span class="boss-symbol" aria-hidden="true">${{gatekeeper:'門',stonebeast:'殻',sentinels:'刃'}[id]}</span><span><b>${b.name}</b><small>HP ${b.hp} / 防御 ${b.armor}</small><small>${game.state.boss_history[id]?.wins?`✓ クリア済み · ${game.state.boss_history[id].wins}勝`:'未クリア'}</small></span>`,'boss',`data-boss="${id}" aria-pressed="${boss===id}"`,'boss')).join('')}</div><div class="boss-traits"><b>${DATA.bosses[boss].name}の特性</b><p>${bossTips[boss]}</p><p class="small muted">基本1ヒット ${DATA.bosses[boss].hit_damage}。制限90秒。会心・毒・反撃の専用無効化はありません。</p></div><label>再現用seed<input type="number" id="seed" min="0" max="4294967295" step="1" value="${seed}"></label>${btn('選んだボスへ挑戦','fight','','primary',Boolean(missing(s).length))}</section>`;
}
function resultAdvice(r) {
  if (r.win) return `今回の勝利まで ${duration(r.time_ms)}。${r.totals.poison?`毒が${r.totals.poison}ダメージ寄与。`:''}${r.totals.counter?`反撃が${r.totals.counter}ダメージ寄与。`:''}別の敵でも同じ結果になる保証はありません。`;
  if (r.hp_remaining>0) return '90秒の時間上限に到達。生存したまま敵HPが残りました。攻撃・手数・発動条件を比較してください。';
  const maxStacks=Math.max(0,...(r.trace||[]).filter(e=>e.kind==='poison').map(e=>e.stacks));
  return `HPが0になり敗北。敵ヒット${r.totals.boss_hits}回に対してガード${r.totals.blocks}回。${r.stats.poison_damage?`毒の観測最大層数は${maxStacks}、稼働${r.totals.poison_ticks}tick。`:''}防御・ガード・手数の変更が次戦にどう影響するか比較できます。`;
}
function resultScreen() {
  const saved=game.state.last_fight;
  if (!saved) return `<div class="screen-head"><span class="eyebrow">04 / RESULT</span><h2>まだ戦闘結果はありません</h2><p>実際の装備・seedから戦闘を計算します。</p></div>${btn('最初のボスを選ぶ','nav','data-tab="expedition"','primary')}`;
  const r=saved.result, t=r.totals;
  const reason=r.win?'突破':r.hp_remaining>0?'時間切れ':'敗北';
  const prev=game.state.previous_fight;
  return `<div class="screen-head"><span class="eyebrow">04 / RESULT</span><p>${DATA.bosses[saved.boss].name} · seed ${saved.seed}</p><h2 class="${r.win?'win':'loss'}" data-testid="outcome">${reason}</h2><p>${(r.time_ms/1000).toFixed(3)}秒 · 自HP ${r.hp_remaining} / 敵HP ${r.boss_hp_remaining}</p></div>
  <section class="panel"><h3>何が結果に影響したか</h3><div class="damage-bars">${[['normal','通常・会心'],['poison','毒'],['counter','反撃']].map(([key,name])=>`<div class="damage-row ${key}"><div class="row"><span>${name}</span><b>${t[key]}</b></div><progress class="damage-track" value="${t[key]}" max="${DATA.bosses[saved.boss].hp}"></progress></div>`).join('')}</div><dl class="result-numbers">${[['通常攻撃',t.attacks+'回'],['会心',t.crits+'回'],['敵ヒット',t.boss_hits+'回'],['ガード',t.blocks+'回'],['毒tick',t.poison_ticks+'回'],['被ダメージ',t.incoming],['実測DPS',(1000*(t.normal+t.poison+t.counter)/Math.max(1,r.time_ms)).toFixed(1)]].map(([k,v])=>`<div><dt>${k}</dt><dd>${v}</dd></div>`).join('')}</dl><p class="explanation">${resultAdvice(r)}</p>${statsBlock(r.stats)}<p class="small muted">この戦闘の構成 · ${saved.loadout.map(id=>DATA.items[id].name).join(' / ')}</p></section>
  ${prev?`<section class="panel"><h3>ひとつ前の戦闘との比較</h3><p>${DATA.bosses[prev.boss].name} · seed ${prev.seed} · ${prev.result.win?'突破':'敗北'} ${(prev.result.time_ms/1000).toFixed(3)}秒</p><div class="comparison-wrap"><table><thead><tr><th>指標</th><th>前回</th><th>今回</th></tr></thead><tbody>${['attack','armor','block_bp','poison_damage','attack_interval_ms'].map(k=>`<tr><td>${effectLabels[k]||'攻撃間隔'}</td><td>${formatStat(k,prev.result.stats[k])}</td><td>${formatStat(k,r.stats[k])}</td></tr>`).join('')}</tbody></table></div><p class="small muted">敵・seedが異なる比較は、構成だけの因果関係を示しません。</p></section>`:''}
  <div class="button-row">${btn('装備を見直す','nav','data-tab="equipment"','primary')}${btn('同じボスへ再挑戦','refight')}</div>${btn('別のボスを選ぶ','nav','data-tab="expedition"')}
  <details class="panel"><summary>戦闘ログ · 実ダメージ</summary><ol class="trace-log">${(r.trace||[]).map(e=>`<li>${(e.t/1000).toFixed(3)}秒 · ${eventName(e)} ${e.damage} · 自HP ${e.player_hp} / 敵HP ${e.boss_hp}</li>`).join('')}</ol></details>`;
}
function eventName(e) { return e.kind==='normal'?(e.critical?'会心':'通常攻撃'):e.kind==='boss_hit'?(e.blocked?'ガード':'敵攻撃'):e.kind==='poison'?`毒 ${e.stacks}層`:'反撃'; }
function battleScreen() {
  const b=DATA.bosses[battle.boss];
  return `<div class="screen-head"><span class="eyebrow">BATTLE / ${battle.seed}</span><h2>${b.name}</h2><p>表示速度だけを変更します。計算結果・抽選数は不変です。</p></div><section class="battle-scene"><div class="fighter explorer"><span aria-hidden="true">旅</span><b>探索者</b></div><span class="versus">×</span><div class="fighter enemy"><span aria-hidden="true">${{gatekeeper:'門',stonebeast:'殻',sentinels:'刃'}[battle.boss]}</span><b>${b.name}</b></div><div class="hp"><label>探索者HP <b id="player-hp"></b></label><progress id="player-bar" aria-label="探索者HP" max="${battle.result.stats.hp}"></progress></div><div class="hp"><label>敵HP <b id="boss-hp"></b></label><progress id="boss-bar" aria-label="敵HP" max="${b.hp}"></progress></div><p id="battle-time"></p><p id="rage"></p><div id="battle-event" aria-live="off"></div></section><section class="panel"><label>表示速度<select id="speed"><option value="1" ${speed===1?'selected':''}>1倍</option><option value="2" ${speed===2?'selected':''}>2倍</option></select></label><div class="button-row">${btn(battle.paused?'再開':'一時停止','pause')}${btn('演出を省略して結果へ','skip')}</div>${btn('現在の戦闘状況を確認','battleStatus','','quiet')}${btn('中断して装備へ戻る','abort','','quiet')}<p class="small muted">仮素材の戦闘表示です。途中の装備変更はできません。中断ではクリア履歴を保存しません。</p></section>`;
}
function elementSelector(el) {
  if (!el || el===document.body) return null;
  if(el.id)return '#'+CSS.escape(el.id);
  const attrs=['data-action','data-tab','data-slot','data-id','data-key','data-family','data-select'];
  const parts=attrs.filter(k=>el.hasAttribute(k)).map(k=>'['+k+'="'+CSS.escape(el.getAttribute(k))+'"]');
  return parts.length?el.tagName.toLowerCase()+parts.join(''):null;
}
function restoreDialogFocus(){
  if(dialogOpener?.isConnected)dialogOpener.focus();
  else if(dialogOpenerSelector)document.querySelector(dialogOpenerSelector)?.focus();
}
function render() {
  if (!game?.state) return;
  if(!$('#dialog').open)focusAnchor=elementSelector(document.activeElement)||focusAnchor;
  const errors=[alert,...game.warnings].filter(Boolean);
  if(game.timeAnomaly) errors.push('TIME_ANOMALY：時計が戻っています。設定から確認付きで「現在の時刻から再開」できます。');
  if(game.startError) errors.push('自動精算の保存に失敗しました。セーブは保全され、実時間精算で再試行できます。');
  $('#app').setAttribute('aria-busy', String(game.busy));
  $('#app').innerHTML=`${status()}${errors.map(e=>`<div role="alert" class="error">${escape(e)}</div>`).join('')}<div class="workspace"><aside>${goalBox()}<section class="side-note"><span class="eyebrow">THE CORE LOOP</span><p>帰還 → 比較 → 変更 → 再挑戦</p><p class="small muted">固定性能・同段階の装備を比較するG1。面白さと長期継続は、人による確認を待っています。</p></section></aside><div class="screen" id="screen">${battle?battleScreen():({return:returnScreen,equipment:equipmentScreen,expedition:expeditionScreen,result:resultScreen}[tab])()}</div></div>`;
  $('#nav').innerHTML=['return','equipment','expedition','result'].map((key,i)=>`<button data-action="nav" data-tab="${key}" aria-current="${tab===key?'page':'false'}" ${battle?'disabled':''}><span>0${i+1}</span>${['帰還','装備','探索','結果'][i]}</button>`).join('');
  document.querySelectorAll('#app button, #app input, #app select').forEach(e=>{ if(game.busy)e.disabled=true; });
  if(battle)updateBattle();
  if(!game.busy&&!$('#dialog').open&&focusAnchor)document.querySelector(focusAnchor)?.focus({preventScroll:true});
}
function showDialog(title, body, actions) {
  dialogOpener=document.activeElement;
  if(!$('#dialog').open)dialogOpenerSelector=elementSelector(dialogOpener);
  $('#dialog-body').innerHTML=`<span class="eyebrow">EXPLORER'S NOTEBOOK</span><h2 id="dialog-title">${title}</h2>${body}`;
  $('#dialog-actions').innerHTML=actions;
  if(!$('#dialog').open)$('#dialog').showModal();
  $('#dialog-actions button').focus();
}
function closeDialog() { $('#dialog').close(); restoreDialogFocus(); }
$('#dialog').addEventListener('close',restoreDialogFocus);
let pendingDialogAction=null;
function confirm(title,body,fn,label='実行する') {
  pendingDialogAction=fn;
  showDialog(title,body,btn(label,'confirm','','primary')+btn('変更せず閉じる','cancel'));
}
function compareIds(ids, title='装備の変更を比較') {
  const before=game.state, next=structuredClone(before); next.equipped=ids;
  let a,b;
  a=safeStats();
  try{b=makeStats(P.getLoadout(next));}catch{b=null;}
  const stillMissing=next.equipped.filter(id=>!next.inventory[id]);
  const changed=ids.filter((id,i)=>id!==before.equipped[i]);
  const source=JSON.stringify(before.equipped);
  const table=b?`<div class="comparison-wrap"><table><thead><tr><th>指標</th><th>現在</th><th>変更後</th></tr></thead><tbody>${statKeys.map(k=>`<tr><td>${effectLabels[k]||'攻撃間隔'}</td><td>${a?formatStat(k,a[k]):'欠損'}</td><td class="${a&&b[k]!==a[k]?'changed':''}">${formatStat(k,b[k])}</td></tr>`).join('')}</tbody></table></div>`:`<p class="error">まだ欠損している枠: ${stillMissing.map(escape).join(', ')}。選んだ1枠を先に修復します。全6枠が揃うまで構成全体の数値を計算できません。</p>`;
  confirm(title,`<p>${changed.length?changed.map(id=>`<b>${DATA.items[next.inventory[id].template_id].name}</b>`).join(' / '):'現在と同じ構成です。'}</p>${table}<p>上昇・低下の両方を確認してください。攻撃力だけで最適解は決まりません。</p><p class="small">毒は通常攻撃時に層を追加。反撃はガード後に生存した場合だけ発動します。</p>`,async()=>{
    await game.apply('EQUIPMENT_CHANGE',s=>{
      if(JSON.stringify(s.equipped)!==source)throw new Error('別画面で構成が変わりました。最新構成で比較し直してください。');
      for(let i=0;i<ids.length;i++){if(ids[i]===s.equipped[i])continue;if(!s.inventory[ids[i]])throw new Error('欠損ID: '+ids[i]);s=P.equip(s,ids[i]);}return s;
    },{templates:ids.map(id=>next.inventory[id]?.template_id||'MISSING')});
    selected.clear();tab='equipment';
  },'この変更を適用する');
}
function choose(slot) {
  const items=Object.values(game.state.inventory).filter(i=>DATA.items[i.template_id].slot===slot);
  showDialog(`${slotNames[slot]}を選ぶ`, `<p>装備を選ぶと、構成全体の比較を表示します。</p><div class="choice-list">${items.map(i=>btn(`<b>${DATA.items[i.template_id].name}</b><small>${effectText(DATA.items[i.template_id])}</small><small>${origins[i.origin]||'探索'} ${game.state.equipped.includes(i.id)?'· 装備中':''}</small>`,'compare',`data-id="${escape(i.id)}"`,'choice')).join('')}</div>`,btn('閉じる','cancel'));
}
function safeDismantleIds() {
  const accepted=[];
  for(const id of Object.keys(game.state.inventory))if(P.previewDismantle(game.state,[...accepted,id]).allowed)accepted.push(id);
  return accepted;
}
function bulk(ids, excluded=0) {
  const preview=P.previewDismantle(game.state,ids);
  const reasons={locked:'ロック',equipped_or_preset:'装備中・保存構成参照',final_copy:'最後の1点'};
  const body=`<p>対象${ids.length}点 / 保護で除外${excluded}点 / 得る素材${preview.essence_delta}</p>${preview.allowed?`<p>${ids.map(id=>DATA.items[game.state.inventory[id].template_id].name).join(' / ')||'分解できる重複品はありません。'}</p>`:`<div class="error">全体を拒否しました。${preview.rejected.map(r=>`${DATA.items[game.state.inventory[r.id]?.template_id]?.name||r.id}：${reasons[r.reason]||r.reason}`).join('、')}</div><p>保護を含む選択を、一部だけ分解することはありません。</p>`}`;
  if(preview.allowed&&ids.length)confirm('一括分解の最終確認',body,async()=>{await game.apply('DISMANTLE',s=>P.dismantle(s,ids),{count:ids.length});selected.clear();},'再検証して分解する');
  else showDialog('一括分解の確認',body,btn('閉じる','cancel'));
}
function settings() {
  showDialog('設定・ローカル記録',`<p>進行はこのブラウザのIndexedDBに保存します。別ブラウザ・別のポート・再インストール時の自動移行はありません。</p><p>操作ログは端末内だけに保持し、氏名・連絡先・外部Analyticsを保存しません。</p><div class="button-column">${btn('観察用ログをJSONで保存','exportLog')}${btn('現在のセーブをJSONで保存','exportSave')}${btn(currentProfile==='experience'?'バランス検証モードへ（別セーブ）':'体験モードへ（元のセーブ）','profile')}${btn('現在の時刻から再開を確認','rebase')}</div><p class="small muted">バランス検証は最初から18点を利用できます。体験モードとデータを分けています。時計基準の更新は報酬なしです。</p><details><summary>G1開発用の保存故障注入</summary><p class="small">次の保存1回だけを失敗させます。製品版から除外する開発機能です。</p><div class="button-column">${btn('次の保存を容量不足にする','fault','data-fault="quota"')}${btn('次の保存をコミット前に中断','fault','data-fault="before_commit"')}${btn('次の保存完了直後の確認を中断','fault','data-fault="after_commit"')}</div></details>`,btn('閉じる','cancel'));
}
function download(name,value) {
  const url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));
  const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function startFight(bossId=boss) {
  const value=Number($('#seed')?.value??seed);
  if(!Number.isSafeInteger(value)||value<0||value>0xffffffff)throw new Error('seedは0〜4294967295の整数を入力してください。');
  seed=value; boss=bossId;
  const loadout=P.getLoadout(game.state),result=fight(loadout,boss,seed,{trace:true});
  battle={boss,seed,loadout,result,time:0,paused:false,finishing:false,lastWall:performance.now()};
  game.event('BOSS_CHALLENGE',{boss,seed});$('#announcer').textContent=DATA.bosses[boss].name+'との戦闘を開始しました。';tab='result';render();requestAnimationFrame(tick);
}
function updateBattle() {
  if(!battle||!$('#player-hp'))return;
  const visible=battle.result.trace.filter(e=>e.t<=battle.time),event=visible.at(-1);
  const hp=event?.player_hp??battle.result.stats.hp,bhp=event?.boss_hp??DATA.bosses[battle.boss].hp;
  $('#player-hp').textContent=hp;$('#player-bar').value=hp;$('#boss-hp').textContent=bhp;$('#boss-bar').value=bhp;
  $('#battle-time').textContent=`${(battle.time/1000).toFixed(1)} / 90秒`;
  const b=DATA.bosses[battle.boss];
  const rage=100+Math.floor(Math.max(0,battle.time-b.enrage_start_ms)*b.enrage_bp_per_second/1000)/100;
  $('#rage').textContent=`敵攻撃倍率 ${rage.toFixed(1)}%${battle.time>b.enrage_start_ms?' · 激昂':''}`;
  $('#battle-event').textContent=event?`${eventName(event)} · ${event.damage}ダメージ`:'初撃の間隔を待っています';
  $('#battle-event').className=event?.kind||'normal';
}
function tick(wall) {
  if(!battle)return;
  if(!battle.paused&&!battle.finishing)battle.time=Math.min(battle.result.time_ms,battle.time+(wall-battle.lastWall)*speed);
  battle.lastWall=wall;updateBattle();
  if(battle.time>=battle.result.time_ms&&!battle.finishing){finishBattle();return;}
  requestAnimationFrame(tick);
}
async function finishBattle() {
  if(!battle||battle.finishing)return;
  battle.finishing=true;
  try { await game.finishFight(battle.boss,battle.result,battle.seed,battle.loadout);$('#announcer').textContent=`${DATA.bosses[battle.boss].name}、${battle.result.win?'突破':'敗北'}。結果を保存しました。`;battle=null;alert='';tab='result'; }
  catch(error){ battle.finishing=false;battle.paused=true;alert='結果の保存に失敗しました。演出省略で保存を再試行できます。 '+error.message; requestAnimationFrame(tick); }
  render();
}
async function boot(profile='experience') {
  currentProfile=profile;game=new Game(profile);game.onChange(render);
  // Test harness can inspect real game state and inject storage faults. No network or telemetry.
  window.__g1={get game(){return game;},get battle(){return battle;},version:'G1-0.1.0'};
  try{await game.start();alert='';render();}
  catch(error){$('#app').innerHTML=`<div class="error" role="alert"><h2>セーブを読み込めません</h2><p>${escape(error.code||'SAVE_FAILED')} · ${escape(error.message)}</p><p>初期化で上書きせず停止しました。ブラウザのデータを削除せず、保存状態を確認してください。</p>${btn('再読込して再試行','reload')}</div>`;}
}
document.addEventListener('change',async event=>{
  const t=event.target;
  try{
    if(t.id==='speed'){speed=Number(t.value);game.event('DISPLAY_SPEED',{speed});}
    if(t.id==='seed'){const n=Number(t.value);if(Number.isSafeInteger(n)&&n>=0&&n<=0xffffffff)seed=n;}
    if(t.id==='auto-duplicates')await game.apply('AUTO_DUPLICATES',s=>P.setAutoDuplicates(s,t.checked));
    if(t.dataset.select){if(t.checked)selected.add(t.dataset.select);else selected.delete(t.dataset.select);render();}
  }catch(e){alert=e.message;render();}
});
document.addEventListener('click',async event=>{
  const el=event.target.closest('button');if(!el||el.disabled)return;
  const action=el.dataset.action;if(!action)return;
  try{
    alert='';
    if(action==='cancel'){closeDialog();return;}
    if(action==='confirm'){
      el.disabled=true;try{await pendingDialogAction();closeDialog();render();}catch(e){el.disabled=false;$('#dialog-body').insertAdjacentHTML('beforeend',`<p class="error" role="alert">${escape(e.message)}</p>`);}return;
    }
    if(battle&&!['pause','skip','abort','battleStatus'].includes(action))return;
    if(action==='nav'){tab=el.dataset.tab;render();}
    if(action==='settle'){await game.settle();game.startError=null;}
    if(action==='debug8')await game.debugAdvance();
    if(action==='choose')choose(el.dataset.slot);
    if(action==='compare'){const ids=[...game.state.equipped];ids[DATA.slots.indexOf(DATA.items[game.state.inventory[el.dataset.id].template_id].slot)]=el.dataset.id;compareIds(ids);}
    if(action==='family'){const ids=DATA.presets[el.dataset.family].map(t=>Object.values(game.state.inventory).find(i=>i.template_id===t).id);compareIds(ids,'試用構成の変更を比較');}
    if(action==='savePreset'){const key=el.dataset.key,name=$('#name-'+key).value;const fn=()=>game.apply('PRESET_SAVE',s=>P.savePreset(s,key,name,true));if(game.state.presets[key])confirm('保存構成を上書き',`<p>「${escape(name)}」を現在の6点で上書きします。以前の参照による保護が解除される場合があります。</p>`,fn,'上書きして保存');else await fn();}
    if(action==='applyPreset'){const ids=game.state.presets[el.dataset.key];compareIds(ids,'保存構成を比較して適用');}
    if(action==='renamePreset'){const key=el.dataset.key,name=$('#name-'+key).value;await game.apply('PRESET_RENAME',s=>P.renamePreset(s,key,name));}
    if(action==='lock')await game.apply('ITEM_LOCK',s=>P.setLocked(s,el.dataset.id,!s.inventory[el.dataset.id].locked));
    if(action==='bulk')bulk([...selected]);
    if(action==='safeBulk'){const ids=safeDismantleIds();bulk(ids,Object.keys(game.state.inventory).length-ids.length);}
    if(action==='craft'){const id=$('#craft-template').value;confirm('制作の確認',`<p>${DATA.items[id].name}を素材120で制作します。</p>`,()=>game.apply('CRAFT',s=>P.craft(s,id),{template:id}),'素材120で制作する');}
    if(action==='reclaim')await game.apply('OVERFLOW_RECLAIM',s=>P.reclaimOverflow(s,el.dataset.template));
    if(action==='convert')confirm('保留品の素材化',`<p>${DATA.items[el.dataset.template].name} 1点を素材2へ。最後の1点を保護します。</p>`,()=>game.apply('OVERFLOW_CONVERT',s=>P.convertOverflow(s,el.dataset.template)),'素材化する');
    if(action==='trialClaim')await game.apply('TRIAL_CLAIM',s=>P.claimTrialItems(s));
    if(action==='route')await game.changeRoute(el.dataset.route);
    if(action==='boss'){boss=el.dataset.boss;render();}
    if(action==='fight')startFight();
    if(action==='refight')startFight(game.state.last_fight.boss);
    if(action==='skip'){battle.time=battle.result.time_ms;await finishBattle();}
    if(action==='battleStatus')$('#announcer').textContent=`探索者HP ${$('#player-hp').textContent}、敵HP ${$('#boss-hp').textContent}、${$('#battle-time').textContent}、${$('#rage').textContent}。${$('#battle-event').textContent}`;
    if(action==='pause'){battle.paused=!battle.paused;battle.lastWall=performance.now();render();}
    if(action==='abort'){game.event('BATTLE_ABORT');battle=null;tab='equipment';render();}
    if(action==='exportLog')download('idle-loot-g1-observation.json',game.logExport());
    if(action==='exportSave')download('idle-loot-g1-save.json',game.state);
    if(action==='profile'){closeDialog();selected.clear();tab='return';await boot(currentProfile==='experience'?'balance':'experience');}
    if(action==='rebase')confirm('現在の時刻から再開',`<p>問題区間の報酬を付与せず、現在のUTC時刻を新しい基準にします。装備・素材・地域の端数は維持します。開発時間送りのオフセットは維持します。</p>`,()=>game.rebaseClock(),'報酬なしで基準を更新');
    if(action==='fault'){game.repo.fault=el.dataset.fault;closeDialog();alert=`開発故障注入 ${el.dataset.fault}：次の保存1回が対象です。`;render();}
    if(action==='reload')location.reload();
    if(!$('#dialog').open)render();
  }catch(error){alert=error.message;$('#announcer').textContent=alert;render();}
});
$('#settings').addEventListener('click',()=>{if(!battle)settings();});
// No background battle loop. On return, only elapsed exploration time is settled.
document.addEventListener('visibilitychange',()=>{
  if(document.hidden){if(battle){battle.paused=true;game.event('BATTLE_PAUSE_HIDDEN');render();}}
  else if(game?.state&&!game.busy&&!battle)game.settle('REAL_TIME_RESUME').catch(e=>{alert=e.message;render();});
});
await boot();
