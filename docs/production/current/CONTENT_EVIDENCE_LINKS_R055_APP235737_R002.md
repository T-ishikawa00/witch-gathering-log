# R055 evidence links — R002 physical furniture mapping

R002 preserves the R055/R054 manual target app SHA `f2a16851b41ee24c5f8efc255ee4d2d5ffa7c7a0fb13648f4e002714242a0a6b`, all 15 R055 rows, the 248-row R054 matrix hash, and readiness counts `242 PARTIAL / 1 NOT_PRODUCED / 5 INCOMPLETE`. It appends `furniture_candidate / FURN_DESK_BOTANICAL` (16 rows total) and adds the independent R052 review link to the home, LUNA, UI-furniture, and physical-furniture rows.

R052’s Xcode simulator executable (`3b1048a46ec0a5d109dca4e7b0b911866c329e2c145ae0d6f8fe66c2eefedc3e`) is distinct from the manual target executable. The test is 1/1 PASS, but its original run remains `RECOVERY_PENDING` because the container UUID changed. Before restore, 637/641 prior JSONs were unchanged and four fixed diagnostic files differed; the separate reconciliation restored those four and then verified all 641 prior JSONs plus the new QA save unchanged. The cause of UUID change remains unknown.

The test selects and places the exact `FURN_DESK_BOTANICAL` identifier; its frozen UI source maps `C_APPRENTICE` to sprite/display alias `LUNA`, gates LUNA’s reading pose on that placed desk ID, and asserts the corresponding Japanese scene label and restart state. The attached in-use screen and source asset hash support this one candidate furniture row. The separate read-only video sampled 48 frames over 12 seconds with no PTS reversal; source-frame/logical-index synchronization remains unproven. No formal adoption or general natural-motion acceptance follows.

Evidence paths under `qa_drafts/` and `independent_review/` are relative to `docs/production/current/`. Paths beginning `native/` are relative to the repository worktree root. Full SHA256 values, run pins, and row-level boundaries are in the JSON.
