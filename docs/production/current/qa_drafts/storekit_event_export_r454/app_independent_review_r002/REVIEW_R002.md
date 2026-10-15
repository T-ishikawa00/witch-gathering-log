# R454 App and bridge final source review

Read-only source review; no edits, build, tests, purchase, or Simulator action.

## Pins

- `GamePurchaseAuthorityQA_R454.swift`: `72cbb7d756087119fa38d1da5c75d48c0ce60934031622d8d97d0a26339811f0`
- `GameStoreKitQA.swift`: `504e78e2a9e0ab4e4b0405ffcc3f0865567288144f5ed894fb2d872a05d6c854`
- `ReusableBridge.swift`: `24f26a7f8b44251aeb2ed6bd615f7e74ef59204370943f54ef4dfda9c52ff62a`
- `LocalPurchaseTransactionIdentityR454.swift`: `d187cf9d2c33e582d9e6ba5656aa35d053bac5e21e9829f3e2fa8e16f1153759`
- `LocalPurchaseDeliveryQAImporterR453.swift`: `0e595275da5035eb9831878147e3e3ec84deb8565a6d1d18bfdc62367b96d890`
- R454 source map includes the App, bridge, and Core helper at those exact hashes.

## Findings

The previous receipt-to-StoreKit identity blocker is fixed. `currentDelivery` obtains an actual verified Xcode transaction for the saved transaction ID and expected account token, constructs the full expected host identity, validates that identity plus operation ID and profile against the receipt, then re-reads StoreKit and returns only after the transaction still matches. The Core helper checks all ten transaction fields. The importer then validates its canonical receipt fingerprint, rechecks the provider on every attempt before consulting SaveRepository, enforces pity/order and gear-UUID uniqueness, and applies only gear, pity, and one save revision. Same-operation replay relies on SaveRepository idempotency. Host code reads refund/tombstone state before and after draw and rechecks on delivery retries.

The enabled path remains DEBUG Simulator-only and requires both existing local StoreKit flags plus an R454 profile/token and isolated `qa-` save. A nil purchase token retains the original `product.purchase()` path. Verified transaction properties are taken from StoreKit; the host profile resolves the test account. The R454 host manifest is `PREPARED_NOT_RUN`; its six tests passed according to `host_runtime_r001/PYTHON_RESULT.json`, while the app/Core test reports are separate local-QA evidence, not Apple or production authorization.

No P1 source blocker found. The cross-system refund race after the final StoreKit check and before the game-save commit remains inherently non-atomic and is already disclosed; keep this QA-only. One low-priority boundary mismatch: App accepts a transaction quantity from 1 through 100 when forming a request, while the pinned R454 host product profile has `maxQuantity: 1` and host validation accepts only quantity 1. Larger quantities fail closed at the host; tightening the App guard to exactly 1 would make the request contract clearer but does not permit an incorrect grant.
