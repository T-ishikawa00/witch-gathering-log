# 検証記録

- INPUT_VERIFICATION: 添付6原本のSHA-256・サイズ一致、5 ZIP CRC検査成功。

## 2026-10-10 11:55 JST — iPhone runtime and ongoing independent corrections
- Simulator `9A067715-7CF3-40D3-9064-38423223959B`, iOS26.5, bundle `local.witch.autonomous.r1`, isolated QA save r002.
- Generated spider overlay loaded in real SpriteKit scene. All seven requested states returned true; 858 rendered frames, max observed delta 0.318s includes load. `native/spider_states_r001.json` and `native/spider_runtime_r001.png`. This confirms texture playback only, not natural animation acceptance; resolve still remains upright and walk has only two poses. Enemy size too large, renderer correction underway.
- CUA actual inputs selected ERNA_TRAVEL and STAFF_MOON; save readback revision4, separate ownership/selected cosmetic/selected weapon maps. Screen confirms costume and staff rendered; grip misalignment found, correction pending recheck (`native/appearance_before_anchor_fix.png`).
- Latest independent audit before ongoing R6 work: core30 tests +11 outside probes pass (see timestamped R002). Full R6 parity still fails inspection; not accepted by test count.
- New Xcode project + two hosted iOS UI tests being run. Build/test verdict not yet available.
- User additional instruction: retain full StoreKit error text, code, location, reproduction, attempted fixes, and hypothesis; investigate autonomously without stopping game. Assigned reviewer to StoreKit investigation. No OS permissions/account changes authorized or performed.

## 2026-10-10 12:10 JST — stable checkpoint and StoreKit crash separation
- Xcode project real Simulator UI tests: 2/2 passed; `native/UITest_r001_summary.json`. Five tabs screenshot attachments and costume/weapon selection persisted across app terminate/relaunch. Render QA still identifies weapon overlap; new hand mask/grip fix is being tested.
- Original protected content: 24,420/24,420 SHA256 unchanged; `PROTECTED_READBACK_R001.json`. Original checkout retains only its preexisting `PROJECT_CURRENT.md` modification.
- Core31-test snapshot exported by core owner, indexed as checkpoint without overwriting newer live core. Current source continues R6 scheduler fidelity work.
- StoreKit probe crashes: 4 IPS share old binary UUID and line36 `.first!` with empty product list. This is a QA probe code defect, separate from notEntitled. Corrected source -> explicit awaited array -> guard first -> unavailable. Rebuilt `.probe.r2`/`.uitests.r2` Simulator regression passed (6.053s); mock flow7/7 passed. Actual StoreKit purchase remains unverified, investigation continues via configured Xcode Run. No SIP/security/account changes.
- White dragon separate-part rig created with explicit candidate pivots and transform curves. Current pack/runtime integration test pending. Existing boar/jelly anchors corrected to bundle-pixel scale in additive metadata overlay.
- Luna seated page-turn four-pose candidate exported with foot registration; desk remains separate. Home interaction render QA pending.

## Native UI r002 / StoreKit Run / timeline integration
- Xcode Simulator UI r002: 4/4 PASS（5tabs、衣装武器再起動、家具配置再起動、採集時間fixture→実craft→comparison→free5draw→再起動）。`native/UITest_r002.xcresult` とsave receiptを参照。比較screenshotのみsheet遷移前のため無効、r003で待機後captureへ修正。
- StoreKit: nil crashは `.first!` と空の商品配列。修正済sourceを古いinstalled binaryと取り違えたことをbinary UUID/mtime/4ipsで確認。Xcode正常RunのStoreKit configが存在しないworkspace内pathを向きExecutableもNoneだった。設定修正後products=2、ローカル購入2種/キャンセル/重複/返金/復元を確認。詳細purchases/およびnative/StoreKitLocalQA/RESULT。hostless Code3は別経路で原因未確定。
- 戦闘UIにtimeline timestamp、初期/最終HP、複数敵、予備動作、statusとdamageの区別、background pauseを接続。swiftc Simulator build PASS。新6件UIテストr003開始、まだ結果待ち。
- E03/E04 part rig r001はroot視覚監査で原画差異/cropを不合格。E03は既存原画stillに戻し、agentがr002修正中。状態数の機械的充足は自然動作合格ではない。

## 13:10 JST追記
実Swift50/50、Python6/6。独立ward置換/RNGfocused各1/1。小型UIr008 6PASS/1fixtureFAIL、r009 1FAIL（bulk cancel表示）、r010 alert修正後1/1PASS。大型r007 3/3PASS、実画像で家具/4人探索を確認。StoreKit最新区分はpurchases/STOREKIT_INCIDENT_CURRENT.md。全30敵sweepと1時間soakは進行中で未合格。


## 14:12 JST native差分とsoak
- app135324 scene_audit_r001: 5地域背景ロードtrue、R02湿原が実画面表示。B04_A 7/7state play受理。CH_R05_02専用灯瓶が点灯/消灯、2体敵とは異なるpropで描画。自然動作完成とは別。
- app125553 1時間soak: 3601.50秒完了、59.70〜60fps、最大常駐266MB。低操作Simulator限定（review/runtime/SOAK_R001.md）。
- app140911 build_r016 PASS: 味方35歩行フレーム、敵clip別canvas/anchor、不足walk/resolveを統合。動画・全210state再監査中。

- 14:54: Core67/67 PASS、35.502s。ログ core/CORE_67_TESTS_R1.log。R023 source SHAは現在Coreと全一致。
- R019 actual encounter sweep30/30完走、29勝1敗（B_R05_B、素材0）、各revision+1/receipt1。独立検証PASS。終盤fixtureなので通常進行証拠ではない。
- R021 R6 read-only preview4patternのevent replay終端HP一致。新規saveはNO_SAVE_BOTHで永続byte検証ではない。R023で明示persist fixture +証拠区分修正し追試中。
- Build R020はSpriteKit import不足、R022はQA region Optional未処理で失敗。修正後R021/R023 Simulator build PASS。安全策を回避せずguardで扱う。
- 原プロジェクト24,420保護ファイル14:53:41再照合PASS（PROTECTED_READBACK_R003.json）、既存PROJECT_CURRENT.md以外のGit差分なし。

## 2026-10-10 15:26 JST 継続

R024 build PASS。動作13体 fresh matching receipt 13/13、旅衣装execute手接続の目視改善。90日実command5seed 450/450日再読込、150/150campaign・75/75challenge攻略、day21/day25、単一方策/隣接seed候補検証。Core68/68 PASS。

## 2026-10-10 16:49 JST — 資源破損と追加動作

- R029 B05_A idle002は0byteでPNG decode不可、sourceは119978bytesで正常。compile後live copyと再packの競合が上流原因の仮説。失敗bundle/r005/r005_retryを保全。
- compile前PNG verify/load・atomic bytes copy・source stability、Xcode資源/assembler freezeへ修正。独立4/4＋root4/4回帰PASS。R030 B05_A/B05_B fresh7state2/2PASS。
- Xcode R015 (164521) build成功、固定1600resource pathsと実bundle SHAが全一致。resource総数はPNG枚数とは別。
- PartyRest36framesをR031へ統合。画面で体格異常を発見しR032にgeometry計測を追加。全4体のheightが意図した表示高ではなく256となることを実測、修正中。自然さ/受入は未合格。
- R030通常R05六戦闘の独立監査6/6勝利、HP終端差なし、revision+1/期待報酬。報酬内容の表示不足P2を修正中。終盤fixtureのため通常進行・初回攻略・重複抑止の証明ではない。

- 17:18追記: Core74/74 PASS（同一battle operationIDの冪等性＋新UUID再戦報酬）。R033 UI5/5、resource regression4/4。R031/R032のPartyRest巨大化は明示size保持で修正しR033 60/60 geometry確認。R034外観4組の通常戦闘/報酬/セーブ同一バイト復帰PASS、左clipはR035配置/角度修正で独立サンプル可視なし。R036新attack36はQA待ち。旧r001 Luna anticipate欠落は現行r002で修正済みだったため現在欠落との判定を訂正。原24,420 files readback17:06 PASS。

- R038 compile失敗: ActiveBattleQA内のnested persistからMainActor隔離propertyを参照。local immutable captureへ修正しR039へ。失敗後にglobal latest receiptをR038名へ誤コピーしたためR038_STALE_RECEIPT_REJECTED.jsonへ隔離、BUILD_RECEIPT_R038はREJECTED_STALE_RECEIPTと明示。成功扱いにはしない。
- R036標準Erna attack4/5のalpha16境界をworld座標へ換算するとx=-4.93/-5.50、透明canvasの負minXだけでなく可視画素の左端逸脱を確認。次版で標準field x=.14→.18へ調整し再検証。旅x=.22を維持、移動したbodyと影も追従するよう補正。

- 2026-10-10T17:43:10+09:00: R037同一process30敵×2周60/60、60勝/0敗、revision各+1・再読込一致・HP差0。1134.52秒、peak397475840bytes（379.06MiB）。終盤fixture、Simulator並列負荷、物理性能/自然進行/バランス承認は別。native/active_battle_r001/RESULT.md参照。R040 movement_r009 7/7、default+4組party再収録完了。

- 18:03 JST R041: 新11敵7state receipt11/11、root視覚でB01A resolve姿勢不合格を残す。最新30連戦PASS、560.15s/410.39MiB/30save一致/HP0/opID30unique。初期JSON SHA実測一致。coldstart独立UI2/2。PNG capture4/buildreceipt2回帰PASS。

- 18:19 R042: gear12/12・movement7/7、独立視覚で重大P1なし。R041の30連戦と別に扱う。最新startup3UITests PASS。R1 Lunaの正本bookと現行staff焼込み矛盾発見→補修制作中。


## 2026-10-10T23:49:26+09:00 — LUNA R007 / fit / battle QA
- app232119 LUNA 3tier×27=81 held frame、原画/index/gear/geometry前後一致。Root全9contactを目視。HAND/靴口/襟は静止候補の改善、BODY01/02は低判読性・裾形状の課題でPARTIAL。独立HAND03視認は3姿勢に限る。
- LUNA 3tier連続動画を収録し36時刻静止画をRoot視認。動画全編の自然さ認定とは別。
- ERNA BODY03 standard27+travel27はsource/frame/gear exact54/54、Root6分割contactを全視認。Noir3tier連続動画の36時刻静止画も視認済み。
- LUNA3tier実戦は購入や模擬表示ではなく、隔離fixtureを明示永続化→通常R01戦闘→報酬coin2/material1→revision+1→同instance装備維持→同save再起動byte一致。旧QA判定はHP JSON辞書{}を文字列0と比較しFAIL、harness修正後にraw証跡を再解析して全3PASS。元FAILを保持し、exact ID集合の追試解析も全3PASS。purchases本番完成とは無関係。
- 裾窓/AIRA HAND03新build234425 exe cbd487740a1584b2b6556c33ebb50744c2848e05b8aa4698537c94f388712d50、sim build/PNG/source PASS。独立code reviewで座標aspect変換/使い回しmaskのclearに明確な欠陥なし、実画面検証は続行。
- unsignediphoneosR010 build成功。署名・物理実機実行はしていない。

## 2026-10-11 05:39 JST — R019統合検証

- app051627のmanual Simulator / Xcode Simulator / unsigned iphoneosは60 app source・1885 game resource一致。PNG1877decode、runtime欠落0、receipt不一致0。正式署名・物理iPhoneは未実施。
- 潜在ID修正は新規Q3→Q4、既存ID互換投影、同op再送、新op上限拒否、保存/再読込、実戦ダメージ差を回帰。全Core139 total/4 skip/0 fail、70.912秒。R005経済120ケースPASS、R004との記録戦闘8813組・主要集計差0。ただしmatrixには旧潜在IDがなく、修正経路の回帰を代替しない。
- 研究効果/費用/条件表示のfocused UI3件PASS、実研究の投影攻撃+1と保存再起動を確認。全UI32件中31PASS/1FAIL。旧課題ボタンを探すテストの不整合は旧FAILを保持し、新lock labelへの修正後、F843で最大文字サイズを実設定した1件がPASS。設定largeへ復元確認。Root画像確認済み。
- 全UI診断には装備Menuのcontrast、探索2操作の小領域、仲間の匿名contrast、Dynamic Type警告が残る。採集帳/工房の2監査がCode -56 timeout。診断testのPASSと指摘0を分離。raw/画像/tree/Root判定は `qa_drafts/r019_research_readability/full_ui_r001/`。
- app051158の採集20遷移R004は20/20PASS、3指定cueは120ms表示/450ms消去、他17に表示なし。save/revision/snapshot不変。これは合成presentation audit。実claimの正gain/zero/failure/controlは別R003証拠。R01金色の弱視認に対する暗い縁取り候補はapp053334へbuildし実画面QA中。
- app051158の15課題sweepは全15で勝利/4人/初回報酬/revision/savePASS。全結果画像をRoot確認。再起動画像がloadingだったため、Core receiptをUIreadyと誤認せず、同一AFTER_SAVEをF843新隔離namespaceへcopyした操作可能画面の補足検証を実施中。fixture装備とQA command起動を明記。
- R014ローカルcheckpoint377f5def。05:23原24420files照合PASS、元checkout既存差分のみ。05:20媒体14050files/46.12GB、不安定0。以後の候補・媒体は次checkpoint対象。push/公開/実課金/認証/SIP変更なし。

## 2026-10-11 06:04 JST — R020 real UI, saved region, and corrected video extraction

- R020 freeze053617 compact buttons: 3/3 PASS (51.010s), 44pt geometry and actual padding taps confirmed; home/explore/shop audit 0/1/0, residual notice Dynamic Type warning preserved. No baseline actual-tap failure was measured.
- app054008 cold saved-region fix: 2/2 PASS (90.497s), real R05→R02 selection and same-save restart, plus challenge foreground. Independent R003 copies15/15 keep R05, normalized snapshot and byte SHA; Root inspected all15 rendered screens. Three-build60source/1885resource alignment PASS. New trace helper is outside that build.
- R020 real gather UI: freeze054602 1/1 PASS17.649s; freeze055553 with isolated buffered frame trace 1/1 PASS17.151s. R004 trace377rows: cue removal0.3762s, alpha0 at0.7929s, present/complete1.7096s, max frame delta0.016667s. Runtime action timing unchanged.
- Initial pre-input-seek plus fps-resampled screenshots misrepresented the cue as one frame. Re-decode from the start with select(t)/showinfo/passthrough establishes462frames/PTS for R003,217 for R004. Root inspected R003 overview and R004 contacts01–07: cue visible after sheet, fades, collected prop later fades and returns. Timing-jump hypothesis withdrawn. Intermediate TRUE_PTS contacts were invalid because vfr dropped frames; CORRECT_PTS artifacts are authoritative. See qa_drafts/r020_cue_frame_trace_r004/RESULT.md.
- Independent AX large2/2 and AXXXL2/3: failedpaddingtest assumes regular tab selector, before reaching control. Font scales but notice warning persists; reachability after scrolling requires follow-up. Agent correcting inconsistent report about an adaptive-nav test actually run after restoringlarge, then fixing test entry only.
# 2026-10-11 06:18 JST — R021 継続検証

- 探索アクションの縦配置: freeze060847でlarge2/2 PASS (39.623秒)、AXXXL2/2 PASS (46.630秒)。上端8%余白タップ、44pt以上、適応ナビゲーション、home/explore/shop診断を確認。Root実画像確認済み。通知のDynamic Type警告65536は残る。F843はlarge復元済み。証拠`qa_drafts/r021_ax_action_layout_r001/`。
- app060521の新namespace連続90戦は実行中。ActiveBattleQAは最終HPの読取を戦場復帰前receipt+revision一致へ修正。まだ全90戦PASSとしない。
- ArtのB_R03_A resolve候補3枚は単独7状態Simulatorで順次表示したが、同appの実戦では決着動作未視認。独立source監査でHP=0の再設定ごとのresolve restart、およびfinishBattle直後のsyncScene/rebuildを確認。Rootは終端状態保持・実描画時間待ちを修正しfreeze061727でビルド中。実画面合格は未判定。
- 保護readback R017 (06:06)は元checkoutの24,420ファイル全一致。media SHA R015 (06:06)は15,685ファイル47,215,251,602bytes、読み取り中変更0。この時刻以後の新媒体は次manifest対象。


## 2026-10-11 06:46 JST — R021 runtime evidence

app060521 continuous 30 enemies x 3 cycles finished 90/90 PASS (1765.776 seconds): each battle revision +1, saved snapshot reload equal, terminal HP mismatch 0, unique operation ID. Simulator resident peak 408.078 MiB; not device/balance approval. native/active_battle_r021/ROOT_REVIEW.md pins this build.

freeze061727 UI3/3 and freeze062301 actual terminal3/3 PASS are retained separately. Independent video review found the defeated party returned to idle after the hit pose; holdingBattleResult plus explicit defer release now addresses that presentation gap, but is not yet built. Combined freeze063438 UI2/2 PASS: 45 inactive samples retained identical scene clock/frame counter, then terminal rendering completed after foreground return. Root and independent reviewer saw compact R03_02 AIRA feet on stone rather than void. qa_drafts/r021_combined_ui_r003 and independent_review/holding_battle_result_r001.


## 2026-10-11 07:08 JST — integrated native checks

- freeze064747 actual R005: B_R03_A victory, dragon victory and defeat3/3 PASS with8checks each. Foreground render holds1.283333/1.266667/1.300000s, revision+1, terminal HP match. Independent sequential PTS review sees defeated4party hit and downed NOIR hit maintained until result ends, then field restored. Original R004 premature-idle evidence retained.
- freeze064747 UI2/2 PASS101.489s: result→field→newR01battle→field and background result.43inactive samples keep identical sceneClock/frame; hold1.25rendered seconds. Evidence qa_drafts/r021_integrated_ui_r004.
- freeze065330/manual065354/XcodeFlightR005/unsignedDeviceR005 build and alignment PASS61source/1889gameResources. PNG1881decode, runtime missing0, receipt mismatch0. Full UI pending in separate independent run.
- movement_r031 dragon and E_R01_03 seven required states verify receipts. r032 adds explicit flight→idle→walk→idle, verifies walk frame0/1 and inactive overlay in flight/idle; independent review confirms route separation, motion quality PARTIAL.
- CombinedR003 20areas×2sizes independent review finds no new obvious floor/collision issue. R03_02 compact gap119.8pt retained; R04_04 raw FAIL kept as parenttexture dimension check mismatch while5clips/4screens visiblyrender.
- PROTECTED_READBACK_R01807:01:24,420unchanged. MediaR01607:01–07:02:16,462files51,542,981,187bytes, unstable0. Later new art repair is outside this timed snapshot.

## 2026-10-11 07:40 JST — R022確定分

- freeze072550 / manualapp072630 / XcodeUIR022MusicR002 / unsignedDeviceR022MusicR002:62 source/1893resources alignmentPASS、1881PNG、参照欠落0。
- Musicreal-playerR00223/23 PASS、旧player解放.426909s≤.600s。R00120/21FAILと同exe21/21PASSは保持。
- R022UI6/6 PASS169.587s。設定永続化はUIassert、実背景停止/復帰は同runhistoryで独立検証。地域メニュー単件PASSは旧fullUI36/37を消さない。
- 同freeze通常gameplay music:home→field→battle→field、5checksPASS。QAfixture起動でありearnedprogressionではない。
- ERNAapp065354:standard/travel×branch/moon4構成、各5heldsourceSHA/manifest/buildreceipt照合、連続動画、家/探索選択表示。rawFAIL2件保持、QAhelper8testsPASS。自然さ/採用はPARTIAL/PENDING。
- 装備R009:53consumersの資源一致を照合、27未監査行をheld画像で追加確認。微細な接触/後続AIRA位置の未検証を区別。新規明白なgrossfit不良は確定していない。


## 2026-10-11 08:00 JST — R023 packaging and evidence scope

R023 startupUI2/2 PASS20.199秒、同freeze region-menu sequential10/10 PASS118.434秒。以前のUIKit SIGSEGV原因UNKNOWNを維持。unsigned archive alignment62sources/1894ownedresources PASS、独立全resource1899一致。未署名/arm64/iPhoneOS17/dSYM UUID一致。earned day90 fourbuilds×5saves20/20合法・勝利、通常campaign R014+500BP; oneboss/seedでありR6 synthetic360previewと混同しない。


## 2026-10-11 08:30 JST — R025固定パッケージとR004棄却

R003結界/毒の2試験は各1/1 PASS。30campaign/15challenge、敗北0、実クリア日20/25。4,974file全SHA一致と各runログ/report/actionのSHAを独立監査。48行matrixは36可用勝利/12不可用。旧source mismatch所見は別run参照による誤りとして撤回。R004 rawは2135x737 RGBA、固定mask外1pxAA許容では差分0だが、前足は逆方向へ移動、爪が広がるため自然動作FAIL。未統合。実機は登録1台切断、NOT_RUN。


## 2026-10-11 08:49 JST — R026 strict input最終照合

6保存×4構成×6戦況×3seed=432条件、324WIN/108UNAVAILABLE/0LOSS/0COMMAND_ERROR。focused1/1 PASS、直接swift process exit0。全6raw source SHA不変、43file freeze一致、432キー重複0。旧入力runとの勝敗/イベント/報酬/HP/時刻差0。時間はCore仮想時間、全4人生存はlate-game候補での範囲。旧compile失敗/teeログ欠落/不正JSON/source旧版未保存は訂正履歴を残す。


## 2026-10-11 09:48 JST — R024限定メッシュ統合と実UI監査

R004 mesh geometry13×429が固定prototypeと完全一致。app092933のdefault16sample/非walk14sample復元PASS。freeze093652の背景UI1/1 PASS23.255秒に加え、host180row検証PASS:31inactive/3.374秒でmesh+frame不変、復帰129row/125mesh変化、idleでwarp除去/subdivision2。初回QAcontext欠落R001は失敗のまま保持。装備AXXXL R8は1/1 PASS47.170秒、保護解除/再起動/save確認。両件独立監査済み。manual094028/XcodeSimulator/unsignediPhoneOSは64source一致、game resource不整合0。実機未実行。自然さと実戦入口接地は未完。


## 2026-10-11 10:37 JST — 復旧とR025実戦入口

checkpoint2c4b3c20/289candidate/64source/1900oldapp hashを独立照合、元24,420files一致。app101722の実戦R004/R005/default3件でgetter・保存・勝敗・cleanupPASS。R004前足19.1516pt移動→R0050.0000153pt、root1.5470pt、実walk.59277秒。visiblemarker55/58対応、独立5負例拒否。7grid/429vertex/930,816正向三角形。自然歩行・全接地PARTIAL。R001長時間captureFAILは勝利文字列の完全一致predicate誤りとしてraw保持/同run保存を別receiptで回収。初回marker遮蔽は後続で修正。R005初回compileのCGPoint曖昧型は修正し別build成功。

manual101722/Xcodefreeze102208 Simulator/unsigneddevice buildPASS、66source一致。後続lifecycleobserverのsourceは別build。装備R031追加26sample・53consumer追跡、R032S03拡大clone比較を不採用。効果46bindingの実証/未実証区別とE_R03_02Core16割り込み到達を保存、nativeは実行中。


## 2026-10-11 10:55 JST — R005実入口lifecycleと最新build

R003UI1/1PASS、host265rowPASS。inactive.423→active3.907secで3.48388sec、OSbackground2.84933sec。frame877/root/4観測点不変、復帰12frame12warp、idle解除、勝利save3。1frameidentityhandoffを限定規約で認め、独立5negative拒否/raw不変。R001タイミング+UI誤判定、R002早すぎるHome、R003初回hostaction規約失敗は保持。66runtime source一致manual104513/sim104543/device104051、各凍結1899resources一致。device未署名/実機未実行。E_R03_02nativeR003はreceipt混入訂正時の元copy未保存で無効化、R005別runを独立監査中。


## 2026-10-11 15:24 JST — R026継続開発

app150510:71source/1892PNG、unsignedfreeze150756とのsource/resource整合PASS。cachehost6/QA契約10/native20場面x2+96IDpressure、lastpressure37evictions、復帰込み最大66864384bytes、state/save不変。E_R03_02fixture実戦1件、revision+1/HP/save/mediaPASS。UI frozen-source build2devicesx2sizes=4/4、16screens、固定51/56復元。manualとはexe差あり。strict72cell/36対両勝、原6save/43Core不変。詳細と各不足はCURRENT_STATUS/原receiptへ。原24420SHA全一致。


## 2026-10-11 15:41 JST — UI可視性の誤判定訂正と再検証

旧run_r003はapp.minYだけの条件でF843 AXXXL home文頭のheader遮蔽を見逃した。Root画像で発見し旧全体可視主張を撤回、raw不変。新freeze153038は同71runtime、testを実ScrollView境界と双方向dragに修正し4/4再成功。F843 claim y293–570.5pt/viewport165.5–578ptで全文表示を直接確認。16画面/各51,56固定復元。runnerの失敗時証拠保全5hosttestsもRoot再実行PASS。
