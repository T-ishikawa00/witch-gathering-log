# 『魔女の採集帳』G2 Codex一元制作・今回の最終報告 R001

2026年10月9日。担当をCodexへ一元化し、全5地域の原画制作、加工、編集元、実行データ、QAを同じ台帳で管理するパイプラインを整備した。Dotsへの新規依頼・連絡は行っていない。**全159制作単位の完成には未到達**。成立した静的素材の方式を地域バッチで展開し、不適格な背景・actor方式の一括量産は止めた。

保存先：/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c

## 納品の現在地

- **R4一式として制作完了：0件**。最終の採用版選択、完全な納品契約、runtime profileが未成立。PNG単体のPASSと完全キットの完成を分けて記録した。
- **実行用の静的候補：99制作単位、357 PNG**。50素材＋29装備＋20採取物。source・編集用ORA・runtime・review・QA・SHAを保持。小サイズ、真のα、ファイル読戻しを独立検査した。
- **見た目の候補基準を満たした確認待ち：84件**。Humanの正式承認は0件。部分候補・不合格15件は正式採用しない。
- **残る60単位は未完成**。代表試作5＋既存の部分成果7＋未制作48。source/referenceの存在だけを完成に換算しない。
- **実機検証済み：0件**。シミュレータを実機合格へ読み替えない。本番G2への取込みも0件。

[全159件の台帳 CSV](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/FINAL_159_LEDGER_R001.csv)／[詳細JSON](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/FINAL_159_LEDGER_R001.json)。各行に正式ID、revision、出自、保存先、QA、SHA、既知問題、承認・端末状態を記録し、[159個別納品manifest](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/deliveries)へ接続した。正本はR4。旧台帳、原画、制作元を削除・上書きしていない。

|地域|全単位|静的PNG候補|確認待ち基準84件|要改善15件|原画/旧source存在|sourceなし|
|---|---:|---:|---:|---:|---:|---:|
|木漏れ日の森|36|24|20|4|32|4|
|眠り霧の湿原|31|19|18|1|21|10|
|こだまの鉱洞|30|18|17|1|19|11|
|白霜の山嶺|29|17|13|4|18|11|
|月隠れの古庭|33|21|16|5|21|12|
|合計|159|99|84|15|111|48|

111には旧14単位が含まれる。今回、別の97単位へ原画候補を追加した。静的99と、代表・旧部分成果12を重複なく数える。全件のHuman採用、ゲーム統合、完全キット、iPhone実機フラグはfalse。

## 代表素材の結果

|正式ID|実証した制作能力|未解決事項|
|---|---|---|
|BG_R01_FIELD|原画4層を再利用・ORA・parallax|A/F足元遮蔽。精密な局所編集と足元profile未確定|
|BG_R02_FIELD|湿原の新規原画と編集用ORA|単一ラスタ。左下の床侵入・光源設定が不適合|
|ACT_E_R02_03|2触手のmeshと6状態60frame・SpriteKit実読込|ハロー・予告の弱さ・古膜脱離不足|
|ACT_B_R03_A|3腕×2関節・5状態94frame・再開検証済みBlender|環開閉・新bodyの肩接合・resolve不足|
|ACT_B_R04_B|3.1H縮尺候補・4部品原画とORA|翼ほぼ不透明。関節・breath・scale gift未制作|

[代表検証の詳細](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/REPRESENTATIVE_ASSESSMENT_R001.md)。くらげの6状態ファイルには部分的なresolveがあり、連槌兵は5状態。単純な上下移動で全アニメーション完成とはしていない。大型竜の4部品は編集可能なsourceで、runtime animationは未作成。

連槌兵の[編集可能.blend](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/runtime/hammer_r004/source_blender_r001/ACT_B_R03_A__editable_rig__r001.blend)は3つの原画をpackし、8ボーン・7メッシュ・5Actionを保持。別プロセスで94pose、固定足、肘の接合、15枚の透過レンダーを検査した。[動きの確認動画](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/runtime/hammer_r004/review_r001/hammer_five_state_gray_r001.mp4)もある。環とresolveを未完成のまま残し、追加原画の[接合性比較](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/representatives/ACT_B_R03_A/ring_exchange_r005/ALIGNMENT_COMPARISON_R001.png)で限界を示した。

## シミュレータの技術検証

iPhone17Pro/iOS26.5 Simulator、署名なしの独立SpriteKitアプリを使った。G1のアプリ・ソース・セーブは変更していない。

|項目|実測・観測|判定範囲|
|---|---|---|
|79アイコン|237 PNGを実decode、15地域×マット組合せ、texture preload完了|独立consumerの読込確認。最終inventory UI・採用ではない|
|icon memory/callback|157.89–158.36MiB、59.998–60.331 update callbacks/s|短いbaseline。実表示/GPU FPS、ゲーム全体memory budgetではない|
|icon background→return|別のG2検証アプリへ切替、終了せず戻る。willResignActive/didEnterBackground/didBecomeActiveと継続描画|限定的なSimulatorアプリ復帰。実機のロック/スリープ、セーブ復帰、戦闘整合性ではない|
|くらげ|現行FX r002の60frameを実copy/readback。6状態の24fps時計がsource durationの1 update以内|再生の読込・時計。予告/ハロー/resolveの品質は部分不合格|
|くらげmemory/callback|136.22–138.73MiB、59.47–62.68 update callbacks/s|R01背景と中立party代理図形による比較用。R02の本来の地域統合は未検証|
|CPU/GPU、発熱、電池、実機fps、実機スリープ復帰|未測定|合格にしない|

[アイコンの現行QA](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/native_sample/static_icons_r002/SIMULATOR_QA_CURRENT_R001.json)／[くらげの現行QA](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/native_sample/jellyfish_r004/SIMULATOR_QA_CURRENT_R001.json)。[実行画面](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/native_sample/static_icons_r002/simulator_stable_r001.png)。背景はaspect-fillで元の比率を保つが、viewportとsourceのanchor profileは未確定。H64、背景寸法、固定カメラをこのfixtureだけでFROZENにしていない。

## レビュー資料

|地域|素材・装備64px、3マット|採取前後128px|
|---|---|---|
|R01|[単体候補](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/static_catalog_review_r001/R01_static_icon_contact_r001.png)|[採取状態](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/ALL20_NODE_QA_R001/R01_CONTACT_R001.png)|
|R02|[単体候補](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/static_catalog_review_r001/R02_static_icon_contact_r001.png)|[採取状態](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/ALL20_NODE_QA_R001/R02_CONTACT_R001.png)|
|R03|[単体候補](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/static_catalog_review_r001/R03_static_icon_contact_r001.png)|[採取状態](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/ALL20_NODE_QA_R001/R03_CONTACT_R001.png)|
|R04|[単体候補](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/static_catalog_review_r001/R04_static_icon_contact_r001.png)|[採取状態](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/ALL20_NODE_QA_R001/R04_CONTACT_R001.png)|
|R05|[単体候補](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/static_catalog_review_r001/R05_static_icon_contact_r001.png)|[採取状態](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/ALL20_NODE_QA_R001/R05_CONTACT_R001.png)|

[静的79件の現行選択index](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/STATIC_CATALOG_INDEX_R001.json)と[採取物全20件の独立QA](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/ALL20_NODE_QA_R001.json)が現在の参照先。19のメタデータ参照には過去の期待SHAがなく、現在値を観測した。過去値の一致は主張しない。生成元provider/rawの対応、既存保護sourceの一致、今回の保存ファイルのreadbackは別の証拠で確認する。

要改善15件：

- NODE_M_R01_G1：NOT_QUALIFIED_STOPPED。詳細は個別delivery manifestの現行review。
- ICO_M_R01_G4：PARTIAL。詳細は個別delivery manifestの現行review。
- NODE_M_R03_G2：STOPPED_PARTIAL_AFTER_TWO_BOUNDED_REPAIRS。詳細は個別delivery manifestの現行review。
- ICO_M_R04_G1：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R04_G3：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R05_G3：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R05_G4：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R01_E2：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R01_BB：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R02_E3：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R04_E1：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R04_BB：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_M_R05_E3：PARTIAL。詳細は個別delivery manifestの現行review。
- ICO_EQ_W_P2：NOT_QUALIFIED。詳細は個別delivery manifestの現行review。
- ICO_EQ_S_03：PARTIAL。詳細は個別delivery manifestの現行review。

素材→装備87接続の[ID読戻し](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/MATERIAL_GEAR_87_TRACE_READBACK_R001.json)は全件一致。quantity、recipe、statsは変更せず、87接続すべての見た目採用が済んだとはしない。装備の装着・外見差分は29アイコンとは別で未完成。特にEQ_S_01の金属槌/木槌の関係は未決。承認済み衣装・杖の持ち方・黒猫の外見は変更していない。

## 残工程と不足する能力

残る60単位の構成は、背景10＋地点差分10＋actor30＋環境5＋戦闘FX5。sourceがある12と未制作48を台帳で分けた。未制作の個々の題材を生成失敗とみなしていない。

現方式では、指定した床を確実に空ける局所編集、透明な膜と骨の分離、欠けた身体の追加原画、別原画間の肩・関節の接合を十分に制御できていない。原画の品質不足・実装方式の未成立という今回の停止条件に該当するため、該当する背景・actor・依存する地域キットの無検証量産は行わない。静的99件の独立工程は全地域まで続行した。

無料の精密ペイント工程で元レイヤー・膜・隠れ部を修整し、旧rigに接合する追加ポーズを先に検証するのが代替案。いま不足しているのは画素/部位を保った精密編集と再接合の品質で、追加の有料契約では解決を承認されていない。床・キャラクター・制作方式の重大な変更はHuman判断の対象。実機には対象端末の確定と使用許可が必要で、現在はprivate端末を接続していない。

[制作パイプライン](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/PIPELINE_AND_OPERATIONS_R001.md)／[使用手段・費用・商用条件の実証R4](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/tool_research/TOOL_CAPABILITY_REVIEW_R4.md)。原画生成は既存の通常利用枠内。最終観測18%。新契約・支払い・API課金経路・クレジット購入は使用せず、個別請求額はUNKNOWN。権利の最終確認もUNKNOWN。

## 保存と保全

原画、編集元、実行用素材、確認動画、QAを役割別のmanifestで管理。ORAは元ラスタを保持しZIP/XML/画素を再読込したが、専用GUI操作は未検証。Blenderは実際の再編集source。PNGはstraight RGBAを記録し、縮小時だけpremultiplied処理を用いた。

並行生成の一部を別の呼出しへ取り込んだ運用不備は、固有output_hintとSHAの照合へ改め、新版を選び直した。[経緯と修復](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/PROVENANCE_INCIDENT_AND_CORRECTION_R001.json)。旧素材を削除せず、帰属UNKNOWNの履歴から正式採用を行わない。

既存5,369ファイルはサイズ/SHAで照合し、G1・セーブ・設計正本・承認済みキャラクターを保全した。[保護確認](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/qa/PROTECTED_STATE_FINAL_R001.json)／[今回の保存ファイルSHA](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/qa/DELIVERY_SHA256_R001.json)／[SHA読戻し](/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/qa/DELIVERY_SHA256_READBACK_R001.json)。Git commit/push、外部公開・投稿、第三者への送信、契約・購入・支払い、認証・セキュリティ設定変更は行っていない。
