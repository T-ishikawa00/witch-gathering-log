# R443 capture helper candidate R002

Status: prepared, not run. This version adds the missing `snapshot()` implementation and uses a single fixed worktree path. It compares R420 against the session START baseline and R437 against Root’s separately sealed post-R441 inventory.

R441 is not rewritten: its original status remains `INCOMPLETE_RETAINED`. R002 accepts that exact closure only when Root’s pinned scoped readback verifies the sole two unexpected changes are `functions.data` and `functions.list` under the R437 Metal cache; all app, other data, cold-save, PID, screenshot, and budget conditions remain mandatory. The R437 baseline file and readback hashes are checked before use.

The helper is snapshot-only. It does not launch or stop apps, edit saves, advance time, build, purchase, restore, or delete. Root must review the pins before any use.
