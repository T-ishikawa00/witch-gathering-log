import XCTest
import StoreKit
import StoreKitTest

/// Runs only against the bundled LOCAL_QA_ONLY StoreKit configuration.
/// Keep this class serial: Apple's SKTestSession instances share one test environment.
final class StoreKitLocalQATests: XCTestCase {
    private func makeSession() throws -> SKTestSession {
        let config = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("WitchLocalTest.storekit")
        let session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.storefront = "JPN"
        session.clearTransactions()
        return session
    }

    func testLocalNonConsumablePurchaseAndRefund() async throws {
        let session = try makeSession()
        let transaction = try await session.buyProduct(identifier: "local.witch.test.furniture")
        XCTAssertEqual(transaction.productID, "local.witch.test.furniture")
        XCTAssertEqual(transaction.environment, .xcode)
        let before = session.allTransactions()
        XCTAssertTrue(before.contains { $0.identifier == UInt(transaction.id) && $0.state == .purchased })
        try session.refundTransaction(identifier: UInt(transaction.id))
        let after = session.allTransactions()
        XCTAssertTrue(after.contains { $0.identifier == UInt(transaction.id) && $0.cancelDate != nil })
    }

    func testConsumablePurchaseAndAskToBuyPending() async throws {
        let session = try makeSession()
        let transaction = try await session.buyProduct(identifier: "local.witch.test.ticket")
        XCTAssertEqual(transaction.productID, "local.witch.test.ticket")
        XCTAssertEqual(transaction.environment, .xcode)

        session.askToBuyEnabled = true
        let pending = try await session.buyProduct(identifier: "local.witch.test.ticket")
        XCTAssertEqual(pending.productID, "local.witch.test.ticket")
        XCTAssertTrue(session.allTransactions().contains { $0.pendingAskToBuyConfirmation })
    }
}
