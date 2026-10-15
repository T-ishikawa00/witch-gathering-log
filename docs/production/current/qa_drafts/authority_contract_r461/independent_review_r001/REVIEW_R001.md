# R461 independent source review

Scope: exact frozen candidate sources only; no tests, build, fixture export, network, or production integration was run.

Reviewed pins:

- Wire contract R002: `CONTRACT_R002.json` SHA-256 `24e88a2e2c197e7be36a8ff6d226cd55478fed007560d398f848c35d0052830d`.
- Python repair R003: service `564b0b2d4fb4c079345c36ced790507c1d722e1b1436dec7ba9e6ba967fb84fe`, tests `84f1b3b418ae0c1d2988e82bfeb3cc4d321479e7e071dfdfa623309f88265e3b`, manifest `c697ec8d000a3e99e6d39992b4917709287bd53e557ae8f6814b5ff87e034d53`.
- Swift R002: source `03bad37f64f990d7b344a0c6a8b60a7cfefac19f0eb864abe6aa24fadc605f9d`, tests `9c8a3b4e2c96e46cf9d0eb9c3d5b7f8d042b1cea50fed30f171f5bed10c3e98a`, manifest `008cd46dd0ca6dfd0e470502a2ce802307bbcd0ecbbe896dc0102be5a480c678`.

R002 had a real wire blocker: unauthenticated Python responses could carry a parsed `operationID`, and policy rejection ran before principal resolution. Swift correctly rejects non-null operation correlation when account binding is null. Python R003 now nulls the operation ID whenever binding is absent, resolves the principal before policy rejection, and keeps correlation only for authenticated policy failures. Its added tests cover default deny, provider failure, malformed request, authenticated policy drift, and database redirection. The ledger pin now checks the exact R459 database path, hard-link count, and local rehearsal marker.

In the reviewed code, I found no remaining blocking source mismatch. Swift R002's exact-key/canonical-byte validation, seven-field item binding and row fingerprints, delivery fingerprint, StoreKit tuple correlation, stale/equal-revision CAS, and persisted-refund rejection are internally consistent with Contract R002. Python R003’s replay reads a fresh ledger snapshot; a refunded transaction suppresses historical delivery, while operation collisions and insufficient/refunded cases are rejected. Both paths keep the result explicitly non-authorizing and do not mutate the game save or grant a production entitlement.

Limits remain material: Python R003 and Swift R002 are unexecuted source candidates; the cross-language fixture is still `NOT_YET_EXPORTED` in the reviewed Python manifest. Swift persistence is expressed as protocols and its restart/CAS tests use a test actor, not a durable production store. The local provider/transport and synthetic signing fixture do not establish Apple authentication, network/TLS trust, revocation, StoreKit production entitlement, or product adoption. Keep those as separate gates.
