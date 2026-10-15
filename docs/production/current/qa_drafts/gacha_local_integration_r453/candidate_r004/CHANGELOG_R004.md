# R453 R004 additive repair

R003 remains preserved in `snapshot_r003/`; no R003 file was edited.

R004 binds an optional `(environment, bundle, transaction)` tuple into `PurchaseAuthority.draw_mock` request fingerprints only for callers that supply it. Inside the existing `BEGIN IMMEDIATE`, the authority validates the current FIFO head and sufficient remaining tickets before generating draws or spending balance. Unbound callers keep the exact previous request object/fingerprint shape. No table or receipt schema changes were made.

The R453 adapter supplies the tuple and now validates `balance_draw` history using the exact `source_*` tuple while requiring the current schema's `purchase_*` fields to remain NULL. An interleaving regression creates two verified ticket lots, lets a concurrent draw consume part of the first lot after the adapter's optimistic check, then verifies the adapter fails atomically instead of consuming from the second lot. A second test verifies unbound legacy replay remains stable and changing the same operation to a bound request collides; malformed, non-Xcode, or wrong-bundle source identities are rejected. The CLI reads profile bytes once and uses that same buffer for SHA-256 validation and JSON parsing, closing the parse/hash time-of-check race.

Test source now has 15 methods. No tests, CLI, DB, Swift, or Simulator execution was performed in R004.
