# R433 helper review correction

R001’s P1 path finding was incorrect and is retracted. R001 treated `BASE` as if it were `candidate_r001`; the actual helper is directly under `qa_drafts/wardrobe_furniture_runtime_r433/`. For that exact file, `BASE.parents[4]` is the worktree root, so `PRIOR` points to the correct R421 helper. The pinned helper SHA resolves; the earlier nonexistent `docs/docs/...` diagnosis must not be relied on.

The cold-phase concern remains bounded: it waits 0.5 seconds, snapshots, and may capture before the reopened UI is visibly ready. Root will confirm the actual UI separately; do not call the helper’s screenshot by itself proof of restored visual state. The other actionable concern is unchanged: the runner does not enforce the 180MB aggregate after writing a screenshot. Keep execution on hold until the operator’s planned post-capture cap/closure guard is in place. No app/helper execution occurred during this review.
