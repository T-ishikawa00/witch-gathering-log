# R459 live integration and regression independent review

Reviewed `live_integration_r001/INTEGRATION_RECEIPT_R001.json`, the retained initial failure `live_regression_r001/RUN.json` and log, the repaired run `live_regression_r002/RUN.json` and log, and R005 candidate result `root_execution_r002/RUN.json`. No rerun or source edit was made.

## Integration identity

The integration receipt is based on checkpoint `ea476c98c3281420b11b5596714126ee8a352909`. Its recorded transformations for the R459 authority/auditor were import-name normalization only; R005 candidate behavior is represented by the recorded source hashes. The live test/adapter hashes in the final run are:

- `authority.py`: `fa181cfb5a9da78ae919dff6d4b6fd1a69abcbd717f3412fcd40a95675bac1ec`
- `signed_transaction_audit.py`: `d49f59e0db971fc517052729e875b1cd73f288398fbc0ea4ba513eb1402a1a0f`
- `sandbox_ledger_adapter_r459.py`: `b4ec379f82d2f1c4cf7da6848e5e68de793cc9db65ec5ff88a3e5947704a4edd`
- `tests/test_sandbox_ledger_r459.py`: `5489b277227077f73fb44d7195cdd975be88d5e8db72d3470475d59aa565577c`

The final source keeps `ingest_apple_jws()` fail-closed. The verifier is configured for Sandbox with online checks disabled; no network or production entitlement path was added. The adapter creates its own marked rehearsal database. `nativeChanged` is false in the receipts.

## Execution accounting

R005’s isolated candidate run reports 68 passed, 0 failed, 0 skipped, 0 warnings in 0.636 seconds (`RUN.json` manifest SHA matches R005). The first live full-suite attempt is retained as a failure: 91 counted tests, two import errors for R453/R454 modules because the repository root was absent from `PYTHONPATH`, and 56 pre-existing SQLite `ResourceWarning`s. The additive harness repair supplied `PYTHONPATH`, explicitly closed nine test connections without changing their transaction assertions, and enabled package/direct adapter imports.

The repaired full suite reports 110 test methods passed, 0 failed, 0 skipped, 0 warnings in 0.837 seconds; the log ends with `Ran 110 tests ... OK`. Do not describe these as 110 unique requirements: 21 crypto-audit cases are intentionally duplicated between the legacy and R459 test modules. The first failure and repair remain visible rather than being rewritten as a pass.

## Limits and remaining integration boundary

The source and tests exercise a local synthetic-certificate Sandbox audit and SQLite rehearsal. They do not prove a real Apple-issued transaction, Apple account authentication, online revocation lookup, production grant authorization, or deployed StoreKit service behavior. R453/R454 test suites pass in this run, but their inputs were omitted from the earlier native build map; Root has separately noted they will be included in checkpoint R086. No new functional defect was identified in the reviewed integration/result evidence.
