import Foundation
import CryptoKit

public struct CommerceAuthorityRequestCandidateV1: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let operationID: String
    public let action: String
    public let signedTransactionJWS: String

    public init(operationID: UUID, signedTransactionJWS: String) throws {
        let parts = signedTransactionJWS.split(separator: ".", omittingEmptySubsequences: false)
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
        guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty,
              signedTransactionJWS.utf8.count <= 65_536,
              signedTransactionJWS.utf8.allSatisfy({ $0 < 0x80 }),
              parts.allSatisfy({ $0.utf8.allSatisfy { alphabet.contains($0) } }),
              !signedTransactionJWS.contains("\n"), !signedTransactionJWS.contains("\r") else {
            throw CoreError.invalidCommand("candidate authority requires a bounded compact StoreKit JWS")
        }
        schemaVersion = 1
        self.operationID = operationID.uuidString.lowercased()
        action = "verifyStoreTransaction"
        self.signedTransactionJWS = signedTransactionJWS
    }

    public func canonicalData() throws -> Data {
        guard schemaVersion == 1, action == "verifyStoreTransaction",
              let uuid = UUID(uuidString: operationID), operationID == uuid.uuidString.lowercased() else {
            throw CoreError.invalidCommand("candidate request identity is invalid")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct PendingCommerceOperationCandidateV1: Codable, Sendable, Equatable {
    public let request: CommerceAuthorityRequestCandidateV1
    public let requestSHA256: String

    public init(operationID: UUID, signedTransactionJWS: String) throws {
        request = try CommerceAuthorityRequestCandidateV1(operationID: operationID,
                                                          signedTransactionJWS: signedTransactionJWS)
        requestSHA256 = SHA256.hash(data: try request.canonicalData())
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Creates a deterministic request identity for a signed StoreKit payload.
    /// The stable transaction operation remains the journal record identity;
    /// distinct signed payloads (for example, a later revocation update) get
    /// separate request/replay identities without losing transaction linkage.
    public init(transactionOperationID: UUID, signedTransactionJWS: String) throws {
        let payloadHash = SHA256.hash(data: Data(signedTransactionJWS.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let digest = SHA256.hash(data: Data((transactionOperationID.uuidString.lowercased() + ":" + payloadHash).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        try self.init(operationID: UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                                               bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                                               bytes[12], bytes[13], bytes[14], bytes[15])),
                      signedTransactionJWS: signedTransactionJWS)
    }

    public func validate() throws {
        let actual = SHA256.hash(data: try request.canonicalData()).map { String(format: "%02x", $0) }.joined()
        guard actual == requestSHA256 else { throw CoreError.invalidCommand("candidate pending request fingerprint mismatch") }
    }
}

/// Proposed authority-v1 wire receipt. This is a candidate format for isolated
/// QA only; it is not an approved production authority contract.
public struct CommerceAuthorityReceiptCandidateV1: Codable, Sendable, Equatable {
    public enum Event: String, Codable, Sendable { case grant, revoke }
    public struct Identity: Codable, Sendable, Equatable {
        public let environment: String
        public let bundleID: String
        public let transactionID: String
        public let originalTransactionID: String
        public let productID: String
        public let quantity: Int
    }
    public struct Grant: Codable, Sendable, Equatable {
        public let entitlementID: String
        public let units: Int
        public let expiresAtEpochSeconds: Int64?
    }

    public let schemaVersion: Int
    public let event: Event
    public let operationID: String
    public let requestSHA256: String
    public let accountBindingSHA256: String
    public let revision: Int64
    public let transaction: Identity
    public let grant: Grant?
    public let keyID: String
    public let signatureBase64: String

    public init(event: Event, operationID: UUID, requestSHA256: String, accountBindingSHA256: String,
                revision: Int64, transaction: Identity, grant: Grant?, keyID: String, signatureBase64: String) {
        schemaVersion = 1
        self.event = event
        self.operationID = operationID.uuidString.lowercased()
        self.requestSHA256 = requestSHA256
        self.accountBindingSHA256 = accountBindingSHA256
        self.revision = revision
        self.transaction = transaction
        self.grant = grant
        self.keyID = keyID
        self.signatureBase64 = signatureBase64
    }

    public func signingBytes() throws -> Data {
        let payload = SignedPayload(schemaVersion: schemaVersion, event: event, operationID: operationID,
                                    requestSHA256: requestSHA256, accountBindingSHA256: accountBindingSHA256,
                                    revision: revision, transaction: transaction, grant: grant, keyID: keyID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    public static func decodeStrict(_ data: Data) throws -> Self {
        guard (1...65_536).contains(data.count),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String,
              let transaction = object["transaction"] as? [String: Any],
              Set(transaction.keys) == ["environment", "bundleID", "transactionID", "originalTransactionID", "productID", "quantity"] else {
            throw CoreError.invalidCommand("candidate authority receipt shape is invalid")
        }
        let commonKeys: Set<String> = ["schemaVersion", "event", "operationID", "requestSHA256", "accountBindingSHA256",
                                       "revision", "transaction", "keyID", "signatureBase64"]
        let expectedKeys = event == "grant" ? commonKeys.union(["grant"]) : commonKeys
        guard (event == "grant" || event == "revoke"), Set(object.keys) == expectedKeys else {
            throw CoreError.invalidCommand("candidate authority receipt fields are invalid")
        }
        if let grant = object["grant"], !(grant is NSNull) {
            guard let grantObject = grant as? [String: Any],
                  Set(grantObject.keys).isSubset(of: ["entitlementID", "units", "expiresAtEpochSeconds"]),
                  grantObject["entitlementID"] != nil, grantObject["units"] != nil else {
                throw CoreError.invalidCommand("candidate authority grant shape is invalid")
            }
        }
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(decoded) == data else {
            throw CoreError.invalidCommand("candidate authority receipt is not canonical JSON")
        }
        return decoded
    }

    public func validate(expectedOperationID: UUID, expectedRequestSHA256: String,
                         expectedAccountBindingSHA256: String, expectedTransaction: Identity,
                         expectedKeyID: String, publicKey: Curve25519.Signing.PublicKey,
                         nowEpochSeconds: Int64) throws {
        guard schemaVersion == 1, operationID == expectedOperationID.uuidString.lowercased(),
              isSHA256(requestSHA256), requestSHA256 == expectedRequestSHA256,
              isSHA256(accountBindingSHA256), accountBindingSHA256 == expectedAccountBindingSHA256,
              revision > 0, transaction == expectedTransaction, transaction.quantity > 0,
              !keyID.isEmpty, keyID == expectedKeyID, keyID.utf8.count <= 128,
              let signature = Data(base64Encoded: signatureBase64), signature.count == 64,
              publicKey.isValidSignature(signature, for: try signingBytes()) else {
            throw CoreError.invalidCommand("candidate commerce receipt signature or correlation is invalid")
        }
        switch event {
        case .grant:
            guard let grant, Self.isCanonicalEntitlementID(grant.entitlementID),
                  grant.units > 0, grant.units <= 100_000,
                  grant.expiresAtEpochSeconds.map({ $0 > nowEpochSeconds }) ?? true else {
                throw CoreError.invalidCommand("candidate commerce grant is invalid or expired")
            }
        case .revoke:
            guard grant == nil else { throw CoreError.invalidCommand("revocation receipt must not contain a grant") }
        }
    }

    public var receiptFingerprint: String {
        let data = (try? signingBytes()) ?? Data()
        return SHA256.hash(data: data + Data(signatureBase64.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct SignedPayload: Codable {
        let schemaVersion: Int
        let event: Event
        let operationID: String
        let requestSHA256: String
        let accountBindingSHA256: String
        let revision: Int64
        let transaction: Identity
        let grant: Grant?
        let keyID: String
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func isCanonicalEntitlementID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains(Int($0))
        }
    }
}

public struct CommerceEntitlementLedgerCandidateV1: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let transactionID: String
        public let productID: String
        public let units: Int
        public let expiresAtEpochSeconds: Int64?
        public let receiptFingerprint: String
    }
    public struct Tombstone: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let transactionID: String
        public let revision: Int64
        public let receiptFingerprint: String
    }

    public private(set) var accountBindingSHA256: String
    public private(set) var revision: Int64
    public private(set) var entries: [Entry]
    public private(set) var tombstones: [Tombstone]
    public private(set) var appliedOperationFingerprints: [String: String]

    public init(accountBindingSHA256: String) throws {
        guard accountBindingSHA256.utf8.count == 64,
              accountBindingSHA256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw CoreError.invalidCommand("invalid ledger account binding")
        }
        self.accountBindingSHA256 = accountBindingSHA256
        revision = 0
        entries = []
        tombstones = []
        appliedOperationFingerprints = [:]
    }

    /// Caller persists the returned ledger and transaction status in one atomic
    /// Keychain item update. Replays are idempotent; conflicting replays fail.
    public mutating func applying(_ receipt: CommerceAuthorityReceiptCandidateV1,
                                  expectedOperationID: UUID, expectedRequestSHA256: String,
                                  expectedTransaction: CommerceAuthorityReceiptCandidateV1.Identity,
                                  expectedKeyID: String,
                                  publicKey: Curve25519.Signing.PublicKey,
                                  nowEpochSeconds: Int64) throws -> Bool {
        try receipt.validate(expectedOperationID: expectedOperationID,
                             expectedRequestSHA256: expectedRequestSHA256,
                             expectedAccountBindingSHA256: accountBindingSHA256,
                             expectedTransaction: expectedTransaction,
                             expectedKeyID: expectedKeyID,
                             publicKey: publicKey, nowEpochSeconds: nowEpochSeconds)
        let operationKey = receipt.operationID + ":" + receipt.event.rawValue
        if let applied = appliedOperationFingerprints[operationKey] {
            guard applied == receipt.receiptFingerprint else {
                throw CoreError.invalidCommand("authority operation replay conflicts with prior receipt")
            }
            return false
        }
        if receipt.event == .grant && tombstones.contains(where: { $0.transactionID == receipt.transaction.transactionID }) {
            throw CoreError.invalidCommand("revoked transaction cannot regain an entitlement")
        }

        switch receipt.event {
        case .grant:
            guard let grant = receipt.grant else { throw CoreError.invalidCommand("grant missing") }
            let duplicateKey = receipt.transaction.transactionID + "/" + grant.entitlementID
            guard !entries.contains(where: { $0.id == duplicateKey }) else {
                throw CoreError.invalidCommand("transaction entitlement already exists under another operation")
            }
            entries.append(Entry(id: duplicateKey, transactionID: receipt.transaction.transactionID,
                                 productID: receipt.transaction.productID, units: grant.units,
                                 expiresAtEpochSeconds: grant.expiresAtEpochSeconds,
                                 receiptFingerprint: receipt.receiptFingerprint))
        case .revoke:
            entries.removeAll { $0.transactionID == receipt.transaction.transactionID }
            if !tombstones.contains(where: { $0.transactionID == receipt.transaction.transactionID }) {
                tombstones.append(Tombstone(id: receipt.transaction.transactionID,
                                            transactionID: receipt.transaction.transactionID,
                                            revision: receipt.revision, receiptFingerprint: receipt.receiptFingerprint))
            }
            // Receipt revisions are a per-account watermark, not an ordering
            // requirement for independently signed transaction deliveries.
        }
        revision = max(revision, receipt.revision)
        appliedOperationFingerprints[operationKey] = receipt.receiptFingerprint
        return true
    }

    /// StoreKit's cryptographically verified revocation is a second revocation
    /// source. Persist its signed-transaction fingerprint as a local tombstone.
    public mutating func applyingVerifiedStoreKitRevocation(transactionID: String,
                                                             proofFingerprint: String) throws {
        guard !transactionID.isEmpty, Self.isSHA256(proofFingerprint) else {
            throw CoreError.invalidCommand("invalid verified StoreKit revocation proof")
        }
        entries.removeAll { $0.transactionID == transactionID }
        if !tombstones.contains(where: { $0.transactionID == transactionID }) {
            // StoreKit's verified JWS is independent evidence, not an authority
            // server revision. A zero revision marks this local tombstone and
            // leaves the server watermark untouched.
            tombstones.append(Tombstone(id: transactionID, transactionID: transactionID,
                                        revision: 0, receiptFingerprint: proofFingerprint))
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

/// Read-only ownership projection for app/UI integration. Empty is the default;
/// this value never edits or serializes GameSnapshot and cannot create rights.
public struct CommerceOwnershipReadModelCandidateV1: Sendable, Equatable {
    public let activeEntitlementIDs: Set<String>
    public let unitsByEntitlementID: [String: Int]

    public init(ledger: CommerceEntitlementLedgerCandidateV1?, nowEpochSeconds: Int64) {
        let active = ledger?.entries.filter { $0.expiresAtEpochSeconds.map { $0 > nowEpochSeconds } ?? true } ?? []
        self.activeEntitlementIDs = Set(active.compactMap { $0.id.split(separator: "/", maxSplits: 1).last.map(String.init) })
        self.unitsByEntitlementID = Dictionary(active.map {
            ($0.id.split(separator: "/", maxSplits: 1).last.map(String.init) ?? $0.id, $0.units)
        }, uniquingKeysWith: max)
    }

    public static let empty = CommerceOwnershipReadModelCandidateV1(ledger: nil, nowEpochSeconds: 0)

    public func owns(_ entitlementID: String) -> Bool { activeEntitlementIDs.contains(entitlementID) }
    public func units(for entitlementID: String) -> Int { unitsByEntitlementID[entitlementID] ?? 0 }
}
