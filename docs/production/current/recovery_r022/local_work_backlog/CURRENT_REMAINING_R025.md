# ③〜⑤の現行ローカル残件 — R025

**判定:** 独立読み取り監査。対象は現行要件、R034 bundle、既存 backlog と後続証跡の整合。コード、画像、保存データ、Simulator は変更していない。機械可読の根拠・SHA は同フォルダの `CURRENT_REMAINING_R025.json`。

## 次に着手できる具体的な作業

1. **クラゲの7状態遷移を最終helperで検証する。** R034 app141658ではACT_E_R02_03の14 early/lateと7 settled、計21サンプルを採取済みだが、run statusは `CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW`。Rootが追加した単調時計offsetとsettled遅延上限を使ったhost判定・見た目確認を完了する必要がある。先の状態確認失敗はanticipateの公称終了から約9ms後に正規終端frameが残ったものなので、33.3msの境界許容だけでは合格にできない。settledのidle復帰、execute→recover→idle、resolve終端保持を別々に確認する。ゲーム内のclip速度は変更しない。

2. **15研究課題の実戦証拠をIDごとに埋める。** 受入基準は複数の毒・結界・反撃・回復・追撃構成と、15課題の敵条件を実装済み効果で検証することを求める。R026の比較で明示された課題はCH_R02_03、CH_R03_03、CH_R05_02の3つ。版順資料も「全15題の実戦テストは未完了」と記録している。まず既存receiptを15 IDに対応づけ、証拠のないIDだけ通常の `resolveChallenge` 経路で戦闘・報酬・revision・save/restartを記録する。既存数値や条件を足さない。

3. **磁印効果を現行候補bundleで1件だけ実戦確認する。** 最新のR025独立照合は31 combat asset IDs中30 IDsのcommit済みtraceを複数buildから確認し、残るACT_E_R03_04_magnet_pullcueをopt-in-onlyとしている。現行R034のsource pinには専用Bindingが含まれるため、残件は全46効果の再試験ではなく、候補設定を明示した実戦で同rootのmark tell、次の実hitまたは既存interruptによるcancel、意図対象、cue/impact cleanupを確認すること。候補イベントが実行されないbuildでは未実施と報告する。

## backlogの更新点

R024 backlogの「竜のbattle-entry観測」は、R025で実際の入口3経路とR005 root/足先同期を採取したため、その測定範囲では閉じている。歩行自然さは別のPARTIAL項目として残る。R026の108 unavailable cellも、実数は6 save-plan loadoutであり、派生save上の通常drop/evolve/equipで到達した。合計988回の勝利drop戦、40回のevolution、36回の固定seed検証戦を要した。これは到達可能性を示すだけで、周回負担の妥当性は示さない。

46効果の広範なcampaign sweepも未更新backlogのまま反復しない。R025の内訳は31 combat中30 IDにcommit済みtrace、15 environment IDに過去count。4行の古いqualification文言が後続証拠と矛盾するというmetadata訂正は残るが、一般の46件再実行を正当化しない。

## 完了・未完の境界

R034 bundleは1,912 files、PNG 1,892件のdecode PASS、runtime missing references 0件。これはcandidate bundleの整合性であり、全内容の受入ではない。support通知36回帰、AIRA 27点のsource監査、6 loadout到達性、30 combat effect IDs across buildsなど後続証跡を、古いR024 backlogの状態で上書きしない。

この比較でR025 status資料には版ずれがある。`CURRENT_STATUS.md` は14:06、`CONTENT_SCOPE_AND_GATES_R1.md` は08:49時点でapp074517/R023を参照し、R034 bundleは14:16のapp141658。次の検証が安定した後、current status/matrix/backlogのbuild pinを揃える。過去記録は改変しない。

未承認候補、自然さ、Humanの面白さ・購入価値判断、物理iPhone/VoiceOver、署名、Sandbox/JWS/本番取引は、上記ローカル作業の代替でも根拠でもない。AIRA walk6のboot pointはsource上で可視だが境界が曖昧との判定であり、現時点で座標移動の根拠にはしない。
