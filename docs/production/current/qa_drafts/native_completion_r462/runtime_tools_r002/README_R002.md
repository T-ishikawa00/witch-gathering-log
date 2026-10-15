# R462 ordinary inventory-filter runtime helper

This is an unsealed preparation for Root-operated UI capture. It is not run, and it does not build, launch, automate the UI, or change live sources. Root must fill the exact R462 Release receipt and current R456 seed hashes/sizes in the runtime seal before use.

The helper installs only the sealed R462 Release product into a fresh bundle namespace and copies exactly three pinned files from R456 revision 138: `save.json`, `save.json.previous`, and `last_standard_play_identity_r169.json`. It protects the prior R445, R454, and R456 app/data containers against their previously recorded baselines. It refuses an existing R462 install or support folder and never deletes or restores data.

Root captures these checkpoints in order: `home`, `empty_search`, `filters_cleared`, `before_cold`, `cold`. The first, second, third, and final checkpoints include screenshots; `before_cold` is save-only. On the inventory screen, Root enters a search that returns no matches, records the empty-result explanation and clear action, then clears the filter and records that the inventory returns. The screenshots demonstrate the visible route; the helper itself cannot assert text recognition. All checkpoints verify revision 138 and byte-exact primary and previous saves, which covers gear and equipment state. Runtime identity is recorded separately because startup can update it. Cold capture requires a different app process and the same save bytes.

The limit is 600 seconds and 1.04 GB total allocated output, with four PNGs, 20 MB per image and 40 MB aggregate evidence. It requires 15 GB free before install and preserves a 10 GB floor. Errors are retained in the run receipt; no retry, automatic relaunch, deletion, or restore is performed.

R456 is historical source evidence only. This candidate does not claim R462 execution, release acceptance, or device validation.
