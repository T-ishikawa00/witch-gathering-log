# StoreKit local Xcode QA result

Date: 2026-10-10 (JST)

## Current conclusion (13:04 JST)

The nil-unwrapping crash is fixed and has a passing empty-product regression. Normal Xcode Run now loads two local products after repairing the Run executable/configuration path and active bundle settings. The linked local-only bridge has concrete Xcode transaction evidence for purchases, cancel, duplicate, pending Ask to Buy, restore excluding consumables, refund update/ownership removal, and persistence-failure-before-finish. Relaunch/redelivery remains UNKNOWN after a Run changed container and cleared the test transaction history. Main-game local integration has now verified purchase delivery, consumable exclusion from restore, and refund removal in its isolated GameSnapshot (see [main app evidence](../../docs/production/current/purchases/STOREKIT_MAINAPP_XCODE_RESULT_R001.md)). Same-installed-app restart preserved the QA save file hash; this does not prove unfinished StoreKit redelivery or QA-state loading without QA launch arguments. Main-app cancellation/pending/write failure and production payment remain NOT COMPLETE. The separate SKTestSession Code 3 / notEntitled path still fails; no causal link to the Swift nil trap is established. No SIP or security settings were changed and no real Apple credentials or payment were used.

Earlier sections below are chronological investigation records. Statements of “blocked/currently unverified” within an earlier section describe that route at that point; the later direct Run and bridge results supersede them only for the explicitly tested local path.

## Scope and safety

- Local-only StoreKit configuration: `WitchLocalTest.storekit`.
- Product identifiers are `local.witch.test.furniture` and `local.witch.test.ticket`; both are explicitly QA-only.
- No Apple account, App Store Connect registration, network call, production product, or real payment was used.
- The Xcode project and test runner are isolated to this directory.

## Implementation

`StoreKitLocalQA.xcodeproj` contains a minimal macOS host app and hosted XCTest target. The shared test scheme points to the local StoreKit configuration. Tests use `SKTestSession(contentsOf:)` and attempt local non-consumable purchase/refund plus consumable purchase/Ask to Buy pending state. Tests are serial because Apple documents that all `SKTestSession` instances share one environment.

## Execution

Environment: Xcode 26.6 (17F113), macOS 26.5, destination `platform=macOS,arch=arm64`.

Command:

```sh
xcodebuild test \
  -project native/StoreKitLocalQA/StoreKitLocalQA.xcodeproj \
  -scheme StoreKitLocalQATests \
  -destination 'platform=macOS,arch=arm64' \
  -resultBundlePath native/StoreKitLocalQA/LocalStoreKit4.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

The project compiled, the host app launched, and XCTest ran both cases. Both failed before any transaction was created:

- `SKTestSession` logged `Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3`.
- Settings mutations (dialogs, storefront, clear transactions) logged the same `SKInternalErrorDomain Code=3`.
- `buyProduct` returned `StoreKit.StoreKitError.notEntitled` for both configured local products.
- Result: 2 tests executed, 2 failures; no purchase/refund/Ask to Buy transaction evidence exists.

The same `notEntitled` failure occurred first in a non-hosted XCTest runner, then again after adding the hosted macOS app and attaching the local configuration to the test scheme. No entitlement was manually added and no signing/account workaround was attempted.

## Outcome and blocker

The Xcode XCTest route is configured and reproducible, but StoreKitTest rejects the test process in this environment. This is an entitlement/runtime blocker, not evidence of a purchase-flow pass or of missing App Store Connect products. A local Xcode test runner cannot presently verify purchase, pending approval, cancellation, restoration, or refund behavior here. Those cases remain unverified.

Apple describes StoreKit Testing in Xcode as a local environment using configured product data and `SKTestSession` for automated transaction tests:

- https://developer.apple.com/documentation/storekittest
- https://developer.apple.com/documentation/storekittest/sktestsession
- https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode

## Follow-up investigation (2026-10-10)

### Reproduction matrix

The original macOS XCTest result alone did not identify the cause. I added a second iOS Simulator test target and ran it on a dedicated iPhone 17 Pro / iOS 26.5 Simulator (`A8E9E99B-F6DC-4EF0-90D8-CB1C4202D514`) to avoid the game's QA simulator. Xcode was 26.6 (17F113), macOS 26.5.2. The `.storekit` file contains two local-only products and parses in Xcode; product IDs are `local.witch.test.furniture` and `local.witch.test.ticket`.

| Route | Observed result | Transactions |
|---|---|---|
| Non-hosted macOS XCTest with `SKTestSession` | `buyProduct` throws `StoreKit.StoreKitError.notEntitled` | None |
| Hosted macOS XCTest with StoreKit configuration on Test action | Same `notEntitled`; test result bundle records 2 failures / 0 passes | None |
| Hostless iOS Simulator XCTest with `SKTestSession` | Same `notEntitled`; same internal Code 3 for session control calls | None |
| SwiftUI iOS app using `Product.products` + `Product.purchase`, launched by a UI test with configuration referenced by the scheme | Product query returned `products=0 ids=`; no product sheet/transaction; app exited during failed UI test | None |

Initial investigation before the direct-run follow-up: the dedicated iOS UI-test launch returned zero products. This showed that route did not reach StoreKit purchase, not that the OS required a permission change. The later direct Xcode Run section below records how the separate Run action was fixed and successfully loaded local products.

### Exact errors and occurrence

The following messages are preserved as emitted by StoreKitTest in the hostless iOS Simulator XCTest process; macOS hosted execution logged the same `SKInternalErrorDomain Code=3` pattern:

```text
[SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[SKTestSession] Error setting value to 1 for identifier 2 for com.apple.dt.xctest.tool: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[SKTestSession] Error setting storefront to JPN for com.apple.dt.xctest.tool: Error Domain=SKInternalErrorDomain Code=3 "(null)"
[SKTestSession] Error deleting all transactions: Error Domain=SKInternalErrorDomain Code=3 "(null)"
Failed to purchase local.witch.test.ticket in off-device buy mode: リクエストを完了できません。
failed: caught error: "notEntitled"
```

These occur while `makeSession()` constructs an `SKTestSession` from the local file, then sets `disableDialogs`, `storefront`, and clears transactions; the thrown purchase error occurs at `buyProduct` in `StoreKitLocalQATests.swift:19` (non-consumable) and `:31` (consumable). No transaction identifier was produced. The normal StoreKit API probe instead returned an empty product array (`products=0 ids=`); it did not produce `notEntitled` because it never got a product to purchase.

### Actions tried and cause classification

- Started with the CLI probe, then added a hosted macOS Xcode test app and attached the local file to its scheme. The same error remained.
- Added a hostless iOS XCTest target and executed it in an iOS 26.5 Simulator. The same error remained, so this is not specific to running the API from a command-line-only/macOS process.
- Added a separate SwiftUI app/UI-test harness using the public StoreKit APIs. Verified the scheme points at the QA `.storekit` file and corrected a missing project file reference; product lookup remained empty in the UI-test-launched app.
- Checked the local product definitions and identifiers. The file is valid and explicitly marks both products as local QA items. The test uses no App Store Connect product.
- Did not change macOS privacy/security settings, add entitlements, sign with a developer identity, authenticate an Apple Account, contact external services, or use real purchases.

**Confirmed:** StoreKitTest control calls fail with `SKInternalErrorDomain Code=3`, then the test-only `buyProduct` call throws `StoreKit.StoreKitError.notEntitled` before creating transactions, on both macOS XCTest and iOS Simulator XCTest. Normal StoreKit product loading also did not find the local IDs in the UI-test run.

**Cause hypothesis (not confirmed):** the XCTest-launched process may not be attached to the StoreKit local test environment or may lack a test-runner capability/context required by the `SKTestSession` mutation/off-device purchase path. The separate app probe indicates its scheme/run integration must also be verified through a direct Xcode Run before drawing a conclusion. Apple’s public setup documentation describes local configuration files and scheme activation but does not document this Code 3 / `notEntitled` combination as requiring a macOS security setting or Apple Account; therefore neither is identified as a proven Human blocker.

Apple’s documentation confirms that Xcode StoreKit Testing is local/offline, that the app obtains configured data when the file is active in its scheme’s Run options, and that `SKTestSession` automates iOS StoreKit tests. This supports trying the documented Simulator/Run path, but does not explain the observed errors:

- [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)
- [StoreKit Test](https://developer.apple.com/documentation/storekittest)

Current purchase QA remains **BLOCKED / NOT PASSED**. Purchase, pending/Ask to Buy, cancellation, restore, and refund are all unverified. `iOSRunner/` contains reproducible experiments and result bundles; `AppProbe/iOSAppStoreKitProbe7.xcresult` shows the zero-product result. A direct Xcode Run of `StoreKitQAProbeApp` with `Products.storekit` active on the dedicated Simulator is the next diagnostic, and should be done after the shared Xcode UI is free. Do not change OS security settings or add signing/account dependencies based only on the current hypothesis.

### StoreKit probe crash root cause and regression

Four diagnostic reports (`StoreKitQAProbeApp-2026-10-10-{115454,115630,115810,120023}.ips`) were read without copying their machine paths into this report. All four identify the same failure:

```text
exception type: EXC_BREAKPOINT
signal: SIGTRAP
termination: Trace/BPT trap: 5
Swift runtime failure: Unexpectedly found nil while unwrapping an Optional value
ProbeApp.swift:36 ProbeView.buy(_:)
```

The reports share arm64 image UUID `9F9ABBA4-E0D1-3A35-B60D-F034612C80AC`; the matching DerivedData executable was built at 11:54:11 JST. The Simulator app was launched from that build. The source at that build contained `try await Product.products(for: [id]).first!`; the four reports were therefore caused by force-unwrapping the first result when the local StoreKit product lookup returned an empty array. Later attempts continued to launch the same bundle/binary, which explains the repeated identical line and UUID. It was a probe-app crash caused by stale installed code, not the StoreKit `notEntitled` error.

The probe now stores the awaited product array in a local variable, uses `guard let` on `.first`, and returns `purchase=unavailable` when no product exists. The UI regression test taps Buy with `products=0` and verifies the unavailable state and live app. Its first rerun still returned the old test case from the installed XCTest runner, so I changed the test-only app and UI-test bundle identifiers to `.probe.r2` / `.uitests.r2` to force a clean install. On a dedicated iPhone 17 Pro / iOS 26.5 Simulator, `testEmptyProductResultDoesNotCrashPurchaseFallback` passed in 6.053 seconds. Result bundle: `iOSRunner/AppProbe/iOSStoreKitCrashGuardRegression.xcresult`. This validates only the empty-result crash guard; it is not a purchase pass.

### Mocked purchase-state coverage

`MockPurchaseFlow/` is a separate protocol-driven, test-only purchase-state harness. It does not grant entitlements in the game and is not a substitute for StoreKit transactions. `swift test --package-path native/StoreKitLocalQA/MockPurchaseFlow` passes 7/7 tests for success, pending, cancellation, empty product results, product lookup failure, purchase failure, idempotent duplicate transaction handling, restore success/error, and consumable exclusion from restore. Native StoreKit remains a distinct test route; its currently runnable local XCTest is blocked before transactions by `notEntitled`, while the app-level API probe finds zero products. Do not report these mock tests as StoreKit purchase QA.

### Direct Xcode Run follow-up (2026-10-10 12:10–12:14 JST)

**Confirmed Run setup defect and repair:** the shared scheme's Run action originally had no executable (`Product > Run` was disabled; `Edit Scheme > Run > Info` showed `Executable: None`). Its StoreKit configuration reference resolved to a nonexistent path under `StoreKitLocalQAiOSProbe.xcodeproj/project.xcworkspace/Products.storekit`; `Edit Scheme > Run > Options` showed `StoreKit Configuration: None` and the file-not-found warning. The App target's active Debug/Release build configurations also used the prior `.probe` bundle ID, while `.probe.r2` existed only in unused project configurations. I selected `StoreKitQAProbeApp.app` as the Run executable, added the existing `Products.storekit` file through Xcode's StoreKit Configuration picker, and aligned the active App target Debug/Release IDs to `local.witch.storekitqa.probe.r2`. The shared Run action now has a runnable product and resolves the actual local file. TestAction remains a separate test route and is not evidence for this direct Run.

**Direct Xcode Run on the dedicated iPhone 17 Pro / iOS 26.5 Simulator (`A8E9E99B-F6DC-4EF0-90D8-CB1C4202D514`):** product query showed both QA-only products. The native purchase sheet displayed its explicit testing-only/no-charge notice and `Environment: Xcode`. `local.witch.test.furniture` (non-consumable) returned `purchase=verified`; `local.witch.test.ticket` (consumable) also returned `purchase=verified`. Closing the consumable purchase sheet with its X button returned `purchase=cancelled`. A repeat purchase request for the already-purchased furniture returned the verified result without opening another confirmation sheet or creating a second record. Xcode's StoreKit Transactions manager showed only `ID 0` furniture and `ID 1` ticket; after the refund test below furniture remained the same single record with status Refunded. A second furniture purchase request returned the same verified display state and the manager still contained one furniture transaction, so no duplicate local record was created. These are StoreKit configuration transaction IDs, not production order identifiers.

**Restore:** invoking `AppStore.sync()` opened the Xcode test-environment prompt: “Sign in with Apple Account / Press ‘OK’ to simulate authenticating with an Apple Account.” The first attempt was canceled and showed `restoreError=StoreKit.StoreKitError.userCancelled`. The prompt had no credential fields and explicitly identified `Environment: Xcode`; after confirming this was the StoreKit local simulation, I selected OK on a second attempt. The app showed `restore=completed`. No Apple Account was authenticated. This confirms only that local `AppStore.sync()` completed; this probe does not reconcile entitlements into the game save.

**Refund:** selected local furniture transaction `ID 0` in Xcode's StoreKit Transactions manager and used its Refund action. The local record changed from Purchased to Refunded and shows `Revoked Today, 12:13:27 (Other)`. The probe had no `Transaction.updates` observer (Xcode emitted the corresponding StoreKit warning), so app-side revocation delivery was not verified. This is local StoreKit testing state only; no actual payment or App Store transaction occurred.

**Build identity receipt:** active bundle ID `local.witch.storekitqa.probe.r2`; simulator installed executable UUID `7065ACB6-F504-3B20-93A3-374C076ACFAF` (arm64), matching the Xcode DerivedData Run product. Current probe source SHA-256 `740b7fe00ec5f6824440af7b772554d6c92b583dd017f3fb214850b6fded1df5`; `Products.storekit` SHA-256 `029001df240390de40e12a831792b0d231edef66ba2d4f9a025e87b399a87dbd`; project SHA-256 `bc8dba351051460d68b7923ca524b14aa52806ce08a7745696fb32c4bb56a23c`; shared scheme SHA-256 `49bb3314b68cbb015db6f6413e8a64b63e2899cd326363cf185acc1376c8a874`.

**Boundary:** the earlier `SKTestSession` XCTest `notEntitled` failures remain a separate route and their underlying cause is unresolved. The direct Xcode Run reproduced `products=0` until its executable and valid scheme file reference were repaired; it now succeeds. Do not infer this resolves the distinct XCTest `SKTestSession` path. These local QA transactions do not implement or verify durable game entitlement delivery, restore-to-game behavior, production product setup, or real payment handling. No real charge, Apple Account authentication, external request, or security permission change occurred.

### Standalone QA-only StoreKit 2 bridge candidate

Added `native/StoreKitLocalQA/ReusableBridge.swift` as an isolated candidate; the production app and game core do not import it. It is typechecked for both DEBUG iOS Simulator and a non-DEBUG Simulator build. `StoreKitLocalQAGate` only opens in `DEBUG && targetEnvironment(simulator)` and also requires the caller to affirm the local Xcode configuration is active and the process launch argument `--xcode-local-storekit-qa`. The shared probe Run scheme now supplies that argument, but the bridge itself has not been compiled into the probe. Every verified transaction is checked for environment `Xcode` before delivery; Sandbox/App Store environments are rejected. Purchase success, StoreKit updates, unfinished transactions, restore, and revocation events pass through an async durable sink with stable idempotency keys. A transaction is finished only after the sink reports success. Restore excludes consumables. A sink failure leaves the transaction unfinished so StoreKit can retry.

Validation run:

- `xcrun swiftc -typecheck -target arm64-apple-ios17.0-simulator -sdk ... -D DEBUG native/StoreKitLocalQA/ReusableBridge.swift` — PASS.
- Same typecheck without `-D DEBUG` — PASS; gate remains closed.
- Existing `MockPurchaseFlow` unit tests — 7/7 PASS. These test the separate mock model, not this StoreKit adapter.

**At the time of this earlier run:** the bridge had not been linked into the probe and the refund listener was absent. The follow-up below supersedes those probe-specific limits. Game save integration, production entitlement flow, and relaunch redelivery remain unverified; this file is not a live purchase implementation.

### Local bridge integration and transaction callbacks (2026-10-10 12:20–12:32 JST)

The dedicated Xcode Run probe now compiles `ReusableBridge.swift` and uses `ProbeReceiptStore` as its isolated durable sink. The sink writes an atomic JSON file, reads it back before returning success, deduplicates by stable transaction/event key, and applies revoke events by removing the product from QA ownership. Its persisted transaction count means **sink callback persisted**, not “StoreKit finish already called.” The bridge calls `Transaction.finish()` only after the sink callback returns successfully; a thrown write error propagates on direct purchase and is swallowed by listeners to leave that transaction unfinished for redelivery.

Direct Xcode Run on the existing dedicated iPhone 17 Pro / iOS 26.5 Simulator exercised these paths with the active `Products.storekit` configuration and `Environment: Xcode`:

- Products loaded as 2. A successful non-consumable and consumable purchase produced durable sink entries. The consumable was recorded as a transaction but did not enter `ownedProductIDs`.
- Repeating the furniture purchase produced one receipt keyed by `storekit-xcode:2:entitlement`, rather than a duplicate. The later refund generated `storekit-xcode:2:revocation`; the durable ownership set became empty. This is direct evidence that the running bridge's update listener received and persisted the local revocation.
- With the injected durable-write failure enabled, ticket purchase ID 4 showed `NSCocoaErrorDomain Code=640` / “The file couldn’t be saved because there isn’t enough space.” No corresponding receipt or persisted transaction marker was written. Xcode Transaction Manager showed ID 4 with “This transaction has not been finished by calling finish()”. This verifies failure-before-finish for that concrete transaction.
- With Xcode StoreKit `Ask to Buy` enabled temporarily, ticket purchase displayed an `[Environment: Xcode]` Ask Permission sheet. Choosing Ask returned `purchase=pending`; Transaction Manager showed ID 5, `Pending Approval`, state `Pending Ask to Buy`. Declining it changed the manager state to `Declined` / `Ask to Buy Declined`; no entitlement receipt was added. The `.storekit` setting was then returned to `Not Enabled` and saved.
- A restore call completed after the Xcode-only simulated Apple Account prompt, and restored a non-consumable. The QA consumable was excluded from restored ownership. No account credentials were entered or authenticated.

Current `ProbeReceiptStore.Snapshot` calls the marker `persistedTransactionIDs`, avoiding the old ambiguous `finishEligibleTransactionIDs` name. The one-shot `Transaction.unfinished` diagnostic button was removed: that stream did not provide a completed snapshot in the UI, while Xcode Transaction Manager supplied the authoritative unfinished warning for ID 4. Listener redelivery of ID 4 after relaunch remains unverified.

Regression harness now verifies atomic disk readback before callback success, a new store instance reloading the durable receipt/ownership, duplicate purchase and revocation idempotency, typed out-of-space error propagation with no file or marker, consumable receipt without ownership, and revocation removal. Result: PASS. Probe Xcode build on the dedicated Simulator destination: BUILD SUCCEEDED. These validate the QA bridge and sink only; no Witch game save or production entitlement flow is integrated.

**Relaunch retry attempt:** after the failure test, I stopped the Xcode Run session and ran the freshly built probe again to check whether unfinished transaction 4 would be re-emitted. This Xcode Run produced a new Simulator app container with an empty durable sink, and the StoreKit Transactions manager for the active configuration was also empty. The test transaction was no longer present, so this sequence cannot prove redelivery or the failure-retry-finish cycle. The simulator app container changed from `77B97477-F5DA-4A10-91EE-038F923F2BD2` to `44AA5788-E2B0-4135-8E01-A3D00A4E2F32` across the Xcode Run. Cause of the StoreKit transaction reset is not established. The earlier same-run evidence that ID 4 was unfinished remains valid; relaunch behavior is still **UNKNOWN / NOT VERIFIED**.

Latest post-cleanup build receipt: arm64 UUID `27DEF6B4-BF64-34D1-AD61-E7676A0F0C9C`, x86_64 UUID `71568085-7A2A-34A2-A911-D0A981FF44BA`; bridge source SHA-256 `4c6582273ac9c19e775e89bf6b2cc9d75ac2d3abe99718be6fa66f6de60ea6b7`, sink source SHA-256 `643446a5e3db5a389780f4e64afbf167edb239715669fb701dd6dae9706805b0`, probe source SHA-256 `7020800e2b78e7cc6413ae456e1b657887586e03496128ee1c5379d795282d5b`, StoreKit config SHA-256 `c0861fbcbe3173144018923b1fff7a7262f8990905d642e0dc302116272fbc3f`, project SHA-256 `f25c48e21155519c2f3e6589c5d925ab2e7ced53da4a4ffa23489e15801ef86d`. The installed binary/container changed during this second Xcode Run; these UUIDs identify the successful latest build output, not proof that the purchase-test transaction database survived that new Run.

Ask-to-Buy is a local Xcode scenario, not an Apple Account approval flow. Apple documents testing Ask to Buy with a StoreKit configuration and transaction manager: https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode


## 2026-10-10 13:31 JST: Main app recovery and error paths
Main app R002 now proves same-install/container unfinished transaction ID8 recovery, byte-identical second restart, cancelled purchase, pending ID10 approval and ID11 decline, real Xcode injected Load Products network error -1009 without crash or save mutation. See docs/production/current/purchases/STOREKIT_MAINAPP_XCODE_RESULT_R002.md. Older main-app recovery UNKNOWN is superseded only for this R002 case. SKTestSession Code3 remains unresolved. Production billing remains incomplete.
