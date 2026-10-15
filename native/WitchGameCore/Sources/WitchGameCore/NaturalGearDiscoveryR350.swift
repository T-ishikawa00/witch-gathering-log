import CryptoKit
import Foundation

/// Candidate-only interpretation of economy_R3.json. Numeric choices remain unapproved.
public struct NaturalGearDiscoveryPolicyR350: Sendable, Equatable {
    public static let policyID = "natural-gear-r350-shared-party-clock"
    public static let sourceSHA256 = "b8ae30f04cf3077f4e8dabe0c575f6d02e43502642c36015201d750e41c03476"
    public static let workSeconds = 300
    public static let workUnitsPerDrop = 6
    public static let unattendedCapSeconds = 172_800
    public static let inventorySafetyCeiling = 50_000
    public static let retainedAcquisitionRecords = 96 // maximum drops in the R144 48-hour cap
    public static let legendaryPityRolls = 100
    public static let localPoolBasisPoints = 6_000
    public static let globalPoolBasisPoints = 4_000
    public static let baseQualityWeights: [(String, Int)] = [("Q0", 4500), ("Q1", 3000), ("Q2", 1800), ("Q3", 600), ("Q4", 100)]
    public static let regionRanks = ["R01": 1, "R02": 2, "R03": 3, "R04": 4, "R05": 5]
    public static let regionPools: [String: [String]] = [
        "R01": ["EQ_W_01", "EQ_F_01", "EQ_A_01", "EQ_S_01", "EQ_BODY_01", "EQ_HAND_01", "EQ_FEET_01", "EQ_AMU_01", "EQ_RING_01", "EQ_W_G1", "EQ_F_BODY_01", "EQ_F_HAND_01", "EQ_F_FEET_01", "EQ_F_RING_01"],
        "R02": ["EQ_W_P1", "EQ_A_02", "EQ_F_02", "EQ_BODY_02", "EQ_AMU_02"],
        "R03": ["EQ_S_02", "EQ_HAND_02", "EQ_FEET_02", "EQ_RING_02"],
        "R04": ["EQ_BODY_03", "EQ_FEET_03", "EQ_RING_03"],
        "R05": ["EQ_W_P2", "EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03", "EQ_HAND_03", "EQ_AMU_03"]
    ]
    public let policyFingerprint: String
    public init() {
        let canonical = "schema=natural-gear-r350-v1\nsourceSHA256=\(Self.sourceSHA256)\npolicyID=\(Self.policyID)\nworkSeconds=300\nworkUnitsPerDrop=6\ncap=172800\nlocalBP=6000\nglobalBP=4000\nquality=Q0:4500,Q1:3000,Q2:1800,Q3:600,Q4:100\n"
        self.policyFingerprint = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Context is frozen on the first completed shared R144 five-minute unit in a six-unit period.
public struct NaturalGearPoolSnapshotR350: Codable, Sendable, Equatable {
    public let regionID: String
    public let sourceRegionRank: Int
    public let highestUnlockedRegionRank: Int
    public let localEligibleTemplateIDs: [String]
    public let globalEligibleTemplateIDs: [String]
    public let discoveredTemplateIDs: [String]
    public let joinedActorIDs: [String]
    public let attunementRankByTemplateID: [String: Int]
    public let desiredTemplateID: String?
    private enum CodingKeys: String, CodingKey {
        case regionID, sourceRegionRank, highestUnlockedRegionRank, localEligibleTemplateIDs
        case globalEligibleTemplateIDs, discoveredTemplateIDs, joinedActorIDs
        case attunementRankByTemplateID, desiredTemplateID
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(regionID, forKey: .regionID)
        try c.encode(sourceRegionRank, forKey: .sourceRegionRank)
        try c.encode(highestUnlockedRegionRank, forKey: .highestUnlockedRegionRank)
        try c.encode(localEligibleTemplateIDs, forKey: .localEligibleTemplateIDs)
        try c.encode(globalEligibleTemplateIDs, forKey: .globalEligibleTemplateIDs)
        try c.encode(discoveredTemplateIDs, forKey: .discoveredTemplateIDs)
        try c.encode(joinedActorIDs, forKey: .joinedActorIDs)
        try c.encode(attunementRankByTemplateID, forKey: .attunementRankByTemplateID)
        if let desiredTemplateID { try c.encode(desiredTemplateID, forKey: .desiredTemplateID) }
        else { try c.encodeNil(forKey: .desiredTemplateID) }
    }
    public init(regionID: String, sourceRegionRank: Int, highestUnlockedRegionRank: Int, local: [String], global: [String], discovered: [String], actors: [String], attunementRanks: [String: Int], desiredTemplateID: String?) {
        self.regionID = regionID
        self.sourceRegionRank = sourceRegionRank
        self.highestUnlockedRegionRank = highestUnlockedRegionRank
        self.localEligibleTemplateIDs = Array(Set(local)).sorted()
        self.globalEligibleTemplateIDs = Array(Set(global)).sorted()
        self.discoveredTemplateIDs = Array(Set(discovered)).sorted()
        self.joinedActorIDs = Array(Set(actors)).sorted()
        self.attunementRankByTemplateID = attunementRanks
        self.desiredTemplateID = desiredTemplateID
    }
}

public struct NaturalGearAcquisitionRecordR350: Codable, Sendable, Equatable {
    public let gearInstanceID: UUID
    public let templateID: String
    public let sourceRegionID: String
    public let attunementRank: Int
    public let naturalRollIndex: Int
    public let qualityID: String
    public let operationID: UUID
}

/// Roll counters, pinned context, and UUID provenance commit atomically with R144 settlement.
/// The unresolved rule for a player-selected "desired template" is deliberately not inferred here.
public struct NaturalGearDiscoveryLedgerR350: Codable, Sendable, Equatable {
    public let futureVersion: Int
    public let seedHex: String
    public var naturalRollIndex: Int
    public var missesSinceQ4: Int
    public var workUnitsIntoDrop: Int
    public var skipLegacyPartialUnit: Bool
    public var pinnedPool: NaturalGearPoolSnapshotR350?
    public var discoveredCraftedTemplateIDs: Set<String>
    public var acquisitionRecords: [NaturalGearAcquisitionRecordR350]

    public init(seedHex: String, skipLegacyPartialUnit: Bool = false) {
        self.futureVersion = 3; self.seedHex = seedHex
        self.naturalRollIndex = 0; self.missesSinceQ4 = 0; self.workUnitsIntoDrop = 0; self.skipLegacyPartialUnit = skipLegacyPartialUnit
        self.pinnedPool = nil; self.discoveredCraftedTemplateIDs = []; self.acquisitionRecords = []
    }
    private enum CodingKeys: String, CodingKey {
        case futureVersion, seedHex, naturalRollIndex, missesSinceQ4, workUnitsIntoDrop, skipLegacyPartialUnit
        case pinnedPool, discoveredCraftedTemplateIDs, acquisitionRecords
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(futureVersion, forKey: .futureVersion)
        try c.encode(seedHex, forKey: .seedHex)
        try c.encode(naturalRollIndex, forKey: .naturalRollIndex)
        try c.encode(missesSinceQ4, forKey: .missesSinceQ4)
        try c.encode(workUnitsIntoDrop, forKey: .workUnitsIntoDrop)
        try c.encode(skipLegacyPartialUnit, forKey: .skipLegacyPartialUnit)
        if let pinnedPool { try c.encode(pinnedPool, forKey: .pinnedPool) } else { try c.encodeNil(forKey: .pinnedPool) }
        try c.encode(discoveredCraftedTemplateIDs, forKey: .discoveredCraftedTemplateIDs)
        try c.encode(acquisitionRecords, forKey: .acquisitionRecords)
    }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: R350DynamicCodingKey.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let keys = Set(raw.allKeys.map(\.stringValue))
        let expected: Set<String> = ["futureVersion", "seedHex", "naturalRollIndex", "missesSinceQ4", "workUnitsIntoDrop", "skipLegacyPartialUnit", "pinnedPool", "discoveredCraftedTemplateIDs", "acquisitionRecords"]
        guard keys == expected else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "R350 ledger has unknown or missing fields")) }
        let version = try c.decode(Int.self, forKey: .futureVersion)
        let seed = try c.decode(String.self, forKey: .seedHex)
        let index = try c.decode(Int.self, forKey: .naturalRollIndex)
        let misses = try c.decode(Int.self, forKey: .missesSinceQ4)
        let units = try c.decode(Int.self, forKey: .workUnitsIntoDrop)
        let skipLegacy = try c.decode(Bool.self, forKey: .skipLegacyPartialUnit)
        let pool = try c.decodeIfPresent(NaturalGearPoolSnapshotR350.self, forKey: .pinnedPool)
        let discovered = try c.decode(Set<String>.self, forKey: .discoveredCraftedTemplateIDs)
        let records = try c.decode([NaturalGearAcquisitionRecordR350].self, forKey: .acquisitionRecords)
        guard version == 3, seed.count == 64, seed.allSatisfy(\.isHexDigit), index >= 0,
              (0...99).contains(misses), (0..<6).contains(units), (units == 0) == (pool == nil),
              records.count <= NaturalGearDiscoveryPolicyR350.retainedAcquisitionRecords,
              records.map(\.naturalRollIndex) == records.map(\.naturalRollIndex).sorted(),
              Set(records.map(\.naturalRollIndex)).count == records.count,
              records.allSatisfy({ $0.naturalRollIndex > 0 && $0.naturalRollIndex <= index }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "R350 ledger values violate the closed ranges"))
        }
        self.futureVersion = version; self.seedHex = seed.lowercased(); self.naturalRollIndex = index
        self.missesSinceQ4 = misses; self.workUnitsIntoDrop = units; self.skipLegacyPartialUnit = skipLegacy; self.pinnedPool = pool
        self.discoveredCraftedTemplateIDs = discovered; self.acquisitionRecords = records
    }
}

private struct R350DynamicCodingKey: CodingKey {
    let stringValue: String; let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

enum NaturalGearCounterRandomR350 {
    static func seed(operationID: UUID) -> String { digestHex("witch-natural-gear-r350/seed/v1|\(operationID.uuidString.lowercased())") }
    static func bounded(seed: String, index: Int, domain: String, upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let hex = digestHex("witch-natural-gear-r350/draw/v1|\(seed)|\(index)|\(domain)")
        let prefix = String(hex.prefix(16))
        let value = UInt64(prefix, radix: 16) ?? 0
        return Int(value % UInt64(upperBound))
    }
    static func uuid(seed: String, index: Int, templateID: String) -> UUID {
        let hex = digestHex("witch-natural-gear-r350/gear-uuid/v1|\(seed)|\(index)|\(templateID)")
        var bytes: [UInt8] = []
        for offset in stride(from: 0, to: 32, by: 2) {
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            if let byte = UInt8(hex[start..<end], radix: 16) { bytes.append(byte) }
        }
        guard bytes.count == 16 else { preconditionFailure("SHA256 UUID material must contain 16 bytes") }
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private static func digestHex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
