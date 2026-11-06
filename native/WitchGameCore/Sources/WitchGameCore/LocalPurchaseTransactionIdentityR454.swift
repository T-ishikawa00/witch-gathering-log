import Foundation

/// Transaction fields copied from the host's local-QA delivery envelope.
/// These values are compared with a locally verified StoreKit event; they are
/// not themselves proof of StoreKit verification or production entitlement.
public struct LocalPurchaseTransactionIdentityR454: Codable, Sendable, Equatable {
    public let environment: String
    public let bundleID: String
    public let transactionID: String
    public let originalTransactionID: String
    public let productID: String
    public let productKind: String
    public let quantity: Int
    public let appAccountTokenSHA256: String
    public let testAccountIDSHA256: String
    public let purchaseTime: Int64

    public init(
        environment: String,
        bundleID: String,
        transactionID: String,
        originalTransactionID: String,
        productID: String,
        productKind: String,
        quantity: Int,
        appAccountTokenSHA256: String,
        testAccountIDSHA256: String,
        purchaseTime: Int64
    ) {
        self.environment = environment
        self.bundleID = bundleID
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.productID = productID
        self.productKind = productKind
        self.quantity = quantity
        self.appAccountTokenSHA256 = appAccountTokenSHA256
        self.testAccountIDSHA256 = testAccountIDSHA256
        self.purchaseTime = purchaseTime
    }
}

/// Pure consistency check between an authority receipt and the actual verified
/// StoreKit transaction identity. It does not authenticate the host or mutate a save.
public enum LocalPurchaseReceiptIdentityR454 {
    private struct Envelope: Decodable {
        let schemaVersion: Int
        let status: String
        let profileFingerprint: String
        let operationID: UUID
        let transaction: LocalPurchaseTransactionIdentityR454
    }

    private static let transactionKeys: Set<String> = [
        "environment", "bundleID", "transactionID", "originalTransactionID",
        "productID", "productKind", "quantity", "appAccountTokenSHA256",
        "testAccountIDSHA256", "purchaseTime"
    ]

    public static func validate(
        _ receipt: Data,
        expectedTransaction: LocalPurchaseTransactionIdentityR454,
        operationID: UUID,
        profileFingerprint: String
    ) throws {
        guard receipt.count <= 1_048_576,
              let root = try JSONSerialization.jsonObject(with: receipt) as? [String: Any],
              let transaction = root["transaction"] as? [String: Any],
              Set(transaction.keys) == transactionKeys else {
            throw CoreError.invalidCommand("R454 receipt transaction shape is invalid")
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: receipt)
        } catch {
            throw CoreError.invalidCommand("R454 receipt identity envelope is invalid")
        }
        guard envelope.schemaVersion == 1,
              envelope.status == "LOCAL_TEST_ONLY_GEAR_DELIVERY",
              envelope.transaction == expectedTransaction,
              envelope.operationID == operationID,
              envelope.profileFingerprint == profileFingerprint else {
            throw CoreError.invalidCommand("R454 receipt does not match the verified StoreKit transaction")
        }
    }
}
