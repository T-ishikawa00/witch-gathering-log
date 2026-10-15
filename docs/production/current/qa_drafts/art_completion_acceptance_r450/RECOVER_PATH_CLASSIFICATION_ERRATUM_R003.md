# R450 R003 erratum — R424 B_R01_A and E_R02_01 evidence

This additive note corrects the R002 classification; R002 and its source records remain unchanged.

**B_R01_A has a rendered execute route.** The preserved first-case recovery record reports three root actions on `ACT_B_R01_A` (16, 18, and 11 visible execute frames; 45 total) in scene generation 6. The original case wrapper failed before batch closure because it expected a fresh-fixture persistence receipt that was not written. The separately retained `RECOVERY_R001.json` marks the case raw, recovered, and still requiring visual/Core review; it also preserves the failed wrapper status. Its three E145-marked samples (scene frames 367/375/382) are explicitly labeled execute in the frame map and show the boar in-frame. Thus R002's claim that B_R01_A had no rendered execute, and the matching “Trace-visible execute frames: None” line in R424's visual-review JSON, are contradicted by the retained trace and sample records. This is a record-classification correction, not a promotion of the failed batch to PASS.

**B_R01_A recover remains unobserved.** The first two execute intervals transition to hit after deferred hits; the third is followed by lethal resolve. There is no eligible no-hit execute→recover window in this capture. It belongs in `executeRenderedButNoRecover`, not `executeAndRecoverBothUnobserved`.

**E_R02_01 is the one natural execute→recover→idle trace route.** The R424 trace records execute frames 433–451, recover 452–470, idle 471–508, then hit and later resolve. The separate recovery review identifies two actual video stills with E145 markers 00451 (attack-end boundary) and 00461 (during recover), with the enemy alive and visible in both. This is scoped visual evidence for the boundary and recovery interval. The trace's own `videoJoin` remains `NOT_ESTABLISHED_OCR_REQUIRED`, and no still is identified for idle frames 471–508. Therefore the route is evidenced, but a fully joined idle-return visual sample is not.

R425's replay of eight captured battle snapshots is a separate Core replay, not a new visual capture; it supports replay parity for those inputs and does not erase R424's wrapper-failure status or extend visual coverage.

## Corrected R450 counts

- R418's original 19-ID recover-missing count is stale after R424.
- E_R02_01 closes one recover route, leaving 18 raw R418 gaps in the R450 accounting, including the support-role exception E_R02_04.
- Among 17 direct-attack IDs still lacking recover evidence, B_R01_A is one of 17 with rendered execute but no recover; the other 16 were already listed that way in R002.
- `executeAndRecoverBothUnobserved` is empty for these 17 after the B_R01_A evidence is included. This does not mean all actors have complete motion review: unobserved/recover-uneligible cases and formal art adoption remain separately scoped.

## Evidence pins

- B_R01_A recovery: `enemy_execute_regression_r424/candidate_r001/first_case_recovery_r001/RECOVERY_R001.json`, SHA-256 `fc479ddddbf3bfc71b1e5951f2b99594a8e4955f62509926b729b197b0186631`.
- B_R01_A trace: `.../case01_B_R01_A/enemy_event_render_r145_e26b112a-50b2-4f38-9803-ee37da6123f9.json`, SHA-256 `968127c0012cc8df28ed116e0ba9f73224a99f78d2776fdf7e765bf348238184`.
- B_R01_A video: SHA-256 `8dcba148552935d7812f66e48824a8875feb0e39db40010ce05aa2c8cc91b17c`; the visual review's sampled frames are 367/375/382 with E145 markers 00365/00373/00380.
- R424 visual-review record: `enemy_execute_regression_r424/independent_visual_review_r001/REVIEW_R001.json`, SHA-256 `87873c1b56c804dccebece3449084a5da859c8f68aebd266550584b20f220f8164`.
- E_R02_01 recovery trace: SHA-256 `b3e8df6345db2691fa86d7b2f72fe955ff9573f351c58350ce6bea54e728d4dd`; its two marker stills and hashes are recorded in `enemy_execute_regression_r424/recovery_classification_r002/REVIEW_R002.json` (SHA-256 `78f57e936f8245491e96b3ccc58f9bce940dcbc3225b972239f6c9b07ba9fedf`).
- R425 eight-case Core replay: `enemy_execute_replay_r425/execution_r002/reuse_run_r003/RUN.json`, SHA-256 `b79b5086305892c8f7e144e3614997b6f8e02aefd54a23e9f65b0767b42e2952`; it is not visual evidence.
