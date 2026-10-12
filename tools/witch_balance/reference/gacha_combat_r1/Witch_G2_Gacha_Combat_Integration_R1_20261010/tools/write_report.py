from pathlib import Path
import json,html,re,platform,sys
R=Path(__file__).resolve().parents[1]
x=json.loads((R/'results/main/EXPERIMENT_RESULTS.json').read_text());post=json.loads((R/'results/POST_ANALYSIS.json').read_text());audit=json.loads((R/'data/SOURCE_AND_MAPPING_AUDIT.json').read_text())
D={(r['case'],r['arm'],r['stage']):r for r in x['summary']}
def get(c,a,stage='FULL'):return D[c,a,stage]
labels={'FRESH4':'4人加入直後・Lv6','FOREST6_PROTECT':'6時間採集・守備支援・Lv8','FOREST6_OFFENSE':'6時間採集・攻撃寄り・Lv8','FOREST12_STRESS':'12時間採集・Lv9／敵HP・威力＋10％'}
lines=['# 魔女の採集帳｜ガチャ → 装備・強化 → R6戦闘 接続検証 R1','',
'2026-10-10 / 新しい「統合検証」のR1。既存の戦闘R1・ガチャR1とは別系譜。',
'**判定：限定接続は成立。C案の育成効果を実際の参照戦闘で確認。一方、初期装備の穴埋め効果が大きく、収益・長期経済・最終仕様は未承認。**','',
'## 1. 今回確認した原本と、実行環境',
'GitHub T-ishikawa00/witch-gathering-log の commit `497549e9339431b5680eaa398fef16ff1b81f117` を固定。成長JSON・計算コード・経済JSON・R6-B入口と支援実装・R5戦闘・Commerce装備メタデータ・ガチャ候補表の計9ファイルを接続経由で読み、Git blob SHAと添付原本の実バイトから計算した値の一致を確認した。全151リモートファイルを再ハッシュしたという意味ではない。',
'添付R1〜R6統合ZIPとガチャAfterDraw R4 ZIPを非破壊で展開。元のvendor/source配置を使い、R6-Bの戦闘実装へ新しいガチャ装備を渡す接続だけを追加した。ソース369ファイルは今回開始時のSHA-256と一致。Mac・GitHub・G1/G2アプリは変更していない。',
'旧R6の既知2条件×強化前後の4ログも、元スクリプトで再計算し、入力識別値と全ログSHA一致を確認した。初回の単純再生は意思決定トレースが無効だったためログ行数が違ったが、原記録どおりdecision_trace=Trueを指定する元の再現スクリプトで一致。勝敗を合わせるための式変更はしていない。','',
'## 2. 装備と副効果の対応',
'|論点|原本で分かったこと|今回の扱い|','|---|---|---|',
'|29型と33型|世界/Commerceの29型は、成長側にも全て存在。成長側に猫の身体・手・足・指輪相当4型が追加|29型の名前・対象・部位・ゲート・親型を照合。33型を検証用カタログに採用するが、猫4型の量産・正式採用は未承認|',
'|AF_BARRIERとAF_WARD|CommerceはAF_BARRIERを参照するが数値実装なし。成長はAF_WARDをbarrier_bonus_bp・5〜10％と定義|入力変換でだけAF_WARDへ対応させる候補。旧データを置換せず、未知IDは拒否。名前が同じ意味だと以前から承認されていたとは扱わない|',
'|個体値の尺度|旧開封モデルの座標は0〜10000、成長のraw qは0〜1000|実装側は成長座標で新個体を生成。旧模擬開封品を実所持品として移行しない|',
'|潜在枠|成長側は普通でも将来用の3枠を保存。旧開封モデルは見えている枠だけ|3枠を入手時に確定。保証副効果は先頭。種類をソートして保証枠を後ろへ移さない|',
'|個体値下限|伝説の合法下限はq600。その他はq0|「合法範囲の上半分」は伝説q800〜1000、その他q500〜1000と明示。品質昇格時には再抽選しない|',
'|研成・強化・分解|原R2は品質粉1/2/4/8/12、投資粉80％回収。強化次段5×段階|原関数を利用。生成時の高研成を架空の投資として返さない。レシピ素材・XP・時間をガチャで足さない|','',
'33型×5品質＝165通りで、装備生成・数値読込・キャラ適格性を検査した。ただし、元のR6戦闘が対応するのは初回森の13型。残り20型の進化固有効果や覚醒戦闘まで合格したという意味ではない。',
'若枝の採集杖から霧花の毒杖への原進化関数も確認。個体ID・潜在枠・qを保持し、入手時の威力保証を進化後に勝手に呪毒へ引き直さない。「保証」は取得時の対象に対するもの。','',
'## 3. 比較条件を先に固定した',
'4人加入直後、守備支援6時間、攻撃寄り6時間、12時間の強敵条件。各条件で採集/制作乱数24組×戦闘乱数8組。基礎装備・素材費は原R2、採集時間と自然装備は原R3。序盤の導入と深部ルート確認は原R4にあった明示的fixtureであり、導入全プレイを再実装したわけではない。',
'**重要：ガチャを引かない対照にも、既に得ていた自然装備と研磨粉を使わせた。** 6時間なら自然装備12個と粉102、12時間なら24個と粉174。使える個体を選び、手持ち粉で強化してから各群へ分ける。以前のR6試験で意図的に未装備だった自然ドロップを、課金側だけ有利に扱わない。',
'装備選択は比較のための固定手順。同じ型か空き部位で、評価する公開能力が全て非減少の候補だけを選ぶ。戦闘結果・未来の乱数・非表示の潜在枠は見ない。最適装備を発見する全探索でも、実プレイヤーが必ずこの手順を取るという仮定でもない。自動装備/自動強化を製品へ追加したわけでもない。',
'開封後はEQUIP（装備変更のみ）とFULL（本人が候補処分を確認した前提で分解し、原式で追加強化）の2段階を比較。品質昇格・副効果再調整・共鳴はこの操作手順に含めない。各段階でXP・素材・解放・採集時間の不変を検査した。','',
'|比較群|今回受け取る量|確率/保証|','|---|---|---|',
'|Aの無料枠|1個|旧Aそのまま|','|Cの無料枠|5個|35/40/20/4/1％、中位20・伝説100、目標保証を維持|','|Aの1,500円換算|10個|旧Aそのまま|','|Cの1,500円換算|50個|Cそのまま|',
'無料枠は一度付与したバッチの比較で、24時間の実カレンダー処理ではない。実課金なし。保証は空から。価格は以前の比較用換算値で、売れる価格・実際のストア商品を検証していない。A/Cは価格と供給量も異なる。','',
'## 4. 勝利数：何が変わったか',
'|初期条件|ガチャなし|C無料5個・FULL|A10個・FULL|C50個・EQUIP|C50個・FULL|','|---|---:|---:|---:|---:|---:|']
for c,label in labels.items():
    vals=[get(c,'NO_GACHA','BASE'),get(c,'C_FIVE_FREE'),get(c,'A_1500'),get(c,'C_1500','EQUIP'),get(c,'C_1500')]
    lines.append('|'+label+'|'+'|'.join(f"{v['wins']}/192" for v in vals)+'|')
lines += ['', '**加入直後では、C50個の恩恵が非常に大きい。** Lv・XPを増やさず、装備だけでも167/192勝、余剰から強化すると174/192勝へ到達した。ただし192人の実績ではなく24装備抽選組を各8戦に使った参照計算。',
'一方、6時間以降では対照も全192戦に勝利した。従来の低い勝率をそのまま「ガチャを引かない人の勝率」と説明できない。今回は、自然装備・手持ち粉の使用と、新しい装備選択手順が同時に変わっている。自然ドロップだけを原因とした単一要因試験ではない。',
'十分準備した条件では勝敗が上限に張り付くため、このボスの勝率だけでA/Cや副効果プールの優劣を決めない。12時間の強敵条件も、既存R6と同じHP/威力＋10％に留め、差を出すために敵を後から強くしていない。','',
'## 5. コモンが実際に働いたのか',
'|C50個・FULL|新しく装備した個体|普通|良質|新しい粉|追加強化段階数|','|---|---:|---:|---:|---:|---:|']
qq={(v['case'],v['arm']):v['means'] for v in post['mean_new_equipped_by_quality']}
for c in labels:
    v=get(c,'C_1500');q=qq[c,'C_1500']
    lines.append(f"|{labels[c]}|{v['mean_new_equipped']:.2f}|{q['Q0']:.2f}|{q['Q1']:.2f}|{v['mean_new_powder']:.2f}|{v['mean_extra_steps']:.2f}|")
lines += ['', 'いずれも24開封組の平均。新しく装備した数は初期の空き部位も含み、全部が既存装備より優れた上位交換ではない。副効果数のある高品質を無条件で自動装備したのではなく、原式の表示能力を使って判断した。粉だけの効果と、穴埋め/交換による効果は分けている。',
'**事後の仕組み診断：** 加入直後の同じC50個の装備型を残して、新しい装備だけ全て普通へ変換し、分解・追加強化を行わず192戦を再計算したところ101勝。これは販売候補ではない反実仮想。普通でも基礎値と型の効果があるため、空き部位を埋めるだけでも大きく前進することを示す。元CのEQUIPは167勝なので、高品質/副効果にも追加価値がある。どちらか一方だけが効果の全てではない。',
'高レアだから基礎攻撃力が何倍にもなる変更はしていない。現行R2は品質で基礎値を乗算しない設計。これが「量を得る効果」が序盤に強い理由の一つ。伝説を集める長期的な魅力の十分性は、別に確かめる必要がある。','',
'## 6. 勝てるようになった後の違い',
'|6時間・守備支援|勝利数|戦闘時間の中央値|','|---|---:|---:|']
for arm,label in [('NO_GACHA','ガチャなし'),('C_FIVE_FREE','C無料5個'),('A_1500','A10個'),('C_1500','C50個')]:
    v=get('FOREST6_PROTECT',arm,'BASE' if arm=='NO_GACHA' else 'FULL');lines.append(f"|{label}|{v['wins']}/192|{v['median_win_seconds']:.2f}秒|")
lines += ['', 'C50個では、ガチャ前に比べた隊全体の威力合計が平均約14.45％、HP合計が約8.64％増加した。ただし合計値はチーム戦力の換算指標ではなく、個々の役割への配分が違えば結果も違う。',
'時間中央値59.11秒→51.39秒は、Simulator表示や実機FPSの測定ではなく、整数ms参照戦闘での決着時刻。既に勝てる戦いでも短くなる例は確認できたが、勝利した戦闘の時間が必ず短くなる一般保証ではない。両方勝った同じseedの時間差も別JSONへ保存した。','',
'## 7. 新しく露出した設計上の問題',
'### 7.1 潜在副効果と、一括分解の意味',
'成長R2では、普通・良質にも将来の3枠が入手時に保存される。見えている能力が同じでも、後で品質昇格したときの種類とqは違う。前回AfterDrawの「見えている効果が劣らない控えを残す」は、現在の比較としては成立しても、将来の品質昇格まで含む不要判定ではなかった。',
'今回FULLは、初入手・装備中・ロック・保存参照・投資済み・必要な控え数を保護したうえで、プレイヤーが候補の処分を明示確認する操作モデル。将来の潜在価値まで安全だとは称さず、失う候補の潜在枠差も診断に記録した。実プレイヤーが全候補を捨てるとは限らず、粉の実取得量は下がり得る。',
'**推奨する次の判断：** 品質昇格で解放される潜在効果を分解前に確認できるようにするか、潜在価値を放棄する一括処分の意味を明示するか。元データを後から引き直す解決は採らない。物品を失わない安全性と、将来の最適個体を捨てない保証は別。',
'### 7.2 ガチャ副効果のプールが、自然入手より狭い',
'Commerceの既存プールは、手数・再使用短縮・会心・直接攻撃などの複数効果を含まない。初期の必須保証以外を成長側の合法プールへ広げる案も別に192条件で比べたが、6時間対照は既に全勝のため、これで優劣を確定しない。狭いプールを無断で広げたり、同じ名前の高レアを必ず自然品より優れていると説明したりしない。',
'### 7.3 C50個は、初回攻略を大きく前倒しする',
'これは不正な未来装備排出ではない。地域ゲート内の基本13型だけで、大量の穴埋めが起きた。課金で早く強くなる方針としては成立し得るが、4人加入直後からこの供給を許すかは、意図した序盤体験と合わせた判断が必要。無料の自然供給を黙って弱体化して帳尻を合わせない。',
'### 7.4 R6の適用範囲と未解決6件は残る',
'今回の追加強化前後3,456組では勝利→敗北は0、敗北→勝利は7。強い準備済み対照が多く勝率も飽和している。過去のR6-Bで残った6/2,000の一般的な強化逆転を解消した証明にはならない。R6の数式/支援判断は一切変更していない。','',
'## 8. 検証件数と境界',
'|検査|実行結果|','|---|---|',
'|今回の接続契約テスト|52件PASS|',
'|原成長R2 / 経済R3 / R6-B / ガチャ比較|55 / 61 / 30 / 30件PASS|',
'|旧R6の既知ケース|2seed×前後＝4ログ・入力識別一致。vendor132ファイル一致|',
'|全33型の数値生成|5品質ずつ、165ケースPASS。戦闘全33型の合格ではない|',
'|主比較＋事前設定の比較補助|7,680回の参照戦闘|',
'|事後の全普通診断|192回。主候補選定に混ぜない|',
'|代表的な勝利への変化|3例×前後ログを追加再計算・保存|',
'|ファイル保全|元ZIPから展開した369ファイルのSHA一致|',
'数字の大きさで面白さや販売価値を証明しない。24個の装備抽選を各8乱数で反復した群であり、192人の独立ユーザーテストではない。',
'未検証：R02〜R05の進化固有効果/覚醒を含む実戦闘、ガチャ込み30/90日攻略、品質昇格/再調整を選ぶプレイ戦略、暮らし共鳴の実戦闘、UI手数と実時間、購入意欲、実StoreKit・保存DB・返金・実機性能。',
'## 9. 結論と、次に固めること',
'**C案の装備・粉が、原R2/R3/R6を通じて実際の育成効果へつながることは、初回森の範囲で確認できた。** ただし、C案の適正価格・最終供給量や、ガチャが必須であることは確認していない。',
'次の判断は、(1) 4人加入後のガチャ解放時期/初期供給、(2) 潜在副効果と分解前確認、(3) ガチャの追加副効果プール、(4) 猫4型の追加範囲。これらを仕様として整理してから、ガチャ込みの長期経済と本番接続を進める。',
'採用済みA案の美術方向は変更しない。既存159地域アセットに、猫4装備の不足制作・衣装・家具を黙って加算しない。今回は保存可能な独立した検証資料であり、Codexの本番実装・Git操作への許可ではない。','']
report='\n'.join(lines);(R/'REPORT.md').write_text(report)
# A small self-contained renderer for this controlled Markdown subset.
def inline(t):
    t=html.escape(t);t=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',t);t=re.sub(r'`([^`]+)`',r'<code>\1</code>',t);return t
parts=[];table=[]
def flush():
    if not table:return
    good=[s for s in table if not re.fullmatch(r'[|:\- ]+',s)]
    rows=[s.strip().strip('|').split('|') for s in good]
    parts.append('<div class="scroll"><table><thead><tr>'+''.join('<th>'+inline(s)+'</th>' for s in rows[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+inline(s)+'</td>' for s in row)+'</tr>' for row in rows[1:])+'</tbody></table></div>');table.clear()
for s in lines:
    if s.startswith('|'):table.append(s);continue
    flush()
    if not s:continue
    if s.startswith('### '):parts.append('<h3>'+inline(s[4:])+'</h3>')
    elif s.startswith('## '):parts.append('<h2>'+inline(s[3:])+'</h2>')
    elif s.startswith('# '):continue
    else:parts.append('<p>'+inline(s)+'</p>')
flush()
css='''*{box-sizing:border-box}body{margin:0;background:#f5f4ef;color:#24312b;font:16px/1.9 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Yu Gothic",sans-serif}header{padding:36px max(20px,calc((100vw - 1050px)/2));background:#18332e;color:#fcfaf2}header h1{font-size:clamp(25px,4vw,36px);line-height:1.5;margin:12px 0}header small{color:#d4c496}main{max-width:1100px;margin:auto;padding:24px 26px 68px}h2{font-size:24px;border-top:2px solid #7a9080;padding-top:18px;margin-top:40px;line-height:1.5}h3{font-size:19px;margin-top:27px}strong{color:#285742}p{margin:14px 0}.notice{background:#ede8d4;padding:16px 20px;border-left:4px solid #9b8152}.kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:20px 0}.kpis div{padding:16px;background:#e7eee7;border:1px solid #c6d1c9}.kpis b{font-size:23px;display:block}.kpis span{font-size:12px}.scroll{overflow-x:auto;margin:20px 0}table{border-collapse:collapse;min-width:660px;width:100%;font-size:14px;line-height:1.7}th{background:#294a3d;color:#fff;text-align:left}td,th{padding:12px 14px;border-bottom:1px solid #cbd5cc;vertical-align:top}tbody tr:nth-child(even){background:#eaf0e8}code{background:#e4e9e4;padding:2px 4px;overflow-wrap:anywhere}a{color:#215b50}footer{padding:22px;border-top:1px solid #d0d6ce;color:#58665b;font-size:12px}@media(max-width:650px){main{padding:20px 16px 40px}.kpis{grid-template-columns:1fr}.kpis b{display:inline;margin-right:12px}h2{font-size:21px}header{padding:25px 18px}}'''
page='<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>魔女の採集帳｜ガチャとR6戦闘の接続検証</title><style>'+css+'</style></head><body><header><small>WITCH’S GATHERING LOG / GACHA × GROWTH × COMBAT / 2026-10-10</small><h1>引いた装備は、<br>本当に攻略へつながったか。</h1></header><main><div class="notice">ゲームUIではなく検証レポートです。原本の数式・R6-Bを使用し、ID対応だけ別の提案に分離。売上・実機・全地域完成の報告ではありません。</div><section class="kpis"><div><b>9原本</b><span>GitHubの固定版とバイト対応</span></div><div><b>7,680戦</b><span>同じ資源条件の主比較・比較補助</span></div><div><b>52契約</b><span>接続部分の自動テスト</span></div></section>'+''.join(parts)+'<h2>実データとコード</h2><p><a href="data/SOURCE_AND_MAPPING_AUDIT.json">ID・副効果対応</a> ／ <a href="results/VALIDATION_SUMMARY.json">検証要約</a> ／ <a href="results/main/EXPERIMENT_RESULTS.json">全比較集計</a> ／ <a href="results/POST_ANALYSIS.json">品質別装備・潜在枠の診断</a></p></main><footer>Mac・GitHub・既存ゲーム未変更。元のR1〜R6は保全。これを制作開始許可として扱わない。</footer></body></html>'
(R/'READABLE_REPORT.html').write_text(page)
summary={'status':'FIRST_REGION_REFERENCE_CONNECTION_VALIDATED_WITH_DESIGN_OPEN_ISSUES','scope':'selected R6-B first-tree fight, R2/R3 item/earning functions; new explicit candidate bridge','pinned_commit':audit['pinned_commit'],'live_remote_blob_matches':len(audit['remote_blob_checks']),'original_files_unchanged':369,'new_contract_tests':52,'baseline_tests':{'growth_r2':55,'economy_r3':61,'support_r6b':30,'gacha_compare':30},'known_golden_replay_cases':4,'all33_static_item_quality_cases':165,'main_battle_cells':7680,'posthoc_mechanism_battles':192,'paired_extra_enhance_checks':post['enhancement_after_equipping_pairs'],'paired_extra_enhance_improvements':post['equip_loss_to_full_win'],'paired_extra_enhance_regressions':post['equip_win_to_full_loss'],'historical_r6_six_of_2000_fixed':False,'production_approved':False,'source_code_modified':False,'mac_or_github_modified':False,'not_tested':['all33 combat/advanced skills','full30_90day economy','liveStoreKit/DB','userfun_and_sales','UI_or_iPhone'],'key_findings':['33=29+4 explicit cat additions; no world ID loss','Barrier ID needs explicit adapter; no numeric Commerce definition','C fills empty starter slots strongly; prepared free control already wins all sampled fights','Low rarity can be equipped; salvage is not its only value','Hidden latent slots invalidate claiming visible duplicates redundant in all future states','Gacha optional pool is narrower than natural pool','Original R6 supports only13 early templates, not all33 skills']}
(R/'results/VALIDATION_SUMMARY.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('Markdown characters',len(report),'HTML characters',len(page))
