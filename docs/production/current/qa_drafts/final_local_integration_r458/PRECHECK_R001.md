# R458 final local integration precheck

Scope: read-only source/evidence review. No code, build, test, Simulator, or save operation was performed. R456 was reported running under the root-owned session; this review did not inspect or alter that process.

## Findings

- No new save-loss or crash blocker was established in the reviewed R454 local purchase path. Its bounded runtime receipt reports `PASS_SCOPED_LOCAL_XCODE_TO_MOCK_AUTHORITY`: one real Xcode StoreKit consumable transaction, one persisted delivery, byte-identical duplicate replay, rejected mock-refund replay without mutation, no consumable regrant on restore, and byte-identical cold relaunch. Receipt: `qa_drafts/storekit_event_export_r454/runtime_r001/RUNTIME_RESULT_R001.json`, SHA-256 `ec784e713b85b1cdaef76a6ee1ab73ef703074ac4e8c34d7878ae5e80afce10a`. The tested save is isolated revision 3 (SHA-256 `63936957bb1ac8c592ee485b17591d294856652c04c06afc2d1766bc70a38034`); the receipt says the normal R445 save and prior PBX were unchanged.
- This is local QA only. `GamePurchaseAuthorityQA_R454.swift` explicitly limits the bridge to DEBUG Simulator and the Xcode environment, uses a fixed local test account and explicit mock host response, and revalidates actual StoreKit transaction identity before applying. `GameStoreKitQA.swift` also labels paid draws/server authority as not integrated. The iOS 18+ consumable-history plist gate addresses retrieval of finished consumables in this QA route; it is not Apple server verification.
- The separate purchase-authority package remains explicitly `UNAPPROVED_REFERENCE / NOT_PRODUCTION`. Its `ingest_apple_jws()` rejects input and it has no Apple verification adapter, application/network integration, live account, or deployment. Its own README lists required Apple signature/notification verification, authenticated account binding, SKU policy, key management/CSPRNG, durable server operations, abuse controls, monitoring, and review.
- Current status records are stale relative to R454. `COMPLETION_REGISTER_R010.json` still describes R453-to-Swift delivery as unconnected (lines 104–110) and describes R445/R447 235-source evidence (lines 174–180), while R454 has a scoped delivery runtime receipt. Correct the status wording in a later register revision; do not treat this precheck as a register update or infer R456 build success.

## Remaining gates

1. Human adoption of the formal product, price, territory, paid-content, and odds policy. R454's fixed local test product and R453 candidate values are not adopted commercial terms.
2. Production purchase authority: real authenticated player/account-token lifecycle; validated Apple signed transactions and server notifications/refunds; production SKU and quantity rules; secure keys and server CSPRNG; transactional durable storage, backup/recovery, monitoring, and abuse controls. None is connected to the app today.
3. Signed install and operation on a paired physical iPhone, including device-specific lifecycle, performance, interruption, and recovery. R447 is an unsigned compile only; R456's current build was still in progress when this precheck was requested. Neither constitutes device runtime validation.
4. Human/platform authorization for signing, distribution, review, and publication.

## Source pins checked

The five R454 paths below match the frozen R454 source map `native/qa_source_20261015T062300/SOURCE_SHA256.json`:

- `WitchApp/GamePurchaseAuthorityQA_R454.swift` `19375066951f5b9381e6fafa7c36ac635c3b6a4967cdc3905aa3f9de1820a11c`
- `WitchApp/GameStoreKitQA.swift` `504e78e2a9e0ab4e4b0405ffcc3f0865567288144f5ed894fb2d872a05d6c854`
- `StoreKitLocalQA/ReusableBridge.swift` `24f26a7f8b44251aeb2ed6bd615f7e74ef59204370943f54ef4dfda9c52ff62a`
- `WitchGameCore/Sources/WitchGameCore/LocalPurchaseDeliveryQAImporterR453.swift` `0e595275da5035eb9831878147e3e3ec84deb8565a6d1d18bfdc62367b96d890`
- `WitchGameCore/Sources/WitchGameCore/LocalPurchaseTransactionIdentityR454.swift` `d187cf9d2c33e582d9e6ba5656aa35d053bac5e21e9829f3e2fa8e16f1153759`

The R456 sealed input names a 238-source map and 1,922 resources, but its terminal build result was not used as evidence here. No release acceptance conclusion is made.
