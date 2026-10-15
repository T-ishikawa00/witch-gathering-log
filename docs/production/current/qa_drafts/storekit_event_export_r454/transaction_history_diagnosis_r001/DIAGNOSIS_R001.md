# R454 finished-consumable lookup diagnosis

The captured R454 failure is consistent with StoreKit's documented history policy. Purchase transaction `2` was durably recorded in save revision 2 (`storekit_qa_ticket: 1`), then the later authority-delivery path failed with `transactionNotFound(2)` while enumerating `Transaction.all`. The retained `last_r454_delivery.json` records that exact error; no host response/request is recorded for the attempted lookup.

The frozen R454 app's built `Info.plist` has no `SKIncludeConsumableInAppPurchaseHistory` key, and its minimum OS is 17.0. Apple's documentation says the key defaults to false and `Transaction.all` excludes finished consumable purchases unless enabled; the feature is available beginning with iOS 18. The purchase path calls `transaction.finish()` after the durable local QA purchase record is applied, so a later history lookup requires this opt-in. Sources: [Apple property-list key](https://developer.apple.com/documentation/bundleresources/information-property-list/skincludeconsumableinapppurchasehistory), [Apple iOS 18 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18-release-notes).

Safe bounded QA correction: set `SKIncludeConsumableInAppPurchaseHistory` to Boolean true in the isolated R454 app's actual input `GameInfo.plist`, verify the built app plist contains true, and keep the R454 local authority UI unavailable unless both `#available(iOS 18.0, *)` and that runtime plist value are true. Current source `GamePurchaseAuthorityQA_R454.swift` now contains this fail-closed gate, but the already-built R454 R003 app is unchanged and its plist still lacks the key; do not count this source edit as tested runtime behavior. A new owned build/install is required to verify the correction.

This key exposes finished consumables through transaction-history APIs; it does not make consumables current entitlements. The existing restore path reads `Transaction.currentEntitlements` and explicitly filters out `.consumable`, so its non-consumable/subscription-only behavior remains separate. Keep the Apple warning in scope: this local QA fixture is not production entitlement authority or server reconciliation.

Pins/evidence:
- R454 R003 installed app `Info.plist`: SHA-256 `5a799e9fd1bba034872bbd528701e0a31ba5a0489c648fc1bf73558cbab87535`; key absent, `MinimumOSVersion=17.0`.
- Input `GameInfo.plist`: SHA-256 `23aa6d25cbe222a126eab26f0235d9bbdcf1894fcf1470b722a4537df0a1eadd`; key absent.
- Captured `STATE.json`: `captures/finished_consumable_unavailable/STATE.json`, SHA-256 `4632ec345467baa0d48ba9c9be07df3928118ef993197faae3bc364543fb11a1`; revision 2 and one saved ticket.
- Captured `last_r454_delivery.json`: exact error `transactionNotFound(2)`.
- Current source `GamePurchaseAuthorityQA_R454.swift` includes the iOS 18 + plist-true guard; it is a later source state than the installed R003 binary.

Scope: read-only diagnosis of retained evidence and source. No app, Simulator, save, build, or StoreKit operation performed by this review.
