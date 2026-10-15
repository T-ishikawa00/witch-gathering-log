# R456 source-only builder preparation

This is a new runner draft only. It has not frozen source, built, installed, launched, or touched R454 outputs. It refuses to run without a Root-sealed input manifest and contract. The fixed inputs must be rebound to the final R454 R004 frozen source map, generated project and StoreKit file reference after that run closes; the earlier R454 project/bundle mismatch makes R001's command-only bundle override obsolete.

At execution, the runner copies the exact R004-frozen `GameInfo.plist` template into its own `build_tools_r002/prepared_inputs/Info_R456.plist`, sets only `CFBundleIdentifier` to the unique R456 ID, removes the QA-only `SKIncludeConsumableInAppPurchaseHistory` key, and supplies that owned file with `INFOPLIST_FILE`. It never edits the R454 project or its Info.plist. The command line retains the normal Release feature flags from R445 and does not set `DEBUG`.

One invocation would build Release for Simulator and then unsigned iPhoneOS into a new shared R456 DerivedData location. It has a single 600-second aggregate attempt, 2 GB allocated-output cap plus 2 GB reserve, 22 GB free-space requirement at start and 20 GB floor. Install and launch are disabled. R445/R447 and final R454 products must be pinned in the sealed manifest and rechecked before/after. No run until Root reviews and seals final R454 inputs and the driver.

The resulting products would establish compilation only; they would not prove StoreKit runtime, Apple authorization, or purchase completion. This draft is not execution-ready: the template intentionally contains unfilled R004 paths/hashes.
