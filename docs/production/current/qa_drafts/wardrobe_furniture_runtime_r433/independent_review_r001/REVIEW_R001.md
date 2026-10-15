# R433 capture helper source review

Status: **BLOCKED before execution**. The helper cannot import as written. At line 10, `BASE.parents[4]` resolves to the repository `docs/` directory because `BASE` is the nested `candidate_r001` folder. Consequently `PRIOR` at line 12 resolves to `docs/docs/production/current/...`; `load_helper()` at lines 24–30 then tries to hash a nonexistent `snapshot_r421_r002.py` before argument handling. No capture or lifecycle operation was run by this review.

Additional bounded issues to account for after the path fix:

- `cold` at lines 110–115 relaunches and waits a fixed 0.5 seconds before copying the save and taking an optional screenshot. That proves byte equality at those instants if the app is still starting, but does not itself prove the reopened UI is ready or visibly restored. Have the operator confirm the reopened screen before the post-cold checkpoint, or add a bounded explicit readiness handshake.
- The 180MB gate runs before each snapshot and reserves a fixed 6MB, but `shot=True` does not enforce an aggregate byte cap after `simctl screenshot` (lines 57–61). A large screenshot could exceed the declared run cap. Add an immediate post-capture aggregate check and preserve an over-cap receipt if it fails.

The fixed executable-path ownership check and app/protected-tree hash comparisons are otherwise narrowly scoped. `stop_owned()` only signals PIDs whose launch receipt names the R420 bundle and whose executable command path matches the pinned app. The helper snapshots support files via the pinned read-only R421 helper; it does not write the game save. These observations do not establish that the planned capture run is safe to start until the import path is corrected.
