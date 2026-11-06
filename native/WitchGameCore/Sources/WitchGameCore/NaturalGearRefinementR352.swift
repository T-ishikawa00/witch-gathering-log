import CryptoKit
import Foundation

/// Explicit, unapproved R2-derived rank progression. It is never enabled by default.
public struct NaturalGearRefinementPolicyR352: Sendable, Equatable {
    public static let policyID = "gear-refinement-r352-r2-candidate"
    public static let sourcePath = "docs/production/current/qa_drafts/latent_combat_r030/source_refs/growth_gear_skills_R2.json"
    public static let sourceSHA256 = "70d36d335e69899f4232567d80e2dc17457d6baec1688590cf3757d8b0b4d874"

    /// Canonical policy provenance. JSON keys and transition rows are kept in stable order.
    /// Values remain an unapproved candidate; this digest is identification, not adoption.
    public static let canonicalManifest = """
    {"birthRank":{"basis":"contiguousCompletedBossGates","gates":["B_R01_B","B_R02_B","B_R03_B","B_R04_B"],"maxRank":5,"regionReachAloneGrantsRank":false},"enhancementCaps":{"1":3,"2":5,"3":7,"4":9,"5":10},"legacy":{"disabledBranch":"preserveExistingRefinementBehavior","positiveRefinementBonus":"preserve","pinnedR350Pool":"preserveCapturedSnapshot","priorGear":"noRetroactiveRank"},"policyID":"gear-refinement-r352-r2-candidate","projection":{"order":["catalogBaseGearBonus","rankMultiplierBasisPoints","quality","legacyRefinement","enhancement","latent"],"rankMultipliersBasisPoints":{"1":10000,"2":16000,"3":24000,"4":34000,"5":46000}},"schema":"natural-gear-refinement-r352-v2","source":{"path":"docs/production/current/qa_drafts/latent_combat_r030/source_refs/growth_gear_skills_R2.json","sha256":"70d36d335e69899f4232567d80e2dc17457d6baec1688590cf3757d8b0b4d874"},"transitions":[{"dust":60,"fromRank":1,"gate":"G_R01_B","materials":{"M_R02_G1":6,"M_R02_G2":6},"toRank":2},{"dust":120,"fromRank":2,"gate":"G_R02_B","materials":{"M_R03_G1":8,"M_R03_G2":8},"toRank":3},{"dust":200,"fromRank":3,"gate":"G_R03_B","materials":{"M_R04_G1":10,"M_R04_G2":10},"toRank":4},{"dust":300,"fromRank":4,"gate":"G_R04_B","materials":{"M_R05_G1":12,"M_R05_G2":12},"toRank":5}]}
    """
    public static let policySHA256 = SHA256.hash(data: Data(canonicalManifest.utf8)).map { String(format: "%02x", $0) }.joined()
    public let policyFingerprint = Self.policySHA256

    public struct Transition: Sendable, Equatable {
        public let fromRank: Int
        public let toRank: Int
        public let gateID: String
        public let dustCost: Int
        public let materialCosts: [String: Int]
        public let statMultiplierBasisPoints: Int
    }

    private static let transitions: [Int: Transition] = [
        1: Transition(fromRank: 1, toRank: 2, gateID: "G_R01_B", dustCost: 60,
                      materialCosts: ["M_R02_G1": 6, "M_R02_G2": 6], statMultiplierBasisPoints: 16_000),
        2: Transition(fromRank: 2, toRank: 3, gateID: "G_R02_B", dustCost: 120,
                      materialCosts: ["M_R03_G1": 8, "M_R03_G2": 8], statMultiplierBasisPoints: 24_000),
        3: Transition(fromRank: 3, toRank: 4, gateID: "G_R03_B", dustCost: 200,
                      materialCosts: ["M_R04_G1": 10, "M_R04_G2": 10], statMultiplierBasisPoints: 34_000),
        4: Transition(fromRank: 4, toRank: 5, gateID: "G_R04_B", dustCost: 300,
                      materialCosts: ["M_R05_G1": 12, "M_R05_G2": 12], statMultiplierBasisPoints: 46_000)
    ]

    public init() {}

    public func transition(from rank: Int) -> Transition? { Self.transitions[rank] }
    public func maximumEnhancement(forRank rank: Int) -> Int? { [1: 3, 2: 5, 3: 7, 4: 9, 5: 10][rank] }
    public func multiplierBasisPoints(forRank rank: Int) -> Int? {
        Self.multiplierBasisPointsForPersistedRank(rank)
    }
    public static func multiplierBasisPointsForPersistedRank(_ rank: Int) -> Int? {
        if rank == 1 { return 10_000 }
        return Self.transitions[rank - 1]?.statMultiplierBasisPoints
    }

    /// Global progression rank follows completed regional boss gates, independent of
    /// the rolled gear template's recipe gate. Region reach alone does not grant rank.
    public static func globalRank(completedEncounterIDs: Set<String>) -> Int {
        let gates = ["B_R01_B", "B_R02_B", "B_R03_B", "B_R04_B"]
        return 1 + gates.prefix(while: completedEncounterIDs.contains).count
    }
}

/// Closed v4 rank payload. Rank I is implicit, so only rank II–V entries are stored.
public struct NaturalGearRefinementLedgerR352: Codable, Sendable, Equatable {
    public let futureVersion: Int
    public private(set) var rankByGearUUID: [String: Int]
    public init() {
        self.futureVersion = 4
        self.rankByGearUUID = [:]
    }
    public var isEmpty: Bool { rankByGearUUID.isEmpty }
    public func rank(for gearID: UUID) -> Int { rankByGearUUID[gearID.uuidString.lowercased()] ?? 1 }
    public var ranksByUUID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: rankByGearUUID.compactMap { key, rank in UUID(uuidString: key).map { ($0, rank) } })
    }
    mutating func setRank(_ rank: Int, for gearID: UUID) {
        let key = gearID.uuidString.lowercased()
        if rank <= 1 { rankByGearUUID.removeValue(forKey: key) }
        else { rankByGearUUID[key] = rank }
    }
    mutating func remove(_ gearID: UUID) { rankByGearUUID.removeValue(forKey: gearID.uuidString.lowercased()) }

    private struct AnyKey: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private enum CodingKeys: String, CodingKey { case futureVersion, rankByGearUUID }
    public init(from decoder: Decoder) throws {
        let any = try decoder.container(keyedBy: AnyKey.self)
        guard Set(any.allKeys.map(\.stringValue)) == Set(["futureVersion", "rankByGearUUID"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "R352 payload keys are not closed"))
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .futureVersion)
        let rows = try c.decode([String: Int].self, forKey: .rankByGearUUID)
        guard version == 4, rows.allSatisfy({ key, value in
            guard let id = UUID(uuidString: key) else { return false }
            return id.uuidString.lowercased() == key && (2...5).contains(value)
        }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "R352 rank payload is invalid"))
        }
        futureVersion = version
        rankByGearUUID = rows
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(4, forKey: .futureVersion)
        try c.encode(rankByGearUUID, forKey: .rankByGearUUID)
    }
}
