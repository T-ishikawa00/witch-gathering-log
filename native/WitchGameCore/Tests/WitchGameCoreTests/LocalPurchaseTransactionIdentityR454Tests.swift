import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

/// Pure receipt-identity tests using the exact R453 host fixture. This helper
/// does not call StoreKit or SaveRepository and grants no entitlement.
final class LocalPurchaseTransactionIdentityR454Tests: XCTestCase {
    private struct Fixture {
        let data: Data
        let root: [String: Any]
        let transaction: LocalPurchaseTransactionIdentityR454
        let operationID: UUID
        let profileFingerprint: String
    }

    private var fixture: Fixture!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["WITCH_R453_DELIVERY_FIXTURE"],
              let expectedSHA = ProcessInfo.processInfo.environment["WITCH_R453_DELIVERY_FIXTURE_SHA256"] else {
            throw XCTSkip("Requires the independently SHA-pinned R453 host fixture")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(Self.sha256(data), expectedSHA)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tx = try XCTUnwrap(root["transaction"] as? [String: Any])
        let transaction = try JSONDecoder().decode(LocalPurchaseTransactionIdentityR454.self,
            from: JSONSerialization.data(withJSONObject: tx, options: [.sortedKeys]))
        fixture = Fixture(
            data: data,
            root: root,
            transaction: transaction,
            operationID: try XCTUnwrap(UUID(uuidString: root["operationID"] as? String ?? "")),
            profileFingerprint: try XCTUnwrap(root["profileFingerprint"] as? String)
        )
    }

    func testExactPinnedReceiptIdentityAcceptsAndEveryBoundFieldMismatchRejects() throws {
        try LocalPurchaseReceiptIdentityR454.validate(
            fixture.data,
            expectedTransaction: fixture.transaction,
            operationID: fixture.operationID,
            profileFingerprint: fixture.profileFingerprint
        )

        let changes: [(String, Any)] = [
            ("environment", "Sandbox"),
            ("bundleID", "other.bundle"),
            ("transactionID", "different-transaction"),
            ("originalTransactionID", "different-original"),
            ("productID", "other.product"),
            ("productKind", "nonConsumable"),
            ("quantity", fixture.transaction.quantity + 1),
            ("appAccountTokenSHA256", String(repeating: "0", count: 64)),
            ("testAccountIDSHA256", String(repeating: "1", count: 64)),
            ("purchaseTime", fixture.transaction.purchaseTime + 1)
        ]
        for (key, value) in changes {
            var root = fixture.root
            var tx = try XCTUnwrap(root["transaction"] as? [String: Any])
            tx[key] = value
            root["transaction"] = tx
            let altered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            XCTAssertThrowsError(try LocalPurchaseReceiptIdentityR454.validate(
                altered,
                expectedTransaction: fixture.transaction,
                operationID: fixture.operationID,
                profileFingerprint: fixture.profileFingerprint
            ), "must reject mismatch in \(key)")
        }

        let otherOperation = UUID()
        XCTAssertThrowsError(try LocalPurchaseReceiptIdentityR454.validate(
            fixture.data, expectedTransaction: fixture.transaction,
            operationID: otherOperation, profileFingerprint: fixture.profileFingerprint))
        XCTAssertThrowsError(try LocalPurchaseReceiptIdentityR454.validate(
            fixture.data, expectedTransaction: fixture.transaction,
            operationID: fixture.operationID, profileFingerprint: "different-profile"))

        var missingRoot = fixture.root
        var missingTransaction = try XCTUnwrap(missingRoot["transaction"] as? [String: Any])
        missingTransaction.removeValue(forKey: "originalTransactionID")
        missingRoot["transaction"] = missingTransaction
        let missingField = try JSONSerialization.data(withJSONObject: missingRoot, options: [.sortedKeys])
        XCTAssertThrowsError(try LocalPurchaseReceiptIdentityR454.validate(
            missingField, expectedTransaction: fixture.transaction,
            operationID: fixture.operationID, profileFingerprint: fixture.profileFingerprint))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
