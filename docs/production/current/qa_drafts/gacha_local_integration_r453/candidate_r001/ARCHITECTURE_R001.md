# R453 local gacha-authority integration proposal

**Status:** proposal only; no source/test/build/StoreKit/Simulator changes. This proposes an isolated mock integration, not a production path or adopted gacha policy.

## Current boundary

The StoreKit QA bridge verifies StoreKit 2 results and only forwards Xcode-environment transactions to its durable sink. Its event currently carries kind, transaction ID, product ID/type, environment, purchase date, revocation date, and a stable `storekit-xcode:<transactionID>:<entitlement|revocation>` key. It does **not** carry original transaction ID, purchase quantity, or `appAccountToken`; purchase calls also do not currently supply an account token.

The app’s current QA sink writes StoreKit QA records and a separate `storekit_qa_ticket` balance in `SaveRepository`; it does not call the Python authority or add gacha gear. The QA panel says its ticket cannot be used for summons. The regular summon action is a separate Swift `.mockSummon` call.

The Python `PurchaseAuthority` can perform account/token-bound mock purchase, ticket grant/spend, candidate draw/pity/history, refund debt/tombstones, and idempotency in SQLite. Its `DrawReceipt` records draw ordinal, template, quality, and pity, but no game gear UUID, affixes/latent payload, or receipt-to-save delivery marker. Python mock transactions are caller-constructed and guarded by an explicit test-only verifier; `ingest_apple_jws` rejects input. The offline signed-transaction auditor is also deliberately not connected and cannot authorize a grant.

Therefore an event-to-ledger adapter alone would not prove that a result was applied exactly once to a game save. A crash after Python commit but before local save, or after local save but before StoreKit `finish()`, needs replay-safe receipt delivery.

## Smallest safe local slice

Add a test-only `StoreKitAuthorityQASinkR453` plus a host-side adapter for the existing SQLite authority, isolated behind the existing DEBUG + Simulator + `--qa-isolated` + Xcode StoreKit gates and a new explicit R453 test flag. Keep the existing QA furniture/ticket sink unchanged. Do not add an HTTP listener, alter regular `.mockSummon`, or enable a Release/device/production path.

The bridge test event needs a strict test-only extension containing `originalTransactionID`, `quantity`, and `appAccountToken`. The R453 local purchase flow must set an ephemeral run-specific UUID as the StoreKit `appAccountToken`, require StoreKit to return that same UUID, and fail closed if any field is absent or inconsistent. Confirm exact StoreKit API availability when implementing; do not synthesize missing identity fields from product or transaction IDs.

A canonical local event payload should contain:

- schema/profile fingerprint and explicit `EXPLICIT_TEST_MOCK` marker;
- Xcode environment, exact bundle ID, product ID and consumable kind;
- transaction ID, original transaction ID, quantity, purchase date and optional revocation date;
- ephemeral authenticated test account ID and `appAccountToken`;
- stable StoreKit delivery key and a distinct authority draw-operation idempotency key.

Use a temporary SQLite database and explicit test `ProductSpec`/pool configuration, with no user save or real account. Pass the StoreKit event through `PurchaseAuthority`; keep its purchase/ledger/refund transaction authoritative for the test. Return a versioned receipt containing the transaction identity, idempotency key, ticket grant/debt/spend, per-draw template/quality/pity, and stable per-item UUID plus complete candidate gear payload. Existing Python receipt rows do not include item UUID/affix/latent fields; add only test-profile fields and mark their candidate provenance. Do not claim parity of identical seeded outcomes across Python and Swift RNGs: they are different generators. Treat one authority result as the draw outcome and compare the client save to that receipt.

The Swift QA sink should apply the returned receipt and persist a delivery marker plus the complete gear instances and pity/transaction metadata in **one** `SaveRepository.transact`. It should use the stable receipt key and item UUIDs so repeated delivery is a no-op; a payload collision under the same key must reject. Only then may the QA bridge finish the StoreKit transaction. If the subprocess/ledger/save fails, throw so StoreKit redelivers. Do not let a client-supplied amount, quality, seed, template, UUID, or pity state override the authority receipt.

## Focused acceptance sequence

1. Use a fresh QA-only StoreKit configuration and temporary DB; prove the normal game save, R445/Core profile, and existing QA ticket records remain byte-identical.
2. A verified local Xcode ticket event with missing/wrong environment, product, bundle, account token, quantity, original transaction identity, or schema is rejected with no DB or game-save mutation. This tests the adapter boundary, not Apple production verification.
3. A valid mock transaction creates one ticket lot and one authority draw receipt; assert exact transaction/account binding, debit/grant, draw rows, pity before/after, and receipt fingerprint. Apply its complete gear payload to the isolated save once; assert stable UUIDs, quality/affix/latent fields, receipt marker, pity, and revision.
4. Inject interruption after authority commit but before local save; redeliver the same StoreKit event. The authority returns the same result, local state receives it exactly once, and the transaction is finished only after persistence.
5. Inject interruption after local save but before `finish()`. Redelivery must be idempotent: identical snapshot bytes except permitted revision/receipt fields, no extra ticket, gear instance, draw, or pity movement.
6. Read back the DB and save after close/reopen; join purchase transaction → ticket lot → draw receipt → gear UUIDs and verify saved instance payloads equal the immutable authority receipt.
7. Reconcile refund/tombstone paths at the authority and read current state separately from historical receipts. Do not silently delete draw history. Gear retention/clawback on refund needs an explicit policy; until defined, record that the refund ledger works but do not claim game-inventory refund semantics are complete.
8. Keep candidate policy values pinned to the selected profile. Initially require the Python authority profile fingerprint and Swift runtime fingerprint to match the agreed local test profile. A changed or unapproved policy should fail preflight rather than silently alter rates or pool.

## Ownership and limits

Initial candidate work can stay in `tools/witch_purchase_authority/` (test-only event adapter/receipt schema/tests), a separate StoreKit QA test sink and bridge payload extension, and one isolated test harness. It should not change `GameEngine.mockSummon`, the regular Gacha UI, signed Apple verification, `GameStoreKitQASink`, normal saves, products, or Release flags. Any later receipt-to-`GameSnapshot` command should be a separate review because it creates a new inventory grant boundary.

No execution was performed for this proposal. Existing proof remains split: Python SQLite mock ledger QA, synthetic offline signature audit, and StoreKit Xcode QA. None alone or in combination proves this end-to-end adapter until the above join/retry tests are run.
