# R459 candidate R002 independent source review

Reviewed the frozen candidate manifest SHA-256 `f85d4f75053931ac1ee483bc982d062a4124aa6449caf0dfce895defd9ef379f` and patch SHA-256 `e885431077f3808e2bee8eca0a0ea56f439a5dec77737a9cdfc5c36ce368fe0e` at fixed candidate R002. This was a read-only source review; tests, database operations, network calls, and production integration were not performed.

## Findings

The R001 admission bypasses are corrected in the candidate’s intended public path. `SandboxLedgerRehearsalR459` now requires its private factory key at construction and `create()` only accepts a nonexistent leaf named `r459-sandbox-rehearsal`. Purchase and notification records are typed R459 records, and `PurchaseAuthority` accepts Sandbox records only when their capability object is the one bound to that authority. The old mock paths remain gated by `allow_test_mock_verifier`; `ingest_apple_jws()` remains fail-closed. These are local Python API boundaries, not protection against malicious code with introspection/import access to private module symbols, and they do not constitute production authorization.

The signed refund path now verifies both the outer notification and nested transaction with the pinned Sandbox verifier; checks bundle, environment, account-token binding, product and quantity; requires a canonical nonzero notification UUID; constrains outer and transaction dates; and orders purchase date ≤ revocation date ≤ transaction signed date ≤ notification signed date. The new focused tests cover malformed UUID/date ordering, notification-ID collision, injected rollback/retry/replay, and a refund tombstone suppressing a later signed purchase.

Ledger application remains inside `BEGIN IMMEDIATE` transactions. The Sandbox notification route delegates to the same inbox/domain transaction used by existing mock notifications, retaining unique notification IDs, payload digests, replay responses, transaction identity checks, refund clawback/debt accounting, and rollback fault points. Existing copied tests include concurrent idempotency and duplicate-notification coverage, though those race tests exercise the shared mock entry point, not simultaneous signed-Sandbox adapter calls specifically.

All audit and adapter statuses still explicitly say authorization is false / not provided and online revocation was not checked. The test JWS chain is synthetic; it exercises the configured verifier path but is not Apple-issued evidence. This candidate does not connect to the application or an external account, nor does it make a production grant decision.

## Residual location-isolation issue

`SandboxLedgerRehearsalR459.create()` checks `root.is_symlink()`, existence, and the required final directory name, then calls `mkdir`. It does not resolve/check ancestor components. A caller can supply a nonexistent `r459-sandbox-rehearsal` leaf under a symlinked parent, redirecting the new database and marker into another location. The exclusive leaf creation avoids overwriting an existing leaf, so this is not an observed data-loss path, but the adapter’s stated isolated-directory guarantee is weaker than its name suggests. Before relying on the location as a safety boundary, reject symlinked ancestors or constrain the resolved parent to an explicit approved scratch root; add a symlink-parent negative test. No test was run here.

## Status

No other source-level P1 was identified in the reviewed path. This is not a runtime/test pass, production StoreKit approval, Apple trust-chain validation, account authentication, online revocation guarantee, or release authorization. The candidate manifest itself correctly records tests as not run and production authorization as not provided.
