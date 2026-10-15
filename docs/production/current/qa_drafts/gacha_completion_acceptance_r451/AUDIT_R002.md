# R451 addendum: existing local purchase-authority reference

**Read-only source review.** This corrects the scope of the initial audit: a local mock paid-ticket/draw ledger is present. The earlier statement that the app lacks a production-authoritative path remains accurate; it must not be read as saying no local server-side reference model exists.

`tools/witch_purchase_authority/authority.py` contains a separate SQLite reference authority. Its explicit mock path binds Xcode environment, bundle, product, quantity, transaction identity, and account token; atomically grants/debts/spends tickets, records ticket-lot provenance, draw rows and pity, and handles idempotency, duplicate callbacks, refunds, tombstones, and retry. `draw_mock()` can consume a previously purchased ticket lot under a separate idempotency key. `ingest_apple_jws()` deliberately rejects every transaction because an Apple verification adapter is not connected.

The package’s documented `QA_RESULT_R001.md` is **21/21 PASS, local test only**. The source also contains 16 notification test methods and a separate signed-transaction audit suite; this audit did not execute them. The signed audit uses synthetic in-memory certificates and explicitly fixes `grant_authorized=false` and `revocation_checked=false`; it neither connects to the authority nor proves a real Apple Sandbox transaction.

The local reference authority is not connected to the app. `App.summon` dispatches directly to Swift `.mockSummon`. `GameStoreKitQASink` only records isolated Xcode QA furniture/ticket records; it stores ticket units under `storekit_qa_ticket`, and `GameStoreKitQAPanel` explicitly says those tickets cannot be used for summons. Thus the substantive locally executable gap is **cross-boundary integration and parity**, not a missing SQLite model. A bounded next local task, if useful, is a test-only adapter contract using the existing Xcode mock event and temporary SQLite authority to verify the grant→draw→receipt path and compare the Swift and Python candidate policy fingerprints/results. Keep it isolated, do not add a network endpoint, and do not call it production integration.

The production gaps remain external: authenticated player identity, genuine Apple signed-transaction/notification verification and revocation, production product policy, server CSPRNG, durable distributed storage/operations, and legal/platform approval. The current local reference is expressly mock-only, not a substitute for those services.

## Source pins

- `authority.py` `ba1ce9e581de66f4f28b7fc0de903700f5505e19832c8fdc4901c656ebc0b02c`
- `README.md` `d982fe281e68442d94e93b33f1b9ef37d04a3692a2b0e8511fdd0020dd4f3b42`
- `QA_RESULT_R001.md` `6d9aed0eaa8e52d20b204545957caf327a7a8a2d32ed4cb3173589a77561ae51`
- `SIGNED_TRANSACTION_AUDIT.md` `74a05950a96def1d453957d8eb6979f1c37aeac41fa2d3b26d4c533b4be6e935`
- `test_authority.py` `94ecca7044d8d89eba87d0531a4b0e4a363f2c19c3be0fe264ce5eb7432bb081`
- `test_notifications.py` `5dfc9df8cf66d27d2184392e89dc869c91fc1583afbbfb08f2a7319665fb8c41`
- `signed_transaction_audit.py` `dd69d282986d222473d38780c5430614231de3a7e2b53d740c98dd4e310a4351`
- `test_signed_transaction_audit.py` `7db17e3f5bb0857eb141bf8bb8754554bb7dc1b87d759b7620e08a7ea74d8634`
- `GameStoreKitQASink.swift` `7da7f638c8ac80803e10cce2069c9590f94f19539a3d03ab17f626f18630652f`
- `GameStoreKitQA.swift` `e368e306df24a4045e7a0d7036e337de209cec40b4ad84e46d01f09ed97f070a`
