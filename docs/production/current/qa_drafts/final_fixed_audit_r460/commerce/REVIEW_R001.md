# R460 commerce fixed-SHA review

**Review target:** `45dc02f73f0bcb7c37ad1f01969c3d4b43ceef2e` (R086). Source and evidence were read from this Git tree; no build, test, device, network, or source edit was performed.

## Finding

The scoped local commerce QA passes, but the production paid-draw path remains unimplemented. `authority.py` deliberately rejects Apple JWS; R454 is a DEBUG Simulator file exchange with a hard-coded QA account and mock product; R459 accepts synthetic signed Sandbox fixtures into a separately marked ledger and explicitly returns `NOT_AUTHORIZED_FOR_PRODUCTION`. Hashes and account-token equality in these fixtures bind test data; they do not authenticate a live user or host.

There is still locally executable engineering work: implement a candidate, fail-closed authority-client/service boundary that accepts an authenticated-principal interface, validates a verified transaction, sends an idempotent purchase/draw request, and consumes an authoritative current-state response for ticket balance, pity/result, and refund/revocation. A local fake transport and generated test keys can exercise strict request/response validation, replay, collision, retry, refund-state rejection, and offline behavior. Keep this isolated from the mock StoreKit path and do not grant production entitlements. Such tests would validate the client protocol; they cannot establish real account authentication, Apple authorization, online revocation, or deployed service security.

The remaining external boundary is real identity/session provisioning, Apple server configuration and current transaction/refund lookup, deployment/key management, final product and price policy, and real Sandbox/device acceptance. Those decisions do not erase the local code gap, and local contract tests do not close the external boundary.

## Evidence boundary

- R453: 7 importer + 17 save-recovery Swift cases passed; Python adapter 73 cases passed and the 15 focused adapter cases passed without resource warnings. This is test-fixture-to-save correctness, not payment authorization.
- R454: 25 Swift and 6 Python cases, two Debug Xcode builds, one local Xcode purchase and three host exchanges. The route uses a QA token/account, file exchange and QA-only receipt.
- R377: fresh restore delivered one nonconsumable; repeated and cold restores were byte-identical under the local Xcode configuration.
- R459: 110 methods passed, but 21 were repeated crypto methods; synthetic certs and fixture account bindings only. No Apple transaction, network, real-money operation, production grant, or online revocation check occurred.

The detailed pins and source claims are in [REVIEW_R001.json](REVIEW_R001.json).
