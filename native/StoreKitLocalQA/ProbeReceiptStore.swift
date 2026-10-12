import Foundation

/// Local probe-only durable receipt file. This is deliberately separate from
/// WitchGameCore save data and is never used for production entitlements.
@available(iOS 17.0, *)
actor ProbeReceiptStore: StoreKitLocalQADurableSink {
    struct Receipt: Codable, Equatable {
        let idempotencyKey: String
        let kind: String
        let transactionID: UInt64
        let productID: String
        let productKind: String
        let environment: String
        let purchaseDate: Date
        let revocationDate: Date?
        let persistedAt: Date
    }

    struct Snapshot: Codable {
        var receipts: [String: Receipt] = [:]
        var ownedProductIDs: Set<String> = []
        /// Transactions whose local durable callback has completed. StoreKit
        /// finish() is performed by the bridge after apply() returns.
        var persistedTransactionIDs: Set<UInt64> = []
    }

    private let url: URL
    private var failWrites: Bool
    private var snapshot: Snapshot

    init(fileURL: URL? = nil, failWrites: Bool = false) {
        self.failWrites = failWrites
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoreKitLocalQA", isDirectory: true)
        let resolvedURL = fileURL ?? directory.appendingPathComponent("probe-receipts.json")
        self.url = resolvedURL
        if let data = try? Data(contentsOf: resolvedURL),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    func apply(_ event: StoreKitLocalQAEvent) async throws {
        var next = snapshot
        if next.receipts[event.idempotencyKey] != nil {
            // Idempotent redelivery is successful only after the prior record
            // is already durable; it may then safely be finished.
            return
        }
        let receipt = Receipt(
            idempotencyKey: event.idempotencyKey,
            kind: event.kind.rawValue,
            transactionID: event.transactionID,
            productID: event.productID,
            productKind: event.productKind.rawValue,
            environment: event.environment,
            purchaseDate: event.purchaseDate,
            revocationDate: event.revocationDate,
            persistedAt: Date()
        )
        next.receipts[event.idempotencyKey] = receipt
        if event.kind == .revocation || event.revocationDate != nil {
            next.ownedProductIDs.remove(event.productID)
        } else if event.productKind != .consumable && event.productKind != .unknown {
            next.ownedProductIDs.insert(event.productID)
        }
        next.persistedTransactionIDs.insert(event.transactionID)

        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: .atomic)
        // Read back the exact atomic file before reporting callback success.
        let persisted = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard persisted.receipts[event.idempotencyKey] == receipt else {
            throw CocoaError(.fileReadCorruptFile)
        }
        snapshot = persisted
    }

    func setFailWrites(_ value: Bool) { failWrites = value }
    func currentSnapshot() -> Snapshot { snapshot }
    func storageURL() -> URL { url }
}
