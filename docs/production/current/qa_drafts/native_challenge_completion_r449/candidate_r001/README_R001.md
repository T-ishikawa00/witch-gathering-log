# R449 ordinary challenge capture (prepared, not run)

This helper records the existing installed R445 app and a Root-operated normal-UI challenge sequence. It does not launch, terminate, install, edit, copy, restore, or delete game state. Its only device call is a requested screenshot. Run every command from the fixed worktree shown below.

The pinned starting state is R446 revision 117 (`af864f432b2e16255e9fa050f0b1cf5189492c297260e64d1eae6ec465d03cc4`). The save already contains seven earlier challenge clear markers and a historical mock draw of five items. Those facts remain in history. The five identified mock UUIDs are not equipped at baseline, and the same equipped UUID set must remain equipped. The run requires a new observed WIN for each of the 15 challenge IDs; an old marker alone cannot count as a replay win. Replaying previously cleared challenges does not imply a first-clear reward.

The capture sequence is: `prepare`; start the app through normal Root operation; capture `before`; record each actual region selection at `region_R01` through `region_R05` (screenshots required for R03–R05); attempt all 15 IDs using `challenge CH_Rxx_yy` immediately after each battle; then `cold_before`, Root cold restart into the same app/data container, `cold_after --screenshot`, and `close`. One optional challenge screenshot is allowed. The helper never performs the cold restart. Each challenge checkpoint is a separate snapshot of the current save and matching challenge sidecars, not a separate game transaction.

The run is capped at 1,800 seconds, 35,000,000 evidence bytes, six PNGs, and a 10 GB free-space floor. Preparation also requires the 35 MB evidence reserve. Existing fixed output or checkpoint names fail closed; there is no retry, cleanup, or restore path. If a cap or check fails, retain all evidence and report `INCOMPLETE_RETAINED`.

Before Root seals or uses this candidate, recheck the pinned R445 build/install receipts, R446 closure/save, R443 historical provenance, installed app/data paths, and all protected trees against the live machine. No result has been produced by this candidate.
