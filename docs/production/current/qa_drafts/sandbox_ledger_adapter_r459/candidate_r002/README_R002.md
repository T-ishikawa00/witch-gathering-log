# R459 Sandbox ledger candidate R002

R002 closes the R001 code-boundary defects without changing production authority. Sandbox purchase and refund records are exact candidate types bound to an isolated authority instance; callers cannot select an environment or pass an arbitrary object/string verifier claim. The rehearsal adapter can only be created for a newly-created `r459-sandbox-rehearsal` directory, and its constructor/verification records require private factory tokens. Mock APIs remain Xcode-only and retain their explicit mock switch.

Refund JWS processing uses the same strict signed-transaction identity/quantity/date policy as purchase processing, with revocation-only fields enabled. It validates UUID notification identity, outer signed time, transaction/revocation ordering, and persists notification receipt plus refund/tombstone changes in one SQLite transaction using the existing inbox collision/replay guard. A refund tombstone prevents a later signed purchase from granting tickets.

All returned rehearsal/audit results explicitly state `NOT_AUTHORIZED_FOR_PRODUCTION`; `grant_authorized` and `revocation_checked` remain false. `PurchaseAuthority.ingest_apple_jws` remains fail-closed. This remains a local Sandbox-format rehearsal using synthetic certificate fixtures and fixture account equality, not Apple production authorization, authenticated user identity, or online revocation verification.

## Validation status

Static Python AST parsing and JSON parsing only. No unit test, build, Apple account, external request, or live authority mutation was run. Proposed regression coverage adds unbound-object/public-constructor rejection, UUID/date/revocation-order rejection, signed inbox replay/collision/rollback, and refund-before-purchase suppression.
