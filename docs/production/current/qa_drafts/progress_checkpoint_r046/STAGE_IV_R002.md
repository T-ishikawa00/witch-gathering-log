# Stage IV current-scope reconciliation R002

**Correction:** the old `111 source / 48 no source` split belongs to the October 8 base ledger. It is not a current runtime-art count. In pinned R093, all **159/159** baseline IDs map to an exact same-ID runtime-index entry, and every counted PNG reference is present and SHA-exact against the R093 build receipt. For the 48 units that had no source declared in the base ledger, this proves a compiled/candidate payload exists; it does **not** prove that an editable source or approved original source is now available.

## Source pins and interpretation

- Base inventory: `assets/g2/production/codex_unified_20261008T221040Z_fa70940c/planning/FINAL_159_LEDGER_R001.json`; SHA-256 `55f48fe35340eeeaa1960aadd3ac21157896415d0ecc5cac164345002742ec9d`. It records 159 units, 111 `source_present`, 48 `no_source`. All 111 units’ declared source/editable file paths still exist and match their declared SHA; the remaining 48 have no source declared by that snapshot.
- Current bundle: `native/build/app_R093_compile_r002/WitchGathering.app`, executable SHA-256 `3190724a9cd50be11468d5241956e5ee4da34de997f5c0d8eb3f62f5cc5866ee`, receipt SHA-256 `f91908d541ac816d2ac48bb9b66bbcd371ce61fa9994c24ed0dea1ca2ceb8309`. Receipt status is `SIMULATOR_BUILD_PASS` with 140 sources and 1,914 resources; `physical_device=false`, `signing=false`, `upload=false`.
- Generated art/runtime register: `native/build/app_R093_compile_r002/WitchGathering.app/Art/runtime_index.json`, SHA-256 `8fc519482a5dd99d6fb3e20aa2e28c758533177217cdc09fd98e05981fe97b95`. It contains 187 entries, including all 159 baseline IDs, four party poses, and 24 additional detail entries. Entry presence is a resource/renderer-candidate registration fact, not an approval or natural-quality result.
- Quality links: `CONTENT_MATRIX_R059_APP020805.json` SHA-256 `c0a1bebf0f03fcf6db521c5ecf9b2d43be20de12031dc67cce9a5397b516a27d` (248 rows, target APP020805), and `CONTENT_PROGRESS_SUPPLEMENT_R071.json` SHA-256 `a5933bd123809f67a14961526693d45ef087c6f989b09bd6e30329e39f1a52d0` (57 rows; all `PARTIAL`). These are linked per item in `ALL159_CURRENT_MAPPING_R001.json`; R059 was not captured on R093.
- Current scope context: `CURRENT_STATUS.md` SHA-256 `5f5a626e0371272ae83fc9e692926579df11378b6c245bc255822c8190b31937` (R108).

## The 159 IDs, reconciled

- Historical declared source: **111/159** have a current matching file at the path and SHA in the old source ledger. **48/159** were `no_source` in that snapshot. Do not label those 48 as currently unmade: their current R093 runtime entries/payloads exist. Current editable-original provenance for those 48 remains `UNKNOWN` from these inputs.
- R093 resource register: **159/159** IDs have exact runtime-index entries. Runtime references resolve to current bundle files whose SHA matches `BUILD_RECEIPT.json`. Effects are expanded through their member IDs; the dragon’s loaded PartRig manifest and its referenced parts are checked separately. R093 contains candidates; it does not establish that each candidate is active or adopted.
- R059 linkage: all 159 map either to a direct row (139 units) or the appropriate regional/effect group (20 kit units). Readiness and issue statements are kept per mapped row. R059 still has 242 `PARTIAL`, 1 `NOT_PRODUCED`, and 5 `INCOMPLETE` rows; those are R059 matrix-wide totals, not 159-unit completeness counts.
- R071 linkage: 53 rows relate to 20 of the 29 baseline gear-icon units. The 57-row supplement is consumer-level evidence, not a one-row-per-item art ledger.

## Enemy states and remaining quality work

All **30** enemy runtime IDs sit under the seven-state request contract: `idle, walk, anticipate, execute, recover, hit, resolve`. **29/30** have indexed frame/registered-pose arrays for all seven states. `ACT_B_R04_B` uses a nested PartRig: idle/flight plus registered combat poses, with walk supplied by the simulator-local R064 candidate; non-Simulator builds keep the prior flight-rendering fallback. It is not seven authored image sequences.

Natural motion is still **PARTIAL for all 30** in the R059 content rows. They explicitly leave Human natural-motion acceptance pending and say historical state receipts do not prove all current combat mechanics. An indexed sequence or controller state does not prove loop seams, contact, direction changes, hit/resolve transitions, or current R093 full-battle behavior. This reconciliation does **not** claim a same-build R093 seven-state native review for all 30.

## Other tracked launch scope

The R059 matrix lists all four party characters as `PARTIAL` on continuous natural motion and final art adoption. It lists three appearance candidates, one furniture candidate, and 14 UI surfaces; these remain `PARTIAL`. Current status R108 records an R094 wardrobe test that failed because the picker value was empty, so wardrobe interaction is unresolved. Character voice remains `NOT_PRODUCED`; no voice direction or production choice is inferred.

This is an inventory and evidence correction only. It makes no sale-count, formal adoption, or release-readiness decision.

Full per-ID source-file checks, R093 path/SHA payloads, R059 row joins, R071 consumer links, and 30-enemy per-state counts are in `ALL159_CURRENT_MAPPING_R001.json`.
