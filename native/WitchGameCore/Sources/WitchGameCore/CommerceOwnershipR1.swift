import Foundation
import CryptoKit

/// Durable source records for cosmetic and furniture ownership. A nil value on
/// GameSnapshot means a legacy save: its existing ownership remains free-owned.
public struct CommerceOwnershipProvenanceR1: Codable, Sendable, Equatable {
    public struct Grant: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let transactionID: String
        public let entitlementID: String
        public let cosmeticIDs: Set<String>
        public let furnitureIDs: Set<String>
        public let expiresAtEpochSeconds: Int64?
        public let receiptFingerprint: String

        public init(transactionID: String, entitlementID: String, cosmeticIDs: Set<String>,
                    furnitureIDs: Set<String>, expiresAtEpochSeconds: Int64?, receiptFingerprint: String) {
            self.id = transactionID + "/" + entitlementID
            self.transactionID = transactionID; self.entitlementID = entitlementID
            self.cosmeticIDs = cosmeticIDs; self.furnitureIDs = furnitureIDs
            self.expiresAtEpochSeconds = expiresAtEpochSeconds; self.receiptFingerprint = receiptFingerprint
        }
    }
    public struct Tombstone: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let transactionID: String
        public let receiptFingerprint: String
        public let authorityRevision: Int64

        public init(transactionID: String, receiptFingerprint: String, authorityRevision: Int64) {
            self.id = transactionID; self.transactionID = transactionID
            self.receiptFingerprint = receiptFingerprint; self.authorityRevision = authorityRevision
        }
    }

    public var legacyFreeCosmeticIDs: Set<String>
    public var legacyFreeFurnitureIDs: Set<String>
    public var grants: [Grant]
    public var tombstones: [Tombstone]
    public var authorityRevision: Int64
    public var appliedOperationFingerprints: [String: String]
    public var appliedOperationRevisions: [String: Int64]

    public init(legacyFreeCosmeticIDs: Set<String> = [], legacyFreeFurnitureIDs: Set<String> = [],
                grants: [Grant] = [], tombstones: [Tombstone] = [], authorityRevision: Int64 = 0,
                appliedOperationFingerprints: [String: String] = [:],
                appliedOperationRevisions: [String: Int64] = [:]) {
        self.legacyFreeCosmeticIDs = legacyFreeCosmeticIDs
        self.legacyFreeFurnitureIDs = legacyFreeFurnitureIDs
        self.grants = grants
        self.tombstones = tombstones
        self.authorityRevision = authorityRevision
        self.appliedOperationFingerprints = appliedOperationFingerprints
        self.appliedOperationRevisions = appliedOperationRevisions
    }

    public func validate() throws {
        func isDigest(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        guard authorityRevision >= 0,
              Set(grants.map(\.id)).count == grants.count,
              Set(tombstones.map(\.transactionID)).count == tombstones.count,
              Set(grants.map { $0.transactionID + "/" + $0.entitlementID }).count == grants.count,
              grants.allSatisfy({ $0.id == $0.transactionID + "/" + $0.entitlementID }),
              tombstones.allSatisfy({ $0.id == $0.transactionID }),
              Set(tombstones.map(\.transactionID)).isDisjoint(with: Set(grants.map(\.transactionID))),
              grants.allSatisfy({ !$0.transactionID.isEmpty && !$0.entitlementID.isEmpty && $0.expiresAtEpochSeconds.map { $0 > 0 } ?? true && isDigest($0.receiptFingerprint) }),
              tombstones.allSatisfy({ !$0.transactionID.isEmpty && isDigest($0.receiptFingerprint) && $0.authorityRevision >= 0 && $0.authorityRevision <= authorityRevision }),
              Set(appliedOperationFingerprints.keys) == Set(appliedOperationRevisions.keys),
              appliedOperationFingerprints.allSatisfy({ key, digest in
                  let pieces = key.split(separator: ":", omittingEmptySubsequences: false)
                  let baseKey = String(pieces.first ?? "")
                  guard (pieces.count == 1 || (pieces.count == 2 && ["grant", "revoke"].contains(String(pieces[1])))),
                        let uuid = UUID(uuidString: baseKey), uuid.uuidString.lowercased() == baseKey,
                        let revision = appliedOperationRevisions[key] else { return false }
                  return isDigest(digest) && revision >= 0 && revision <= authorityRevision
              }) else {
            throw CoreError.invalidCommand("commerce ownership provenance is malformed")
        }
    }

    public mutating func adoptLegacyOwnership(cosmetics: Set<String>, furniture: Set<String>) {
        legacyFreeCosmeticIDs.formUnion(cosmetics)
        legacyFreeFurnitureIDs.formUnion(furniture)
    }

    public func activeCosmeticIDs(nowEpochSeconds: Int64) -> Set<String> {
        legacyFreeCosmeticIDs.union(grants.filter { $0.expiresAtEpochSeconds.map { $0 > nowEpochSeconds } ?? true }
            .reduce(into: Set<String>()) { $0.formUnion($1.cosmeticIDs) })
    }
    public func activeFurnitureIDs(nowEpochSeconds: Int64) -> Set<String> {
        legacyFreeFurnitureIDs.union(grants.filter { $0.expiresAtEpochSeconds.map { $0 > nowEpochSeconds } ?? true }
            .reduce(into: Set<String>()) { $0.formUnion($1.furnitureIDs) })
    }
}

/// A command capability can only be constructed after validating a signed
/// candidate-authority receipt. The authority schema remains unapproved.
public struct VerifiedCommerceOwnershipMutationR1: Sendable, Equatable {
    public let event: CommerceAuthorityReceiptCandidateV1.Event
    public let operationID: String
    public let receiptFingerprint: String
    public let transactionID: String
    public let authorityRevision: Int64
    public let entitlementID: String?
    public let cosmeticIDs: Set<String>
    public let furnitureIDs: Set<String>
    public let expiresAtEpochSeconds: Int64?

    /// The server request identity can legitimately progress from a grant to a
    /// revoke for the same StoreKit transaction. SaveRepository's command key
    /// therefore includes the event, while exact retries stay idempotent.
    public var durableOperationID: UUID {
        let digest = SHA256.hash(data: Data((operationID + ":" + event.rawValue).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private init(event: CommerceAuthorityReceiptCandidateV1.Event, operationID: String,
                 receiptFingerprint: String, transactionID: String, authorityRevision: Int64,
                 entitlementID: String?, cosmeticIDs: Set<String>, furnitureIDs: Set<String>,
                 expiresAtEpochSeconds: Int64?) {
        self.event = event; self.operationID = operationID; self.receiptFingerprint = receiptFingerprint
        self.transactionID = transactionID; self.authorityRevision = authorityRevision
        self.entitlementID = entitlementID; self.cosmeticIDs = cosmeticIDs; self.furnitureIDs = furnitureIDs
        self.expiresAtEpochSeconds = expiresAtEpochSeconds
    }

    public static func validate(receipt: CommerceAuthorityReceiptCandidateV1,
                                expectedOperationID: UUID, expectedRequestSHA256: String,
                                expectedAccountBindingSHA256: String,
                                expectedTransaction: CommerceAuthorityReceiptCandidateV1.Identity,
                                expectedKeyID: String, publicKey: Curve25519.Signing.PublicKey,
                                nowEpochSeconds: Int64,
                                contentByEntitlementID: [String: (cosmeticIDs: Set<String>, furnitureIDs: Set<String>)]) throws -> Self {
        try receipt.validate(expectedOperationID: expectedOperationID,
                             expectedRequestSHA256: expectedRequestSHA256,
                             expectedAccountBindingSHA256: expectedAccountBindingSHA256,
                             expectedTransaction: expectedTransaction, expectedKeyID: expectedKeyID,
                             publicKey: publicKey, nowEpochSeconds: nowEpochSeconds)
        var cosmetics = Set<String>(), furniture = Set<String>()
        var entitlement: String?
        var expiry: Int64?
        if receipt.event == .grant {
            guard let grant = receipt.grant,
                  let content = contentByEntitlementID[grant.entitlementID],
                  !content.cosmeticIDs.isEmpty || !content.furnitureIDs.isEmpty else {
                throw CoreError.invalidCommand("candidate entitlement has no approved local content mapping")
            }
            entitlement = grant.entitlementID
            cosmetics = content.cosmeticIDs; furniture = content.furnitureIDs
            expiry = grant.expiresAtEpochSeconds
        }
        return Self(event: receipt.event, operationID: receipt.operationID,
                    receiptFingerprint: receipt.receiptFingerprint,
                    transactionID: receipt.transaction.transactionID,
                    authorityRevision: receipt.revision, entitlementID: entitlement,
                    cosmeticIDs: cosmetics, furnitureIDs: furniture, expiresAtEpochSeconds: expiry)
    }

    /// Internal bridge for StoreKit's already-verified `revocationDate` evidence.
    /// The app adapter is the only production caller and passes the signed-JWS
    /// digest retained in its account-scoped journal.
    static func verifiedStoreKitRevocation(transactionID: String, proofFingerprint: String,
                                           authorityRevision: Int64, operationID: UUID) throws -> Self {
        guard !transactionID.isEmpty, proofFingerprint.utf8.count == 64,
              proofFingerprint.allSatisfy({ "0123456789abcdef".contains($0) }), authorityRevision == 0 else {
            throw CoreError.invalidCommand("invalid verified StoreKit revocation mutation")
        }
        return Self(event: .revoke, operationID: operationID.uuidString.lowercased(),
                    receiptFingerprint: proofFingerprint, transactionID: transactionID,
                    authorityRevision: authorityRevision, entitlementID: nil,
                    cosmeticIDs: [], furnitureIDs: [], expiresAtEpochSeconds: nil)
    }
}

public extension GameSnapshot {
    mutating func reconcileCommerceOwnershipR1(nowEpochSeconds: Int64) {
        let ledger = commerceOwnershipR1 ?? CommerceOwnershipProvenanceR1(
            legacyFreeCosmeticIDs: ownedCosmeticIDs, legacyFreeFurnitureIDs: ownedFurnitureIDs)
        let cosmetics = ledger.activeCosmeticIDs(nowEpochSeconds: nowEpochSeconds)
        let furniture = ledger.activeFurnitureIDs(nowEpochSeconds: nowEpochSeconds)
        for id in ownedCosmeticIDs.subtracting(cosmetics) {
            selectedCosmeticIDs = selectedCosmeticIDs.filter { $0.value != id }
            selectedWeaponAppearanceIDs = selectedWeaponAppearanceIDs.filter { $0.value != id }
        }
        placedFurnitureIDs.formIntersection(furniture)
        ownedCosmeticIDs = cosmetics
        ownedFurnitureIDs = furniture
        commerceOwnershipR1 = ledger
    }

    /// Applies signed receipt results atomically to the game ownership projection.
    /// No purchase rights are created by a raw product ID or ordinary UI command.
    mutating func applyCommerceOwnershipR1(_ mutation: VerifiedCommerceOwnershipMutationR1,
                                          catalog: GameCatalog, nowEpochSeconds: Int64) throws {
        var ledger = commerceOwnershipR1 ?? CommerceOwnershipProvenanceR1(
            legacyFreeCosmeticIDs: ownedCosmeticIDs, legacyFreeFurnitureIDs: ownedFurnitureIDs)
        let operationKey = mutation.operationID + ":" + mutation.event.rawValue
        if let prior = ledger.appliedOperationFingerprints[operationKey] {
            guard prior == mutation.receiptFingerprint else {
                throw CoreError.invalidCommand("commerce operation replay conflicts with prior receipt")
            }
            commerceOwnershipR1 = ledger
            return
        }
        let isStoreKitRevocation = mutation.event == .revoke && mutation.authorityRevision == 0
        guard isStoreKitRevocation || mutation.authorityRevision > 0 else {
            throw CoreError.invalidCommand("commerce authority revision is invalid")
        }
        switch mutation.event {
        case .grant:
            guard let entitlement = mutation.entitlementID,
                  !ledger.tombstones.contains(where: { $0.transactionID == mutation.transactionID }),
                  !ledger.grants.contains(where: { $0.transactionID == mutation.transactionID && $0.entitlementID == entitlement }) else {
                throw CoreError.invalidCommand("commerce grant is duplicate, revoked, or invalid")
            }
            guard mutation.cosmeticIDs.allSatisfy({ id in catalog.appearances.contains(where: { $0.id == id }) }),
                  mutation.furnitureIDs.allSatisfy({ catalog.furnitureIDs.contains($0) }) else {
                throw CoreError.invalidCommand("commerce grant maps to unknown local content")
            }
            ledger.grants.append(.init(transactionID: mutation.transactionID, entitlementID: entitlement,
                                       cosmeticIDs: mutation.cosmeticIDs, furnitureIDs: mutation.furnitureIDs,
                                       expiresAtEpochSeconds: mutation.expiresAtEpochSeconds,
                                       receiptFingerprint: mutation.receiptFingerprint))
        case .revoke:
            if !ledger.tombstones.contains(where: { $0.transactionID == mutation.transactionID }) {
                ledger.tombstones.append(.init(transactionID: mutation.transactionID,
                                              receiptFingerprint: mutation.receiptFingerprint,
                                              authorityRevision: mutation.authorityRevision))
            }
            ledger.grants.removeAll { $0.transactionID == mutation.transactionID }
        }
        if !isStoreKitRevocation {
            ledger.authorityRevision = max(ledger.authorityRevision, mutation.authorityRevision)
        }
        ledger.appliedOperationFingerprints[operationKey] = mutation.receiptFingerprint
        ledger.appliedOperationRevisions[operationKey] = mutation.authorityRevision
        commerceOwnershipR1 = ledger
        reconcileCommerceOwnershipR1(nowEpochSeconds: nowEpochSeconds)
        try commerceOwnershipR1?.validate()
    }
}
