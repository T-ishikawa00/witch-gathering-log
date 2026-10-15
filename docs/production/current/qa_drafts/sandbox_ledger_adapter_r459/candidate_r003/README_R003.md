# R459 Sandbox ledger candidate R003

R003 is an additive correction to frozen candidate R002. It canonicalizes the existing database parent before creating the one-use `r459-sandbox-rehearsal` child, preventing `/var` and `/private/var` aliases from creating distinct logical roots. The authority binds a Sandbox capability only after verifying its database is the marked rehearsal database, rather than any arbitrary SQLite path.

The copied test suite is corrected to patch the actual candidate module name and to expect the explicit `NOT_AUTHORIZED_FOR_PRODUCTION` receipt status. Test setup resolves temporary roots consistently with the factory, and adds coverage for symlink-parent canonicalization and rejection of capability binding to an unmarked database. A source scan confirmed the signed refund test constructs and passes its `notification_jws`; no undefined refund token was found.

R002 was briefly edited during this correction, then restored from R001 plus its sealed `SOURCE_PATCH_R002.diff`. Every restored source/test file matched the SHA recorded by `MANIFEST_R002.json`; see `RESTORE_NOTE_R003.md`. R002 manifest, README, patch, and prior candidate remain preserved.

Validation is static AST parsing and manifest JSON parsing only. No unit tests, build, external requests, account use, or live changes were performed. All receipts remain `NOT_AUTHORIZED_FOR_PRODUCTION`; Apple JWS ingest remains fail-closed and no online revocation lookup is claimed.
