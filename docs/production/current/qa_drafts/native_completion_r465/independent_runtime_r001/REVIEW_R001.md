# R465 inventory-clear runtime review

## Result

R465 closes the specific R462 inventory-clear UI failure within the captured scope. In the saved `empty_search` image, the 43-item inventory shows 0 matches, the Japanese query is visible, and the no-results guidance/clear button is present. In `filters_cleared`, the field displays its placeholder, quality is 「すべて」, and all 43 items are visible. The cold-reopen image returns to the inventory screen with 43/43, the placeholder, and 「すべて」. R462 had shown the old IME query remaining after the list was restored; R465's before/after/cold images show the corrected state.

The three images prove the ordinary entered-query clear and cold state. Root separately reports a second interaction: after focusing and typing `zz`, clearing while IME composition was active removed the query and restored all 43 entries. That active-composition action has no dedicated screenshot, so it is recorded as a run observation rather than independently image-verified here. The reported Return check did not resurrect the earlier query; a paste attempt had no observable effect and is not counted as successful input.

## Save and build correspondence

`ROOT_RUNTIME_RESULT_R001.json` records `SCOPED_UI_SAVE_COLD_PASS`, revision 138, exact primary and previous save hashes, 7,776 protected files unchanged, and the app stopped. All five R465 checkpoints report revision 138 and unchanged protection; cold primary/previous bytes are exact. The derived startup identity receipt changed on launch as expected and is separate from the game save.

The raw run is `CAPTURE_CLOSED_FILTER_GUIDANCE_COLD_SAVES_EXACT` for bundle `local.witch.autonomous.r1.completion.r465`. Its sealed build receipt is SHA-256 `66b45e87c0154446c58c71507cb7535dcd99cd11e9f414ddf87efd18b99fe38e`. The build result reports both Release SDK targets, 240 frozen source inputs, 1,922 resources, exact resource parity, and no install/launch during build. Freeze source-map SHA `6f50a2e250c99450d303e509946d9199fa14e95fac2718df7619947d8a1a268a` matches the build result; the mapped `WitchApp/App.swift` SHA `3ae262c5c3bae250b20e7c4971256ff1c3ec00043f4b607de34b2e683603594a` and `WitchApp/WorkflowViews.swift` SHA `59aad7ee6c0476744f2e93b1d64f57c87509ba392375d1e968609d3bb793dfc8` match the current live files. This links the observed fix to the frozen R465 build inputs.

R462 remains preserved as the prior UI failure; this report does not rewrite that result. The R465 run does not establish all accessibility sizes, physical-device behavior, or broader UI/art quality.

## Evidence pins

- R465 raw `RUN.json`: SHA-256 `4e07fe87f54f83066d4fdfa5cdbd42e5f7b3f961b2365ee3f12d164af75303b1`.
- R465 root result: SHA-256 `c5e2fe7c64d04b652533de32235e8899471c8670ad4b92334ebf5069c49b685f`.
- R465 home image: `e7c58836dd391e1a5dcbed4c3460870ef7a6a52b7a43766e9e1586a98bc1f160`.
- R465 empty-search image: `18d551c325a2f61f58533093035b3aeebb36d09dc95e529b1d39f8d3bc0ac7c9`.
- R465 cleared image: `e9cea1052b19155614807a3eacbe470724c37d279cf6e1a9ae4c81f619ca552c`.
- R465 cold inventory image: `327b7070f9e1dff972b9567a42caa4b60edcef42883b859f97940a6f1ef963de`.
- R462 prior run: `native_completion_r462/runtime_tools_r003/runs/799b47c3-09fb-4461-a16b-2f754a5278be/RUN.json`, SHA-256 `70f6aad69924dee2b1bab2d5e9f469ba35671b6b6e25328767b81ceec701e71a`.

Review was read-only; no run, app, save, or build artifacts were changed.
