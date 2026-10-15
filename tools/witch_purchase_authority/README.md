# Witch purchase-authority reference (local test only)

**Status: UNAPPROVED_REFERENCE / NOT_PRODUCTION.** This isolated Python/SQLite package models the server trust boundary requested by mission acceptance. It has no HTTP/API listener, real product catalog, authenticated live account, production verification route, or deployment. R453/R454 connect an explicitly mock local ledger to Swift QA delivery and an actual Xcode-local transaction; the normal iPhone app does not enable production paid draws. R459 connects the [offline signed-transaction audit](SIGNED_TRANSACTION_AUDIT.md) to a newly created, marked Sandbox rehearsal database. That route uses synthetic cryptographic fixtures and cannot authorize a production grant. It must not be described as production-complete.

## Existing contract mapping

- Mission `03_ACCEPTANCE_AND_BLOCKERS.md` requires transaction identity, user binding, server-side paid draw/pity/history, refunds, duplicate callbacks, time/device consistency, and makes client-only paid draw results unacceptable.
- Current core records paid tickets as `ticket_paid_mock`; candidate R3 odds are Q0/Q1/Q2/Q3/Q4 = 35/40/20/4/1%, Q3 floor after 20 low rolls, Q4 at the 100th non-Q4, and target top-quality 50/50 with a next-top guarantee after a miss. All are explicitly unapproved test values.
- Current StoreKit Xcode QA proves local client persistence/retry/revocation but explicitly leaves Sandbox/production receipts and server authority unimplemented.
- This reference scopes a transaction identity as `(environment, bundle_id, transaction_id)`, checks product and quantity against a server-configured allowlist, and requires account-bound `appAccountToken`. SQLite `BEGIN IMMEDIATE`, composite/unique keys and one transaction ensure purchase grant, debt handling, ticket spend, draw output, pity mutation, history, and idempotency receipt commit together.
- Refunds claw back unspent tickets and create a non-negative spent-ticket debt. Paid draws stop while debt remains; later verified grants first repay the debt. Refund notifications received before the matching purchase delivery create a validated identity tombstone, so delayed delivery cannot grant tickets. Refunded StoreKit identities are never accepted again. Already-recorded draw history is not silently deleted; replaying a refunded purchase operation is rejected rather than returning a stale successful receipt.
- Ticket-only purchase (`draw_count=0`) is supported. Later `draw_mock()` spends stored paid ticket lots atomically with server pity/result/history under its own idempotency operation UUID; each draw records the exact originating ticket lot. Repeating the same draw UUID returns the stored result, payload collisions reject.
- Transaction quantity, draw count, test seed, and candidate product bounds require strict bounded integers; booleans/floats are rejected.

## Verification boundary

The original `ingest_apple_jws()` always rejects; it is not the entrypoint for the later R459 offline adapter. Mock delivery requires `allow_test_mock_verifier=True` and an explicit `MockVerifiedPurchase` carrying `EXPLICIT_TEST_MOCK`. R459 separately verifies synthetic Sandbox-format signatures before using a capability bound to its isolated rehearsal ledger. Neither route authorizes production delivery. Seeded RNG exists only for deterministic tests. A production design needs a server CSPRNG adapter and must ignore client seeds/selection/outcomes.

Run from this directory:

```sh
python3 -m unittest discover -s tests -v
```

The tests use temporary databases; they do not touch game saves or products. They cover duplicate identity/idempotency collision, concurrent same-operation and two-terminal retries, account/token/bundle/environment/product/quantity binding, fail-closed fake JWS, atomic fault points with successful StoreKit-style retry, ticket-only purchase and later independent draw UUID, source-lot attribution, candidate pity persistence, refund-before-purchase tombstones, post-refund retry rejection, refund clawback/debt/no-regrant, strict integers, and deterministic candidate draw boundaries.

## Deliberate production gaps

Still required before a live path: validated Apple App Store Server API / signed transaction verification and notification reconciliation, server-authenticated player identity and appAccountToken binding lifecycle, production SKU/territory/quantity policy, key management, CSPRNG, multi-region database consistency/backup/restore, abuse limits, operational monitoring, legal/platform review, and integration/penetration testing. None are simulated as PASS here.

Apple's [App Store Server Python Library](https://github.com/apple/app-store-server-library-python/blob/main/README.md) documents `SignedDataVerifier` construction with Apple root certificates, online checks, environment, bundle ID, and `appAppleId` (required for Production). Apple's [`appAccountToken` reference](https://developer.apple.com/documentation/appstoreservernotifications/appaccounttoken) is the platform field to bind verified StoreKit transactions to the authenticated player account. The original SQLite authority remains independent of those services. The later offline audit uses a separately installed pinned dependency and ephemeral synthetic certificates; it makes no Apple API call or account connection and does not validate a real Apple purchase.
## Local mock notification inbox (R003)

The package can optionally ingest explicitly constructed `MockNotificationDelivery` fixtures when `allow_test_mock_verifier=True`. Inbox deduplication, purchase/refund/tombstone updates, account balance/debt, ticket ledger, and the historical delivery receipt commit in one SQLite transaction. Replays return an immutable historical `delivery_receipt` separately from a freshly queried `current_transaction`; callers must use the latter for current status and balance. Schema version 2 databases are upgraded by adding the inbox table and setting version 3; existing authority rows are retained.

This notification capability is test-only. `ingest_apple_jws()` continues to reject input, and mock notification fixtures do not verify Apple signatures or authorize production entitlements. The separate R459 adapter verifies signed Sandbox-format purchase and refund envelopes before invoking capability-bound rehearsal ledger methods; no network endpoint or live account is connected.

## R459 isolated signed Sandbox rehearsal

`SandboxLedgerRehearsalR459.create()` requires a fresh `r459-sandbox-rehearsal` directory, canonicalizes its existing parent, and writes a non-production marker. The ledger capability is tied to that authority instance and marked database. Typed signed records cannot be substituted with a generic object, payload dictionary, or caller-selected environment. This protects against accidental API misuse; it is not a security boundary against arbitrary Python code running in the same process.

Purchase and refund envelopes pass the official library's strict certificate/signature checks and the local identity, quantity, ownership and date policy. Signed refund notices also require a UUID, valid outer date and revocation chronology. Notification receipt and refund/tombstone changes are atomic. Tests cover signed draw rollback, retry, spent-ticket debt, notification replay/collision and refund-before-purchase suppression. Existing mock entrypoints still require exact mock types and explicit enablement.

The rehearsal uses fixture account bindings and deterministic test seeds. Every result retains `NOT_AUTHORIZED_FOR_PRODUCTION`, `grantAuthorized=false` and no online revocation verification. It adds a local integration test path, not an Apple purchase authority or production server. No real JWS, signing key or account credential is stored by its tests.

## R461 typed local client/service contract

`local_service_r461.py` wraps R459 without a listener or network calls. Its default principal provider denies every request. Tests inject a fixture principal out of band; the request cannot choose an account, product policy, seed or draw result. A policy fingerprint is pinned to the marked rehearsal database so reopening it with changed draw rules cannot silently reinterpret an old receipt.

Responses separate immutable delivery history from current account revision, refund status, balance and debt. The Swift `PurchaseAuthorityClientR461` validates the same canonical schema, identity and item fingerprints, then atomically advances its observation store. It does not grant game items or mutate `GameSnapshot`.

The final R461 run passed 12 new Swift contract tests plus 25 existing purchase/save regressions. It consumed the exact response exported from a synthetic signed purchase and refund through the actual offline verifier and ledger. Python's 10 focused service tests passed after a test-fixture repair; 110 unchanged legacy method executions passed in the preceding combined run. The first Python fixture error and Swift test compilation failure remain in the evidence. At this checkpoint, durable client stores and native transport wiring are not established by these tests; they must not be inferred from an in-memory retry test.

R463 subsequently adds `FileBackedAuthorityStoreR463` for an explicitly marked, private local rehearsal directory. Its eight tests join the 37 existing Swift cases, for 45 passing methods. A separate seven-process probe verifies restart readback, competing compare-and-save writers, durable refund state and rejection of an older success state. It does not prove physical-device power-loss behavior or app purchase integration. Records are deliberately preserved: the 256-operation limit is cumulative per rehearsal account, not a rolling pending queue. New operations fail at that boundary without evicting retry evidence. Production retention, authenticated network transport and native production purchase wiring remain unimplemented.
