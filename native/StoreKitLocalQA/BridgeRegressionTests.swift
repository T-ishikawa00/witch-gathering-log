import Foundation

@main
enum BridgeRegressionTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreKitLocalQABridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("receipts.json")
        let store = ProbeReceiptStore(fileURL: file)

        let purchase = event(kind: .purchase, transactionID: 42, productID: "furniture", productKind: .nonConsumable)
        try await store.apply(purchase)
        let first = await store.currentSnapshot()
        precondition(first.receipts.count == 1 && first.ownedProductIDs == ["furniture"])
        let disk1 = try JSONDecoder().decode(ProbeReceiptStore.Snapshot.self, from: Data(contentsOf: file))
        precondition(disk1.receipts[purchase.idempotencyKey] != nil, "callback success must follow durable readback")

        try await store.apply(purchase)
        let duplicate = await store.currentSnapshot()
        precondition(duplicate.receipts.count == 1, "redelivery must be idempotent")
        precondition(duplicate.persistedTransactionIDs == [42], "durable transaction marker must remain singular")
        let restartedStore = ProbeReceiptStore(fileURL: file)
        let afterRestart = await restartedStore.currentSnapshot()
        precondition(afterRestart.receipts.count == 1 && afterRestart.ownedProductIDs == ["furniture"],
                     "ownership and idempotency must survive a store reload")

        let failedFile = directory.appendingPathComponent("failed.json")
        let failing = ProbeReceiptStore(fileURL: failedFile, failWrites: true)
        var observedFailure: Error?
        do {
            try await failing.apply(event(kind: .purchase, transactionID: 43, productID: "ticket", productKind: .consumable))
            preconditionFailure("injected durable write failure must throw")
        } catch { observedFailure = error }
        precondition((observedFailure as? CocoaError)?.code == .fileWriteOutOfSpace,
                     "write failure must propagate to prevent transaction finish")
        precondition(!FileManager.default.fileExists(atPath: failedFile.path), "failed persistence must not leave finishable receipt")
        let failedSnapshot = await failing.currentSnapshot()
        precondition(failedSnapshot.receipts.isEmpty && failedSnapshot.persistedTransactionIDs.isEmpty)

        let revoke = event(kind: .revocation, transactionID: 42, productID: "furniture", productKind: .nonConsumable,
                           revocationDate: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.apply(revoke)
        let afterRevoke = await store.currentSnapshot()
        precondition(!afterRevoke.ownedProductIDs.contains("furniture"), "revocation must remove local QA ownership")
        precondition(afterRevoke.receipts.count == 2, "revocation uses an independent idempotency key")
        let ticket = event(kind: .purchase, transactionID: 44, productID: "ticket", productKind: .consumable)
        try await store.apply(ticket)
        let afterTicket = await store.currentSnapshot()
        precondition(!afterTicket.ownedProductIDs.contains("ticket"), "consumables are recorded but never become durable ownership")
        try await store.apply(revoke)
        let afterDuplicateRevoke = await store.currentSnapshot()
        precondition(afterDuplicateRevoke.receipts.count == 3, "duplicate revocation must not add another receipt")
        print("PASS: durable callback/readback, restart and duplicate idempotency, failure propagation, revocation, consumable ownership exclusion")
    }

    static func event(
        kind: StoreKitLocalQAEventKind,
        transactionID: UInt64,
        productID: String,
        productKind: StoreKitLocalQAProductKind,
        revocationDate: Date? = nil
    ) -> StoreKitLocalQAEvent {
        StoreKitLocalQAEvent(
            kind: kind, transactionID: transactionID, productID: productID,
            productKind: productKind, environment: "Xcode",
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000), revocationDate: revocationDate
        )
    }
}
