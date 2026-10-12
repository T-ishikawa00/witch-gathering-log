# Witch purchase-authority reference (local test only)

**Status: UNAPPROVED_REFERENCE / NOT_PRODUCTION.** This isolated Python/SQLite package models the server trust boundary requested by mission acceptance. The granting authority has no HTTP/API listener, Apple verification adapter, real product catalog, app integration, network, live account, purchase SDK, or deployment. It does not enable paid draws in the iPhone app. It must not be described as production-complete. A separate [offline signed-transaction audit](SIGNED_TRANSACTION_AUDIT.md) now exercises the official library's cryptographic checks; it cannot authorize a grant and is not connected to this authority.

## Existing contract mapping

- Mission `03_ACCEPTANCE_AND_BLOCKERS.md` requires transaction identity, user binding, server-side paid draw/pity/history, refunds, duplicate callbacks, time/device consistency, and makes client-only paid draw results unacceptable.
- Current core records paid tickets as `ticket_paid_mock`; candidate R3 odds are Q0/Q1/Q2/Q3/Q4 = 35/40/20/4/1%, Q3 floor after 20 low rolls, Q4 at the 100th non-Q4, and target top-quality 50/50 with a next-top guarantee after a miss. All are explicitly unapproved test values.
- Current StoreKit Xcode QA proves local client persistence/retry/revocation but explicitly leaves Sandbox/production receipts and server authority unimplemented.
- This reference scopes a transaction identity as `(environment, bundle_id, transaction_id)`, checks product and quantity against a server-configured allowlist, and requires account-bound `appAccountToken`. SQLite `BEGIN IMMEDIATE`, composite/unique keys and one transaction ensure purchase grant, debt handling, ticket spend, draw output, pity mutation, history, and idempotency receipt commit together.
- Refunds claw back unspent tickets and create a non-negative spent-ticket debt. Paid draws stop while debt remains; later verified grants first repay the debt. Refund notifications received before the matching purchase delivery create a validated identity tombstone, so delayed delivery cannot grant tickets. Refunded StoreKit identities are never accepted again. Already-recorded draw history is not silently deleted; replaying a refunded purchase operation is rejected rather than returning a stale successful receipt.
- Ticket-only purchase (`draw_count=0`) is supported. Later `draw_mock()` spends stored paid ticket lots atomically with server pity/result/history under its own idempotency operation UUID; each draw records the exact originating ticket lot. Repeating the same draw UUID returns the stored result, payload collisions reject.
- Transaction quantity, draw count, test seed, and candidate product bounds require strict bounded integers; booleans/floats are rejected.

## Verification boundary

`ingest_apple_jws()` always rejects because no Apple JWS signature/certificate/issuer/environment verification adapter exists. The only successful path is `purchase_and_draw_mock()` with `allow_test_mock_verifier=True` and an explicit `MockVerifiedPurchase` carrying `EXPLICIT_TEST_MOCK`. Its seeded Python RNG exists only for deterministic tests. A production design needs a server CSPRNG adapter and must ignore client seeds/selection/outcomes.

Run from this directory:

```sh
python3 -m unittest discover -s tests -v
```

The tests use temporary databases; they do not touch game saves or products. They cover duplicate identity/idempotency collision, concurrent same-operation and two-terminal retries, account/token/bundle/environment/product/quantity binding, fail-closed fake JWS, atomic fault points with successful StoreKit-style retry, ticket-only purchase and later independent draw UUID, source-lot attribution, candidate pity persistence, refund-before-purchase tombstones, post-refund retry rejection, refund clawback/debt/no-regrant, strict integers, and deterministic candidate draw boundaries.

## Deliberate production gaps

Still required before a live path: validated Apple App Store Server API / signed transaction verification and notification reconciliation, server-authenticated player identity and appAccountToken binding lifecycle, production SKU/territory/quantity policy, key management, CSPRNG, multi-region database consistency/backup/restore, abuse limits, operational monitoring, legal/platform review, and integration/penetration testing. None are simulated as PASS here.

Apple's [App Store Server Python Library](https://github.com/apple/app-store-server-library-python/blob/main/README.md) documents `SignedDataVerifier` construction with Apple root certificates, online checks, environment, bundle ID, and `appAppleId` (required for Production). Apple's [`appAccountToken` reference](https://developer.apple.com/documentation/appstoreservernotifications/appaccounttoken) is the platform field to bind verified StoreKit transactions to the authenticated player account. The original SQLite authority remains independent of those services. The later offline audit uses a separately installed pinned dependency and ephemeral synthetic certificates; it makes no Apple API call or account connection and does not validate a real Apple purchase.
