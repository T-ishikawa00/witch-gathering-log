# R086 fixed-SHA gameplay and save audit

- Audited revision: `45dc02f73f0bcb7c37ad1f01969c3d4b43ceef2e` (R086).
- The native gameplay/Core source files inspected match that revision. The checkout has an unrelated modified PBX file; it was excluded from this review.
- Scope: progression, combat completion, natural gear/evolution/economy evidence, SaveRepository implementation and retained crash/cold-start evidence. No tests, builds, devices, or saves were run or changed.

## Findings

No reproducible gameblocking save or progression defect was found in this scope. The evidence supports bounded claims, not blanket release acceptance.

- **Campaign and challenges:** R443 documents a normal UI progression from 28 to 30/30 campaign encounters, then a run ending with 7 challenge clears. The five free mock-draw products were in the earlier loadout, so this is not a pristine no-mock campaign. R449 later records 15 new challenge wins on the current 19-slot loadout, with zero historical mock UUIDs equipped; 18 equipped items have natural-acquisition provenance and one is a starter. It starts with 7 earlier challenge clears/rewards, so those first-clear rewards are prior history. Its distinct-process cold reopen preserved revision 137 byte-for-byte.
- **Long progression:** R448 provides one passing, scripted 30-day Core case (seed 100049); its earlier failed assertions and wrapper-incomplete status remain preserved. R452 adds two passing 30-day Core cases (seeds 100069 and 200071). Across these three cases, each reports 30 campaign wins, 15 challenge wins, 5 studies, one craft, 11 evolutions, zero summons, and zero synthetic grants. This establishes reproducibility for those virtual schedules, not natural player pace or retention.
- **Economy:** R374 ran 16 candidate treatment/horizon cases with one Release build and seed 100049; all 16 rows report PASS. These are virtual profiles, not actual purchases, adopted products, or human pacing evidence.
- **Save integrity:** `SaveRepository` serializes transactions, checks operation-ID/fingerprint replay and revision, writes and decodes a staged generation, preserves a previous generation, atomically replaces the primary, and reports possible post-replace commit via the stored receipt (`SaveRepository.swift:493-644`). Recovery selects a valid previous generation for ordinary corruption while refusing recognized future schema/markers rather than silently rolling back (`SaveRepository.swift:655-713`). Core tests cover opaque-field preservation, invalid/future data, previous-only recovery, replay, and injected write failures (`SaveRepositoryRecoveryR001Tests.swift`; `R169SaveRecoveryRegressionTests.swift`). R362 separately killed the exact child after the primary replacement and before directory sync, then reopened, checked both generations, and replayed the same operation without changing the committed save. This is a process-kill test, not hardware power-loss testing. R449 and R456 also record distinct-process cold saves matching exactly.

## Residual conditions

- Real-device behavior, all-OS recovery, and power-loss durability remain unverified; the R362 process-kill boundary does not prove them.
- Natural human play pace and long-term retention are not established by virtual-day Core schedules.
- Candidate economy values and purchase value remain unadopted; none of these simulations proves market or balance acceptance.
- Large-text inventory gesture evidence remains inconclusive after harness attempts; no product scroll defect is demonstrated by those failures. Keep this separate from gameplay/save acceptance.
- This review does not certify visual quality, all 159 art units, commerce, signing, or release readiness. R086 itself leaves the full fixed-SHA audit and Human/device gates open.

## Evidence pins

| Evidence | SHA-256 | Bounded result |
|---|---|---|
| `COMPLETION_REGISTER_R012.json` | `05b0e2d5e7d13585a180652bc429109d20859a57c6c09fc26a5b2db6789ec1bc` | Current R086 scope and limitations |
| `normal_progression_continuation_r443/independent_review_r001/FINAL_R003.json` | `10f06fdf7db989f1e8dac485d8665bf727f5c21164a74b4622d1f2bd46254b4f` | 30 campaign; history-qualified progression and cold save |
| `native_challenge_completion_r449/candidate_r001/execution_r001/CLOSURE.json` | `76152d3e32f96a7f5ef51d1e99eda3fcd44e51c5c10a748e725c5317ac5723c2` | 15 new challenge wins; retained prior history; cold save exact |
| `native_challenge_completion_r449/independent_review_r001/REVIEW_R001.json` | `d7042c4343ee711927e8c6ae27b632b9c9f5c164a8a2fcaeec32e8f6a8581912` | Independent result/receipt/loadout reconciliation |
| `zero_summon_first_craft_r448/ROOT_SCOPED_RESULT_R001.json` | `484d8b2287e437ec41c8934696ca79006815a6abda518cf04a624199dab6a4de` | One scripted 30-day Core case; wrapper failure retained |
| `zero_summon_seed_robustness_r452/ROOT_SCOPED_RESULT_R001.json` | `ceb1e6794d3281712226e56420e3b34692d4ac6194ea965761479d48d8abeca1` | Two additional 30-day Core cases; no summons/grants |
| `economy_release_matrix_r374/candidate_r002/runner_r002/runs/R374_MATRIX_001/RUN.json` | `860273ae6557762adb657dd4a4eee9966fb51f124dd2bbf7c36e2800624aad07` | 16 virtual candidate cases; all report PASS |
| `save_crash_completion_r362/direct_completion_root_r002/execution_r001/trial_001/RUN.json` | `64656be33d3275ce386169c0ae4ff9c718249c873b33d043c4b899ea09016249` | Exact child-kill boundary, replay and save preservation |
| `native_completion_r456/ROOT_RUNTIME_RESULT_R001.json` | `3b98eee9c794c6b1af73ea6b398bbb7dbea988cceb05f23110722e9c29ef77f8` | Final-boss ordinary runtime and exact cold save |

**Disposition:** no gameplay/save code patch is justified by this audit. Continue to preserve the stated device, natural-play, and full-release limits; do not convert this bounded result into overall completion.
