# R093 equipment consumer native review

Status: **technical trace confirmed, visual legibility PARTIAL; not formal acceptance**. This was a read-only review of three isolated forced-render showcases, not ordinary combat.

## Pin and preservation check

- App: `native/build/app_R093_compile_r002/WitchGathering.app`; executable SHA-256 `3190724a9cd50be11468d5241956e5ee4da34de997f5c0d8eb3f62f5cc5866ee`; build receipt SHA-256 `f91908d541ac816d2ac48bb9b66bbcd371ce61fa9994c24ed0dea1ca2ceb8309`.
- Source snapshot: 140/140 source files matched pinned bytes. Bundle resources: 1914/1914 resource files matched. The 20 selected detail PNGs also matched byte hashes; independently decoded sRGB/premultiplied RGBA pixel hashes matched the recorded texture pixels across all 33390 sample records.
- Each run reports fixed receipts restored and prior JSON exact: v01 1090 prior / 104 fixed; v02 752 / 94; v03 1092 / 104. Each owned process was stopped and recorder exit/decode/probe were zero.

## Coverage and limits

The three variants cover 18 + 18 + 17 = 53 distinct formal consumer IDs. Each trace has 630 monotonic rows; every consumer contributes 90 samples in each of idle, walk, anticipate, execute, recover, hit, and resolve. Sprite-owner mapping, body-frame association, registered geometry, texture/resource identity, and world bounds passed the R084 validator after an in-memory correction of its stale `hand` expectation to the actual `hands` slot. I did not modify that validator.

The validator still returns only visibility exceptions: 106 rows in v01, 467 in v02, and 455 in v03. These are backed by explicit runtime visibility rules: source rows marked `semantic_occluded_row`, hem rows marked `exact_hem_underlay_occluded_candidate`, and familiar gear `EQ_F_02/03` with `visible=false` in non-cast phases. They are not missing texture/pixel/geometry rows. The raw records remain unvalidated status; this review does not turn the exception-bearing raw runs into PASS.

Video was decoded without frame-rate resampling and every 30th decoded frame was OCR sampled. Exact EQ53 marker joins were 22/25 for v01, 21/25 for v02, and 22/25 for v03 (65/75 total); all observed marker values pointed to matching trace rows. This is a sampled join, not proof that all 630 trace rows appear in the video.

## Visual finding

The inspected full screens show the four characters against the exploration field, the EQ53 QA marker, and the `4人で自動戦闘中・0秒` banner. That is forced QA presentation, not a natural battle. At F843 the ring detail is 2.8545 pt, roughly 5.7 raster pixels on the 2x screenshot; at 9A it is 3.8709 pt, roughly 11.6 pixels on the 3x screenshot. The trace proves that the ring sprite is present and registered: LUNA and AIRA rows are visible in all 630 samples; ERNA is visible in 620/630, with ten source-declared walk occlusions. At these footprints the crops do not let me independently identify the ring design with confidence, so perceptual legibility remains PARTIAL.

Evidence includes the exact selected full-frame screenshots and no-resampling diagnostic crops under `marker_samples/`; full capture, trace, video, selected-resource and pixel-hash pins are recorded in `REVIEW_R001.json`. Human approval, formal adoption, natural motion and natural combat are not claimed.
