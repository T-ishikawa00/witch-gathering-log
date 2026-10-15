# R459 R004 independent source review

Reviewed frozen manifest SHA-256 `3f3fcfbe12b8278375680d2545fcf3e648c1304cf7a8e787bb410ddbae6eef1e` and the R004 repair diff SHA-256 `9b93b0b307985e7cffe693cdec73d6ebbb35fb072b74001ddd9996b22354619f`. All changed source/test file hashes match `MANIFEST_R004.json`. Read-only inspection only; no tests or runtime actions were performed.

## Result

I found no remaining source-level P1 in the reviewed admission, notification, or location-isolation paths that should block Root’s bounded candidate test run.

R004 closes the R003 generic-dictionary bypass at the deepest `_apply_notification_payload` entry: it accepts only an exact `MockNotificationDelivery` while the explicit mock gate is enabled, or an exact `SandboxVerifiedNotificationR459` carrying the capability bound to that authority. The method derives the environment from that typed record rather than accepting a caller-provided environment. The negative tests now cover both a `SimpleNamespace` and a raw dictionary at this deepest entry point. The same capability/type checks protect Sandbox purchases and refunds; the ordinary `ingest_apple_jws()` remains fail-closed.

R003’s directory fix is retained: `create()` resolves the existing parent before making the new, fixed-name leaf, so a symlink alias resolves to one canonical destination. The authority bind checks that the database and marker are in the expected leaf, rejects symlinked leaf/database/marker paths, verifies the exact marker contents, and permits binding only once. Tests cover a symlinked parent resolving to the canonical location and reject binding an unmarked arbitrary database. This is appropriate for the explicitly local rehearsal boundary; Python private names and same-process introspection are not a production security boundary.

The signed notification review from R002 remains intact: both JWS layers are verified as Sandbox, outer notification time and UUID are validated, transaction/revocation dates are ordered, and inbox receipt plus refund/purchase effects use one `BEGIN IMMEDIATE` transaction with collision, replay, rollback, and refund-tombstone handling. R004 changes to the audit module are absent, and its manifest confirms those bytes are unchanged.

## Limits

The candidate is still source-only and untested. Existing race tests exercise the shared SQLite/mock notification implementation, not concurrent signed-Sandbox deliveries end-to-end. Synthetic certificates and offline verification establish neither a real Apple transaction nor online revocation, account authentication, production entitlement, or release approval. Keep `grant_authorized=false`, `onlineRevocationChecked=false`, and production authorization absent in any result.
