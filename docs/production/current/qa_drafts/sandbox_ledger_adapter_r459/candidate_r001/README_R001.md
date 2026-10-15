# R459: Sandbox signature to isolated ledger rehearsal candidate

Status: source candidate only; NOT RUN, NOT PRODUCTION, and no live source was changed.

## Change

- `authority_r459.py` is a candidate overlay of the current reference authority. Existing `purchase_and_draw_mock` and `refund_mock` preserve their explicit Xcode-mock gates and delegate to shared internal transaction methods. Those internal methods retain the existing SQLite transaction, duplicate identity checks, idempotency receipts, refund tombstones/debt accounting, and rollback fault points.
- `signed_transaction_audit_r459.py` retains the pinned 3.1.2 Sandbox transaction verifier and adds a signed `REFUND` notification verifier that verifies both the notification JWS and nested transaction JWS, checks the bundle/environment/account token/product/quantity, and requires a revocation timestamp. It does not claim an online Apple revocation lookup.
- `sandbox_ledger_adapter_r459.py` is an explicit test adapter. It can create only a new directory named `r459-sandbox-rehearsal`, a fixture account binding and configured test product policy, then pass signature-verified Sandbox purchase/refund records to the same internal atomic ledger paths. All returned statuses say `NOT_AUTHORIZED_FOR_PRODUCTION`; no method connects to Apple, the app, or a network. Fixture account-token equality is not real user authentication.
- `test_sandbox_ledger_r459.py` adds three synthetic-crypto cases: signed Sandbox purchase and same-operation replay / duplicate transaction rejection; identity, product, environment, token, and signature rejection without ledger mutation; and signed refund notification rollback/retry/replay. Existing audit, authority, and notification regression suites are copied as compatibility tests and import the candidate overlay.

## Bounded regression command for Root review

Use only the installed pinned audit environment; do not install or update dependencies:

```sh
cd docs/production/current/qa_drafts/sandbox_ledger_adapter_r459/candidate_r001
PYTHONPATH="$PWD" ../../../../../../tools/witch_purchase_authority/.venv_signed_audit_r001/bin/python -m unittest -v test_sandbox_ledger_r459 test_authority_compat_r459 test_notifications_compat_r459
```

This command is a proposal, not run evidence. The independent auditor tests can be run separately with `test_sandbox_ledger_r459` only if Root wants the shortest first pass. No production authority or live DB path is configured by this candidate.

## Explicit limits

The synthetic certificate chain is locally generated and not Apple-issued. `grant_authorized` remains false and `revocation_checked` remains false in audit objects. This candidate can exercise the cryptographic verifier plus the existing database transaction path, not prove a real Apple Sandbox purchase or production entitlement. Product IDs, prices, territory, quantities, odds, account authentication, Apple trust configuration, key custody, online notification delivery, and deployed service policy remain unapproved or external configuration. `ingest_apple_jws()` remains fail-closed.
