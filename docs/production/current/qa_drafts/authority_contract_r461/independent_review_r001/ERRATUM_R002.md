# Addendum R002 — bounded Python execution readback

This addendum preserves `REVIEW_R001` and updates only the Python execution/fixture status.

The Python R003 service source remained byte-identical at SHA-256 `564b0b2d4fb4c079345c36ced790507c1d722e1b1436dec7ba9e6ba967fb84fe`. The initial broad run retained its 119-pass/1-error outcome: the synthetic refund test stub omitted the `notice.status` field required by the existing R459 refund path. The repair changed only the test fixture (`root_candidate_r004` test SHA `d1c4db90f54bf27fb19ce3f1268de359d3efaee96f0c3256f1bc14b291b2bb50`); the focused rerun recorded 10 methods, 10 passed, zero errors/skips/warnings, exit 0. The original failure remains preserved and is not converted to a pass.

The same bounded run exported a cross-language fixture using the real offline cryptographic verifier and synthetic certificate, then exercised the R459 rehearsal ledger through delivery, byte-identical replay, and refund. The result reports two draws, tickets spent 2, refund clawback 2, debt 2, zero network calls, no persisted private key, and `productionEntitlementAuthorized=false`. Fixture SHA-256 is `0e68e855f2458ce679a6b8ec7e7018ffb84fbddd4244f461215235659380059d`. This is not an Apple-signed transaction, online revocation check, Swift cross-language test, production entitlement, or StoreKit adoption.

At readback time the Swift R002 candidate remained unexecuted. Therefore the exported fixture exists, but Swift consumption of that exact fixture and full combined acceptance remain unverified.
