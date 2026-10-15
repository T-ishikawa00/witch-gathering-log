import Foundation
import CryptoKit

/// Local file exchange used only by the dedicated DEBUG Simulator purchase QA.
/// It deliberately has no network client and confers no production entitlement.
struct LocalAuthorityQAContextR454: Sendable {
    let token: UUID
    let profileFingerprint: String
    let accountID = "r454-local-account"
    let directory: URL

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func operationID(bundleID: String, transactionID: UInt64) -> UUID {
        let b = Array(SHA256.hash(data: Data("r454-draw:\(bundleID):\(transactionID)".utf8)).prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    func currentDelivery(bridge: StoreKitLocalQABridge, transactionID: UInt64, operationID: UUID) async throws -> Data {
        let event = try await bridge.currentVerifiedXcodeTransaction(transactionID: transactionID, expectedAppAccountToken: token)
        guard event.productID == "local.witch.test.ticket", event.productKind == .consumable,
              let originalID = event.originalTransactionID, let quantity = event.quantity, (1...100).contains(quantity),
              let bundle = event.transactionBundleID, bundle == Bundle.main.bundleIdentifier,
              event.appAccountToken == token, event.environment == "Xcode" else {
            throw CoreError.invalidCommand("R454 local transaction identity is incomplete")
        }
        let requests = directory.appendingPathComponent("requests", isDirectory: true)
        let responses = directory.appendingPathComponent("responses", isDirectory: true)
        for path in [directory, requests, responses] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            guard !(try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false) else {
                throw CoreError.invalidCommand("R454 exchange path cannot be a symlink")
            }
        }
        guard try FileManager.default.contentsOfDirectory(atPath: requests.path).count < 24 else {
            throw CoreError.invalidCommand("R454 bounded QA exchange request limit reached")
        }
        let requestID = UUID().uuidString.lowercased()
        let request: [String: Any] = [
            "schemaVersion": 1, "status": "XCODE_LOCAL_QA_REQUEST", "requestID": requestID,
            "operationID": operationID.uuidString.lowercased(), "profileFingerprint": profileFingerprint,
            "count": 1, "testSeed": 453,
            "event": ["schemaVersion": 1, "eventKind": "purchase", "verification": "EXPLICIT_TEST_MOCK",
                      "environment": "Xcode", "bundleID": bundle, "transactionID": String(event.transactionID),
                      "originalTransactionID": String(originalID), "productID": event.productID,
                      "productKind": "consumable", "quantity": quantity, "appAccountToken": token.uuidString.lowercased(),
                      "purchaseTime": Int64(event.purchaseDate.timeIntervalSince1970),
                      "idempotencyKey": event.idempotencyKey, "testAccountID": accountID]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys, .withoutEscapingSlashes])
        let requestURL = requests.appendingPathComponent(requestID + ".json")
        let responseURL = responses.appendingPathComponent(requestID + ".json")
        try bytes.write(to: requestURL, options: .withoutOverwriting)
        let start = ContinuousClock.now
        while start.duration(to: .now) < .seconds(60) {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: responseURL.path) {
                let attributes = try responseURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= 1_048_576 else {
                    throw CoreError.invalidCommand("R454 response path or size rejected")
                }
                let responseBytes = try Data(contentsOf: responseURL)
                guard let response = try JSONSerialization.jsonObject(with: responseBytes) as? [String: Any],
                      response["schemaVersion"] as? Int == 1,
                      response["requestID"] as? String == requestID,
                      response["operationID"] as? String == operationID.uuidString.lowercased(),
                      response["requestSHA256"] as? String == Self.hash(bytes) else {
                    throw CoreError.invalidCommand("R454 response does not match the fresh request")
                }
                guard response["status"] as? String == "DELIVERY",
                      let encoded = response["receiptBase64"] as? String, let receipt = Data(base64Encoded: encoded),
                      response["receiptSHA256"] as? String == Self.hash(receipt) else {
                    throw CoreError.invalidCommand("R454 current host authority rejected the local delivery")
                }
                let expected = LocalPurchaseTransactionIdentityR454(environment: "Xcode", bundleID: bundle,
                    transactionID: String(event.transactionID), originalTransactionID: String(originalID),
                    productID: event.productID, productKind: "consumable", quantity: quantity,
                    appAccountTokenSHA256: Self.hash(Data(token.uuidString.lowercased().utf8)),
                    testAccountIDSHA256: Self.hash(Data(accountID.utf8)),
                    purchaseTime: Int64(event.purchaseDate.timeIntervalSince1970))
                try LocalPurchaseReceiptIdentityR454.validate(receipt, expectedTransaction: expected,
                    operationID: operationID, profileFingerprint: profileFingerprint)
                _ = try await bridge.currentVerifiedXcodeTransaction(matching: event)
                return receipt
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw CoreError.invalidCommand("R454 host response timed out; retry keeps the same operation ID")
    }
}

extension GameModel {
    var localAuthorityQAContextR454: LocalAuthorityQAContextR454? {
        #if DEBUG && targetEnvironment(simulator)
        // Finished consumables are available to Transaction.all only with this
        // explicit iOS 18+ history opt-in. Keep the local QA path closed otherwise.
        guard #available(iOS 18.0, *),
              Bundle.main.object(forInfoDictionaryKey: "SKIncludeConsumableInAppPurchaseHistory") as? Bool == true else { return nil }
        let args = ProcessInfo.processInfo.arguments
        func argument(_ key: String) -> String? {
            guard args.filter({ $0 == key }).count == 1, let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard localStoreKitQAEnabled, args.contains("--r454-local-authority-qa"),
              let rawToken = argument("--r454-test-token"), let token = UUID(uuidString: rawToken),
              let profile = argument("--r454-profile-fingerprint"), profile.count == 64,
              profile.allSatisfy({ "0123456789abcdef".contains($0) }),
              let saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else { return nil }
        return LocalAuthorityQAContextR454(token: token, profileFingerprint: profile,
            directory: saveURL.deletingLastPathComponent().appendingPathComponent("r454-authority-qa", isDirectory: true))
        #else
        return nil
        #endif
    }

    func qaReceiveAuthorityGearR454() {
        guard !busy, let context = localAuthorityQAContextR454, let bridge = qaPurchaseBridge,
              let engine, let catalog, let bundleID = Bundle.main.bundleIdentifier else { return }
        let records = state.localStoreKitQARecords.values.filter { $0.productID == "local.witch.test.ticket" && $0.kind == .purchase }
        guard let newest = records.max(by: { $0.recordedAt < $1.recordedAt }), let transactionID = UInt64(newest.transactionID) else {
            purchaseStatus = "先に検証券を購入してください"; return
        }
        busy = true; purchaseStatus = "ローカル台帳の応答を待っています"
        Task {
            defer { busy = false }
            do {
                let operationID = LocalAuthorityQAContextR454.operationID(bundleID: bundleID, transactionID: transactionID)
                let importer = try LocalPurchaseDeliveryQAImporterR453(explicitIsolatedTestMode: true, catalog: catalog,
                    bundleID: bundleID, profileFingerprint: context.profileFingerprint,
                    accountHash: LocalAuthorityQAContextR454.hash(Data(context.accountID.utf8)),
                    tokenHash: LocalAuthorityQAContextR454.hash(Data(context.token.uuidString.lowercased().utf8)))
                // First fresh response supplies a pinned immutable delivery. Every later
                // importer retry asks the host again; no saved JSON bypasses current checks.
                let first = try await context.currentDelivery(bridge: bridge, transactionID: transactionID, operationID: operationID)
                let provider = FirstCurrentDeliveryR454(first: first, context: context, bridge: bridge,
                                                      transactionID: transactionID, operationID: operationID)
                let receipt = try await importer.apply(expectedFileSHA256: LocalAuthorityQAContextR454.hash(first), saves: engine.saves) {
                    try await provider.current()
                }
                await refresh(); purchaseStatus = "検証装備を受取済み（保存 \(receipt.revision)）"
                writeReceipt("r454_delivery", "LOCAL_TEST_ONLY_DELIVERED", metadata: ["operationID": operationID.uuidString, "receiptFingerprint": receipt.requestFingerprint ?? "", "productionEntitlementAuthorized": false])
            } catch {
                purchaseStatus = "検証受取: \(String(describing: error))"
                writeReceipt("r454_delivery", "REJECTED_OR_RETRYABLE", metadata: ["error": String(describing: error)])
            }
        }
    }
}

private actor FirstCurrentDeliveryR454 {
    private var first: Data?
    let context: LocalAuthorityQAContextR454
    let bridge: StoreKitLocalQABridge
    let transactionID: UInt64
    let operationID: UUID
    init(first: Data, context: LocalAuthorityQAContextR454, bridge: StoreKitLocalQABridge, transactionID: UInt64, operationID: UUID) {
        self.first = first; self.context = context; self.bridge = bridge; self.transactionID = transactionID; self.operationID = operationID
    }
    func current() async throws -> Data {
        if let first { self.first = nil; return first }
        return try await context.currentDelivery(bridge: bridge, transactionID: transactionID, operationID: operationID)
    }
}
