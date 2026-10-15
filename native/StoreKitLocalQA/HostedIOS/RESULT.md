# iOS app-hosted SKTestSession probe R001

Date: 2026-10-10 JST. QA-only; no account sign-in, external StoreKit connection, or real purchase.

## Question and setup

The prior iOS XCTest was hostless. This experiment added a separate iOS host app and unit-test bundle with TEST_HOST and BUNDLE_LOADER pointing to StoreKitHostedHost.app/StoreKitHostedHost. The test bundle embeds the existing local-only WitchLocalTest.storekit and runs one non-consumable purchase case. The scheme's Test action references that StoreKit configuration. It ran on the dedicated Witch 03to05 Compact QA Simulator, UDID F843518C-7377-434C-A960-B26FB7F34C4B, iOS 26.5. It did not touch the 9A soak or the separate StoreKit and art QA simulators.

Apple's current documentation states that SKTestSession automates StoreKit transaction tests and that local Xcode StoreKit testing uses the configuration selected in the scheme. It does not document the observed Code 3 / notEntitled combination or require an Apple Account for this local path: [StoreKit Test](https://developer.apple.com/documentation/storekittest), [SKTestSession](https://developer.apple.com/documentation/storekittest/sktestsession), [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).

## Result

The Xcode build succeeded and launched the hosted test inside the app host. It still failed before producing a transaction:

    HOSTED_STOREKIT_TEST bundle=local.witch.storekit.hostedqa.tests config=.../StoreKitHostedHost.app/PlugIns/StoreKitHostedTests.xctest/WitchLocalTest.storekit
    [SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3 "(null)"
    [SKTestSession] Error setting value to 1 for identifier 2 for local.witch.storekit.hostedqa: Error Domain=SKInternalErrorDomain Code=3 "(null)"
    Failed to purchase local.witch.test.furniture in off-device buy mode: Unable to Complete Request
    failed: caught error: "notEntitled"

The test error occurred at HostedStoreKitTests.swift:13 when session.buyProduct(identifier: "local.witch.test.furniture") ran. XCTest recorded 1 test, 1 failure; no transaction ID was returned. Full command log: HostedStoreKitQA_20261010_r002.log; result bundle: HostedStoreKitQA_20261010_r002.xcresult.

This run is a valid app-hosted XCTest: the StoreKit session error identifies the host app bundle local.witch.storekit.hostedqa, rather than com.apple.dt.xctest.tool. Therefore the failure is not limited to the earlier hostless test runner identity. It still does not establish why the local StoreKit session cannot apply its settings or create the transaction. This is separate from the fixed ProbeApp nil unwrap and from the previously repaired direct-Xcode-Run product lookup.

## Configuration correction during setup

The first generated scheme had invalid debugger/launcher identifiers. Xcode 26.6 crashed while reading its launch/test scheme action, before building or invoking StoreKit. Diagnostic report xcodebuild-2026-10-10-135752.000.ips recorded EXC_BAD_ACCESS (SIGSEGV), Thread stack size exceeded due to excessive recursion, with repeated -[IDELaunchTestSchemeAction commandLineArgumentEntries] frames. Correcting the scheme to Xcode's debugger/launcher identifiers stopped that tooling crash; xcodebuild -showBuildSettings and the hosted test then ran. This setup crash is not the StoreKit error.

## Reproduction

    xcodebuild test \
      -project native/StoreKitLocalQA/HostedIOS/HostedIOS.xcodeproj \
      -scheme HostedStoreKitQA \
      -destination 'platform=iOS Simulator,id=F843518C-7377-434C-A960-B26FB7F34C4B' \
      -derivedDataPath native/StoreKitLocalQA/HostedIOS/DerivedData \
      -resultBundlePath native/StoreKitLocalQA/HostedIOS/HostedStoreKitQA_20261010_r002.xcresult \
      CODE_SIGNING_ALLOWED=NO

Observed result: TEST_EXIT:65 due to the one failed StoreKit test.

## Evidence identity

- Host/HostApp.swift: SHA-256 dbc5efcf6763c8ad32e7442e3775b72dac0665f7e1dd089a7b886e7d6086e42c
- Tests/HostedStoreKitTests.swift: SHA-256 4c3f80293583e692a78fe4b42cdc5a400039ae03b548dd9d8be7c032d5c3722e
- HostedIOS.xcodeproj/project.pbxproj: SHA-256 125e2cc3a91e98a9e5f628011fbb8eaed83270107d9e957e3cf33de486f0206e
- HostedStoreKitQA.xcscheme: SHA-256 069669380644397222a13491a7ac89b5ba60c592f7dc5fc15202a9e8c04e497d
- WitchLocalTest.storekit: SHA-256 029001df240390de40e12a831792b0d231edef66ba2d4f9a025e87b399a87dbd

## Conclusion

Confirmed: app-hosted iOS XCTest still reproduces Code 3 and notEntitled before transaction creation, despite the correct host-app identity and a valid local StoreKit Test configuration. Cause remains UNKNOWN. It does not prove that a Human must change macOS security settings or authenticate an Apple Account; no such change or authentication was attempted. Direct Xcode Run local StoreKit transactions and this automated SKTestSession API route are separate mechanisms, and success in the former does not close this failure.

## Follow-up R003: configuration in host app bundle

Apple's initializer documentation says to include the configuration in the application bundle. To remove the remaining bundle-placement ambiguity, R003 added the same local file to the host app's Resources and changed the test to call SKTestSession(configurationFileNamed: "WitchLocalTest"). The XCTest log confirmed the URL resolved inside StoreKitHostedHost.app itself:

    HOSTED_STOREKIT_TEST bundle=local.witch.storekit.hostedqa config=.../StoreKitHostedHost.app/WitchLocalTest.storekit
    [SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3 "(null)"
    [SKTestSession] Error setting value to 1 for identifier 2 for local.witch.storekit.hostedqa: Error Domain=SKInternalErrorDomain Code=3 "(null)"
    Failed to purchase local.witch.test.furniture in off-device buy mode: Unable to Complete Request
    failed: caught error: "notEntitled"

R003 ran only the same one test on the same dedicated F843 Simulator. Result: 1 test, 1 failure, no transaction, TEST_EXIT:65. Full log and result bundle: HostedStoreKitQA_20261010_r003.log and HostedStoreKitQA_20261010_r003.xcresult. This rules out only the specific test-bundle-only configuration placement and contentsOf initializer used in R002; it does not identify the underlying cause.

R003 source/config hashes: HostedStoreKitTests.swift ef6be62b55653a3e22febe408db124ddb89985ec98dc6bea73c7306820e43fa8; project.pbxproj 41f69f3e4f39594e131ea0e4ea599e3f4826b08239431d77470a43d0faf49a40; scheme 069669380644397222a13491a7ac89b5ba60c592f7dc5fc15202a9e8c04e497d; host-bundled WitchLocalTest.storekit 029001df240390de40e12a831792b0d231edef66ba2d4f9a025e87b399a87dbd.

