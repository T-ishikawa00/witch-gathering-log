# R456 build preparation (not executed)

Purpose: compile the already-frozen R454 source as a normal Release for both iOS Simulator and unsigned iPhoneOS, so the 238-source R454 delta is checked by both SDKs. R445/R447 build results cover their older 235-source input and cannot substitute for this source revision.

This preparation deliberately does not freeze, regenerate, copy resources, install, launch, or run `xcodebuild`. The existing R454 project at `native/WitchGatheringQA_20261015T060856.xcodeproj` and its 1,922-resource tree are pinned in `PREPARED_PLAN_R001.json`; the frozen source map was compared read-only and matches all 238 rows. Root must wait for the active R454 R003 build/UI work to close, compare the frozen source/project/resource pins with its final receipt, and create a separate R456 root seal before execution.

The intended sequential commands (one aggregate 600-second attempt, shared DerivedData) are:

```sh
xcodebuild build -project native/WitchGatheringQA_20261015T060856.xcodeproj -scheme WitchGathering -destination 'generic/platform=iOS Simulator' -derivedDataPath native/build/ActiveIntegrationR456/<sealed-input-key> -configuration Release 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=STANDARD_PLAY_R169 FIRST_CRAFT_AID_R179 EQUIPMENT_LOADOUTS_R342 NATURAL_GEAR_R350 NATURAL_GEAR_REFINEMENT_R352 GEAR_DISMANTLE_REFUND_R353' PRODUCT_BUNDLE_IDENTIFIER=local.witch.autonomous.r1.completion.r456 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -jobs 2

xcodebuild build -project native/WitchGatheringQA_20261015T060856.xcodeproj -scheme WitchGathering -destination 'generic/platform=iOS' -sdk iphoneos -derivedDataPath native/build/ActiveIntegrationR456/<sealed-input-key> -configuration Release 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=STANDARD_PLAY_R169 FIRST_CRAFT_AID_R179 EQUIPMENT_LOADOUTS_R342 NATURAL_GEAR_R350 NATURAL_GEAR_REFINEMENT_R352 GEAR_DISMANTLE_REFUND_R353' PRODUCT_BUNDLE_IDENTIFIER=local.witch.autonomous.r1.completion.r456 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -jobs 2
```

A future runner must validate a Root-sealed manifest, fixed worktree and all source/project/resource pins, no competing compiler, ≥20 GB start free, ≥10 GB remaining floor, ≤2 GB new allocated output plus 2 GB reserve, and one-attempt 600-second aggregate cap. It must preserve R445, R447, and R454 outputs; any pin drift or running R454 job is a hard stop. No present receipt claims a build passed.
