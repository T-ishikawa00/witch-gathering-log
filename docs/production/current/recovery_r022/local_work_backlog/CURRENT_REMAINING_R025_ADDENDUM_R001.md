# R025残件監査の時点差追補 R001

この追補は `CURRENT_REMAINING_R025.md/json` を履歴として保持し、後続証拠で変わった評価だけを訂正する。元ファイルは編集していない。

## 訂正

1. **Jelly E_R02_03** — 旧R025本文は21sampleのRoot/visual判定を残件としていた。後続 `qa_drafts/enemy_loop_seams_r001/jelly_e02_r001/midpoint_walkb_idle_a_r002/native_states_r003/ROOT_REVIEW_R001.json` と隣接 `jelly_settled_transition_r001/independent_review` により、Rootの21sample全判定、直接contact確認、およびart独立source/resource/UUID/7 settled/20 restore/video decode検証が完了した。旧記載はこの範囲で解消済みとする。自然さ/Human採用の意味には拡張しない。
2. **46 effects metadata** — 4行の新証拠照合は `recovery_r022/effect_campaign_audit/independent_r025/INDEPENDENT_ADDENDUM_R025_R003.md` で解消済み。baseline欄は歴史のまま保持され、30/31 combat IDs across buildsにcommitted traceがあるという限定も変わらない。全46最新build再実行ではない。
3. **status/build時点** — CURRENT_REMAINING_R025の「status 14:06対bundle 14:16」時点差は古い。現 `CURRENT_STATUS.md` は2026-10-11 14:26 JSTでR024 checkpoint/app141658と後続のchallenge/effect/Jelly記録を含む。今回の15課題対応表はR019 app051158を対象とする別の履歴証拠であり、app141658の再実行とは称さない。
4. **15 challenge実戦** — 旧文面が求めたID別既存receipt照合を行った。R019 app051158のNative battle runとrestart/reanalysisには15/15全IDがあるため「実戦receiptのないID」は0件。未解決はより狭く、①R019再起動画面が15件ともR01を表示した問題の修正後15 ID確認、②candidate challenge mechanicの正式仕様忠実性/獲得済みbuild戦略多様性/Human評価である。R016のchallenge foreground/地域復帰はCH_R03_03のみ。

詳細は `challenge_coverage_r026/CHALLENGE_COVERAGE_R026.md/json` を参照。Core候補fixture 15件、Native candidate runtime実戦15件、R019 restart readback15件は別々の証拠クラスとして記録した。R034 matrixのchallenge rowsが各0の意味は未解決のまま残し、「実戦なし」として転記しない。

## Pins

追補作成時の既存根拠SHAは以下のとおり。

- `CURRENT_REMAINING_R025.md`: `1b7ae306ce2196a3961a462d669b9ccdfd4d57d853fc1f0e085031461a81e219`
- `CURRENT_REMAINING_R025.json`: `cac953da4f02d7172ea2d85074d9bf6a192c9f2e5635c8703ca64166ff0ae143`
- R025 effects addendum R003: `824ed579a00fa26c75c519a84f7d0780d8f838efb92a8648f7db51a8fba5beb5`
- `CURRENT_STATUS.md` at audit: `47d6e79030acd651dd59107d38b9166e961b1dae43518cc16ddc4ed41dff055b`
- R019 native challenge run: `90e5d6117780b6369aaa3f65a7279c199a150d5705b1bf143d92b56a819179f1`
- R019 restart run: `18beb5751f113ab3aa20fc5a89969469928ef07f4157e03708c38fd809e36e28`
