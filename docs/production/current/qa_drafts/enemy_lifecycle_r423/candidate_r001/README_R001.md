# R423 focused lifecycle validation candidate

This is an unrun source-only host validator, not a game test result. It consumes the existing R239 sidecar written by the saved-combat replay route (`App.swift` 849–861, 1093–1144). The replay observer already joins actor, root action, scene generation, and event sequence and writes under a unique replay UUID. The R411 fixture is technical/synthetic, not ordinary progression.

`validate_r214_lifecycle_r423.py <trace.json> --expect deferred-hit-complete` checks that a deferred visual hit starts only after the finite execute completes and then completes itself. `--expect lethal-cancel` requires a `lethal_resolve` cancellation tied to the same execute/hit identity, and rejects a later deferred-hit start. Missing evidence exits nonzero as NOT_OBSERVED; it is never accepted as a pass.

The current app has no unit-test target for `EnemyMotionController`; direct tests would require a refactor/test seam. The existing saved-combat replay is the narrowest reusable integration path. It can cover the successful transition sequence. Lethal cancellation requires a deterministic replay exhibiting that race. Reset/stop and malformed-clip fallback are not observable through the current one-group R239 observer and need a later test seam or dedicated app-controller test. No clip, source, live save, or device state is changed here.

Validator SHA-256: `3733687529442b7dbff4b5d990cdda79ec6a99089f6884b5c7e17d903e989c57`. Current source pins and bounded run conditions are in `TEST_CANDIDATE_CONTRACT_R001.json`.
