import Foundation
import CryptoKit
import CoreFoundation

/// R461 wire request. No account, environment, SKU, quantity, or random seed is
/// accepted from the client; the signed transaction is the only purchase input.
public struct PurchaseAuthorityRequestR461: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let operationID: String
    public let action: String
    public let signedTransactionJWS: String

    public init(operationID: UUID, signedTransactionJWS: String) throws {
        guard !signedTransactionJWS.isEmpty,
              signedTransactionJWS.utf8.count <= 65_536,
              signedTransactionJWS.utf8.allSatisfy({ $0 < 0x80 }),
              Self.isCompactJWS(signedTransactionJWS),
              !signedTransactionJWS.contains("\n"), !signedTransactionJWS.contains("\r") else {
            throw CoreError.invalidCommand("R461 JWS must be 1..65536 single-line UTF-8 bytes")
        }
        schemaVersion = 1
        self.operationID = operationID.uuidString.lowercased()
        action = "purchaseAndDraw"
        self.signedTransactionJWS = signedTransactionJWS
    }

    public func canonicalData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 70_000 else { throw CoreError.invalidCommand("R461 request exceeds 70000 bytes") }
        return bytes
    }

    public func validate() throws {
        guard schemaVersion == 1,
              let uuid = UUID(uuidString: operationID), operationID == uuid.uuidString.lowercased(),
              action == "purchaseAndDraw", !signedTransactionJWS.isEmpty,
              signedTransactionJWS.utf8.count <= 65_536,
              signedTransactionJWS.utf8.allSatisfy({ $0 < 0x80 }),
              Self.isCompactJWS(signedTransactionJWS),
              !signedTransactionJWS.contains("\n"), !signedTransactionJWS.contains("\r") else {
            throw CoreError.invalidCommand("R461 request has unsupported fields or identity")
        }
    }

    private static func isCompactJWS(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, !segments[0].isEmpty, !segments[2].isEmpty else { return false }
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
        return segments.allSatisfy { segment in segment.utf8.allSatisfy { alphabet.contains($0) } }
    }
}

/// Persist this exact request across app restart and retry. Reusing an operation
/// UUID with a different JWS/request fingerprint is rejected by the caller.
public struct PendingPurchaseOperationR461: Codable, Sendable, Equatable {
    public let request: PurchaseAuthorityRequestR461
    public let requestSHA256: String

    public init(operationID: UUID, signedTransactionJWS: String) throws {
        let request = try PurchaseAuthorityRequestR461(operationID: operationID, signedTransactionJWS: signedTransactionJWS)
        self.request = request
        requestSHA256 = Self.sha256(try request.canonicalData())
    }

    public func validate() throws {
        let actual = Self.sha256(try request.canonicalData())
        guard actual == requestSHA256 else {
            throw CoreError.invalidCommand("R461 pending operation fingerprint mismatch")
        }
    }

    fileprivate static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Local StoreKit facts used only to compare server echoes; not sent as authority.
public struct LocalStoreKitPurchaseExpectationR461: Sendable, Equatable {
    public let environment: String
    public let bundleID: String
    public let transactionID: String
    public let originalTransactionID: String
    public let productID: String
    public let quantity: Int
    public let accountBindingSHA256: String
    public let accountIDSHA256: String

    public init(environment: String, bundleID: String, transactionID: String, originalTransactionID: String,
                productID: String, quantity: Int, accountBindingSHA256: String, accountIDSHA256: String) throws {
        guard !environment.isEmpty, !bundleID.isEmpty, !transactionID.isEmpty, !originalTransactionID.isEmpty,
              !productID.isEmpty, quantity > 0, Self.isLowerSHA256(accountBindingSHA256),
              Self.isLowerSHA256(accountIDSHA256) else {
            throw CoreError.invalidCommand("R461 expected StoreKit identity is invalid")
        }
        self.environment = environment
        self.bundleID = bundleID
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.productID = productID
        self.quantity = quantity
        self.accountBindingSHA256 = accountBindingSHA256
        self.accountIDSHA256 = accountIDSHA256
    }

    private static func isLowerSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

/// Small Codable JSON value so the R453-compatible immutable delivery can be
/// preserved without converting it to a locally-authorized entitlement.
public indirect enum PurchaseJSONValueR461: Codable, Sendable, Equatable {
    case object([String: PurchaseJSONValueR461])
    case array([PurchaseJSONValueR461])
    case string(String)
    case integer(Int64)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int64.self) { self = .integer(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([PurchaseJSONValueR461].self) { self = .array(value); return }
        if let value = try? container.decode([String: PurchaseJSONValueR461].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    fileprivate var foundationValue: Any {
        switch self {
        case .object(let value): return value.mapValues { $0.foundationValue }
        case .array(let value): return value.map { $0.foundationValue }
        case .string(let value): return value
        case .integer(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct HistoricalPurchaseDeliveryR461: Codable, Sendable, Equatable {
    public let transactionIdentity: TransactionIdentity
    public let operationID: String
    public let profileID: String
    public let profileFingerprint: String
    public let drawReceipt: [String: PurchaseJSONValueR461]
    public let deliveredItems: [DeliveredItem]
    public let deliveryFingerprint: String

    public struct TransactionIdentity: Codable, Sendable, Equatable {
        public let environment: String
        public let bundleID: String
        public let transactionID: String
        public let originalTransactionID: String
        public let productID: String
        public let quantity: Int
    }

    public struct DeliveredItem: Codable, Sendable, Equatable {
        public let gearID: UUID
        public let definitionID: String
        public let qualityID: String
        public let affixIDs: [String]
        public let latentEffectID: String?
        public let drawIndex: Int
        public let drawRowFingerprint: String
    }
}

public struct CurrentPurchaseAccountStateR461: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable, Equatable { case active, refunded, unknown }
    public enum OperationStatus: String, Codable, Sendable, Equatable { case delivered, notDelivered = "not_delivered", unknown }
    public let revision: Int64
    public let status: Status
    public let ticketBalance: Int
    public let ticketDebt: Int
    public let operationStatus: OperationStatus
}

public struct PurchaseAuthorityResponseR461: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable, Equatable { case delivered = "DELIVERED", rejected = "REJECTED" }
    public let schemaVersion: Int
    public let status: Status
    public let operationID: String?
    public let requestSHA256: String
    public let accountBindingSHA256: String?
    public let authorizationStatus: String
    public let historicalDelivery: HistoricalPurchaseDeliveryR461?
    public let currentState: CurrentPurchaseAccountStateR461?
    public let errorCode: String?

    /// Exact closed JSON shapes are required; unknown nested receipt fields fail closed.
    public static func decodeStrict(_ data: Data) throws -> Self {
        guard (1...1_048_576).contains(data.count),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["schemaVersion", "status", "operationID", "requestSHA256", "accountBindingSHA256", "authorizationStatus", "historicalDelivery", "currentState", "errorCode"] else {
            throw invalid("response envelope shape")
        }
        let canonical = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]) + Data([0x0A])
        guard canonical == data else { throw invalid("response must be canonical compact JSON with one final LF") }
        if let delivery = root["historicalDelivery"] as? [String: Any] {
            guard Set(delivery.keys) == ["transactionIdentity", "operationID", "profileID", "profileFingerprint", "drawReceipt", "deliveredItems", "deliveryFingerprint"],
                  let identity = delivery["transactionIdentity"] as? [String: Any],
                  Set(identity.keys) == ["environment", "bundleID", "transactionID", "originalTransactionID", "productID", "quantity"],
                  ["environment", "bundleID", "transactionID", "originalTransactionID", "productID"].allSatisfy({ (identity[$0] as? String)?.isEmpty == false }),
                  Self.exactInteger(identity["quantity"], min: 1),
                  let draw = delivery["drawReceipt"] as? [String: Any],
                  Set(draw.keys) == ["accountIDSHA256", "idempotencyKey", "transactionIdentity", "ticketsGranted", "ticketsDebtOffset", "ticketsDrawn", "ticketsRemainingFromPurchase", "draws", "pityAfter", "status"],
                  let drawRows = draw["draws"] as? [[String: Any]], !drawRows.isEmpty,
                  let items = delivery["deliveredItems"] as? [[String: Any]],
                  (1...50).contains(drawRows.count),
                  items.count == drawRows.count,
                  Set(items.compactMap { ($0["drawIndex"] as? NSNumber)?.intValue }) == Set(0..<drawRows.count),
                  items.allSatisfy({ item in
                      guard Set(item.keys) == ["gearID", "definitionID", "qualityID", "affixIDs", "latentEffectID", "drawIndex", "drawRowFingerprint"],
                            Self.exactInteger(item["drawIndex"], min: 0, max: 49),
                            let rowHash = item["drawRowFingerprint"] as? String, Self.isLowerSHA256(rowHash),
                            let definition = item["definitionID"] as? String, !definition.isEmpty,
                            let quality = item["qualityID"] as? String, ["Q0", "Q1", "Q2", "Q3", "Q4"].contains(quality),
                            let affixes = item["affixIDs"] as? [String], affixes.allSatisfy({ !$0.isEmpty }),
                            item["latentEffectID"] is NSNull || item["latentEffectID"] is String,
                            let rawID = item["gearID"] as? String,
                            let uuid = UUID(uuidString: rawID) else { return false }
                      return rawID == uuid.uuidString.lowercased()
                  }) else {
                throw invalid("historical delivery shape")
            }
            guard Self.exactInteger(draw["ticketsDrawn"], min: 1, max: 50),
                  (draw["ticketsDrawn"] as? NSNumber)?.intValue == drawRows.count,
                  Self.exactInteger(draw["ticketsGranted"], min: 0),
                  Self.exactInteger(draw["ticketsDebtOffset"], min: 0),
                  Self.exactInteger(draw["ticketsRemainingFromPurchase"], min: 0),
                  let grant = draw["ticketsGranted"] as? NSNumber,
                  let offset = draw["ticketsDebtOffset"] as? NSNumber, offset.int64Value <= grant.int64Value else {
                throw invalid("draw receipt number fields")
            }
            for (index, drawRow) in drawRows.enumerated() {
                guard Set(drawRow.keys) == ["drawIndex", "qualityID", "gearTemplateID", "pityBefore", "pityAfter"],
                      Self.exactInteger(drawRow["drawIndex"], min: 0, max: Int64(drawRows.count - 1)),
                      (drawRow["drawIndex"] as? NSNumber)?.intValue == index,
                      let quality = drawRow["qualityID"] as? String, ["Q0", "Q1", "Q2", "Q3", "Q4"].contains(quality),
                      let gear = drawRow["gearTemplateID"] as? String, !gear.isEmpty,
                      let item = items.first(where: { ($0["drawIndex"] as? NSNumber)?.intValue == index }),
                      item["qualityID"] as? String == quality, item["definitionID"] as? String == gear,
                      let rowBytes = try? JSONSerialization.data(withJSONObject: drawRow, options: [.sortedKeys, .withoutEscapingSlashes]),
                      item["drawRowFingerprint"] as? String == PendingPurchaseOperationR461.sha256(rowBytes) else {
                    throw invalid("draw receipt row shape, values, or item binding")
                }
            }
            let pityRows = drawRows.flatMap { [$0["pityBefore"], $0["pityAfter"]] } + [draw["pityAfter"]]
            for pity in pityRows {
                guard let row = pity as? [String: Any], Set(row.keys) == ["drawsSinceTop", "drawsSinceMid", "targetTemplateID", "guaranteeTargetOnNextTop"],
                      Self.exactInteger(row["drawsSinceTop"], min: 0, max: 99),
                      Self.exactInteger(row["drawsSinceMid"], min: 0, max: 19),
                      row["targetTemplateID"] is NSNull || row["targetTemplateID"] is String,
                      let guarantee = row["guaranteeTargetOnNextTop"] as? NSNumber,
                      CFGetTypeID(guarantee) == CFBooleanGetTypeID() else {
                    throw invalid("pity shape or values")
                }
            }
            guard let receiptAfter = draw["pityAfter"] as? [String: Any],
                  let lastRow = drawRows.last?["pityAfter"] as? [String: Any],
                  NSDictionary(dictionary: receiptAfter).isEqual(NSDictionary(dictionary: lastRow)) else {
                throw invalid("post-pity value differs from final draw row")
            }
        } else if !(root["historicalDelivery"] is NSNull) {
            throw invalid("historical delivery must be object or null")
        }
        if let state = root["currentState"] as? [String: Any] {
            guard Set(state.keys) == ["revision", "status", "ticketBalance", "ticketDebt", "operationStatus"],
                  Self.exactInteger(state["revision"], min: 0), Self.exactInteger(state["ticketBalance"], min: 0),
                  Self.exactInteger(state["ticketDebt"], min: 0) else {
                throw invalid("current state shape or number fields")
            }
        } else if !(root["currentState"] is NSNull) {
            throw invalid("current state must be object or null")
        }
        guard Self.exactInteger(root["schemaVersion"], min: 1, max: 1),
              let status = root["status"] as? String, ["DELIVERED", "REJECTED"].contains(status),
              let auth = root["authorizationStatus"] as? String, auth == "NOT_AUTHORIZED_FOR_PRODUCTION",
              let requestSHA = root["requestSHA256"] as? String, Self.isLowerSHA256(requestSHA),
              Self.validOptionalUUID(root["operationID"]), Self.validOptionalHash(root["accountBindingSHA256"], nullable: true),
              Self.validOptionalError(root["errorCode"]) else { throw invalid("response envelope values") }
        if status == "DELIVERED" {
            guard root["operationID"] is String, root["accountBindingSHA256"] is String,
                  root["historicalDelivery"] is [String: Any], root["currentState"] is [String: Any], root["errorCode"] is NSNull else {
                throw invalid("DELIVERED response has inconsistent nullable fields")
            }
        } else if root["errorCode"] is NSNull {
            throw invalid("REJECTED response requires a known error code")
        }
        if root["accountBindingSHA256"] is NSNull {
            guard root["operationID"] is NSNull, root["currentState"] is NSNull,
                  root["historicalDelivery"] is NSNull, status == "REJECTED",
                  ["AUTHENTICATION_REQUIRED", "AUTHENTICATION_PROVIDER_ERROR", "REQUEST_INVALID"].contains(root["errorCode"] as? String ?? "") else {
                throw invalid("unauthenticated response must be an auth-denied envelope")
            }
        } else {
            guard root["operationID"] is String else { throw invalid("authenticated response requires operationID") }
        }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw invalid("response value types") }
    }

    private static let errorCodes: Set<String> = [
        "REQUEST_INVALID", "AUTHENTICATION_PROVIDER_ERROR", "AUTHENTICATION_REQUIRED",
        "TRANSACTION_REFUNDED", "OPERATION_ID_COLLISION", "INSUFFICIENT_TICKETS",
        "TRANSACTION_REJECTED", "AUTHORITY_REJECTED", "REQUEST_FAILED",
        "CURRENT_STATE_UNAVAILABLE", "CURRENT_STATE_NOT_DELIVERABLE", "DELIVERY_PROJECTION_FAILED"
    ]
    private static func validOptionalUUID(_ value: Any?) -> Bool {
        guard let raw = value as? String else { return value is NSNull }
        guard let uuid = UUID(uuidString: raw) else { return false }
        return raw == uuid.uuidString.lowercased()
    }
    private static func validOptionalHash(_ value: Any?, nullable: Bool) -> Bool {
        guard let raw = value as? String else { return nullable && value is NSNull }
        return isLowerSHA256(raw)
    }
    private static func validOptionalError(_ value: Any?) -> Bool {
        guard let code = value as? String else { return value is NSNull }
        return errorCodes.contains(code)
    }
    private static func isLowerSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private static func exactInteger(_ value: Any?, min: Int64, max: Int64 = Int64.max) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        guard let parsed = Int64(number.stringValue) else { return false }
        return parsed >= min && parsed <= max
    }
    private static func invalid(_ detail: String) -> CoreError {
        .invalidCommand("R461 response rejected: " + detail)
    }
}

/// Highest matched server observation. Persist a newer refunded/debt state before
/// returning a business rejection, so a prior success cannot reappear after restart.
public struct AuthorityObservationR461: Codable, Sendable, Equatable {
    public let accountBindingSHA256: String
    public let revision: Int64
    public let status: CurrentPurchaseAccountStateR461.Status
    public let ticketBalance: Int
    public let ticketDebt: Int
}

public protocol PurchaseAuthorityTransportR461: Sendable {
    /// Explicitly injected. This candidate has no network/default transport and
    /// does not provide TLS/server authentication or production authorization.
    func exchange(_ requestBytes: Data) async throws -> Data
}

public protocol AuthorityObservationStoreR461: Sendable {
    func load(accountBindingSHA256: String) async throws -> AuthorityObservationR461?
    /// Atomically store only if `expectedPreviousRevision` still matches; nil means
    /// there must be no prior observation. Equal revisions are allowed only when
    /// every observed value is identical, to confirm a response against current state.
    func compareAndSave(_ observation: AuthorityObservationR461, expectedPreviousRevision: Int64?) async throws -> Bool
}

public enum PurchaseAuthorityClientResultR461: Sendable, Equatable {
    case candidateDeliveryRecorded(PurchaseAuthorityResponseR461)
}

public protocol PendingPurchaseOperationStoreR461: Sendable {
    /// Atomically insert if absent; if the UUID exists, require byte-identical
    /// canonical request bytes and fingerprint. Implementations must persist this
    /// record before network exchange so retries after restart reuse it.
    func registerIfAbsent(_ pending: PendingPurchaseOperationR461) async throws
}

/// Contract validation only: no GameSnapshot, SaveRepository, currency, ticket,
/// gear, or production-entitlement mutation is performed here.
public struct PurchaseAuthorityClientR461: Sendable {
    private let transport: any PurchaseAuthorityTransportR461
    private let observations: any AuthorityObservationStoreR461
    private let pendingOperations: any PendingPurchaseOperationStoreR461

    public init(transport: any PurchaseAuthorityTransportR461,
                observations: any AuthorityObservationStoreR461,
                pendingOperations: any PendingPurchaseOperationStoreR461) {
        self.transport = transport
        self.observations = observations
        self.pendingOperations = pendingOperations
    }

    public func submit(_ pending: PendingPurchaseOperationR461,
                       expectedStoreKit: LocalStoreKitPurchaseExpectationR461) async throws -> PurchaseAuthorityClientResultR461 {
        try pending.validate()
        try await pendingOperations.registerIfAbsent(pending)
        // Always ask for a fresh current state. A prior refund/debt is never
        // overwritten by old history, but it may have been reconciled server-side.
        let prior = try await observations.load(accountBindingSHA256: expectedStoreKit.accountBindingSHA256)
        if let prior {
            guard prior.accountBindingSHA256 == expectedStoreKit.accountBindingSHA256,
                  prior.revision >= 0, prior.ticketBalance >= 0, prior.ticketDebt >= 0 else {
                throw invalid("persisted authority observation is invalid")
            }
        }
        let requestBytes = try pending.request.canonicalData()
        let response = try PurchaseAuthorityResponseR461.decodeStrict(await transport.exchange(requestBytes))
        guard response.schemaVersion == 1,
              Self.isLowerSHA256(response.requestSHA256),
              response.requestSHA256 == pending.requestSHA256,
              response.authorizationStatus == "NOT_AUTHORIZED_FOR_PRODUCTION" else {
            throw invalid("schema, request hash, or authorization label mismatch")
        }

        // Authentication denial or an uncorrelated reply cannot poison local state.
        guard response.operationID == pending.request.operationID,
              let binding = response.accountBindingSHA256,
              binding == expectedStoreKit.accountBindingSHA256 else {
            throw invalid("operation or account correlation mismatch")
        }
        if response.status == .delivered {
            guard response.errorCode == nil, response.historicalDelivery != nil, response.currentState != nil else {
                throw invalid("DELIVERED response lacks delivery or current state")
            }
        } else if response.errorCode == nil {
            throw invalid("REJECTED response lacks a stable error code")
        }
        if let delivery = response.historicalDelivery {
            guard delivery.operationID == pending.request.operationID,
                  delivery.transactionIdentity.environment == expectedStoreKit.environment,
                  delivery.transactionIdentity.bundleID == expectedStoreKit.bundleID,
                  delivery.transactionIdentity.transactionID == expectedStoreKit.transactionID,
                  delivery.transactionIdentity.originalTransactionID == expectedStoreKit.originalTransactionID,
                  delivery.transactionIdentity.productID == expectedStoreKit.productID,
                  delivery.transactionIdentity.quantity == expectedStoreKit.quantity,
                  delivery.transactionIdentity.quantity > 0,
                  (1...50).contains(delivery.deliveredItems.count),
                  delivery.deliveredItems.allSatisfy({ !$0.definitionID.isEmpty && ["Q0", "Q1", "Q2", "Q3", "Q4"].contains($0.qualityID) }),
                  Set(delivery.deliveredItems.map(\.gearID)).count == delivery.deliveredItems.count,
                  delivery.drawReceipt["accountIDSHA256"] == .string(expectedStoreKit.accountIDSHA256),
                  delivery.drawReceipt["idempotencyKey"] == .string(pending.request.operationID),
                  delivery.drawReceipt["transactionIdentity"] == .string([
                    delivery.transactionIdentity.environment, delivery.transactionIdentity.bundleID,
                    delivery.transactionIdentity.transactionID
                  ].joined(separator: "/")),
                  Self.isLowerSHA256(delivery.deliveryFingerprint),
                  Self.validDrawReceipt(delivery.drawReceipt, items: delivery.deliveredItems),
                  Self.validDeliveryFingerprint(delivery) else {
                throw invalid("historical delivery does not match verified local transaction")
            }
        }

        if let state = response.currentState {
            guard state.revision >= 0, state.ticketBalance >= 0, state.ticketDebt >= 0 else {
                throw invalid("current account state contains invalid numbers")
            }
            if let prior {
                guard state.revision >= prior.revision else { throw invalid("current state revision is stale") }
                if state.revision == prior.revision {
                    guard state.status == prior.status, state.ticketBalance == prior.ticketBalance,
                          state.ticketDebt == prior.ticketDebt else {
                        throw invalid("equal current revision has conflicting state")
                    }
                }
                // CAS even for an identical revision: another request may have
                // advanced the persisted observation while this exchange awaited.
                let saved = try await observations.compareAndSave(
                    AuthorityObservationR461(accountBindingSHA256: binding, revision: state.revision, status: state.status,
                                             ticketBalance: state.ticketBalance, ticketDebt: state.ticketDebt),
                    expectedPreviousRevision: prior.revision)
                guard saved else { throw invalid("concurrent account-state update; fetch fresh state") }
            } else {
                let saved = try await observations.compareAndSave(
                    AuthorityObservationR461(accountBindingSHA256: binding, revision: state.revision, status: state.status,
                                             ticketBalance: state.ticketBalance, ticketDebt: state.ticketDebt),
                    expectedPreviousRevision: nil)
                guard saved else { throw invalid("concurrent first account-state observation") }
            }
        }

        guard response.status == .delivered,
              response.errorCode == nil,
              response.historicalDelivery != nil,
              let state = response.currentState,
              state.status == .active, state.operationStatus == .delivered,
              state.ticketDebt == 0 else {
            throw invalid("delivery rejected by fresh current account state")
        }
        return .candidateDeliveryRecorded(response)
    }

    private static func isLowerSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private static func validDeliveryFingerprint(_ delivery: HistoricalPurchaseDeliveryR461) -> Bool {
        guard !delivery.profileID.isEmpty, isLowerSHA256(delivery.profileFingerprint) else { return false }
        let identity = delivery.transactionIdentity
        let items: [[String: Any]] = delivery.deliveredItems.map { item in
            ["gearID": item.gearID.uuidString.lowercased(), "definitionID": item.definitionID,
             "qualityID": item.qualityID, "affixIDs": item.affixIDs,
             "latentEffectID": item.latentEffectID.map { $0 as Any } ?? NSNull(),
             "drawIndex": item.drawIndex, "drawRowFingerprint": item.drawRowFingerprint]
        }
        let payload: [String: Any] = [
            "profileID": delivery.profileID, "profileFingerprint": delivery.profileFingerprint,
            "transactionIdentity": ["environment": identity.environment, "bundleID": identity.bundleID,
                "transactionID": identity.transactionID, "originalTransactionID": identity.originalTransactionID,
                "productID": identity.productID, "quantity": identity.quantity],
            "operationID": delivery.operationID,
            "drawReceipt": delivery.drawReceipt.mapValues { $0.foundationValue },
            "deliveredItems": items
        ]
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]) else { return false }
        return PendingPurchaseOperationR461.sha256(bytes) == delivery.deliveryFingerprint
    }

    private static func validDrawReceipt(_ draw: [String: PurchaseJSONValueR461], items: [HistoricalPurchaseDeliveryR461.DeliveredItem]) -> Bool {
        guard case .string(let transactionIdentity) = draw["transactionIdentity"], !transactionIdentity.isEmpty,
              case .string("COMMITTED_TEST_ONLY") = draw["status"],
              case .integer(let granted) = draw["ticketsGranted"], granted >= 0,
              case .integer(let debtOffset) = draw["ticketsDebtOffset"], debtOffset >= 0,
              case .integer(let remaining) = draw["ticketsRemainingFromPurchase"], remaining >= 0,
              case .integer(let drawn) = draw["ticketsDrawn"], Int(drawn) == items.count,
              case .array(let rows) = draw["draws"], rows.count == items.count else { return false }
        for (index, row) in rows.enumerated() {
            guard case .object(let fields) = row,
                  case .integer(let ordinal) = fields["drawIndex"], ordinal == Int64(index),
                  case .string(let quality) = fields["qualityID"], quality == items[index].qualityID,
                  case .string(let template) = fields["gearTemplateID"], template == items[index].definitionID else { return false }
        }
        return true
    }
    private func invalid(_ detail: String) -> CoreError { .invalidCommand("R461: " + detail) }
}
