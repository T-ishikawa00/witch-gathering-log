# R443 ordinary progression capture helper

Status: source prepared, not run. Root operates the ordinary R420 app. The helper only archives stable support-file snapshots and takes optional screenshots; it does not launch/stop apps, alter save bytes, change the clock, build, install, or purchase.

The target is the sealed R436 final save, revision 75, SHA-256 `51c07a8d8c262f930bda41728b2775ac1338187644ed3a60fda05fbf24786475`. The R420 app inventory and all R436 historical protected trees are checked. If the R437 data container is one of those historical trees, only that exact path is rebased through a separately Root-sealed post-R441 data inventory; every other R436 tree remains pinned. The R437 app is compared to its pinned install/build receipt.

Because R441 changes the R437 data state, `start` requires a separately Root-sealed post-R441 baseline manifest and its SHA. The manifest format and exact R441 closeout path are in `RUN_CONTRACT_R001.json`. The helper verifies the R441 closure, checks R437 is stopped, then compares the current R437 tree to the manifest before creating `execution_r001`. Missing, stale, unsealed, or mismatching evidence is a HOLD.

Root may claim genuine elapsed work, craft only from the ordinary UI if the displayed recipe and current materials permit it, equip genuinely earned items, and attempt the two remaining bosses and ordinary research. No QA grant or clock change is used. A run may close early; anything unattempted remains `NOT_REACHED`.

Limits: 40 minutes, 40 MB, ten screenshots, no video, and a 10 GB free-space floor plus the evidence reserve. Each snapshot double-reads support files and records their hashes. A cold check requires a Root-operated process restart and byte-exact primary-save SHA equality.
