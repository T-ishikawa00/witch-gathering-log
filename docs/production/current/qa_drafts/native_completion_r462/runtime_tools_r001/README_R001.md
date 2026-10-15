# R462 bounded home and gear runtime helper (candidate only)

`run_r462.py` is an unsealed install/checkpoint/finish helper. It has not been run. Root must fill and seal `RUNTIME_SEAL_R001.json` only after the R462 Release build receipt is final. The simulator is not launched by this helper; all visible UI actions are Root-operated.

The helper requires the closed R456 runtime receipt and its exact Release build, the R454 installed-origin receipt, the R445/R454 prior-tree baseline recorded by the R456 run, and explicit paths for all six old R445/R454/R456 app and data containers. It checks the R456 revision-138 primary save SHA (`3725e9c13d0e514804d5941d23b7847e12d7c13eb04aac0b3e676b190ae3a3c1`) and copies only three Root-pinned support files (`save.json`, `save.json.previous`, and `last_standard_play_identity_r169.json`) into a fresh R462 app-support namespace. It never overwrites an existing R462 install/container or changes an older save.

The allowed visible checkpoints are `launch`, `gear`, `before_cold` (save-only), and `cold`. Root can capture up to three screenshots: launch/home, gear comparison, and home after a manual cold relaunch. The target is the ordinary home/party/gear comparison route; battle, purchase, crafting, collection, and other gameplay actions are outside scope. The seeded primary and previous saves must remain byte-exact at every checkpoint and revision must remain 138. The runtime-identity file is recorded separately because ordinary app startup may update it. Cold relaunch requires a different running app process and exact primary/previous save bytes.

Limits are 600 seconds, 1.04 GB total additional disk use (1 GB install/runtime plus a separately measured 40 MB evidence ceiling), 15 GB free before install and a 10 GB floor, three PNGs (20 MB each, 40 MB aggregate evidence cap). Failures are retained as HOLD; the helper does not delete, restore, or relaunch.

The copied R456 clock test is source-only and was not executed. This capture does not claim release acceptance, production purchase authorization, or device validation.
