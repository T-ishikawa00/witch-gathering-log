# R214/R239 evidence reuse review

**Disposition:** do not schedule a separate R423 build yet. Existing R239 evidence already covers the saved-replay path's successful deferred-hit completion and cancellation by a later execute. It does not cover the new R418 diagnostics-off/default-on branches.

The five-row R239 trace `AC851C27…` binds an execute (sequence 97, `enemy:B_R05_B:3`) to a deferred hit (sequence 106, same root), then records execute completion followed by hit start and completion. The second trace `023FB60C…` binds execute 27 and hit 29 on `enemy:B_R05_A:1`; the hit begins after execute and is cancelled by `superseded_by_execute`. Both files are retained in the R373 development-before snapshot; their SHA-256 pins and paths are in the JSON receipt.

R214's source review covers generation-guard and cleanup logic but performed no build/runtime test; it explicitly says rebuild cancellation rows are cleared before they can be read. R217 is the saved-combat replay mechanism, not an independent controller XCTest. No lifecycle XCTest was found in the scoped R214/R217/R239 folders.

R418 R003 changes actual behavior beyond feature gating: the finite-hit deferral bookkeeping is now active when diagnostics are off, including Release/device routes; looped or invalid-duration execute clips fall back to immediate hit. Lethal resolve clears pending presentation state outside the diagnostics gate. R004 only fixes diagnostic serialization. Consequently the old R239 traces cannot establish these newly enabled paths. The main uncovered cases are diagnostics-off default behavior, lethal pending-hit clearing, invalid/missing/looping clip fallback, and stop/rebuild invalidation.

R423's trace validator would validate already-recorded diagnostic rows; it cannot prove the diagnostics-off path. Prioritize the requested R424 real execute coverage and avoid a standalone build unless that evidence leaves one of the changed branches material and unobserved. This is not a release or animation-quality approval.
