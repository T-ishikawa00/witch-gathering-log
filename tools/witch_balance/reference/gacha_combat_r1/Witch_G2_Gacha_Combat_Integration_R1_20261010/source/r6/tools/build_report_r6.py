from bootstrap import ROOT
import json,datetime,html,importlib.util
from pathlib import Path
s=json.loads((ROOT/'results/VALIDATION_SUMMARY_R6.json').read_text())
B=s['second_stage']; paired=B['paired']
labels={'holdout_protect6':'守備支援・6時間相当','holdout_offense6':'攻撃寄り・6時間相当','holdout_protect12_power110':'守備支援・12時間／敵威力+10%','holdout_protect12_joint110':'守備支援・12時間／敵HPと威力+10%'}
table='|同じ資源・同じ装備・同じ乱数で比較|R5 強化前→後|R6-B 強化前→後|強化で勝利→敗北 R5→R6-B|\n|---|---:|---:|---:|\n'
for job,label in labels.items():
    a=next(x for x in paired if x['job']==job and x['model']=='r5');b=next(x for x in paired if x['job']==job and x['model']=='r6b')
    table+=f'|{label}|{a["wins_before"]}→{a["wins_after"]} /500|{b["wins_before"]}→{b["wins_after"]} /500|{a["win_to_loss"]}→{b["win_to_loss"]}|\n'
crafttable='|副効果seed・装備方向|R5 強化前→90粉強化後|R6-B 強化前→90粉強化後|\n|---|---:|---:|\n'
for index in range(10):
    job=f'gear_{index:02d}_'+('protect' if index%2==0 else 'offense')
    a=next(x for x in paired if x['job']==job and x['model']=='r5' and x['upgrade']=='paid90');b=next(x for x in paired if x['job']==job and x['model']=='r6b' and x['upgrade']=='paid90')
    crafttable+=f'|{index:02d}・'+('守備支援' if index%2==0 else '攻撃寄り')+f'|{a["wins_before"]}→{a["wins_after"]} /50|{b["wins_before"]}→{b["wins_after"]} /50|\n'
md=f'''# 魔女の採集帳 — 支援AI・強化逆転の再検証 R6

**検証日：2026-10-10 JST。採用候補はR6-B。最終バランス／本番実装承認ではない。**

## 0. 結論

前回のF07「強化前は勝ち、強化後は負けた2条件」は、R5の時系列ログを完全一致で再現した。今回のR6-Bでは2条件とも強化前後に勝利する。

さらに、候補決定後の未使用乱数で4条件×500組を比較すると、強化による勝利→敗北は **R5の47/2,000比較からR6-Bの6/2,000比較へ減少**。別の副効果10組×50乱数×4強化方法では **20/2,000比較から0/2,000比較** となった。

**ただし、全条件で逆転がなくなったわけではない。** 残る6条件をログ付きで保存し、一般のF07はOPENを維持する。副効果1組ではR5よりR6-Bの勝率が低かったことも残した。平均勝率の改善と、あらゆる強化が必ず有利になる性質は別である。

## 1. 固定したもの・変更したもの

4人・完全自動・作戦設定不要を維持。敵のHP・威力・防護・技の配分はR5本命候補のまま。味方のスキル倍率、詠唱・再使用・反応ICD、強化費、素材供給、研究、覚醒、装備のID／個体UUID／副効果を変更していない。R5の1/10000単位の内部精度も維持する。

通常攻撃の時刻解釈もR5を継承。味方の行動を無料にしたり、クールダウンを短縮したり、負けた結果を後から勝利へ書き換えたりしていない。特定seedを救済する条件分岐は入れていない。

変更したのは **回復の発動判断、結界の用途判断、同時刻のAI計画順**。かばうの発動条件を過度に広げる初期案は採らず、R5の危険判定と本人の安全条件を最終候補で維持した。

## 2. 残HP割合だけで回復を遅らせない

旧案は「残HP70%以下」等の条件が中心だった。最大HPの大きい仲間は、回復できる傷が十分あっても、70%を下回るまで待ってしまう。

R6-Bは、予約回復を差し引いた不足HPが **回復1回の50%以上** なら候補にする。たとえば回復量200なら、100以上を有効に使えるときに回復候補となる。瀕死の公開予告へ間に合う回復は緊急枠で扱う。

候補同士では、切迫した致死予告、低いHP割合、有効回復量、安定したキャラID順で絞る。HP満タン、死亡者、実質1だけの傷には通常回復を浪費しない。作戦編集や新スキルは不要。

**HP割合を計算から全面撤廃したわけではない。** 優先対象の順位付け、かばうの安全条件などには残る。回復力を上げると有効回復の50%基準も変わるため、一般の単調性は証明していない。

## 3. 結界を『今弱っているか』だけで使わない

R6-Bの結界は、公開済みの攻撃が近づき、詠唱が間に合い、その結界を実際に消費する見込みがある対象へ使用する。

既存の結界の残量・期限、予約済みの回復・結界、既に予定されたかばうを考慮する。通常は新しい結界の50%以上を吸収へ使える見込みを基準とし、公開済み致死予告は例外とする。同じ主動作の連撃をまとまりとして扱う。

予測対象は **次の命中が1.5秒以内の公開済み動作**。その動作の残りの命中を最長3秒先まで含める。未予告の次の敵行動や未来の会心・ガード抽選は見ない。時刻が同じ支援完了は保守的に間に合うと数えない。

予測の途中でHP0になった者を、後からの通常回復で生き返らせない。期限の切れる弱体化や結界を、将来の軽減として誤算しない。最終値は実戦の確定イベントで計算し、予測をそのまま実ダメージに使わない。

## 4. 『守る相手』を先に共有する

初期修正案R6-Aには副作用があった。未使用の500条件で、強化後の攻撃寄り構成が **R5の434勝に対して380勝**。その条件では結界の未使用失効量も増えた。この結果を隠さず、R6-Aは最終推奨から外した。

改善として、同じ論理時刻のAI段階だけを **アイラの防御予定 → ルナの回復・結界 → 攻撃役の予定** の順にする。アイラが実際にかばう詠唱を開始したなら、ルナはその予約を見て、攻撃を引き受ける相手へ結界を張れる。

例：猫が狙われる → アイラが引受の詠唱を開始 → ルナは猫へ無駄な結界を置かず、実際に受ける側を評価する。アイラが再使用待ち・行動中なら、存在しないかばうを見込まない。

これは戦闘時間を早送りする処理ではない。同じms内のAI計画順だけを変え、毒tick→期限切れ→命中等の確定効果→反応→AI→終了制限というイベント種別の順序は保つ。詠唱時間・再使用時間・通常攻撃間隔は変えない。

R6-Bはこの変更を含むため、R6-Aの合格結果をそのまま転記せず、新しいseed群で再検証した。

## 5. 元の2条件の再現と修正

|seed|R5 強化前|R5 強化後|R6-B 強化前|R6-B 強化後|
|---|---|---|---|---|
|100049|勝利|敗北|勝利|勝利|
|100069|勝利|敗北|勝利|勝利|

R5は4つのログすべてが保存済み原本と一致。元の200条件全体も161勝→184勝、うち2組が勝利→敗北という結果を再現した。R6-Bは186勝→192勝、勝利→敗北0組。**この200条件は既知の再現用で、新しい独立検証には数えない。**

## 6. 新しい乱数2,000組での確認

R6-Bを固定してからseed 900001〜900500を各条件で共通使用。同じ装備・同じ資源・同じ敵・同じseedの中で、R5とR6-B、強化前と強化後を比較した。

{table}

強化内容は、魔女の杖、弟子の本、最初に制作した装備の3個を各+3、計研磨粉90。守備支援では3個目はアイラの衣、攻撃寄りでは魔女の手袋。同じ対戦の途中で装備を差し替える操作ではない。

上の時間は採集時間の比較入力であり、待機を強制する仕様ではない。初期導入・森の深部の通常探索は引き続き完了fixture。自然ドロップ品は保存するが装備・売却に使わず、比較条件を揃えている。

4条件の強化逆転は合計47→6へ減った。ただし各条件で同じ500seedを使っており、2,000人の独立したプレイテストではない。報告データには条件ごとのWilson95%区間も残すが、全ゲームへの保証には使わない。

## 7. 副効果を変えても通用するか

R6-B固定後、別の制作seed10組と、別の戦闘seed 950001〜950050を使った。各組で①90粉の3個強化、②魔女杖+1、③弟子の本+1、④最初の制作装備+1を比較。**10×50×4=2,000の強化前後比較** となる。

R5は20組が勝利→敗北、R6-Bは0組。基礎戦闘は同じ組の4比較で共有しているため、これは2,000本の独立サンプルではない。新しい副効果seedで追試した結果として扱う。

{crafttable}

**例外も重要。** 副効果seed01の攻撃寄り構成では、R5の45→49勝に対してR6-Bは37→41勝と低かった。R6-B内では強化で改善しているが、全装備構成でR5を上回る証明にはならない。新AIに向く／不利になる配分や時刻の条件は継続調査対象。

記録中の操作名`armor5`は旧ラベル。実際には`craft:0`の+1を指す。守備支援なら衣、攻撃寄りなら手袋であり、全件を『タンク防具の強化』とは説明しない。

## 8. 残る6条件

R6-Bでも主検証で6組が逆転。いずれも入力、強化費、前後の戦闘ログ、支援判断時点を保存した。

|条件|seed|
|---|---|
|守備支援6時間|900182|
|攻撃寄り6時間|900188|
|敵HPと威力+10%|900072、900158、900256、900342|

900182では、最初に異なった支援行動は41.15秒時点の回復先。強化前はアイラ、強化後は魔女だった。ほかにも回復先の順位、かばうの発動、通常攻撃の時刻が変わる例がある。**『最初に観測した分岐』は保存したが、全6件の唯一の原因を証明したとは扱わない。**

強化でHP・威力・防護は増えている。全体の勝率も上がる一方、自律判断や撃破時刻が変わることによる例外が残る。したがって **F07は既知2症例を解消、一般の強化逆転は未解決** とする。全乱数で単調に勝ちやすくなることを断言しない。

## 9. ゲームの役割が壊れていないか

別の100seedずつで対照試験を行った。

|対照|R5|R6-B|
|---|---:|---:|
|Lv1初期装備で大猪|0/100勝|0/100勝|
|導入報酬後Lv6・2人で大猪|100/100勝|100/100勝|
|加入直後の4人・装備未制作で古樹|0/100勝|0/100勝|
|24時間相当・守備支援で古樹|100/100勝|100/100勝|
|24時間相当・攻撃寄りで古樹|100/100勝|100/100勝|
|6時間相当・支援を検証用に無効化|0/100勝|0/100勝|

戦闘中にAIの賢さだけで誰でも勝つ、という変更にはしていない。2人の大猪戦は支援役不在で、選んだ3seedのR5/R6-B時系列ログも一致した。支援OFFは検証スイッチであり、プレイヤー向け作戦ではない。

## 10. 検証数と保存

|検証|実施範囲|
|---|---|
|R6-A比較|13,800戦。副作用も保存|
|R6-B比較|13,800戦。うち旧再現800戦、新乱数・副効果比較13,000戦|
|対照試験|1,200戦。別途2人ログ一致6戦|
|R6-A契約テスト|60件PASS|
|R6-B契約テスト|30件PASS|
|旧R2/R3/R4/R5回帰|55/61/53/48件PASS|
|旧パッケージ原本照合|132ファイル一致|

**比較27,600戦と対照1,200戦は別集計。** 候補探しの開発比較、既知症例の記録再生、ユニットテスト内の小戦闘はここへ重複計上しない。中断した開発実行も完成件数に含めない。

テストは数式、座標ではない戦闘時計、残HP／結界上限、再使用待ち、詠唱時間、支援予約、同時刻の処理順、元データの保全等を確認したもの。面白さ・商品性の合格ではない。

## 11. 次へ渡す際の境界

推奨する比較基準は **`tools/selected_final.py` の `FinalBattleR6`**。`support_ai.py`内には不採用・比較用の候補が残っているため、そちらのデフォルトを本番モデルとして選ばない。

ゲーム本体・Mac・GitHub・Codexの美術制作を変更していない。4人戦闘の本番実装、R02〜R05、複数敵、覚醒や進化武器の全効果、実機、実DBの電源断、長期継続性は未検証。

全R1〜R5の統合原ZIPを`history/`でそのまま保全し、R5の実行可能スナップショットを`vendor/r5/`に保持した。今回の差分、試験計画、入力、結果、残件も同梱。あとでCodexへ一式保存するための文書は`handoff/`に置く。**資料の保存指示と、未承認の数値やAIを本番へ採用する許可は分ける。**
'''
(ROOT/'REPORT_R6.md').write_text(md)
from markdown_it import MarkdownIt
body=MarkdownIt('commonmark').enable('table').render(md)
css='''*{box-sizing:border-box}body{margin:0;background:#faf9f5;color:#21382e;font:16px/1.9 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Yu Gothic",sans-serif}header{padding:38px 24px;background:#294f41;color:#fff}header>div{max-width:1040px;margin:auto}header h1{font-size:clamp(28px,4vw,40px);margin:10px 0;line-height:1.4}header p{margin:5px 0}.wrap{max-width:1110px;margin:auto;padding:26px 26px 70px}.kpi{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:24px}.kpi>div{background:#edf3ed;border:1px solid #c9d8cd;padding:18px;border-radius:6px}.kpi b{display:block;font-size:25px}.kpi span{font-size:13px}.notice{padding:18px;border-left:4px solid #9f773f;background:#f4ecd8}.content>h1{display:none}h2{font-size:24px;line-height:1.5;border-top:3px solid #577363;padding-top:16px;margin-top:42px}h3{font-size:18px}p{margin:14px 0}table{width:100%;border-collapse:collapse;font-size:14px;line-height:1.65;margin:22px 0}thead{background:#315749;color:#fff}th,td{padding:12px;text-align:left;border-bottom:1px solid #d5dfd5;vertical-align:top}tbody tr:nth-child(even){background:#edf1eb}strong{color:#173d2b}code{font:13px ui-monospace,monospace;overflow-wrap:anywhere;background:#edf1e9;padding:2px 4px}a{color:#285f43}.table-scroll{overflow-x:auto}footer{padding:24px;border-top:1px solid #ccd8cf;font-size:12px;text-align:center;color:#56675c}@media(max-width:680px){.wrap{padding:18px 15px 40px}.kpi{grid-template-columns:1fr}.kpi>div{padding:12px}h2{font-size:21px}table{min-width:620px}header{padding:26px 18px}}'''
body=body.replace('<table>','<div class="table-scroll"><table>').replace('</table>','</table></div>')
page=f'''<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>魔女の採集帳｜支援AIの再検証 R6</title><style>{css}</style></head><body><header><div><p>WITCH'S GATHERING LOG · G2-C · R6 / 2026-10-10 JST</p><h1>強化した仲間を、AIが生かせるか。</h1><p>かばう・回復・結界の判断を分離して検証。採用候補はR6-B。</p></div></header><main class="wrap"><section class="kpi"><div><b>2症例を再現・対応</b><span>旧ログ完全一致。新案で両方の強化後勝利</span></div><div><b>47 → 6 / 2,000</b><span>主検証の強化逆転。ゼロには未到達</span></div><div><b>27,600戦</b><span>2段階の比較。実機・本番合格ではない</span></div></section><div class="notice"><strong>判定：</strong>R6-Bを次の設計比較の基準に推薦。一般の強化逆転、特定装備での旧AIとの差、全地域の実戦は未解決・未検証。Mac/GitHubへの書込みや本番採用を意味しません。</div><article class="content">{body}</article></main><footer>原本・数値・世界設定は保持。生成資料の保存と、本番実装の許可は別管理。</footer></body></html>'''
(ROOT/'READABLE_REPORT.html').write_text(page)
print('wrote report',len(page))
