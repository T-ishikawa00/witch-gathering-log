# R362 save crash completion candidate

Status: prepared only; XCTest, build, and Simulator have not been run.

The candidate repeats the R342 save-loadout transaction against a newly created isolated Core fixture. It asks the test host to stop after SaveRepository atomically replaces the primary save and before the directory sync completes. The host must identify the exact marker PID by a one-run phase token, the fixed XCTest driver path, the unique compiled `.xctest` bundle path, and the exact test invocation. It sends SIGKILL only to that PID, never to a process group. The `swift test` supervisor then exits normally; the bounded test barrier self-fails after 40 seconds if no verified host signal arrives.

The verify phase checks that the primary generation contains the complete first loadout payload and command receipt, `save.json.previous` is the exact pre-transaction generation, the same operation replays without changing either file, and cold reopen preserves the complete snapshot/receipt. The seed is a synthetic new-factory snapshot written only under the unique run evidence directory. It does not open or modify an earned save.

The runner is copied from the prior R348 harness for its fixed-input inventory/preservation discipline; the R348 failure was caused by killing the Swift wrapper process group while the actual XCTest driver had a different PID/process group. R362 changes the barrier control to a nonce- and executable-path-bound XCTest PID, retains the wrapper for ordinary recovery, and audits that the unique bundle process is absent afterward. R348 evidence is unchanged and remains incomplete; this preparation is not evidence that the crash boundary passed.

Execution contract: one run; seed/compile, crash-child with the same compiled test executable, verify with that executable; 180 seconds total, 55 seconds per phase, 300 MB logical/allocated cap, 12 GB free-space floor plus 2 GB reserve. Runner requires caller-supplied absolute protected namespace, namespace manifest/SHA, actual save path/SHA, app executable, and PBX path/SHA. Root review and execution are pending. No runner invocation was made while preparing this candidate.
