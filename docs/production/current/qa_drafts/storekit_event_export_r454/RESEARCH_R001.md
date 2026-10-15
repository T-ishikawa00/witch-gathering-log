# R454 StoreKit-to-host QA event handoff — source research

Read-only, 2026-10-15. No source, test, build, Simulator, purchase, or save changes.

## Finding

The existing StoreKit QA bridge cannot yet supply the R453 authority’s full event identity. `StoreKitLocalQAEvent` currently contains transactionID, productID/type, environment, purchaseDate, revocationDate and a locally derived idempotency key (`native/StoreKitLocalQA/ReusableBridge.swift`, lines 47–75). `makeEvent` does not export originalID, purchasedQuantity, transaction.appAccountToken, or transaction.appBundleID (235–247). The purchase path calls `product.purchase()` with no options (165–175). The current QASink commits only the app’s separate mock QA ticket/furniture records and returns; it does not export a host event or import the R453 gear receipt (`native/WitchApp/GameStoreKitQASink.swift`, lines 13–42). The panel explicitly says QA tickets cannot be used for draws and paid draws/server authority are not integrated (`GameStoreKitQA.swift`, lines 37–47).

These omissions block a real event-to-R453 handoff, rather than indicating a StoreKit transaction verification failure. The bridge already accepts only verified transactions, requires `Environment.xcode`, gates to DEBUG Simulator with both the active Xcode local configuration and explicit launch flag, and finishes only after its durable sink returns (`ReusableBridge.swift`, lines 5–24, 123–139, 170–175, 201–213, 220–232).

## Minimal local-QA delta

Extend the event projection using only verified `Transaction` properties: `id`, `originalID`, `productID`, `productType`, `purchasedQuantity`, `purchaseDate`, `revocationDate`, `environment`, `appBundleID`, and the optional `appAccountToken`. Apple documents `originalID` and `purchasedQuantity` as transaction fields, `appAccountToken` as an optional value returned only when one was supplied in purchase options, and `appBundleID` as the app identifier on the transaction ([Transaction properties](https://developer.apple.com/documentation/storekit/transaction-properties), [purchasedQuantity](https://developer.apple.com/documentation/storekit/transaction/purchasedquantity), [appAccountToken](https://developer.apple.com/documentation/StoreKit/transaction/appaccounttoken), [appBundleID](https://developer.apple.com/documentation/StoreKit/transaction/appbundleid)). Check `appBundleID` against the running bundle before export.

Do not generate an account UUID, transaction ID, original transaction ID, or token. Export a missing token as absent and fail closed for R453 ticket/gear processing. If a future QA profile already has a pre-registered appAccountToken, the purchase request may pass that exact configured UUID via `Product.PurchaseOption.appAccountToken`; StoreKit returns the same token on the resulting transaction. Without that pinned profile value the bridge cannot create a usable token (`https://developer.apple.com/documentation/StoreKit/Product/PurchaseOption/appAccountToken(_:)`). StoreKit does not expose R453’s `testAccountID`; the host must resolve an actual token against its existing isolated authority profile and reject zero or multiple matches, never infer a customer from the product or current save.

For no-network Simulator QA, export the immutable event as a bounded JSON sidecar under the unique QA app-support namespace, using atomic create-new/replace rules. A host-side watcher can read it and call the existing local authority adapter. Before every R453 receipt response, the host must re-read current purchase/refund/tombstone and ticket-lot state; the iOS process cannot execute the host Python authority. The response exchange should be request/response files in that same isolated namespace with explicit operation IDs and hashes. The app should keep the StoreKit transaction unfinished until the host-authority operation and the local `SaveRepository` gear+pity transaction both report durable success; otherwise the bridge’s existing `finish()` after sink success would close StoreKit delivery before a later gear-import failure can be retried.

R453 remains a mock test authority, not Apple authentication or a production server. Its contract uses a ticket-grant operation followed by a separate, source-lot-bound draw; export must preserve that two-step flow and must not convert StoreKit product quantity directly into item count. The current R453 importer has a separate cross-store race: a refund may arrive after the host’s last check and before local save commit. JSON handoff alone cannot make the host database and game save atomic; label that limitation and test the late-refund window rather than claiming refund-safe delivery.

## Identity available vs. unavailable

| Field | Source | Handling |
|---|---|---|
| transaction / original transaction ID | verified `Transaction.id` / `.originalID` | export exact decimal values |
| product / type / quantity / dates / environment | verified `Transaction` | export exact values; require Xcode environment |
| app bundle | verified `Transaction.appBundleID` | compare with running bundle, then export |
| app account token | verified `Transaction.appAccountToken` | optional; preserve nil, do not synthesize |
| R453 test account ID | not present in the `Transaction` fields | resolve only through a pinned host QA profile keyed by actual token; otherwise reject |
| host operation ID / draw seed | generated by authority for a distinct grant/draw operation | not a StoreKit transaction field; retain host authority as owner |

## Pins and scope

`ReusableBridge.swift` SHA-256 `4c6582273ac9c19e775e89bf6b2cc9d75ac2d3abe99718be6fa66f6de60ea6b7`; `GameStoreKitQA.swift` `e368e306df24a4045e7a0d7036e337de209cec40b4ad84e46d01f09ed97f070a`; `GameStoreKitQASink.swift` `7da7f638c8ac80803e10cce2069c9590f94f19539a3d03ab17f626f18630652f`; `LocalPurchaseDeliveryQAImporterR453.swift` `0e595275da5035eb9831878147e3e3ec84deb8565a6d1d18bfdc62367b96d890`; host adapter `local_delivery_r453.py` `d0c254bfcbf682c31dbd82cbe87c298e0207410509bfb0e139dafe1093beb8a4`.
