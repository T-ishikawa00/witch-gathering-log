import Foundation
import CoreFoundation
import CryptoKit
import Darwin

fileprivate struct SaveEnvelope {
    var schemaVersion: Int
    var generation: Int64
    var snapshot: GameSnapshot
    var receipts: [UUID: CommandReceipt]
    var sourceData: Data?
    var sourceModelData: Data?
    var recoveryStatus: SaveRecoveryStatus
    var rejectedPrimaryData: Data?
}

private struct PersistedRecoveryNotice: Codable {
    let rejectedPrimaryRevision: Int64?
    let rejectedPrimaryByteCount: Int?
    let preservedRejectedPrimaryFilename: String?
    let possibleRevisionRollback: Int64?
}

public struct SaveRecoveryStatus: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case memory, primary, legacyMigrationPending, previousGeneration }
    public let source: Source
    public let loadedGeneration: Int64
    public let loadedRevision: Int64
    public let rejectedPrimaryRevision: Int64?
    public let rejectedPrimaryByteCount: Int?
    public let preservedRejectedPrimaryFilename: String?
    private let recordedRevisionRollback: Int64?
    public var recoveredPreviousGeneration: Bool { source == .previousGeneration }
    public var possibleRevisionRollback: Int64? {
        if let recordedRevisionRollback { return recordedRevisionRollback }
        guard let rejectedPrimaryRevision else { return nil }
        guard rejectedPrimaryRevision > loadedRevision else { return 0 }
        let (difference, overflow) = rejectedPrimaryRevision.subtractingReportingOverflow(loadedRevision)
        return overflow ? Int64.max : difference
    }

    init(source: Source, loadedGeneration: Int64, loadedRevision: Int64,
         rejectedPrimaryRevision: Int64?, rejectedPrimaryByteCount: Int?, preservedRejectedPrimaryFilename: String?,
         recordedRevisionRollback: Int64? = nil) {
        self.source = source
        self.loadedGeneration = loadedGeneration
        self.loadedRevision = loadedRevision
        self.rejectedPrimaryRevision = rejectedPrimaryRevision
        self.rejectedPrimaryByteCount = rejectedPrimaryByteCount
        self.preservedRejectedPrimaryFilename = preservedRejectedPrimaryFilename
        self.recordedRevisionRollback = recordedRevisionRollback
    }
}

public enum SaveRepositoryError: Error, Equatable {
    case invalidDocument
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
    case unsupportedFutureVersionMarker(path: String, value: Int64)
    case unsafeOpaqueArrayMutation(path: String)
    case noValidRecoveryGeneration
    case injectedWriteFailure(String)
    case commitMayHaveSucceeded(operationID: UUID, revision: Int64)
}

enum SaveWritePhase: String, Sendable {
    case beforeStage, afterStageSync, afterBackupReplace, beforePrimaryReplace, afterPrimaryReplace
}

private struct PersistedSave: Codable {
    var schemaVersion: Int
    var generation: Int64
    var snapshot: GameSnapshot
    var receipts: [UUID: CommandReceipt]
    var recoveryNotice: PersistedRecoveryNotice?
    var integritySHA256: String?

    enum CodingKeys: String, CodingKey { case schemaVersion, generation, snapshot, receipts, recoveryNotice, integritySHA256 }

    init(schemaVersion: Int, generation: Int64, snapshot: GameSnapshot, receipts: [UUID: CommandReceipt],
         recoveryNotice: PersistedRecoveryNotice?, integritySHA256: String?) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.snapshot = snapshot
        self.receipts = receipts
        self.recoveryNotice = recoveryNotice
        self.integritySHA256 = integritySHA256
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        if schemaVersion >= SaveDocumentCodec.currentSchemaVersion {
            generation = try c.decode(Int64.self, forKey: .generation)
        } else {
            generation = try c.decodeIfPresent(Int64.self, forKey: .generation) ?? 0
        }
        snapshot = try c.decode(GameSnapshot.self, forKey: .snapshot)
        if schemaVersion >= SaveDocumentCodec.currentSchemaVersion {
            receipts = try c.decode([UUID: CommandReceipt].self, forKey: .receipts)
        } else {
            receipts = try c.decodeIfPresent([UUID: CommandReceipt].self, forKey: .receipts) ?? [:]
        }
        recoveryNotice = try c.decodeIfPresent(PersistedRecoveryNotice.self, forKey: .recoveryNotice)
        integritySHA256 = try c.decodeIfPresent(String.self, forKey: .integritySHA256)
    }
}

/// Lossless envelope codec. Known fields are regenerated from typed state; opaque fields are
/// recursively merged from the exact prior bytes. Ambiguous unkeyed-array association fails closed.
enum SaveDocumentCodec {
    static let currentSchemaVersion = 1

    struct Decoded {
        fileprivate let envelope: SaveEnvelope
    }

    /// Validate the narrowly supported R144 discriminator before Codable decoding.
    /// Future markers elsewhere remain governed by the generic recursive guard.
    private static func validateR144WorkTargetMarker(_ root: [String: Any]) throws {
        guard let snapshot = root["snapshot"] as? [String: Any],
              let rawTarget = snapshot["partyWorkTargetR144"] else { return }
        let path = "$.snapshot.partyWorkTargetR144"
        guard let target = rawTarget as? [String: Any],
              let version = target["futureVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.intValue == 2,
              let kind = target["kind"] as? String, kind == "gather" || kind == "investigate",
              let targetID = target["targetID"] as? String, !targetID.isEmpty else {
            throw SaveRepositoryError.unsupportedFutureVersionMarker(path: path, value: 2)
        }
    }

    /// R350 owns an exact nested future-version shape; older schema-1 readers reject marker 3.
    /// R352 stores only non-default per-instance ranks in a closed future-version payload.
    private static func validateR352RefinementPayload(_ root: [String: Any]) throws {
        guard let snapshot = root["snapshot"] as? [String: Any], let raw = snapshot["naturalGearRefinementR352"] else { return }
        let path = "$.snapshot.naturalGearRefinementR352"
        func reject() throws -> Never { throw SaveRepositoryError.unsupportedFutureVersionMarker(path: path, value: 4) }
        func exactInt(_ raw: Any?, range: ClosedRange<Int>) -> Int? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite, n.doubleValue.rounded(.towardZero) == n.doubleValue,
                  let value = Int(n.stringValue), range.contains(value) else { return nil }
            return value
        }
        let expected: Set<String> = ["futureVersion", "rankByGearUUID"]
        guard let payload = raw as? [String: Any], Set(payload.keys) == expected,
              exactInt(payload["futureVersion"], range: 4...4) != nil,
              let ranks = payload["rankByGearUUID"] as? [String: Any],
              let gear = snapshot["gear"] as? [[String: Any]] else { try reject() }
        let gearIDs = Set(gear.compactMap { row -> String? in
            guard let rawID = row["id"] as? String, let id = UUID(uuidString: rawID) else { return nil }
            return id.uuidString.lowercased()
        })
        guard gear.count == gearIDs.count else { try reject() }
        for (rawID, rawRank) in ranks {
            guard let uuid = UUID(uuidString: rawID), uuid.uuidString.lowercased() == rawID,
                  gearIDs.contains(rawID), exactInt(rawRank, range: 2...5) != nil else { try reject() }
        }
    }

    private static func validateR350NaturalGearPayload(_ root: [String: Any]) throws {
        guard let snapshot = root["snapshot"] as? [String: Any], let raw = snapshot["naturalGearDiscoveryR350"] else { return }
        let path = "$.snapshot.naturalGearDiscoveryR350"
        func reject() throws -> Never { throw SaveRepositoryError.unsupportedFutureVersionMarker(path: path, value: 3) }
        func exactInt(_ raw: Any?, range: ClosedRange<Int>) -> Int? {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let value = Int(number.stringValue), range.contains(value), number.doubleValue == Double(value) else { return nil }
            return value
        }
        let expected: Set<String> = ["futureVersion", "seedHex", "naturalRollIndex", "missesSinceQ4", "workUnitsIntoDrop", "skipLegacyPartialUnit", "pinnedPool", "discoveredCraftedTemplateIDs", "acquisitionRecords"]
        guard let payload = raw as? [String: Any], Set(payload.keys) == expected,
              exactInt(payload["futureVersion"], range: 3...3) != nil,
              let seed = payload["seedHex"] as? String, seed.count == 64, seed.allSatisfy({ $0.isHexDigit }),
              let index = exactInt(payload["naturalRollIndex"], range: 0...Int.max),
              let misses = exactInt(payload["missesSinceQ4"], range: 0...99),
              let units = exactInt(payload["workUnitsIntoDrop"], range: 0...5),
              let skipRaw = payload["skipLegacyPartialUnit"] as? NSNumber, CFGetTypeID(skipRaw) == CFBooleanGetTypeID(),
              let discovered = payload["discoveredCraftedTemplateIDs"] as? [String], Set(discovered).count == discovered.count,
              let records = payload["acquisitionRecords"] as? [[String: Any]], records.count <= NaturalGearDiscoveryPolicyR350.retainedAcquisitionRecords else { try reject() }
        if units == 0 {
            guard payload["pinnedPool"] is NSNull else { try reject() }
        } else {
            let keys: Set<String> = ["regionID", "sourceRegionRank", "highestUnlockedRegionRank", "localEligibleTemplateIDs", "globalEligibleTemplateIDs", "discoveredTemplateIDs", "joinedActorIDs", "attunementRankByTemplateID", "desiredTemplateID"]
            guard let pool = payload["pinnedPool"] as? [String: Any], Set(pool.keys) == keys,
                  let region = pool["regionID"] as? String, ["R01", "R02", "R03", "R04", "R05"].contains(region),
                  let sourceRank = exactInt(pool["sourceRegionRank"], range: 1...5),
                  let unlockedRank = exactInt(pool["highestUnlockedRegionRank"], range: sourceRank...5),
                  sourceRank == (["R01": 1, "R02": 2, "R03": 3, "R04": 4, "R05": 5][region] ?? -1),
                  ["localEligibleTemplateIDs", "globalEligibleTemplateIDs", "discoveredTemplateIDs", "joinedActorIDs"].allSatisfy({ key in
                      guard let rows = pool[key] as? [String] else { return false }; return Set(rows).count == rows.count
                  }),
                  let globalRows = pool["globalEligibleTemplateIDs"] as? [String], !globalRows.isEmpty,
                  let rawRanks = pool["attunementRankByTemplateID"] as? [String: Any], Set(rawRanks.keys) == Set(globalRows),
                  rawRanks.values.allSatisfy({ exactInt($0, range: 1...min(sourceRank, unlockedRank)) != nil }),
                  (pool["desiredTemplateID"] is NSNull || pool["desiredTemplateID"] is String) else { try reject() }
        }
        let recordIndices = records.compactMap { exactInt($0["naturalRollIndex"], range: 1...Int.max) }
        guard recordIndices.count == records.count, recordIndices == recordIndices.sorted(),
              Set(recordIndices).count == recordIndices.count, recordIndices.allSatisfy({ $0 <= index }) else { try reject() }
        let recordKeys: Set<String> = ["gearInstanceID", "templateID", "sourceRegionID", "attunementRank", "naturalRollIndex", "qualityID", "operationID"]
        for row in records {
            guard Set(row.keys) == recordKeys,
                  let gearID = row["gearInstanceID"] as? String, UUID(uuidString: gearID) != nil,
                  let template = row["templateID"] as? String, !template.isEmpty,
                  let region = row["sourceRegionID"] as? String, ["R01", "R02", "R03", "R04", "R05"].contains(region),
                  exactInt(row["attunementRank"], range: 1...5) != nil,
                  exactInt(row["naturalRollIndex"], range: 1...index) != nil,
                  let quality = row["qualityID"] as? String, ["Q0", "Q1", "Q2", "Q3", "Q4"].contains(quality),
                  let operation = row["operationID"] as? String, UUID(uuidString: operation) != nil else { try reject() }
        }
        _ = misses // range-validated above; retained for explicit schema audit.
    }

    /// R342 owns a closed, exact JSON shape. Reject malformed or unknown nested fields
    /// before Codable can discard them or recovery can select an older generation.
    private static func validateR342GearLoadoutsPayload(_ root: [String: Any]) throws {
        guard let snapshot = root["snapshot"] as? [String: Any],
              let rawPayload = snapshot["gearLoadoutsR342"] else { return }
        let path = "$.snapshot.gearLoadoutsR342"
        func reject() throws -> Never {
            throw SaveRepositoryError.unsupportedFutureVersionMarker(path: path, value: 2)
        }
        guard let payload = rawPayload as? [String: Any],
              Set(payload.keys).isSubset(of: Set(["futureVersion", "first", "second"])),
              let rawVersion = payload["futureVersion"] as? NSNumber,
              CFGetTypeID(rawVersion) != CFBooleanGetTypeID(),
              rawVersion.doubleValue.isFinite, rawVersion.doubleValue == 2,
              payload["first"] != nil || payload["second"] != nil else { try reject() }
        for name in ["first", "second"] {
            guard let rawLoadout = payload[name] else { continue }
            guard let loadout = rawLoadout as? [String: Any],
                  Set(loadout.keys) == Set(["gearByActorSlot"]),
                  let assignments = loadout["gearByActorSlot"] as? [String: Any],
                  !assignments.isEmpty else { try reject() }
            var seen = Set<String>()
            for (key, value) in assignments {
                let parts = key.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
                      let uuidText = value as? String, UUID(uuidString: uuidText) != nil,
                      seen.insert(uuidText.lowercased()).inserted else { try reject() }
            }
        }
    }

    static func decode(_ data: Data) throws -> Decoded {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw SaveRepositoryError.invalidDocument }
        guard let rawObject = raw as? [String: Any] else { throw SaveRepositoryError.invalidDocument }
        let declaredVersion: Int
        if let value = rawObject["schemaVersion"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue > Double(Int64.min), number.doubleValue < Double(Int64.max),
                  let parsed = Int(exactly: number.int64Value) else { throw SaveRepositoryError.invalidSchemaVersion(-1) }
            declaredVersion = parsed
        } else {
            declaredVersion = 0
        }
        guard declaredVersion >= 0 else { throw SaveRepositoryError.invalidSchemaVersion(declaredVersion) }
        guard declaredVersion <= currentSchemaVersion else { throw SaveRepositoryError.unsupportedFutureSchemaVersion(declaredVersion) }

        try validateR342GearLoadoutsPayload(rawObject)
        try validateR350NaturalGearPayload(rawObject)
        try validateR352RefinementPayload(rawObject)
        try rejectFutureVersionMarkers(raw: raw, path: "$", schema: currentSchemaVersion)
        try validateR144WorkTargetMarker(rawObject)
        if declaredVersion == currentSchemaVersion {
            try validateCurrentSchema(rawObject)
        }
        let value: PersistedSave
        do { value = try JSONDecoder().decode(PersistedSave.self, from: data) }
        catch { throw SaveRepositoryError.invalidDocument }
        guard value.generation >= 0, value.snapshot.revision >= 0 else { throw SaveRepositoryError.invalidDocument }
        do { try value.snapshot.commerceOwnershipR1?.validate() }
        catch { throw SaveRepositoryError.invalidDocument }
        guard value.receipts.allSatisfy({ pair in
            let (key, receipt) = pair
            return key == receipt.operationID && receipt.revision > 0 && receipt.revision <= value.snapshot.revision
        }) else { throw SaveRepositoryError.invalidDocument }

        let modeledData = try JSONEncoder().encode(value)
        let status = SaveRecoveryStatus(source: declaredVersion == 0 ? .legacyMigrationPending : .primary,
                                       loadedGeneration: value.generation,
                                       loadedRevision: value.snapshot.revision,
                                       rejectedPrimaryRevision: value.recoveryNotice?.rejectedPrimaryRevision,
                                       rejectedPrimaryByteCount: value.recoveryNotice?.rejectedPrimaryByteCount,
                                       preservedRejectedPrimaryFilename: value.recoveryNotice?.preservedRejectedPrimaryFilename,
                                       recordedRevisionRollback: value.recoveryNotice?.possibleRevisionRollback)
        return Decoded(envelope: SaveEnvelope(schemaVersion: currentSchemaVersion,
                                              generation: value.generation,
                                              snapshot: value.snapshot,
                                              receipts: value.receipts,
                                              sourceData: data,
                                              sourceModelData: modeledData,
                                              recoveryStatus: status,
                                              rejectedPrimaryData: nil))
    }

    static func encode(snapshot: GameSnapshot, receipts: [UUID: CommandReceipt], generation: Int64,
                       recoveryStatus: SaveRecoveryStatus,
                       preserving priorData: Data?, priorModelledData: Data?) throws -> (data: Data, modelData: Data) {
        let notice: PersistedRecoveryNotice? = (recoveryStatus.rejectedPrimaryRevision != nil ||
            recoveryStatus.rejectedPrimaryByteCount != nil || recoveryStatus.preservedRejectedPrimaryFilename != nil)
            ? PersistedRecoveryNotice(rejectedPrimaryRevision: recoveryStatus.rejectedPrimaryRevision,
                                      rejectedPrimaryByteCount: recoveryStatus.rejectedPrimaryByteCount,
                                      preservedRejectedPrimaryFilename: recoveryStatus.preservedRejectedPrimaryFilename,
                                      possibleRevisionRollback: recoveryStatus.possibleRevisionRollback)
            : nil
        let value = PersistedSave(schemaVersion: currentSchemaVersion, generation: generation,
                                  snapshot: snapshot, receipts: receipts, recoveryNotice: notice,
                                  integritySHA256: nil)
        let typedData = try JSONEncoder().encode(value)
        let typed = try JSONSerialization.jsonObject(with: typedData, options: [.fragmentsAllowed])
        let merged: Any
        if let priorData {
            guard let priorModelledData else { throw SaveRepositoryError.invalidDocument }
            let prior = try JSONSerialization.jsonObject(with: priorData, options: [.fragmentsAllowed])
            let priorModelled = try JSONSerialization.jsonObject(with: priorModelledData, options: [.fragmentsAllowed])
            merged = try mergeOpaque(prior: prior, priorModelled: priorModelled, modeled: typed, path: "$")
        } else {
            merged = typed
        }
        guard var finalObject = merged as? [String: Any] else { throw SaveRepositoryError.invalidDocument }
        finalObject.removeValue(forKey: "integritySHA256")
        let checksum = try checksum(for: finalObject)
        finalObject["integritySHA256"] = checksum
        var modeledValue = value
        modeledValue.integritySHA256 = checksum
        let modelData = try JSONEncoder().encode(modeledValue)
        return (try JSONSerialization.data(withJSONObject: finalObject, options: [.sortedKeys, .fragmentsAllowed]), modelData)
    }

    static func checksum(for object: [String: Any]) throws -> String {
        var payload = object
        payload.removeValue(forKey: "integritySHA256")
        let canonical = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .fragmentsAllowed])
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateCurrentSchema(_ object: [String: Any]) throws {
        guard let snapshot = object["snapshot"] as? [String: Any] else { throw SaveRepositoryError.invalidDocument }
        let requiredEnvelopeKeys: Set<String> = ["generation", "snapshot", "receipts"]
        guard requiredEnvelopeKeys.isSubset(of: Set(object.keys)) else { throw SaveRepositoryError.invalidDocument }
        let requiredSnapshotKeys: Set<String> = [
            "revision", "currency", "materials", "characterXP", "gear", "unlockedRegionIDs",
            "completedResearchIDs", "equippedGearIDs", "ownedCosmeticIDs", "selectedCosmeticIDs",
            "selectedWeaponAppearanceIDs", "ownedFurnitureIDs", "placedFurnitureIDs", "offlineRemainderSeconds",
            "pendingPurchaseIDs", "partyActorIDs", "completedEncounterIDs", "craftedGearOnce",
            "gearComparisonSeen", "gachaUnlocked", "gachaPity", "mockPurchaseRecords",
            "localStoreKitQARecords", "localStoreKitQAOwnedProductIDs", "localAdSkipEntitledForQA",
            "localAdWorkBlockSeconds", "localAdWorkBlockXPByActor", "localAdWorkBlockDust",
            "localAdXPFractionalCarry", "localAdDustFractionalCarry", "localAdNextOpportunitySequence",
            "localAdRewardOpportunities", "localAdAttemptRecords"
        ]
        guard requiredSnapshotKeys.isSubset(of: Set(snapshot.keys)) else { throw SaveRepositoryError.invalidDocument }
        guard requiredSnapshotKeys.allSatisfy({ !(snapshot[$0] is NSNull) }) else {
            throw SaveRepositoryError.invalidDocument
        }
        // Legacy saves omit this field. Once a provenance ledger is present,
        // null must not silently turn purchased ownership into legacy free rights.
        if let commerce = snapshot["commerceOwnershipR1"], !(commerce is [String: Any]) {
            throw SaveRepositoryError.invalidDocument
        }
        guard let recordedChecksum = object["integritySHA256"] as? String, recordedChecksum.count == 64,
              recordedChecksum.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              try checksum(for: object) == recordedChecksum else { throw SaveRepositoryError.invalidDocument }
    }

    private static func rejectFutureVersionMarkers(raw: Any, path: String, schema: Int) throws {
        if let rawObject = raw as? [String: Any] {
            for (key, rawValue) in rawObject {
                let childPath = path + "." + key
                let isKnownVersionMarker = key == "futureVersion" || key == "schemaVersion" ||
                    (key == "version" && path.components(separatedBy: ".").contains("candidateLatentSlots"))
                if isKnownVersionMarker {
                    guard let number = rawValue as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(),
                          number.doubleValue.isFinite,
                          number.doubleValue.rounded(.towardZero) == number.doubleValue,
                          number.doubleValue > Double(Int64.min), number.doubleValue < Double(Int64.max) else {
                        throw SaveRepositoryError.invalidSchemaVersion(-1)
                    }
                    let marker = number.int64Value
                    guard marker >= 0 else { throw SaveRepositoryError.invalidSchemaVersion(Int(marker)) }
                    let r144CandidateTarget = childPath == "$.snapshot.partyWorkTargetR144.futureVersion" && marker == 2
                    let r342GearLoadouts = childPath == "$.snapshot.gearLoadoutsR342.futureVersion" && marker == 2
                    let r350NaturalGear = childPath == "$.snapshot.naturalGearDiscoveryR350.futureVersion" && marker == 3
                    let r352Refinement = childPath == "$.snapshot.naturalGearRefinementR352.futureVersion" && marker == 4
                    if marker > Int64(schema) && !r144CandidateTarget && !r342GearLoadouts && !r350NaturalGear && !r352Refinement {
                        throw SaveRepositoryError.unsupportedFutureVersionMarker(path: childPath, value: marker)
                    }
                }
                try rejectFutureVersionMarkers(raw: rawValue, path: childPath, schema: schema)
            }
        } else if let rawArray = raw as? [Any] {
            for (index, value) in rawArray.enumerated() {
                try rejectFutureVersionMarkers(raw: value, path: path + "[\(index)]", schema: schema)
            }
        }
    }

    static func mergeOpaque(prior: Any, priorModelled: Any, modeled: Any, path: String) throws -> Any {
        if let old = prior as? [String: Any], let new = modeled as? [String: Any] {
            let oldKnown = priorModelled as? [String: Any] ?? [:]
            var result = new
            for (key, oldValue) in old {
                guard let oldKnownValue = oldKnown[key] else {
                    if new[key] == nil { result[key] = oldValue }
                    continue
                }
                if let newValue = new[key] {
                    result[key] = try mergeOpaque(prior: oldValue, priorModelled: oldKnownValue,
                                                  modeled: newValue, path: path + "." + key)
                }
            }
            return result
        }

        if let old = prior as? [Any], let oldKnown = priorModelled as? [Any], let new = modeled as? [Any] {
            if let oldByID = indexedObjectsByID(old), let knownByID = indexedObjectsByID(oldKnown),
               let newByID = indexedObjectsByID(new) {
                return try new.map { item in
                    guard let object = item as? [String: Any], let id = stableID(object),
                          newByID[id] != nil, let oldItem = oldByID[id], let knownItem = knownByID[id] else { return item }
                    return try mergeOpaque(prior: oldItem, priorModelled: knownItem, modeled: item,
                                           path: path + "[id:\(id)]")
                }
            }
            let oldHasOpaque = old.count != oldKnown.count ||
                zip(old, oldKnown).contains(where: { hasOpaque(prior: $0.0, modeled: $0.1) })
            if oldHasOpaque {
                guard old.count == oldKnown.count, oldKnown.count == new.count,
                      zip(oldKnown, new).allSatisfy({ knownFieldsMatch(prior: $0.0, modeled: $0.1) }) else {
                    throw SaveRepositoryError.unsafeOpaqueArrayMutation(path: path)
                }
                return try zip(old, zip(oldKnown, new)).enumerated().map { index, pair in
                    try mergeOpaque(prior: pair.0, priorModelled: pair.1.0, modeled: pair.1.1,
                                    path: path + "[\(index)]")
                }
            }
            return new
        }
        return modeled
    }

    private static func indexedObjectsByID(_ values: [Any]) -> [String: [String: Any]]? {
        var result: [String: [String: Any]] = [:]
        for value in values {
            guard let object = value as? [String: Any], let id = stableID(object), result[id] == nil else { return nil }
            result[id] = object
        }
        return result
    }

    private static func stableID(_ object: [String: Any]) -> String? {
        guard let value = object["id"] else { return nil }
        if let text = value as? String {
            // JSONEncoder/JSONDecoder may emit equivalent UUIDs with different casing.
            // Match identity by UUID value so opaque fields follow the same item.
            if let uuid = UUID(uuidString: text) { return uuid.uuidString.lowercased() }
            return text
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func hasOpaque(prior: Any, modeled: Any) -> Bool {
        if let old = prior as? [String: Any] {
            guard let new = modeled as? [String: Any] else { return !old.isEmpty }
            for (key, value) in old {
                guard let newValue = new[key] else { return true }
                if hasOpaque(prior: value, modeled: newValue) { return true }
            }
            return false
        } else if let old = prior as? [Any] {
            guard let new = modeled as? [Any], old.count == new.count else { return !old.isEmpty }
            for index in old.indices where hasOpaque(prior: old[index], modeled: new[index]) { return true }
            return false
        }
        return false
    }

    /// For an unkeyed array, positional preservation is defensible only when every modeled
    /// value still matches at the same position. Any reorder or known-field mutation with
    /// opaque descendants fails closed instead of transferring extension data.
    private static func knownFieldsMatch(prior: Any, modeled: Any) -> Bool {
        if let old = prior as? [String: Any], let new = modeled as? [String: Any] {
            return new.allSatisfy { entry in
                let (key, value) = entry
                guard let oldValue = old[key] else { return false }
                return knownFieldsMatch(prior: oldValue, modeled: value)
            }
        }
        if let old = prior as? [Any], let new = modeled as? [Any] {
            return old.count == new.count && zip(old, new).allSatisfy {
                knownFieldsMatch(prior: $0.0, modeled: $0.1)
            }
        }
        return (prior as? NSObject)?.isEqual(modeled) ?? false
    }
}

/// Serializes mutations and persists versioned generations using a recoverable atomic replacement.
public actor SaveRepository {
    private let url: URL?
    private let faultInjector: (@Sendable (SaveWritePhase) throws -> Void)?
    private var envelope: SaveEnvelope

    public init(initial: GameSnapshot = GameSnapshot(), fileURL: URL? = nil) throws {
        self.url = fileURL
        self.faultInjector = nil
        if let fileURL {
            self.envelope = try Self.load(fileURL: fileURL, initial: initial)
        } else {
            self.envelope = Self.memoryEnvelope(initial)
        }
    }

    init(initial: GameSnapshot = GameSnapshot(), fileURL: URL?,
         faultInjector: (@Sendable (SaveWritePhase) throws -> Void)?) throws {
        self.url = fileURL
        self.faultInjector = faultInjector
        if let fileURL {
            self.envelope = try Self.load(fileURL: fileURL, initial: initial)
        } else {
            self.envelope = Self.memoryEnvelope(initial)
        }
    }

    public func snapshot() -> GameSnapshot { envelope.snapshot }
    public func receipt(for operationID: UUID) -> CommandReceipt? { envelope.receipts[operationID] }
    public func recoveryStatus() -> SaveRecoveryStatus { envelope.recoveryStatus }

    /// Resolve a post-replacement error without replaying its mutation. Require
    /// the exact receipt in the PRIMARY, then retry the directory durability
    /// barrier before acknowledging it. A backup generation cannot confirm it.
    public func confirmCommittedReceipt(operationID: UUID, revision: Int64) throws -> CommandReceipt {
        let unresolved=SaveRepositoryError.commitMayHaveSucceeded(operationID:operationID,revision:revision)
        guard let url else {
            guard let receipt=envelope.receipts[operationID],receipt.revision == revision else {throw unresolved}
            return receipt
        }
        do {
            return try withFileLock(url) {
                var primary=try Self.loadPrimaryOnly(fileURL:url)
                guard let receipt=primary.receipts[operationID],receipt.revision == revision,
                      receipt == envelope.receipts[operationID] else {throw unresolved}
                try Self.syncDirectory(url.deletingLastPathComponent())
                primary.recoveryStatus=envelope.recoveryStatus
                envelope=primary
                return receipt
            }
        } catch {throw unresolved}
    }

    public func transact(expectedRevision: Int64, operationID: UUID, requestFingerprint: String? = nil,
                         mutation: @Sendable (inout GameSnapshot) throws -> String) throws -> CommandReceipt {
        if let url {
            return try withFileLock(url) {
                envelope = try Self.load(fileURL: url, initial: envelope.snapshot)
                return try apply(expectedRevision: expectedRevision, operationID: operationID,
                                 requestFingerprint: requestFingerprint, mutation: mutation)
            }
        }
        return try apply(expectedRevision: expectedRevision, operationID: operationID,
                         requestFingerprint: requestFingerprint, mutation: mutation)
    }

    private func apply(expectedRevision: Int64, operationID: UUID, requestFingerprint: String?,
                       mutation: @Sendable (inout GameSnapshot) throws -> String) throws -> CommandReceipt {
        if let receipt = envelope.receipts[operationID] {
            guard receipt.requestFingerprint == requestFingerprint else { throw CoreError.duplicateOperation }
            return receipt
        }
        guard envelope.snapshot.revision == expectedRevision else {
            throw CoreError.revisionConflict(expected: expectedRevision, actual: envelope.snapshot.revision)
        }
        guard envelope.snapshot.revision >= 0, envelope.snapshot.revision < Int64.max,
              envelope.generation >= 0, envelope.generation < Int64.max else {
            throw CoreError.invalidCommand("save revision or generation is outside the writable range")
        }

        var candidate = envelope.snapshot
        let result = try mutation(&candidate)
        candidate.revision = envelope.snapshot.revision + 1
        let receipt = CommandReceipt(operationID: operationID, revision: candidate.revision,
                                     result: result, requestFingerprint: requestFingerprint)
        var next = envelope
        next.schemaVersion = SaveDocumentCodec.currentSchemaVersion
        next.generation = envelope.generation + 1
        next.snapshot = candidate
        next.receipts[operationID] = receipt
        do {
            try persist(&next)
            envelope = next
        } catch {
            if let url, let latest = try? Self.loadPrimaryOnly(fileURL: url),
               latest.receipts[operationID] == receipt {
                var committed = latest
                committed.recoveryStatus = next.recoveryStatus
                envelope = committed
                throw SaveRepositoryError.commitMayHaveSucceeded(operationID: operationID, revision: receipt.revision)
            }
            throw error
        }
        return receipt
    }

    private func withFileLock<T>(_ url: URL, operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CoreError.invalidCommand("cannot open save lock") }
        guard flock(descriptor, LOCK_EX) == 0 else { close(descriptor); throw CoreError.invalidCommand("cannot lock save file") }
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        return try operation()
    }

    private func persist(_ value: inout SaveEnvelope) throws {
        guard let url else { return }
        let rejectedArchiveURL: URL? = value.rejectedPrimaryData.map { _ in
            url.deletingLastPathComponent().appendingPathComponent(
                url.lastPathComponent + ".corrupt-\(UUID().uuidString)")
        }
        if let damaged = value.rejectedPrimaryData {
            value.recoveryStatus = SaveRecoveryStatus(source: .primary,
                loadedGeneration: value.generation, loadedRevision: value.snapshot.revision,
                rejectedPrimaryRevision: value.recoveryStatus.rejectedPrimaryRevision,
                rejectedPrimaryByteCount: damaged.count,
                preservedRejectedPrimaryFilename: rejectedArchiveURL?.lastPathComponent,
                recordedRevisionRollback: value.recoveryStatus.possibleRevisionRollback)
        }
        let encoded = try SaveDocumentCodec.encode(snapshot: value.snapshot, receipts: value.receipts,
            generation: value.generation, recoveryStatus: value.recoveryStatus,
            preserving: value.sourceData, priorModelledData: value.sourceModelData)
        let newData = encoded.data
        try faultInjector?(.beforeStage)
        let stagedURL = url.deletingLastPathComponent().appendingPathComponent(".save-stage-\(UUID().uuidString)")
        var staged = false
        do {
            try Self.writeExclusive(newData, to: stagedURL)
            staged = true
            try faultInjector?(.afterStageSync)
            let verified = try SaveDocumentCodec.decode(Data(contentsOf: stagedURL))
            guard verified.envelope.generation == value.generation,
                  verified.envelope.snapshot == value.snapshot,
                  verified.envelope.receipts == value.receipts else { throw SaveRepositoryError.invalidDocument }

            if let prior = value.sourceData, !value.recoveryStatus.recoveredPreviousGeneration {
                _ = try SaveDocumentCodec.decode(prior)
                let backupURL = Self.previousURL(for: url)
                let backupStage = url.deletingLastPathComponent().appendingPathComponent(".save-backup-stage-\(UUID().uuidString)")
                try Self.writeExclusive(prior, to: backupStage)
                guard Self.renameReplacing(backupStage, backupURL) else {
                    throw CoreError.invalidCommand("cannot replace previous save generation")
                }
                try Self.syncDirectory(url.deletingLastPathComponent())
                try faultInjector?(.afterBackupReplace)
            }

            if let damaged = value.rejectedPrimaryData {
                guard let rejectedArchiveURL else { throw SaveRepositoryError.invalidDocument }
                try Self.writeExclusive(damaged, to: rejectedArchiveURL)
            }
            try faultInjector?(.beforePrimaryReplace)
            guard Self.renameReplacing(stagedURL, url) else { throw CoreError.invalidCommand("cannot atomically replace save") }
            staged = false
            try faultInjector?(.afterPrimaryReplace)
            try Self.syncDirectory(url.deletingLastPathComponent())
        } catch {
            if staged { try? FileManager.default.removeItem(at: stagedURL) }
            throw error
        }
        value.sourceData = newData
        value.sourceModelData = encoded.modelData
        value.rejectedPrimaryData = nil
    }

    private static func memoryEnvelope(_ snapshot: GameSnapshot) -> SaveEnvelope {
        SaveEnvelope(schemaVersion: SaveDocumentCodec.currentSchemaVersion, generation: 0,
                     snapshot: snapshot, receipts: [:], sourceData: nil, sourceModelData: nil,
                     recoveryStatus: SaveRecoveryStatus(source: .memory, loadedGeneration: 0,
                        loadedRevision: snapshot.revision, rejectedPrimaryRevision: nil,
                        rejectedPrimaryByteCount: nil, preservedRejectedPrimaryFilename: nil),
                     rejectedPrimaryData: nil)
    }

    private static func load(fileURL: URL, initial: GameSnapshot) throws -> SaveEnvelope {
        let manager = FileManager.default
        let primaryExists = manager.fileExists(atPath: fileURL.path)
        if primaryExists {
            let primaryData = try Data(contentsOf: fileURL)
            do { return try SaveDocumentCodec.decode(primaryData).envelope }
            catch let error as SaveRepositoryError {
                switch error {
                case .invalidSchemaVersion, .unsupportedFutureSchemaVersion, .unsupportedFutureVersionMarker:
                    throw error // Never roll back a recognized newer semantic version.
                default:
                    return try recover(primaryError: error, primaryData: primaryData, fileURL: fileURL)
                }
            } catch {
                return try recover(primaryError: error, primaryData: primaryData, fileURL: fileURL)
            }
        }
        let backupURL = previousURL(for: fileURL)
        if manager.fileExists(atPath: backupURL.path) {
            let backupData = try Data(contentsOf: backupURL)
            let decoded = try SaveDocumentCodec.decode(backupData).envelope
            return recovered(decoded, primaryData: nil, fileURL: fileURL, primaryRevision: nil)
        }
        return memoryEnvelope(initial)
    }

    private static func loadPrimaryOnly(fileURL: URL) throws -> SaveEnvelope {
        try SaveDocumentCodec.decode(Data(contentsOf: fileURL)).envelope
    }

    private static func recover(primaryError: Error, primaryData: Data?, fileURL: URL) throws -> SaveEnvelope {
        let backupURL = previousURL(for: fileURL)
        guard FileManager.default.fileExists(atPath: backupURL.path) else { throw primaryError }
        let backupData = try Data(contentsOf: backupURL)
        do {
            let decoded = try SaveDocumentCodec.decode(backupData).envelope
            return recovered(decoded, primaryData: primaryData, fileURL: fileURL,
                             primaryRevision: readableRevision(primaryData))
        } catch let error as SaveRepositoryError {
            switch error {
            case .invalidSchemaVersion, .unsupportedFutureSchemaVersion, .unsupportedFutureVersionMarker:
                throw error
            default:
                throw SaveRepositoryError.noValidRecoveryGeneration
            }
        } catch {
            throw SaveRepositoryError.noValidRecoveryGeneration
        }
    }

    private static func recovered(_ envelope: SaveEnvelope, primaryData: Data?, fileURL: URL,
                                  primaryRevision: Int64?) -> SaveEnvelope {
        var result = envelope
        result.recoveryStatus = SaveRecoveryStatus(source: .previousGeneration,
            loadedGeneration: envelope.generation, loadedRevision: envelope.snapshot.revision,
            rejectedPrimaryRevision: primaryRevision, rejectedPrimaryByteCount: primaryData?.count,
            preservedRejectedPrimaryFilename: nil)
        result.rejectedPrimaryData = primaryData
        return result
    }

    private static func readableRevision(_ data: Data?) -> Int64? {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshot = root["snapshot"] as? [String: Any], let number = snapshot["revision"] as? NSNumber else { return nil }
        return number.int64Value
    }

    private static func previousURL(for url: URL) -> URL { url.appendingPathExtension("previous") }

    private static func writeExclusive(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CoreError.invalidCommand("cannot create save staging file") }
        var keepFile = false
        defer { close(descriptor); if !keepFile { try? FileManager.default.removeItem(at: url) } }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    throw CoreError.invalidCommand("cannot write save staging file")
                }
                guard result > 0 else { throw CoreError.invalidCommand("save staging write made no progress") }
                offset += result
            }
        }
        guard fsync(descriptor) == 0 else { throw CoreError.invalidCommand("cannot sync save staging file") }
        keepFile = true
    }

    private static func renameReplacing(_ source: URL, _ destination: URL) -> Bool {
        source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in Darwin.rename(sourcePath, destinationPath) == 0 }
        }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw CoreError.invalidCommand("cannot open save directory for sync") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw CoreError.invalidCommand("cannot sync save directory") }
    }

}
