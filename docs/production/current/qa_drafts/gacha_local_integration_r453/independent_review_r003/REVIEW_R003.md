# R453 R003 independent source review

Scope: read-only review of the exact pinned adapter, tests, and R003 manifest. No tests, CLI, database, Swift build, or production wiring were run. This is not production approval.

## Pins

- `tools/witch_purchase_authority/local_delivery_r453.py` — `a7dcca1b6fe12d137f3a8cdbfa1b23641ffeb69250114477d9b844117955860f`
- `tools/witch_purchase_authority/tests/test_local_delivery_r453.py` — `1ec97c15c0fdc5587f4febd4b534174abc87c5aba7d78ddc967006aff79005c9`
- `candidate_r003/MANIFEST_R453_R003.json` — `c8f5d677fdfbe87d0e8345d229c92c1c047c7bb0da50ba05d864f9080f77b8f1`

## Findings

**Blocking for concurrent authority use — draw source validation is post-commit, not atomic.** In `draw_from_ticket_balance` the adapter reads the account and FIFO lots at lines 403–414, then calls `PurchaseAuthority.draw_mock` at line 415. That authority method begins and commits its own transaction while selecting from the current FIFO lots (authority.py lines 491–495, 538–563). The adapter checks committed source rows only afterward (adapter lines 417–424). A concurrent refund or draw can change the FIFO between the precheck and `draw_mock`; the authority can therefore commit a draw from another verified lot, then the adapter raises on the post-commit identity check. The authority mutation is irreversible and no gear receipt is exported. The current FIFO mismatch test mutates the row before the adapter precheck, so it does not cover this interleaving. Bind the required purchase source within the same authority transaction, or serialize the precheck and draw under a transaction/lock that also protects refund and other draw operations.

**Medium integrity hardening — profile digest and parsed bytes are read separately.** `main` parses via `_read_json` at line 597, then obtains the claimed-byte digest with a second `read_bytes()` at lines 598–601. A concurrent replacement can make the supplied SHA validate bytes other than those parsed into the profile. Read the profile bytes once, validate their digest, then parse that same byte buffer. This is a local-fixture TOCTOU edge, not evidence of a production authority bypass.

## R003 corrections confirmed

- `_preflight_paths` runs before `PurchaseAuthority` construction; existing output, output/cache path equality, symlink components, hardlinked authority/cache paths, and cache/input aliases are rejected before authority initialization (adapter lines 555–580; tests 241–276).
- Cache separation uses `os.path.samefile` for existing paths, closing the prior hardlink alias gap (lines 548–552).
- The output is created with `O_EXCL`, so a competing creator cannot have its file overwritten (lines 609–612).
- The R003 test module has 13 test methods, including regressions for output collision and hardlinked cache. None were executed for this review.
- Replay/profile collision, sidecar-write reconstruction, refund tombstone suppression, original-transaction matching, FIFO tuple matching, and fail-closed Apple JWS behavior are covered in source and focused tests. This does not verify runtime behavior without test execution.

## Boundary

The adapter remains explicitly `EXPLICIT_TEST_MOCK` / `UNAPPROVED_TEST_OVERLAY`; no Apple verification, StoreKit-to-Core wiring, production entitlement, formal price/rate, or release claim is established. The noted race concerns the local authority ledger/export consistency if operations overlap.

## Addendum — deterministic successful-draw blocker

A direct cross-read of the pinned `authority.py` adds a deterministic P1 ahead of the concurrency race above. `PurchaseAuthority.draw_mock` intentionally records `operation_kind='balance_draw'` and writes `purchase_environment`, `purchase_bundle_id`, and `purchase_transaction_id` as `NULL` while preserving actual FIFO provenance in `source_environment/source_bundle_id/source_transaction_id` (`authority.py` lines 523–524). The R453 adapter then requires **both** tuples to equal the event tuple (`local_delivery_r453.py` lines 419–423). Thus every positive balance draw reaches the post-commit check, fails because the `purchase_*` tuple is null, and leaves ticket balance/pity/draw ledger committed without a gear export. The happy-path test expects a positive draw to succeed (`test_local_delivery_r453.py` lines 88–118), but it was not executed. The correct validation for this `balance_draw` operation is to bind/check the `source_*` tuple against the referenced FIFO lot and not require the deliberately-null `purchase_*` tuple; this must be checked before treating the path as usable. The concurrency concern remains after that correction unless source selection is protected atomically.
