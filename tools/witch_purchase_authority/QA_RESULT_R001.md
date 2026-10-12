# Purchase Authority Reference QA R001

State: **21/21 PASS, LOCAL TEST ONLY**. Executed 2026-10-10 using Python 3.9.6 and stdlib SQLite/unittest from `tools/witch_purchase_authority/`.

Command: `python3 -m unittest discover -s tests -v`

Coverage: Apple JWS fail-closed; explicit mock-only verifier gate; exact product/quantity, environment, bundle, and appAccountToken binding; account isolation; request-fingerprint idempotency collision; transaction identity one-use; same-operation concurrency and two-terminal race; six injected purchase/draw commit failures with full rollback and retry; draw-from-balance failure rollback; ticket-only purchase followed by independent operation-UUID draw; actual source ticket-lot attribution; persisted per-draw pity and result history; refund-before-purchase tombstone blocks delayed delivery; tombstone fault rollback permits valid retry; purchase idempotent retry after refund rejects stale success; refund clawback, spent-ticket debt, later debt repayment, duplicate refund and no regrant; refund fault rollback; bool/float/out-of-range guards; old database schema fails closed; deterministic candidate pity boundary tests.

Command: `python3 -m py_compile authority.py __init__.py tests/test_authority.py` completed without diagnostics. All databases were created in temporary directories and removed after each test. No app save, StoreKit transaction, server, network, account, secret, or payment was accessed.

This is SQLite single-node behavior in one local process/file; it does not establish production concurrency, durability/restore, Apple signature validity, CSPRNG quality, legal compliance, or live paid-draw readiness.
