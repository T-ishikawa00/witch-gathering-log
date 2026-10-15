# Fixed-SHA Commerce audit

**Audited tree:** `28d3d0b92c840f215a945f47e574fcb30ef2253b` (R087), compared with `45dc02f73f0bcb7c37ad1f01969c3d4b43ceef2e` (R086). Read with `git show` at those revisions; the current worktree has an unrelated unstaged `project.pbxproj` change and was not used as source of truth.

## Findings

No P0/P1 authorization, delivery-integrity, or replay defect is demonstrated in the fixed R461/R463 implementation or its scoped results. R461’s default principal provider denies requests; the facade accepts only the explicitly marked R459 Sandbox rehearsal ledger, validates the full fixed policy, checks the transaction through the rehearsal auditor, reads refund/current-account state in a single read-only snapshot, and labels every response `NOT_AUTHORIZED_FOR_PRODUCTION`. The Swift client validates correlation and delivery fingerprints and does not mutate `GameSnapshot`. R463 persists only pending request/observation state under a marked private rehearsal directory; its source explicitly says it is not wired to production app flows or gameplay saves.

The receipts and implementation pins match. R461 Python focused result: 10/10 passed (`root_test_tools_r002/PYTHON_RESULT.json`, file SHA-256 `e3849588a3dfaee6105ebbed7b7abb9d804e96650630bfc8c45f2c4d65b2befe`). R461 Swift: 37/37 passed across 12 client-contract, 7 importer, 1 transaction-identity, and 17 existing save-recovery methods (`root_test_tools_r003/RESULT.json`). R463 adds 8 store methods, yielding 45/45 in `root_execution_r002/RESULT.json`. Its manifest pins the tested R461 client and R463 store/test bytes to the committed sources; the separate seven-process probe also passed cold reopen, one-writer CAS, persisted refund, and stale-success rejection. These results establish isolated local behavior, not production authentication or power-loss behavior.

R014’s Commerce item correctly remains `releasequality`, with completion limited to local verification and formal adoption false. Its remaining-work text names production authentication, product/account contract, live network, and app purchase wiring as incomplete. One phrase (“R461/R463 SDK integrated”) could be read as normal-app integration; the fixed diff only adds the Core client/store and Python rehearsal facade, not a production transport or App purchase path. Read it as Core/test-target integration only. This is a documentation precision issue, not evidence that production was completed.

## Boundaries that remain open

- No production app transport/server endpoint is connected. The transport in `AuthorityClientContractR461` is injected and explicitly supplies no TLS/server authentication. No verified-principal provider for a real authenticated account is implemented; the default denies all.
- `authority.py` still deliberately has no HTTP server, Apple JWS production verifier, production RNG, StoreKit production wiring, or product catalog. R459 validates synthetic Sandbox-format fixtures only.
- The app continues to keep Xcode-local StoreKit QA behind its QA gate; ordinary summon remains `mockSummon`. The fixed commit’s only native UI change is inventory search/empty-state behavior, not commerce.
- R014 appropriately leaves real Apple Sandbox/production, normal-app paid integration, external product/price decisions, signing/keys, deployment, and operational retention/security review unfinished. No credentials, external service, or live purchase was exercised.

**Disposition:** no new local commerce scaffold or repeated test is warranted from this fixed-SHA audit. Retain the existing local suite. Production acceptance remains blocked on a concrete trusted-service/authentication and product contract, followed by real App Store sandbox/device validation. No tests, builds, app launch, network access, or source changes were performed.
