# R461 Swift client contract candidate

Status: candidate validation only; no StoreKit production authority, game-save mutation, default transport, account authentication, server endpoint, TLS, or release integration is supplied.

The Swift files implement the frozen R461 JSON request/response contract and validate a candidate delivery against the locally observed StoreKit tuple plus the opaque account-binding correlation. The client records no `GameSnapshot` changes. Its result is explicitly `candidateDeliveryRecorded` and remains labeled `NOT_AUTHORIZED_FOR_PRODUCTION`.

`PurchaseAuthorityTransportR461`, `PendingPurchaseOperationStoreR461`, and `AuthorityObservationStoreR461` are injected interfaces. An eventual adapter must persist the exact pending operation before exchange and implement per-account revision compare-and-save atomically. This candidate's XCTest actor store checks protocol behavior and simulated Codable restart only; it is not durable-storage or power-loss proof.

The opt-in cross-language XCTest must be enabled by the bounded Root runner with:

- `WITCH_R461_CROSS_LANGUAGE_FIXTURE_REQUIRED=1`
- `WITCH_R461_EXCHANGE_FIXTURE_PATH=<Root-pinned wrapper path>`
- `WITCH_R461_EXCHANGE_FIXTURE_SHA256=<exact wrapper SHA-256>`

It checks exact fixture/request/response bytes and invokes `PurchaseAuthorityClientR461.submit` for synthetic delivery, same-operation replay, post-refund state persistence/rejection, then rejects the old delivery as stale. The fixture is not an Apple-authorized purchase and contains no exported signing key.

No Swift compile, XCTest, app build, Simulator, network request, or live source edit was performed while preparing this candidate. Root review and a separately bounded runner are required before execution.
