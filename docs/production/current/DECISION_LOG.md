# 判断記録

- 2026-10-10: 正式依頼のローカル開発権限を適用。過去の資料保存限定指示は当時の記録。
- 既存mainの変更を保護し専用worktreeを使用。
- 品質倍率、昇格費用、ガチャ確率、商品価格は未承認の実装試験値。

- 14:54: R6正準2seedの全damage・毒tick・終端HP/時間一致を確認。イベントschema/countは不一致なので「全trace同値」としない。通常campaignの小さい値とR6固定小数点を無断置換せず、actual装備を使うread-only R6 QA adapterで比較する。
- 14:54: EQ_S_03のcover barrierは候補Python実装のSmith本人付与に合わせる。op名cover_targetとの曖昧さをR6_CAMPAIGN_EFFECT_RECONCILIATION_R1へ記録。F03 1500msは装備候補、正準fixturesの2000msは保持。
- 14:54: claimOfflineの素材gate迂回は通常処理の不具合として修正。設計値の正式承認ではない。保存破損/legacy target/逆時計の回帰を追加。
- 14:54: 表示はR6CombatPresentationSemanticsへ統一。poison_burstは同攻撃のannotationで二重減算しない。heal_followupは攻撃。enemy_heal_cycleは回復。表示のHPを終端補正前に照合する。
- 14:54: 標準衣装の選択杖用bodyは候補layerとして追加し、無選択の原画は維持。生成帽子切れを棄却し再制作。商用衣装/家具点数の確定は行わない。
- 14:54: R6 previewのnil==nilは新規save不存在として分離。既存保存byte比較には明示QA fixture setup後の永続fileを使う。

## 2026-10-10 15:26 JST 継続

監査も誤り得るため画像個体誤認・尾切断判定を原画像/alpha連結で訂正。B03_A旧receipt混入と視覚証拠を分離。Dynamic Type/VoiceOver/通常shop復元表示の独立指摘に対応中。

## 2026-10-10 16:49 JST — 資源固定と味方追加動作

- ローカル実装修正として、正常終了code/全path存在/SHA記録だけでbuild合格とせず、compile前にPNG構造/画像decode/source不変を検証する。Xcode --freezeも全資源/assemblerを固定。R029失敗bundleは不変更で証拠保存。
- 4正本キャラに沿ったidle/hit/resolve各3framesを未承認候補として追加。foot基準/actor共通scaleで書き出し、瞬きに短い表示時間を割当。別衣装/独立杖Ernaにはfull-staff画像を重ねず静止fallbackを維持し、その追加動作は未完成。frame数と自然さ/Human採用は別判定。

## 18:03 JST — 残件の実制作

全7state受理が通っても、B01A決着に見えない最終姿勢は不合格として修正する。R4のlater attachmentは今回の追加制作委任を停止する条件ではなく、既存5魔女杖をcandidateとして展開する。新販売SKUは作らない。AppIconは未承認ローカル候補1点。背景は無意味なfar/mid分割をせず、実際の手前遮蔽不足と比較master二重描画を修正する。

18:24補正: R1 Lunaは主絵が本持ちだが衣装variantに杖もあるため、既存杖poseを正本違反とは断定しない。今回の具体的gapはEQ_A_01/02/03装備の外見連携不足。原姿は維持しbook装備時のみcandidate別腕/手/本へ切替。

2026-10-10 18:46 JST — R014 AX warning実体をexportして照合。樹脂ころがしframe x358..422は375pt幅の画面右端4枚目で、スクリーンショット上は3枚のみ可視。親clip境界をまたぐoffscreen文字の測定が原因仮説。ラベル/監査を隠さず、horizontal cardを表示幅3枚に合わせてviewAligned scrollへ変更し、現在の実sourceで再検証する。未検証のためwarning解決とは記録しない。


## 2026-10-10 19:42 JST — local integration corrections (candidate only)

- Luna book attachment: reject approximate R001 palm coordinates and full-body foreground R002 (book hidden during casts). Adopt R003 only as a runtime comparison candidate: 27 measured palm positions, head/forearm/palm selective masking, three independent books, original art retained. R052 sample visual review passed; Human natural motion/adoption pending.
- Strict persistence evidence: R023 test was insufficient and visually failed two restart cases because isolated fixtures were memory-only. Preserve the false-confidence test log and images. R024 adds explicit QA fixture persistence and actual equipped-name assertions; three post-restart files contain intended IDs/owner/revision. This fix concerns harness setup/assertions; do not label the earlier image as a production save defect without evidence.
- Individual ledger schema: array-of-string clip references were absent from previous per-ID paths. Schema r003 yields 2227 R052 references (previous232); full PNG decode/hash checks were already valid. No artwork or approval changed. New207-row matrix separates historical executable evidence from current bundle presence.
- Device build: frozen193217 source compiles arm64 iphoneos Release without signing. No physical install/run, Apple authentication, Sandbox validation, or upload is implied.
- New boss mechanics: fixed-offense regression failures remain open while reachable pre-boss builds and material gates are investigated. Numerical/event changes remain test candidates; earlier98PASS is not current-head evidence.


## 2026-10-10 20:15 JST — front-row requirement as an explicit test candidate

R4 requires front-row charges for E_R01_01/B_R01_A, but no authoritative actor-to-row assignment was found. Existing renderer depth is presentation and is not proof of a gameplay formation. Under the user's delegation of detailed design, Root authorizes a minimum UNAPPROVED_TEST_OVERLAY candidate: front C_SMITH/C_FAMILIAR, rear C_WITCH/C_APPRENTICE, based on melee hammer/catalyst versus staff/book roles. Only explicitly front-row charge mechanics filter living targets; ordinary target weights remain unchanged. If no front actor survives, use surviving rear actors. Preserve the immutable R6/source-profile path. Required tests: living-front restriction, dead-target exclusion, no-front fallback, no unbounded retry, and actual-command progression. This is a testable design decision, not Human adoption or a launch formation announcement. Core work is in progress.

## 2026-10-10 20:15 JST — visual review outranks an empty automated audit

R027 at actual maximum accessibility text size reported no issues in 12 initial viewports, yet manual review found excessive footer height, tiny segmented choices, and a narrow wardrobe action column. R028 replaces the accessibility-size footer with a labelled navigation menu, fits currency horizontally when possible, uses actor/quality menu pickers and vertically lays out wardrobe actions. Navigation across all five pages and actor/quality filtering passed. Scrolled screenshots exposed inventory actions wrapping to one character per line; R029 changes them to two columns and comparison cards to vertical layout at accessibility sizes. Audit findings at other sizes/viewports remain reported, not suppressed.


## 2026-10-10T23:49:26+09:00 — 装備の原画位置と裾表示窓
- RootがLUNAの27原画について袖口と肌の境界を直接再測定した。R007はfreeHandとHAND scale .065だけ変更し、freePalm/boots/BODY等を維持。R005の掌/指先への過大表示は不合格として履歴保持。
- AIRA/ERNAの旧BODY01/02 underlay R003の部位誤認を修正。前掛け/コート裾を原画で特定した3姿勢ずつを先にnativeで試験。AIRAの腕付近からの浮きは改善したが、全白布が過大に出る。ERNA BODY02 idleは髪下の隙間漏れを確認し不合格。
- 小さな裾裏地という候補範囲に限定するため、確認済み裾近傍のみ描画する明示visibilityRegionを追加。R005は12行だけ（3姿勢×2人×2装備）に窓を設定。他行は未修正と明記。AIRA R012はHAND03 .06候補だけで他部位を保存。新app234425へ統合、実画面再検証中。
- Humanの仕様/美術採用、自然さ、商品数を承認した扱いにはしない。

## 2026-10-11 01:03 JST — 防御演出とQA観測の修正

- E_R03_01は甲殻軽減eventをpincer演出へ追加。E_R04_03は殻を閉じる/軽減eventへ防御板を対応、通常hitから解除。Coreの数値/発火は変更しない。E_R04_01追撃markerは予告なので即impactへ結合しない。E_R03_04はheavyのみ実装、R4 mark/buffは未実装のまま未binding。すべて候補仕様。
- Xcode generatorがUI診断2fileを含めない不備を修正。3fileを凍結/targetへ登録。採集帳AXXXLの最初のFAILは片方向swipeの測定漏れ、双方向dragと全step位置記録に修正して同じ完全表示条件をPASS。警告抑制/画面コード変更はない。
- readback QAは再起動後の実GameModel snapshot/保存fileSHAを別receiptに記録し、ディスクbytes不変だけの証拠を補う。Simulator限定・隔離qa-saveのみで保存commandは発行しない。
- B_R04_Bは状態差が弱いため、原画/4partsを維持し回転・移動幅だけのR002候補を別manifestで試験中。naturalness/ground gaitは未完成。

## 2026-10-11 01:54 JST — R012表示対象修正とR013ポーズ試験

- R012は同rootの実打撃対象を優先し、自己強化通知でAoE中心を動かさない。予告なし状態付与も全recipientを集約し、明示された未知対象を別の味方で代替しない。戦闘数値/保存契約は変更しない。app013655でsynthetic17/17、影響7体＋対照3体の実戦13検査が10/10 PASS。
- 9独立プレビューはraw FAILを保持。4 multiケースは存在しないload成功キー要求というQA不備で、実ノードgeometry/actorID/移動開始を要求する修正を統合。E05 transferの重複集計は同一eventの別表示をrunnerが足していたため訂正。B02反射17件中6件の粒子省略は同時2演出上限によるもので、全粒子表示合格にはしない。通常ダメージ表示は別に確認する。
- 竜は画像4点を追加し、neutralと個別接地anchorを持つ5状態の候補へ統合。待機/飛行は既存part rigを保持。短いdissolveと明示transformは中間解剖の生成ではなく、自然動作完成の根拠にしない。原画/生成PNGは編集しない。R013は実画面QA前のUNAPPROVED試験で、独立静的監査も継続。
- E_R03_04は原文のmark→同対象強打が未実装で数値未定。委任範囲内の試験候補としてパラメータ検証と実イベント実装案をoffglob準備する。正式採用/商品数を決めた扱いにはしない。

## 2026-10-11 02:34 JST — R014 integrated candidate and evidence

App022009 explicitly injects CandidateCombatOverlay.r014LocalCandidate; canonical catalog heavy and source-profile R6 stay unchanged. 800+1200ms/12500bp is not Human adoption. Core129 tests, paired5 seeds×90days,23 renderer cases and2 actual campaign battles passed within recorded limits; ordinary magnetic hits were barrier-absorbed, not HP damage proof. New-bundle dragon109ms gap aligned with81ms ImageIO decode; prior770ms shader correlation is separate evidence. Preparation experiment remains off-glob, no performance pass. Content matrix expanded207→246 rows, including10variants/14UI/8DSP/2unmadeaudio/5externalgates.


## 2026-10-11 03:02 JST — R015 local integration

20 R4 area routes were integrated without changing save schema. Two R01 playfield candidates reuse the original remaining layers; eight other area candidates remain fullframe replacements. All candidate-only. app025637 build/resource PASS; 23 effect regressions plus10 external assertions PASS; matrix246 rows now239 partial/2 unproduced/5 incomplete gates. Area runtime and actual flow QA are in progress. Foot magnet indicator is presentation only and follows cue lifetime. Preparation snapshots moved a ~331ms stall into preparation but did not prove overall performance improvement; no release performance pass granted.


## 2026-10-11 R016 exploration and challenge return

- 既存20採集物のpresent/collected画像を、採集先に応じて既存場面へ描画。報酬が正の実collect成功時だけ結果sheetのonDismiss後に状態切替する。リスポーン時間や報酬を新規仕様として採用していない。0.65秒表示等は描画用候補。
- 探索の操作パネルを初期折りたたみにし、4人と採集物を確認できる面積を確保。選択中の素材と受取操作を残す。app034944 UI29/29、20node runtime、claim3条件はPASS。
- 研究課題は一時的に別地域を描画する。終了後は保存済み遠征地域に表示を戻し、保存された採集先・経過時間を変えない。app035902でforeground復帰、達成、R05採集先表示、保存再起動1/1PASS。
- R04雪は戦闘予告を隠さないよう最大2、予告中非表示、解除後復帰。54policy/通常戦闘の抑制検査PASS。雪の個別視認性はINCONCLUSIVEで美術完成に昇格しない。
- 全てUNAPPROVED_TEST_OVERLAY。Human美術・数値・商品採用、課金完成、物理実機を推定しない。


## 2026-10-11 R017 growth experiment and onboarding

- R2には経験値からLv1–60へ自動成長する候補式が存在する。経験値のconsumer不在は実装欠落。資料に設計がないという初回監査を訂正。小さいcampaign基礎値をR2の絶対値へ無断置換せず、R2の相対成長を0/25/100%で明示注入して比較する。保存は既存XPだけ、levelは導出し、R6固定profile/default Coreは維持。実装比較前に通常appへ採用しない。
- 鑑定の目標と日次受取は既存gachaUnlockedを共用する。初期5枚、確率/保証は変更しない。実際の制作/比較による解放と保存不変を検証する。
- 日次Date引数はCoreの実行で将来日を受け入れると確認。ローカル時計は経過日の権威ではない。OS時計を操作せず、今後の時刻サービス/オフライン方針を未完として残す。根拠なく課金・報酬制限を正式化しない。


## 2026-10-11 04:36 JST — R017 low-growth selection and R018 readability trial

- Rootは保存済み同装備/初期装備の112 paired previewを比較し、500bpをローカル開発アプリの候補profileへ接続。0/250/500/750/1000/2500/10000bpのうち、250bpは最小の正値だが初期の威力増加が乏しい。500bpは日7で全員に威力+1以上、median TTK短縮は保存装備8.85%/初期装備13.96%、Rootの試験基準25%以内。比較基準自体も承認済み設計ではない。10000bpは一部ボス5tick/無被害であり選ばない。Core既定nil、固定R6、敵自動調整、保存XPを変えない。
- 90日runnerのLv60到達は日21、以後69日capのまま余剰XP保持。R2にcalendar日数の指定は見つからず、直ちに違反とは扱わないが長期目標の不足リスク。仲間2人開始/途中加入・追付きは既存4人開始との別gapとして保持し、この修正に混ぜない。
- S02の在庫アイコン状板を透明炎晶に置換するcandidate overlayを追加。既存槌/旧detail/S03を保持。Root画像レビュー通過は試作統合可の判断であり美術承認ではない。27frame位置/連続動作は次buildで検証。
- 採集R01_G3/R04_G1/G3の状態差/雪上輪郭を補助する0.36秒cue、R04_G1/G3だけの接地影を試験。原画変更なし、報酬と既存リスポーン表示時間は不変更。丸いcueが標的マーカーに見える可能性も実画面で判定し、良くなければ棄却する。


## R017 onboarding authority reconciliation

`docs/design/DESIGN_BIBLE.md:9,30`と`docs/design/DECISION_LOG.md:D002`は4人パーティーを採用済み、加入順を未確定と明記する。一方、R2成長資料39–45行は2人開始→R01で別イベント加入・1回だけ最大EXP追付きという候補。現開発版の4人開始はR2の加入実装ではない。今回の500bp導入は、最初から4人で動く既存の試験構成を維持し、加入イベントや権利を既存セーブに追加しない。R2加入案は未採用の別案として残す。4人開始をHuman承認済みと記録せず、加入時追付きのQA済みとも記録しない。

## R018 visual rejection and automation crash

- The app043901 gather ellipse passed functional QA but Root and the independent reviewer found it read as a target ring. It is rejected. app045211 changes only GatherNodePresentation to three short-lived crystals; source images, shadows, rewards and existing transition timing are retained. All game resources are identical; only ASSET_COMPILE.log differs. Visual validation is pending.
- app043901 challenge foreground UI failed with SIGABRT. The raw crash and Simulator log show an Objective-C exception in XCTAutomationSupport element filtering while inserting nil into NSMutableOrderedSet. Core victory at23ticks was committed; presentation did not finish. Same-condition reproduction is pending, and app contribution is not ruled out. There is no evidence of a causal connection to StoreKit first! or Code3. No OS/SIP change.
- Economy R003 reuses seeds across daily sessions and its equipped-build metric cannot establish acquisition availability. R004 separates inventory/equipability/equipped milestones and per-operation paired seeds. Old raw results are retained;500bp remains an unapproved candidate.


## R019 research and latent integrity candidate (2026-10-11 05:23 JST)
Research UI now derives bonuses/costs/gates from the actual catalog and replaces unavailable actions with readable conditions. Three focused UI tests verify actual +1 attack, persistence, challenge launch and observational AX. Q4 promotion wrote an unrecognized latent ID; new promotion now uses existing LATENT_POWER_TEST, with projection/display compatibility for legacy LATENT_TEST_01. This chooses an existing test effect only, not an approved balance rule. Full Core: 139 total, 4 skipped, 0 failures. R005 repeats the current-contract economy matrix after this behavior change; R004 remains immutable. app051627/freeze051517 source/resource alignment passes across manual Simulator, Xcode Simulator and unsigned iPhoneOS. Full UI is still running and has one stale-selector failure; the diagnostic test now targets the actual lock label and will be rerun with an explicitly recorded content size.

## R019完了結果とR020操作領域候補（2026-10-11 05:39 JST）

R019全UIは31/32PASS、旧selector1FAILを保存。修正テストは実際の最大文字サイズで1/1PASS、元設定へ復元済み。R005経済は120ケースPASS、8813組の記録戦闘と主要集計はR004と同じ。どちらも元のFAIL/限界を消さない。

探索2ボタンはラベルに44ptのframeがある一方、AX監査は約14ptを報告した。R020ではこの2ラベルだけに `contentShape(.interaction, Rectangle())` を追加し、見た目の余白もタップ対象へ含める候補を検証する。AX専用frameを広げるだけの対処はしない。根拠APIはApple [interaction](https://developer.apple.com/documentation/swiftui/contentshapekinds/interaction) と [accessibility](https://developer.apple.com/documentation/swiftui/contentshapekinds/accessibility)。新テストは44pt以上のAX frameと上端余白への実tapで受領画面/操作パネルが開くことを要求する。未検証段階の採用・改善確定とはしない。

敵30体の台帳に一律のHuman承認待ちだけを書くのは、追加制作の優先順位を決める材料として不足する。既存の実動画/描画を再利用し、個体別の技術的動作欠点と残るHuman美術採用を別々に評価する。氷竜以外の次の具体的な改善箇所も並行して選定する。

## 2026-10-11 06:04 JST — evidence corrections and next local work

- Keep R020 source action timing: actual renderer trace and sequential video decode contradict a timing-jump defect inferred from incorrect fast-seek images. Preserve old artifacts and label invalid extraction; no speculative delay added.
- Cold-load selected region follows catalog-valid saved activeRegionID only at startup. Do not move this assignment to generic refresh(), which would disturb temporary challenge battle scenes.
- ACT_B_R03_A one-frame resolve is a specific production gap; authorize additive candidate settle frames and real native playback while preserving source clips. R030 no-specific-defect findings on other actors are not natural-motion completion.
- B_R04_B generated poses have readable phase differences but torso/tail detail drift. Try one bounded renderer-mask composition using fixed original core and full candidate legs, with claws and hip overlap reviewed. No live rig replacement until evidence supports it.
- ActiveBattleQA previously queried scene HP after fight() had restored gathering and cleared combat nodes. Use the terminal playback HP receipt produced before transition, requiring matching revision. This fixes the QA observation phase, not battle damage or rewards. Run three uninterrupted30-enemy cycles on an exact candidate bundle and report fixture/performance limits.


## 2026-10-11 06:46 JST — terminal hold and bounded visual candidates

Keep results on screen for actual foreground rendering time; transaction commit remains before presentation and is never repeated by the hold. Preserve hit poses through the result phase and release the hold explicitly on both normal completion and cancellation. Existing defensive resets remain.

Limit the R03_02 compact placement change to AIRA on the exact fullframe scene; inspect all20 areas on two screen sizes before extending it. Keep EQ_S_02 0.18 height as a candidate after same-pose visual comparison. Neither change adopts new product counts or new art as formally approved.

The dragon R004 mask prototype preserves visible pixels outside leg/hip masks but cannot claim an unchanged tail root. Integrate only ground walk; existing flight keeps its old rendering path. Root review caught an animation action targeted at a crop container instead of the candidate sprite before runtime QA; Core is correcting it. No security, signing, publication, push or real purchase action is authorized by these local fixes.


## 2026-10-11 07:08 JST — ground walk, explicit flight and art rejection

freeze065330 separates explicit flight from the existing walk alias and validates rig idle fps before mutating body visibility. The ground-only two-frame leg overlay is a technical candidate, not natural-motion completion. Runtime and independent review confirm its frame switch and inactive state during flight/idle. Four-pose R002 C/D contain isolated blue shards in candidate imagery; integration is withheld until localized image repair and repeat review. Do not erase the original render or broaden masks to hide an artwork defect.

The compact R03_02 party placement has no newly demonstrated floor/collision fault in 40 area-size samples, but AIRA's119.8pt separation is a documented tradeoff. Do not invent a better position without floor evidence. The R04_04 zero-texture parent QA failure is a harness limitation with visible child rendering, not evidence that the dragon is absent.

## 2026-10-11 07:40 JST — R022音楽候補と証拠範囲

家/探索/戦闘の3場面に限ってoriginal16bar音楽をローカル制作し、独立音量/消音・loop・scene切替・背景停止を実装。販売商品数やvoice範囲は確定しない。新音楽/動作/成長は引き続きUNAPPROVED_TEST_OVERLAY。R002では音源失敗後の旧曲挙動を統一し、実decoder失敗も回帰対象にした。

竜4pose C/D青断片のimagegen局所修正4案は周囲変形により棄却。元body/2pose既存統合を保持し、完成判定はPARTIAL。ERNA4構成の現行LayeredMotion動画/選択表示と53装備consumerを照合し、古い静止画数だけによる追加制作要求は採用しない。判定不足の微細な接触は個別残件として保持。

fullUI36/37のUIKit SIGSEGV、旧XCTest内部SIGABRT、StoreKit nil SIGTRAPとSKTestSession Code3は別事故。単件再PASSを原因解決としない。


## 2026-10-11 08:00 JST — R023 packaging and evidence scope

R023はPrivacyInfoのみ追加するpackaging候補。現行62Swift/ゲーム資源はR022と同じ。ローカルunsigned archive作成まで進め、Apple署名/実機/Sandboxを完了扱いにしない。6panel竜draftはpixel数だけでなく輪郭異物と関節登録不足で棄却。単姿勢のuniform runtime座標変換は検討可能だが、非一様伸縮やmask拡大で欠陥を隠さない。


## 2026-10-11 08:30 JST — R025進行比較と竜中間姿勢

旧runの結果は改変せず、装備段階の後退とクリア日+1を試験runnerで修正してR003へ再実行。legacy_firstはanalysis runnerの既定、nondecreasing_highestは比較専用。ゲームへ自動装備仕様は追加しない。500BPは未承認のまま。竜R003/R004は透明化やmask保全だけで採用せず、足の軌道/形状不整合で棄却。生成R002の透明指定漏れは実行側設定ミスであり、imagegenの制約と断定しない。


## 2026-10-11 08:49 JST — R026最終入力の訂正

初回R026のactive入力が旧tier_safe保存だったため、原rawを残し、指定されたfrozen_r003保存へ差し替えて同じ分析sourceで再実行。ソース/仕様の変更はない。324勝/108未所持と戦闘指標は一致。比較を候補値の正式採用には使用しない。


## 2026-10-11 09:48 JST — R024限定メッシュ統合と実UI監査

原body textureを保持する四脚メッシュR004をSimulatorの二重QAフラグに限定して組み込む。既定2poseは維持し、新規画像・商品数・正式採用を増やさない。idle skeleton1.0秒とmesh1.2秒は別timelineで、一般progressをgait位相とは記録しない。静止画/取得成功/driverPASSだけで完成を認定せず、actual geometryとstate復元を別検証。実戦入口0.6秒の接地/滑りは同期観測がまだない。既存長期比較や課金QAの成功を新しい自然さ証明へ流用しない。


## 2026-10-11 10:37 JST — R005限定接地補正と復旧

22時間超の成果とcheckpoint2c4b3c20を保全し、実行中driverがないことを照合して続行。原画を変えず、実戦0.6秒の左向き軌道とrootの補正を追加したR005は二重候補flag+Simulator+isolatedでのみ有効。一点の地面固定と画面の自然さを区別し、通常起動への採用は保留。原R004/失敗capture/古いmarker遮蔽/幾何harness失敗も保持する。

S03装備の一律拡大は位置外れを解消する根拠がなく、帯状の可読性も十分に改善しないためclone試験のみで不採用。原資源を改変しない。全53consumerを実証範囲別に追跡する。効果Core到達、fixture実画面、earned実画面を別の証拠範囲とし、未実証を成功数に含めない。


## 2026-10-11 10:55 JST — lifecycle検証規約と証拠不備

入口の0.6秒を延ばさず、テストだけ3秒前準備を追加しHome駆動を安定化する。別nodeのwarp終端とrootwait→idleには1描画frame差が生じ得るため、終端identity/home/最終walk唯一行/次frameidleの全条件を満たす場合だけ認める。一般的なaction停止や複数frame停滞は5負例で拒否する。

E_R03_02nativeR003の古いreceiptコピーをproducerが原bytesを保全せず置換したため、同組を無効化し、原bytesはNOT_PRESERVEDと記録する。後から再構成して原証拠に見せない。別freshR005は独立照合が終わるまで成功範囲を確定しない。元プロジェクト原画/ソースへの変更とは区別する。


## 2026-10-11 15:24 JST — R026継続開発

シーン画像cacheは64MiB/128entryの費用上限LRUへ変更。RGBA8推定と実RSS/GPUの違いを保持する。accessibility文字ではscroll indicator許可、通常Largeの外観は同一。比較対照は実所有の武器だけを通常equipし、手動save改変でutilityゼロを捏造しない。キノコalpha bbox誤読の平滑化提案は棄却。UI run_r002の一時metrics未退避は失われた証拠として残し、元bytes保全と区別する。
