from pathlib import Path
import json,hashlib,re,html
ROOT=Path(__file__).resolve().parents[1]
r=json.loads((ROOT/'results/EXPERIMENT_RESULTS.json').read_text());sc=r['scenarios']
receipt=json.loads((ROOT/'results/PROGRESSION_RECEIPT.json').read_text())
findings=[
 {'id':'F01','severity':'HIGH','category':'SOURCE_FORMULA_BEHAVIOUR','title':'初期強化の費用があるのに能力が変化しない',
  'evidence':'R2 item_primaryは装備単位で切り捨て。威力14の武器は+0/+1/+2/+3で14/14/14/15。初期の手袋と指環は+3まで全基礎値が同じ。',
  'action':'現行値を凍結しない。固定小数点化・表示増分・強化単位/最低増分を別overlayで比較し、+1から実効改善が分かる規則を選ぶ。今回の実験は元式のまま。'},
 {'id':'F02','severity':'HIGH_SCOPE','category':'GATE_REACHABILITY','title':'古樹の初回戦では毒杖/結界杖分岐や覚醒を使えない',
  'evidence':'EQ_W_G1、覚醒I、研究2、研成IIはG_R01_B以降。EQ_W_P1はG_R02_A以降。森の初回戦へ持ち込むのは未来装備。',
  'action':'初回森は役割・配分の導入として評価。武器分岐の評価は撃破後の再戦/次地域へ分離。初回攻略に未来素材を要求しない。'},
 {'id':'F03','severity':'MEDIUM_HIGH','category':'CANDIDATE_BALANCE','title':'古樹の仮火力に対する勝率の感度が大きい',
  'evidence':'同じ50seed、12時間・守備支援装備。仮火力190の42/50勝に対して209では5/50勝。HP12500は同じ。',
  'action':'敵の数値は固定しない。標的偏り・回復周期・パーティー被害のログを比較し、複数の準備経路が成立する帯を詰める。'},
 {'id':'F04','severity':'SPEC_GAP','category':'TIMING_AMBIGUITY','title':'通常攻撃の「間隔」が開始か命中か曖昧',
  'evidence':'R2 combat.basic_first_hit_at_msと技能windup、本文のタイマー到達後に実行という表現に解釈の余地。2解釈を別モードで比較。',
  'action':'本案は初弾/次弾の命中可能時刻を基準にする。未承認の解釈であり、正本の明示改訂が必要。'},
 {'id':'F05','severity':'SPEC_GAP','category':'INTRO_FIXTURE','title':'導入報酬の品質・qはあるが副効果の種類と段階配布が未指定',
  'evidence':'R3は総EXP920・粉30・4素材各12、Q2杖raw_q350のみ。本案はAF_POWER/AF_HP/AF_DEFを固定試験入力にした。',
  'action':'今回の副効果は承認済みにしない。導入戦と配布順は本番UI付きで別に確定。'},
 {'id':'F06','severity':'UX_REVIEW','category':'DROPS','title':'共用装備は装備者によって副効果が働かない場合がある',
  'evidence':'R2は対応可能な仲間がいれば共用候補に含める。本試験の護符には呪毒効果があり、猫/鍛冶師に渡しても呪毒は発生しない。',
  'action':'無効効果・適性を装備比較で明示し、総合戦力の上矢印だけで誤誘導しない。'}
]
(ROOT/'data/FINDINGS_R4.json').write_text(json.dumps(findings,ensure_ascii=False,indent=2)+'\n')
lines=["# 魔女の採集帳｜2人→4人 初回攻略の接続検証 R4", "", "2026-10-09 / G2-C / 参照モデル・レビュー用。ゲーム本体の改変、素材制作、iPhone動作検証ではない。", "",
"## 1. 結論", "",
"素材と経験値を得て装備を制作し、その装備でボスと戦い、実際に勝った場合だけ進行・素材を記録する接続を作った。以前のR3準備モデルのように、所定の資源が揃えば勝利したと仮定する方式ではない。", "",
"一方、初期強化の端数切り捨てと初回攻略に使える装備範囲に重要な課題がある。接続の再現はできたが、最終バランスは不採用ではなく保留。本番の面白さ/収益性を判定するデータではない。", "",
"## 2. 元資料・今回の仮定・未実施を分離", "",
"|区分|内容|", "|---|---|",
"|変更しなかった入力|成長R2の能力・スキル係数・CD・装備/副効果・レシピ費用、経済R3の供給量・抽選・初回報酬、世界R1のIDと解放順。source/は原本と同じSHA。|",
"|今回だけの仮設定|2ボスのHP・威力・防護・行動間隔、初期アクティブ使用可、通常攻撃の時刻解釈、連撃予測、導入固定杖の副効果種類。data/LOCAL_CANDIDATES.jsonへ分離。|",
"|モデルの対象|根絡みの大猪に2人で挑戦→実勝利の記録→弟子と鍛冶師の別加入→素材収集/制作→古樹に4人で挑戦→実勝利の記録。|",
"|明示した開始条件|R3の導入4課題は完了済みの入力。通常敵の導入戦や深部初回探索の戦闘は未実装で、明示したクリアfixtureを使う。20〜30分の操作体験を測ったわけではない。|",
"|対象外|複数敵全般、覚醒以降の全効果、R02〜R05の敵、実UI・アート・実機・実DB/電源断・広告SDK・課金・長期継続率。|", "",
"入力の読み取り経路は source/growth_r2 と source/economy_r3。新コードは tools/battle_model.py（整数msのイベント処理）と tools/progression_bridge.py（素材・装備・勝利記録の接続）。全体を完成ゲームエンジンと呼ばない。", "",
"## 3. 今回の敵数値は検証用", "",
"|対象|Lv|HP|威力|防護|行動|", "|---|---:|---:|---:|---:|---|",
"|根絡みの大猪|6|2,300|115|42|1.8秒予告→2.6倍単体突進→3秒後隙＋1.4秒休止。最初の予告1.4秒。|",
"|苔冠の古樹|12|12,500|190|105|0.75倍×3回の単体連撃と、1.5倍の全体枝打ちを交互に使う。各予告/後隙はJSON参照。|", "",
"敵LvをプレイヤーLvへ追従させない。いずれも毒完全無効なし、戦闘上限120秒。結果が良くなるまで旧資料の味方ステータスや費用を書き換えてはいない。敵候補自体が未確定なので、勝率を既存ゲームの実測と取り違えない。", "",
"## 4. 2人で最初の中ボス", "",
"導入完了入力はLv6、初期の魔女と猫のみ。弟子の回復、鍛冶師のかばう、未来の防具、覚醒は持ち込まない。", "",
"|状態|勝利/試行|勝利時の中央戦闘秒数|", "|---|---:|---:|" ]
for key,label in [('A_START_L1','開始時相当Lv1・初期武器'),('A_INTRO_Q2','導入報酬後Lv6・固定希少杖'),('A_INTRO_PLUS1','上と同じ杖を＋1'),('A_INTRO_PLUS3','上と同じ杖を＋3')]:
 x=sc[key];lines.append(f"|{label}|{x['wins']}/{x['n']}|{x['win_seconds_p50'] if x['win_seconds_p50'] is not None else '—'}|")
lines += ["", "この条件では導入報酬で勝ちに届く一方、＋1は強化費5粉を払っても元と能力が同じ。Lv1対照は開始直後にこのボスを倒す条件ではなく、育成差を確かめるための負例。", "",
"## 5. 大猪の勝利から4人へ", "",
"勝利後にG_R01_Aと根絡みの牙1個を一度だけ保存する。帰宅で弟子、深部で鍛冶師という別加入イベントを処理し、EXP920に合わせ、初期武器を一度だけ付与。全員が加入したときだけ古樹初回戦を許可する。", "",
"加入に稀少素材や追加ガチャは不要。遠征のXPは全員へ同量、素材と装備は隊に一度だけ。深部ルートの確認は、このモデルでは明示的な未プレイfixture。", "",
"## 6. 4人で古樹：素材の使い道を比較", "",
"守備支援案は採集衣2個・お守り2個を制作。攻撃寄り案は手袋2個・お守り2個。どちらも必要材料計96、導入で持っていた分を除き72個＝6時間の指定採集で揃う。粉102と自然装備12個も並行して得る。", "",
"比較を制御するため、自然装備は台帳に保存するが装備せず、分解収益も使わない。制作の副効果は実際のR2 create_itemで固定seedから生成し、今回の試験用に都合のよい値を手で足していない。導入杖の副効果種類だけは前述の未定義補完。", "",
"|状態|Lv|採集時間|勝利/100|勝利時の中央秒数|", "|---|---:|---:|---:|---:|" ]
for key,label in [('B_JOINED_NO_WAIT','加入直後・初期武器中心'),('B_PROTECT_6H','守備支援4点を制作'),('B_PROTECT_12H','同じ4点＋レベル成長'),('B_PROTECT_24H','同じ4点＋さらにレベル成長'),('B_OFFENSE_12H','同時間・攻撃寄り4点'),('B_OFFENSE_24H','攻撃寄り4点＋成長')]:
 x=sc[key];lines.append(f"|{label}|{x['level']}|{x['credited_h']:g}時間|{x['wins']}|{x['win_seconds_p50'] if x['win_seconds_p50'] is not None else '—'}|")
lines += ["", "時間は大猪攻略後の有効な素材収集時間。導入操作・ボス戦を眺める時間・UIの判断・未計上の生活時間を含むクリア予測ではない。6/12/24時間を強制する通行ゲートもない。", "",
"### 同じ装備を誰に持たせるか", "",
f"同Lv9・同じ4個体・同じ素材消費・同じ100seedで、守備支援の配分は{sc['B_PROTECT_12H']['wins']}/100勝、配分を変えた対照は{sc['B_SAME_ITEMS_REALLOCATED_12H']['wins']}/100勝。", "",
"前者は衣をアイラ/ルナへ、お守りをエルナ/ルナへ。後者は衣をエルナ/ルナへ、お守りをアイラ/猫へ。プレイヤーが触るのは装備であり、AI作戦や手動回復はない。共用品の副効果の適性も変わるので、配分差は単純なHP差だけではない。", "",
"これは装備配分が結果に影響する証拠であって、最適構成を証明する全探索でも面白さの証明でもない。守備支援案と攻撃寄り案は、ともに24時間相当の成長では試験内100/100勝（再配分対照の24時間条件は未実施）。初回古樹で毒杖/結界杖2枝の比較ができたとは主張しない。", "",
"## 7. 診断用の比較", "",
"回復等を止めるスイッチは検証コードだけのもので、プレイヤー向け設定にはしない。守備支援12時間の同条件で、支援をすべて無効にすると50試行中0勝、回復とその派生支援を止めても0勝。毒なしでは8勝。仲間の働きがダメージ・被害・回復ログへ現れている。", "",
"仮敵の数値感度は大きい。同じ別50seedで、古樹HPを12,500に固定したまま威力190では42勝、209では5勝。『今の数値で大丈夫』と凍結する判断には進まない。", "",
"通常攻撃の時間の解釈も比較した。命中可能時刻を間隔の基準にした案と、行動開始時刻を基準にした案では、別の50seedで結果が変わる。この違いはドット絵のフレーム数ではなく戦闘仕様として確定する必要がある。", "",
"制作副効果は20種の固定seed、各10戦で比較した。この小標本だけでドロップのバランスを保証しない。希少な初期杖の抽選1,000個には、今回の2ボスに対して働かない耐性2つの個体が14個あった。『使い道がない副効果』を万能に強化するのではなく、対象と用途が分かるUIと導入固定報酬を検討する。", "",
"## 8. 修正・判断が必要な点", ""]
for f in findings:
 lines += [f"### {f['id']} {f['title']}（{f['severity']}）", "",f['evidence'],"", "**対応案：** "+f['action'],""]
lines += ["## 9. 通し処理と安全性の検査", "",
"古樹の実計算で勝利したreceiptを入力し、G_R01_Bと生木核1個を保存。同じreceiptの再送は状態ハッシュが変わらず、二重配布しない。失敗した戦闘、改ざんしたreceipt、装備変更後の古い戦闘結果では解放しない。", "",
"勝利後にも研究・覚醒・研成を勝手に購入しない。結界杖は勝利後の素材を払って初めて進化でき、元の個体ID・品質・副効果を保つ。ボス素材を使い切っても地域の永久解放は消えない。", "",
"これはメモリ内の原子的差替えモデル。実DBの耐障害性・悪意あるチートの防止・署名の安全性ではない。保存中の実電源断テストは別。", "",
"|検査|結果|境界|", "|---|---:|---|",
"|旧成長R2テスト再実行|55件PASS|新しい4人戦の合格数ではない|",
"|旧経済R3テスト再実行|61件PASS|元モデルの回帰確認|",
"|今回の接続・戦闘テスト|53件PASS|既知の端数問題を検出・再現するテストを含む|",
"|比較バッチ|2,200戦|仮敵・固定条件。実ユーザーの勝率ではない|",
"|代表ログ|大猪/古樹各1戦|result、input fingerprint、時系列ログを同梱|", "",
"テストPASSは数式・契約どおりに計算できたという意味であり、数式が望ましいことを保証しない。端数による無成長は『不具合がなかった』ではなく、再現された設計課題。", "",
"## 10. 次の判断", "",
"1. 初期強化の無効段階を修正する候補を別overlayで比較する。", "2. 森初回は配分・役割連携の導入、武器分岐は撃破後という評価範囲を明確にする。", "3. 敵数値・回復周期・通常攻撃時刻を調整し、同じ資源条件と乱数群で再検証する。", "",
"今回は原画/アニメーション/エンジン選定/広告課金へ作業範囲を広げない。MacのG1コード、現在のCodexアセット制作、保存済み正本は一切変更していない。", "",
"この結果を参照設計へ取り込む場合も、まず保存・再現・レビューのみ。4人戦と全地域の本番統合を自動承認したことにしない。", ""]
report='\n'.join(lines)
(ROOT/'REPORT_R4.md').write_text(report)
# Minimal Markdown-to-HTML for this controlled report; no external resources.
def inline(t):
 t=html.escape(t)
 t=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',t)
 return t
parts=[];table=[]
def flush():
 if table:
  rows=[x for x in table if not re.match(r'^\|[ :\-]+(?:\|[ :\-]+)*\|?$',x)]
  cells=[x.strip().strip('|').split('|') for x in rows]
  parts.append('<div class="scroll"><table><thead><tr>'+''.join('<th>'+inline(x.strip())+'</th>' for x in cells[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+inline(x.strip())+'</td>' for x in row)+'</tr>' for row in cells[1:])+'</tbody></table></div>');table.clear()
for line in lines:
 if line.startswith('|'):table.append(line);continue
 flush()
 if not line:continue
 if line.startswith('### '):parts.append('<h3>'+inline(line[4:])+'</h3>')
 elif line.startswith('## '):parts.append('<h2>'+inline(line[3:])+'</h2>')
 elif line.startswith('# '):continue
 else:parts.append('<p>'+inline(line)+'</p>')
flush()
# Actual log excerpts, not a rendered game scene.
loghtml=[]
for name,file in [('大猪：2人の攻撃と毒','GOLDEN_BOAR_LOG.json'),('古樹：4人の支援と反撃','GOLDEN_TREE_LOG.json')]:
 obj=json.loads((ROOT/'results'/file).read_text());interesting=[x for x in obj['log'] if x['kind'] in ('telegraph','heal','echo','barrier','death') or (x['kind']=='damage' and x.get('kind_damage') in ('counter','chase'))]
 selected=interesting[:24]
 loghtml.append('<details><summary>'+name+' — 実計算ログ抜粋</summary><pre>'+html.escape(json.dumps(selected,ensure_ascii=False,indent=2))+'</pre></details>')
css='''*{box-sizing:border-box}body{margin:0;background:#faf9f5;color:#21382e;font:16px/1.9 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Yu Gothic",sans-serif}header{padding:38px max(22px,calc((100vw - 1040px)/2));background:#294f41;color:#fff}header h1{font-size:clamp(25px,4vw,38px);line-height:1.45;margin:10px 0}header p{margin:6px 0;color:#ecf1ea}.wrap{max-width:1100px;margin:auto;padding:24px 28px 65px}.kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:0 0 24px}.kpis div{background:#edf3ed;border:1px solid #c9d8cd;padding:18px;border-radius:6px}.kpis b{display:block;font-size:23px}.kpis span{font-size:12px}.notice{padding:16px 20px;border-left:4px solid #9f773f;background:#f4ecd8;margin-bottom:30px}h2{font-size:23px;line-height:1.5;border-top:3px solid #58725e;padding-top:16px;margin-top:40px}h3{font-size:18px;margin-top:26px;line-height:1.6}p{margin:13px 0}.scroll{overflow-x:auto;margin:22px 0}table{border-collapse:collapse;width:100%;min-width:590px;font-size:14px;line-height:1.65}th{background:#315749;color:#fff;padding:12px;text-align:left}td{border-bottom:1px solid #d5dfd5;padding:12px;vertical-align:top}tr:nth-child(even){background:#edf1eb}strong{color:#224d37}details{border:1px solid #cad6ce;padding:12px 16px;margin:14px 0;border-radius:5px}summary{cursor:pointer;font-weight:600}pre{overflow:auto;max-height:420px;font:12px/1.6 ui-monospace,monospace;white-space:pre-wrap;overflow-wrap:anywhere}footer{padding:22px;border-top:1px solid #ddd;color:#5b695f;font-size:12px;text-align:center}@media(max-width:650px){.wrap{padding:20px 16px 45px}.kpis{grid-template-columns:1fr}.kpis div{padding:12px}.kpis b{display:inline;margin-right:12px}h2{font-size:21px}header{padding:26px 18px}}'''
page='<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>魔女の採集帳｜初回攻略の接続検証 R4</title><style>'+css+'</style></head><body><header><p>WITCH’S GATHERING LOG / G2-C R4 / 2026-10-09</p><h1>素材集めから、2人と4人の攻略へ。</h1><p>成長R2・経済R3を保全した、初回ボス2戦の数値接続検証。</p></header><main class="wrap"><section class="kpis"><div><b>2,200戦</b><span>固定候補での比較バッチ</span></div><div><b>53項目</b><span>新しい接続・戦闘テスト</span></div><div><b>最終調整は保留</b><span>初期強化などに設計課題</span></div></section><div class="notice"><strong>完了したのは数値・処理の接続です。</strong>敵の数値は仮案。導入や深部の通常探索は入力条件であり、実際のゲーム画面・iPhone・プレイテストは未実施です。</div>'+''.join(parts)+'<h2>代表ログを確認</h2>'+''.join(loghtml)+'</main><footer>原本はsource/に保持。実装・素材・広告・公開への追加許可なし。</footer></body></html>'
(ROOT/'READABLE_REPORT.html').write_text(page)
validation={'date':'2026-10-09','status':'REFERENCE_CONNECTION_PASSED_WITH_DESIGN_FINDINGS','new_tests':53,'new_tests_pass':True,'baseline_growth_tests':55,'baseline_economy_tests':61,'batch_battles':2200,'source_hashes_verified':len(json.loads((ROOT/'data/SOURCE_HASHES.json').read_text())), 'known_findings':findings,'not_tested':['normal_intro_battles','deep_area_survey_gameplay','all_4_character_endgame_effects','multi_enemy_general_engine','device','database_power_failure','visuals','retention','monetization'],'not_final_balance':True}
(ROOT/'results/VALIDATION_SUMMARY.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
print('report',len(report),'html',len(page))
