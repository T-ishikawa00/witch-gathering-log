# R087 fixed-SHA UI/art audit

**Target:** `28d3d0b92c840f215a945f47e574fcb30ef2253b` (R087), compared with base R086 `45dc02f73f0bcb7c37ad1f01969c3d4b43ceef2e`. Read-only; no build, test, app launch, or source change.

## Finding

No P0/P1 UI or art regression is supported by the fixed evidence. R462’s inventory clear action had a real UI defect: after the list returned to 43 items, the Japanese IME query remained visible. R465 preserves that failed run and shows the correction in the ordinary UI screenshots and cold reopen. R014’s UI-01 status is appropriately scoped; its description of the defect as resolved matches the R465 evidence.

R014 does not claim final acceptance of the 159 assets, all party motion, or all enemy motion. Its ART-01 and ART-02 entries remain partial. That is consistent with the evidence: the 17 direct-attack recovery routes are still unobserved, but the R457 eligibility reconciliation found zero retained eligible-but-uninspected intervals, and no reproduced renderer fault. This is a bounded evidence/natural-motion gap, not 17 demonstrated broken assets. Formal art adoption remains separately pending; it is not being used here to erase the technical limits.

## R462 failure and R465 correction

R462 run `799b47c3-09fb-4461-a16b-2f754a5278be` is retained with status `CAPTURE_CLOSED_FILTER_GUIDANCE_COLD_SAVES_EXACT`. Its `filters_cleared` screenshot shows 43/43 and 「すべて」 but still displays the query text. The exact screenshot SHA-256 is `c3a00aa8687eb31d264a73e92b43a5aa1ce9b59996cf0b4d7c711afdf29017d3`. R465 root result explicitly says `replacesFailure: false` and `priorFailure: R462 preserved UI_FAIL; R465newsource scopedPASS`.

R465 run `f3fdf3c8-7ba7-4c69-ae3f-f58253bbadce` shows the expected no-results state, then a visibly empty search field with 43/43 after clearing; its cold screen reopens the inventory with the placeholder, 43/43, and all quality selected. All three screenshot hashes match both the RUN screenshot hashes and the SHA-256 of the image blobs in R087. R465 records revision 138 throughout, `protectedUnchanged: true`, and exact `save.json` and `save.json.previous` hashes at cold reopen. The Root result records that retyping works and that clearing during active IME composition also works; the active-composition interaction has no dedicated screenshot, so it remains an execution observation rather than a separate image-verifiable claim.

The fix is present in the exact frozen R465 inputs: `WorkflowViews.swift` has `@FocusState`, binds focus to the search field, and gives the field a generation identity that increments on clear. The R465 source map contains 240 entries; its source-map SHA equals the build receipt’s `sourceMapSHA256`. The mapped `App.swift` and `WorkflowViews.swift` hashes match the blobs in this fixed commit. The R465 build receipt reports both Release SDK targets, 1,922 packaged resources, exact resource maps and SDK parity. This verifies the UI result against the recorded build inputs, not a physical device.

## ART-01 / ART-02 limits

- **Party/art assets:** R014 retains ART-01 as partial and does not equate state-route presence with natural-motion acceptance. R460’s scoped review found no concrete high-impact party/costume/furniture defect at its audited source revision; this audit finds no new screenshot evidence that contradicts it.
- **Enemies:** R014 retains the 17 recovery observations as unobserved. R457’s R002 reconciliation records 16 routes where hit/terminal resolve preempts recovery and B_R01_A without rendered execute, with zero eligible retained windows left to inspect. This does not justify modifying combat priority or marking those actors failed. It also does not justify marking every recover route visually accepted.
- **159-unit register:** keep the per-row partial/unaccepted classification. The reviewed record does not prove all 159 assets are absent or defective, and this bounded audit does not elevate them to fully accepted.

No additional local source or asset change is justified by this fixed-SHA review. The remaining limitations are broader natural-motion/asset acceptance and formal adoption, not a reproduced P0/P1 defect.

## Fixed evidence pins

- R087 commit: `28d3d0b92c840f215a945f47e574fcb30ef2253b`; R086 base: `45dc02f73f0bcb7c37ad1f01969c3d4b43ceef2e`.
- R014 register `final_acceptance_r360/COMPLETION_REGISTER_R014.json`: SHA-256 `b6cae7083e9c266b5f9d20c657c4a2004b0ec0b66c34617dd6b4e16856fb2ee8`.
- R462 `RUN.json`: SHA-256 `70f6aad69924dee2b1bab2d5e9f469ba35671b6b6e25328767b81ceec701e71a`.
- R465 `ROOT_RUNTIME_RESULT_R001.json`: SHA-256 `c5e2fe7c64d04b652533de32235e8899471c8670ad4b92334ebf5069c49b685f`.
- R465 `RUN.json`: SHA-256 `4e07fe87f54f83066d4fdfa5cdbd42e5f7b3f961b2365ee3f12d164af75303b1`.
- R465 build result: SHA-256 `66b45e87c0154446c58c71507cb7535dcd99cd11e9f414ddf87efd18b99fe38e`; source-map SHA-256 `6f50a2e250c99450d303e509946d9199fa14e95fac2718df7619947d8a1a268a`.
- R457 recovery eligibility addendum: SHA-256 `fd095cf16dbf160c26fda63444cbd49b37004d35cb410bad0387ef39f1abaab1`.
- R460 UI/art review: SHA-256 `5d3fcfa5542dddbdcd3d134014c83a0b6708da91dff405e5160f1f873707a75d`.
