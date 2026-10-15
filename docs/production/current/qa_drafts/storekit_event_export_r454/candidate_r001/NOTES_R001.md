# R454 bridge identity extension

This candidate changes only `native/StoreKitLocalQA/ReusableBridge.swift`.

- Source before: `4c6582273ac9c19e775e89bf6b2cc9d75ac2d3abe99718be6fa66f6de60ea6b7`
- Source after: `cdfab865f28b7f73bfd30b4872dfd889327434584fd6cdbef255bd7a17ce55f5`
- Patch: `5741b1a863ef963c2172006cb816402a1220f9efd427798e477b211d5b226fed`

`StoreKitLocalQAEvent` gains four optional fields with default-`nil` initializer arguments, so existing construction sites remain source-compatible. `makeEvent` fills them from the verified StoreKit transaction (`originalID`, `purchasedQuantity`, `appAccountToken`, and `appBundleID`). `purchase(productID:)` keeps the original no-options call when its optional token is absent; when supplied, it forwards exactly that UUID as `.appAccountToken` and does not generate identity.

`currentVerifiedXcodeTransaction(matching:)` reads `Transaction.all` under the existing local QA gate. It returns only an exactly matching verified Xcode transaction for the running bundle; unknown, unverified, revoked, or mismatched transactions throw. This is a current StoreKit lookup, not an atomic reservation: host-authority state must still be revalidated, and StoreKit plus the game save cannot be committed atomically by this bridge alone.

SDK interface evidence was read from the installed iPhone Simulator 26.5 StoreKit interface. It exposes the transaction properties and `.appAccountToken(_:)`; the bridge's existing iOS 17/macOS 14 availability floor is sufficient. No compile, test, build, StoreKit purchase, Simulator action, or live-save change was performed. `git diff --check` passed. Existing DEBUG + Simulator + local-configuration + launch-argument gates are unchanged.
