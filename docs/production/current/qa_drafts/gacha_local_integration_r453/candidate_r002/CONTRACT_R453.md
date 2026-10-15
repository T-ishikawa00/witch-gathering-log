# R453 local receipt-delivery candidate

Status: `UNAPPROVED_TEST_OVERLAY`. This is a host-side fixture exporter over the existing Python `PurchaseAuthority`. It does not verify Apple signatures, start a server, wire StoreKit into the game, authorize production entitlement, choose formal prices/rates, or establish release readiness.

The event envelope is deliberately stricter than the current `StoreKitLocalQAEvent`: in addition to the Xcode environment, bundle, product, transaction ID, and event key, this local test envelope requires original transaction ID, quantity, app-account token, purchase timestamp, and an explicit test account ID. Those fields are needed to test the authority boundary; the current Swift event does not carry all of them, so this candidate does not claim a StoreKit-to-authority integration.

The ticket-grant operation commits through `purchase_and_draw_mock` with zero draws. A later draw is a separate `draw_mock` operation, constrained to the referenced, currently verified FIFO ticket lot. The adapter verifies the saved draw rows and current transaction status before exporting gear. Refund or refund tombstone state blocks a new export and replay. Previously exported local gear is not automatically removed by the authority refund path; the revocation fixture says so explicitly and requires a later save reconciliation design.

The JSON fixture’s `gearInstances` array uses the current Core `GearInstance` field names directly: `id`, `definitionID`, `ownerID`, `protected`, `enhancement`, `refinement`, `latentEffectID`, `candidateLatentSlots`, `qualityID`, `affixIDs`, and `investmentDust`. Per-item provenance is kept in a separate `gearProvenance` array joined by `gearID`. `postPityState` uses the current four `GachaPityState` keys. Ticket currency remains in the authority ledger and is not folded into Core game currency. The operation UUID and profile fingerprint bind the payload; item UUIDs are UUIDv5 values derived from the fixed R453 namespace, profile fingerprint, test account, transaction, operation UUID, and draw ordinal.

Quality-to-affix/latent mapping is supplied by an explicitly pinned candidate profile. Affix and latent IDs must end in `_TEST`, affix count is capped at four, and caller-supplied gear payload fields are rejected. This mapping is a test fixture, not an adopted rate or item policy. The authority continues to provide its existing seeded candidate draw; this adapter adds deterministic serialization and item identity, not a new or production RNG.

The adapter stores its delivery receipt in a separate local sidecar SQLite file so a crash after the authority commit can retry the same authority idempotency key and reconstruct the same item UUIDs. The two databases are not one transaction. The later Swift importer must use `SaveRepository.transact` with the receipt’s stable `operationID` and fingerprint so repeated import cannot add the same UUID twice. No change to SaveRepository, Core, App, `authority.py`, StoreKit, or `ingest_apple_jws()` is part of this candidate.

The test module covers ticket-only grant then a separate draw, exact replay, same-operation and profile-payload collision, current refund and pre-purchase tombstone suppression, stable distinct item UUIDs, strict identity rejection, and the still-fail-closed Apple JWS entrypoint. Tests and CLI were not run by this candidate author. A Python syntax compile check was inadvertently run once during authoring; no test database was opened and no test ran.

The CLI requires `--allow-test-mock-verifier`, a profile JSON and exact file-byte SHA-256, a mock event JSON, an already existing isolated authority test database, a separate delivery-cache database path, and a new output JSON path. It has no network/listener mode and refuses to overwrite output. Passing an Apple-looking marker does not create Apple verification.

## Remaining integration gates

- The Swift importer must decode the exact `GearInstance`/pity keys, verify fixture and receipt hashes, confirm current transaction state, and apply gear plus stable operation receipt in one `SaveRepository.transact` call.
- StoreKit's current event schema does not provide all required authority identity fields; a reviewed local-only test envelope or a later authenticated backend contract is still needed.
- Revoking after a successful Swift import does not retract already imported gear. Reconciliation behavior is intentionally not invented here.
- `PurchaseAuthority.ingest_apple_jws()` remains unavailable and fail-closed. No Sandbox, device, production entitlement, external credential, or paid transaction was used or verified.
