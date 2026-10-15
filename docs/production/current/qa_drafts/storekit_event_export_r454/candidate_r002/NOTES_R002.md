# R454 bridge overload correction

Additive revision; R001 files and source snapshot remain unchanged.

- R001 source SHA (R002 base): `cdfab865f28b7f73bfd30b4872dfd889327434584fd6cdbef255bd7a17ce55f5`
- R002 source SHA: `24f26a7f8b44251aeb2ed6bd615f7e74ef59204370943f54ef4dfda9c52ff62a`
- R002 patch SHA: `1eccf1e1d21e770bb266f3e6b15efb6bcba395cb71e7505a749a391ec34d9ef6`

Added `currentVerifiedXcodeTransaction(transactionID:expectedAppAccountToken:)`. It reads the actual `Transaction.all` record and returns its projected event only after verifying the transaction, Xcode environment, no revocation, running bundle ID, and exact expected account token. It avoids constructing an expected event from persisted data. Unknown, unverified, revoked, or identity-mismatched records fail closed. The existing event-matching overload remains unchanged. This remains a local QA lookup, not an atomic StoreKit/host/save transaction; callers must revalidate host authority.

No other source was changed. No build, test, purchase, or Simulator action was run.
