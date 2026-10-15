# R456 install and manual-capture helper (prepared only)

`run_r456.py` has not been invoked. It does not build or launch the app. Root must seal `RUNTIME_SEAL_R001.json` only after the R456 Release build closes and the R454 origin record is final. The seal pins the R456 build result, exact current R454 origin receipt, exact R445 simulator containers, and the three R445 support files at revision 137.

The `install` action refuses an already-installed R456 bundle, verifies the Simulator Release app and all 1,922 packaged resources against the R456 build receipt, verifies the R454 origin and R445 seed, and takes full file-hash snapshots of both older apps/data before any install. It installs the exact unique R456 bundle to simulator `9A067715-7CF3-40D3-9064-38423223959B`, copies only `save.json`, `save.json.previous`, and `last_standard_play_identity_r169.json` into the new R456 support namespace with APFS clone mode, and checks old app/data trees again. It never launches, uninstalls, overwrites an existing container, modifies an older save, or changes source.

After Root manually operates the app, `checkpoint` records stable double-read hashes and copies of the three save files, revision, exact running process identity, and optionally one screenshot. Supported screenshot checkpoints are `launch`, `gear`, `battle`, and `cold`; `before_cold` is a save-only marker. `cold` requires a newly started app process after `before_cold` and exact `save.json`/`save.json.previous` bytes across that relaunch. `finish` closes only after those checkpoints. The run is bounded to 600 seconds, 500 MB additional storage with 2 GB reserve, 22 GB free at start and 20 GB floor, four screenshots/15 MB total. Failed evidence is retained under the unique run ID.

The helper is a capture aid, not a gameplay or StoreKit acceptance claim. It records no UI automation and does not interact with purchase dialogs.

The intended sequence, after Root seals the file, is `install`, then a Root-operated first launch followed by `checkpoint --label launch --screenshot`; optional `gear` and `battle` screenshots; `checkpoint --label before_cold` without a screenshot; Root manually cold-restarts; `checkpoint --label cold --screenshot`; and `finish`. No helper action sends UI taps or launches/terminates the app.


R002 delta: the R454 preserved-save check is bound to `Library/Application Support/Witch03to05R1/qa-storekit-authority-r454-save.json` under the pinned R454 data container; it does not use the R169 `save.json`. `simctl get_app_container` calls have a 15-second timeout. This revision is prepared only; no installation or runtime capture was performed.
