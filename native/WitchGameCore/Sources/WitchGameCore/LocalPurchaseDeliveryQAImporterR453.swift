import Foundation
import CryptoKit
import CoreFoundation

/// A DEBUG-only integration boundary for isolated, explicitly mocked purchase QA.
/// Hashes pin test inputs; they do not authenticate Apple or grant production rights.
/// The provider must revalidate the current authority state on EVERY call, including
/// retries. A saved JSON file alone is not a current-authority provider.
public struct LocalPurchaseDeliveryQAImporterR453: Sendable {
    private let catalog: GameCatalog
    private let bundleID: String
    private let profileFingerprint: String
    private let accountHash: String
    private let tokenHash: String

    public init(explicitIsolatedTestMode: Bool, catalog: GameCatalog, bundleID: String,
                profileFingerprint: String, accountHash: String, tokenHash: String) throws {
        #if DEBUG
        guard explicitIsolatedTestMode, !bundleID.isEmpty,
              [profileFingerprint, accountHash, tokenHash].allSatisfy(Self.isHash) else {
            throw CoreError.invalidCommand("R453 requires explicit isolated test identity pins")
        }
        #else
        throw CoreError.invalidCommand("R453 local purchase importer is unavailable in Release")
        #endif
        self.catalog = catalog; self.bundleID = bundleID
        self.profileFingerprint = profileFingerprint; self.accountHash = accountHash; self.tokenHash = tokenHash
    }

    @discardableResult
    public func apply(expectedFileSHA256: String, saves: SaveRepository,
                      currentDelivery: @Sendable () async throws -> Data) async throws -> CommandReceipt {
        guard Self.isHash(expectedFileSHA256) else { throw Self.invalid("missing file pin") }
        for attempt in 0..<3 {
            // Do not return a cached save receipt, or retry a CAS conflict, before
            // rechecking current refund/tombstone state with the provider.
            let data = try await currentDelivery()
            guard data.count <= 1_048_576, Self.hash(data) == expectedFileSHA256 else {
                throw Self.invalid("receipt file changed or exceeds size limit")
            }
            let receipt = try validate(data)
            let fingerprint = "r453-local-delivery:" + receipt.receiptFingerprint
            let state = await saves.snapshot()
            do {
                return try await saves.transact(expectedRevision: state.revision, operationID: receipt.operationID,
                                                requestFingerprint: fingerprint) { snapshot in
                    guard snapshot.gachaPity == receipt.pityBefore else {
                        throw Self.invalid("out-of-order delivery or different local pity state")
                    }
                    let existing = Set(snapshot.gear.map(\.id))
                    guard existing.count == snapshot.gear.count,
                          receipt.items.allSatisfy({ !existing.contains($0.id) }) else {
                        throw Self.invalid("gear UUID collision without a matching operation receipt")
                    }
                    snapshot.gear.append(contentsOf: receipt.items)
                    snapshot.gachaPity = receipt.pityAfter
                    // Tickets remain exclusively in the authority ledger; no free/paid
                    // client currency or natural-drop provenance is synthesized here.
                    return "LOCAL_TEST_ONLY R453 delivered \(receipt.items.count) gear; fingerprint=\(receipt.receiptFingerprint); productionEntitlementAuthorized=false"
                }
            } catch CoreError.revisionConflict {
                if attempt == 2 { throw Self.invalid("save busy; delivery must be retried") }
            }
        }
        throw Self.invalid("delivery retry exhausted")
    }

    private struct Validated: Sendable {
        let operationID: UUID
        let receiptFingerprint: String
        let items: [GearInstance]
        let pityBefore: GachaPityState
        let pityAfter: GachaPityState
    }

    private func validate(_ data: Data) throws -> Validated {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Self.invalid("object required") }
        try Self.keys(root, ["schemaVersion", "status", "candidateRulesID", "profileID", "profileFingerprint", "operationID", "receiptFingerprint", "transaction", "drawReceipt", "gearInstances", "gearProvenance", "postPityState", "productionEntitlementAuthorized"])
        guard Self.integer(root["schemaVersion"]) == 1,
              root["status"] as? String == "LOCAL_TEST_ONLY_GEAR_DELIVERY",
              root["candidateRulesID"] as? String == "UNAPPROVED_R3_CANDIDATE",
              root["profileFingerprint"] as? String == profileFingerprint,
              Self.boolean(root["productionEntitlementAuthorized"]) == false,
              let profileID = root["profileID"] as? String, !profileID.isEmpty,
              let operationText = root["operationID"] as? String, let operation = UUID(uuidString: operationText),
              let fingerprint = root.removeValue(forKey: "receiptFingerprint") as? String, Self.isHash(fingerprint),
              Self.hash(try Self.canonical(root)) == fingerprint,
              let tx = root["transaction"] as? [String: Any],
              let draw = root["drawReceipt"] as? [String: Any],
              let items = root["gearInstances"] as? [[String: Any]],
              let provenance = root["gearProvenance"] as? [[String: Any]],
              let rows = draw["draws"] as? [[String: Any]], (1...50).contains(items.count),
              items.count == rows.count, items.count == provenance.count,
              Self.integer(draw["ticketsDrawn"]) == items.count,
              draw["accountIDSHA256"] as? String == accountHash,
              draw["idempotencyKey"] as? String == "r453:draw:" + operationText,
              draw["transactionIdentity"] as? String == "PAID_TICKET_BALANCE",
              draw["status"] as? String == "COMMITTED_TEST_ONLY",
              tx["environment"] as? String == "Xcode", tx["bundleID"] as? String == bundleID,
              tx["productKind"] as? String == "consumable",
              tx["testAccountIDSHA256"] as? String == accountHash,
              tx["appAccountTokenSHA256"] as? String == tokenHash,
              let transactionID = tx["transactionID"] as? String, !transactionID.isEmpty else {
            throw Self.invalid("identity, schema, or fingerprint mismatch")
        }
        try Self.keys(tx, ["environment", "bundleID", "transactionID", "originalTransactionID", "productID", "productKind", "quantity", "appAccountTokenSHA256", "testAccountIDSHA256", "purchaseTime"])
        try Self.keys(draw, ["accountIDSHA256", "idempotencyKey", "transactionIdentity", "ticketsGranted", "ticketsDebtOffset", "ticketsDrawn", "ticketsRemainingFromPurchase", "draws", "pityAfter", "status"])
        guard let quantity = Self.integer(tx["quantity"]), (1...100).contains(quantity),
              let purchaseTime = Self.integer(tx["purchaseTime"]), purchaseTime >= 0,
              let originalID = tx["originalTransactionID"] as? String, !originalID.isEmpty,
              let productID = tx["productID"] as? String, !productID.isEmpty,
              Self.integer(draw["ticketsGranted"]) == 0, Self.integer(draw["ticketsDebtOffset"]) == 0,
              Self.integer(draw["ticketsRemainingFromPurchase"]) == 0 else { throw Self.invalid("invalid balance-draw identity or ticket fields") }
        let allowedDefinitions = Set(catalog.gear.map(\.id))
        let allowedAffixes: Set<String> = ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]
        let allowedLatents: Set<String> = ["LATENT_POWER_TEST", "LATENT_VITALITY_TEST", "LATENT_GUARD_TEST"]
        var decoded: [GearInstance] = []
        var previousPity: GachaPityState?
        var firstPity: GachaPityState?
        for index in items.indices {
            let item = items[index], source = provenance[index], row = rows[index]
            try Self.keys(item, ["id", "definitionID", "ownerID", "protected", "enhancement", "refinement", "latentEffectID", "candidateLatentSlots", "qualityID", "affixIDs", "investmentDust"])
            try Self.keys(source, ["status", "profileID", "transactionID", "operationID", "drawOrdinal", "drawRowFingerprint", "gearID"])
            try Self.keys(row, ["drawIndex", "qualityID", "gearTemplateID", "pityBefore", "pityAfter"])
            guard let rawID = item["id"] as? String, let id = UUID(uuidString: rawID),
                  item["ownerID"] is NSNull, item["candidateLatentSlots"] is NSNull,
                  Self.boolean(item["protected"]) == false,
                  Self.integer(item["enhancement"]) == 0, Self.integer(item["refinement"]) == 0,
                  Self.integer(item["investmentDust"]) == 0,
                  let definition = item["definitionID"] as? String, allowedDefinitions.contains(definition),
                  let quality = item["qualityID"] as? String, ["Q0", "Q1", "Q2", "Q3", "Q4"].contains(quality),
                  row["gearTemplateID"] as? String == definition, row["qualityID"] as? String == quality,
                  Self.integer(row["drawIndex"]) == index, Self.integer(source["drawOrdinal"]) == index,
                  source["gearID"] as? String == rawID, source["operationID"] as? String == operationText,
                  source["transactionID"] as? String == transactionID, source["profileID"] as? String == profileID,
                  source["status"] as? String == "LOCAL_TEST_ONLY",
                  source["drawRowFingerprint"] as? String == Self.hash(try Self.canonical(row)),
                  let affixes = item["affixIDs"] as? [String], Set(affixes).count == affixes.count,
                  Set(affixes).isSubset(of: allowedAffixes),
                  item["latentEffectID"] is NSNull || allowedLatents.contains(item["latentEffectID"] as? String ?? "") else {
                throw Self.invalid("gear payload or draw provenance mismatch")
            }
            let before = try Self.pity(row["pityBefore"]), after = try Self.pity(row["pityAfter"])
            guard [before.targetTemplateID, after.targetTemplateID].allSatisfy({ target in target.map { allowedDefinitions.contains($0) } ?? true }) else {
                throw Self.invalid("pity target is outside the current catalog")
            }
            guard previousPity == nil || previousPity == before else { throw Self.invalid("broken pity sequence") }
            if firstPity == nil { firstPity = before }; previousPity = after
            decoded.append(GearInstance(id: id, definitionID: definition, latentEffectID: item["latentEffectID"] as? String,
                                        qualityID: quality, affixIDs: affixes))
        }
        let post = try Self.pity(root["postPityState"])
        guard Set(decoded.map(\.id)).count == decoded.count, let firstPity,
              previousPity == post, try Self.pity(draw["pityAfter"]) == post else { throw Self.invalid("duplicate gear or pity mismatch") }
        return Validated(operationID: operation, receiptFingerprint: fingerprint, items: decoded, pityBefore: firstPity, pityAfter: post)
    }

    private static func pity(_ raw: Any?) throws -> GachaPityState {
        guard let row = raw as? [String: Any] else { throw invalid("pity object missing") }
        try keys(row, ["drawsSinceTop", "drawsSinceMid", "targetTemplateID", "guaranteeTargetOnNextTop"])
        guard let top = integer(row["drawsSinceTop"]), (0...99).contains(top),
              let mid = integer(row["drawsSinceMid"]), (0...19).contains(mid),
              let guarantee = boolean(row["guaranteeTargetOnNextTop"]),
              row["targetTemplateID"] is NSNull || row["targetTemplateID"] is String else { throw invalid("invalid pity fields") }
        return GachaPityState(drawsSinceTop: top, drawsSinceMid: mid, targetTemplateID: row["targetTemplateID"] as? String, guaranteeTargetOnNextTop: guarantee)
    }
    private static func keys(_ object: [String: Any], _ expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw invalid("unexpected or missing fields") }
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let i = Int(n.stringValue) else { return nil }; return i
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }; return n.boolValue
    }
    private static func canonical(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func isHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
    private static func invalid(_ message: String) -> CoreError { .invalidCommand("R453 local purchase delivery: " + message) }
}
