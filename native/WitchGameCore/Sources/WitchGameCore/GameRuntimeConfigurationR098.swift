import CryptoKit
import Foundation

/// One resolved, immutable source of App/test candidate runtime settings.
/// This describes the R098 app candidate; it does not imply balance adoption.
public struct GameRuntimeConfigurationR098: Sendable {
    public static let schemaVersion = 1
    public static let defaultGrowthStrengthBP = 500
    public static let allowedGrowthStrengthBP: Set<Int> = [0, 250, 500, 750, 1_000, 2_500, 10_000]

    public let profileID: String
    public let profileVersion: Int
    public let catalog: GameCatalog
    public let latentPolicy: CandidateLatentSlotPolicyR003
    public let combatOverlay: CandidateCombatOverlay
    public let growth: CandidateCharacterGrowth
    /// Preserve catalog order because the existing summon RNG indexes this array.
    public let summonPoolIDs: [String]
    public let sortedCatalogGearIDs: [String]
    public let catalogSHA256: String
    public let latentPolicySHA256: String
    public let sortedGearIDsSHA256: String
    public let initialSnapshotSHA256: String
    public let configurationFingerprint: String
    public let canonicalManifest: Data

    public enum ConfigurationError: Error, Equatable {
        case invalidGrowthStrengthBP(Int)
        case resourceHashMismatch(name: String, expected: String, actual: String)
        case wrongCatalogGearCount(Int)
        case unsupportedGachaOdds([String: Int])
        case unsupportedDailyFreeGrant(Int)
        case missingResource(String)
    }

    private struct FingerprintPayload: Encodable {
        struct StarterGear: Encodable {
            let id: String
            let templateID: String
            let ownerID: String?
            let slot: String
            let protected: Bool
        }
        let schemaVersion: Int
        let profileID: String
        let profileVersion: Int
        let catalogSHA256: String
        let latentPolicySHA256: String
        let overlayID: String
        let overlayStatus: String
        let overlayTargetEnemyID: String
        let overlayActionPattern: String
        let overlayMarkWindowMs: Int
        let overlayStrikeWindupMs: Int
        let overlayStrikeCoefficientBP: Int
        let growthID: String
        let growthStrengthBP: Int
        let summonPoolIDsInDrawOrder: [String]
        let sortedCatalogGearIDs: [String]
        let sortedGearIDsSHA256: String
        let qualityOddsBasisPoints: [String: Int]
        let dailyFreeTicketGrant: Int
        let initialPartyActorIDs: [String]
        let initialRegionID: String?
        let initialUnlockedRegionIDs: [String]
        let initialStarterGear: [StarterGear]
        let initialCurrency: [String: Int]
        let initialMaterials: [String: Int]
        let initialGachaUnlocked: Bool
        let initialSnapshotSHA256: String
        let initialFactory: String
        let legacySavePolicy: String
    }

    /// Resolves exact bundled resource bytes and validates the candidate profile.
    /// QA growth overrides are explicit; invalid values fail closed.
    public static func resolve(growthStrengthBP: Int = defaultGrowthStrengthBP) throws -> GameRuntimeConfigurationR098 {
        guard allowedGrowthStrengthBP.contains(growthStrengthBP) else {
            throw ConfigurationError.invalidGrowthStrengthBP(growthStrengthBP)
        }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        let catalogData = try resourceData("catalog_overlay", bundle: bundle)
        let latentData = try resourceData("candidate_latent_policy_r004", bundle: bundle)
        let catalogHash = sha256(catalogData)
        let latentHash = sha256(latentData)
        let expectedCatalogHash = "bb218f0fe6b4b1a6037faa75ddb301ded27d7b9de070747bebf99a3e72209337"
        let expectedLatentHash = "59ae258fce8d2451b8dd3d3cdd78e494c069d040aa56146abb249398dbfb4109"
        guard catalogHash == expectedCatalogHash else {
            throw ConfigurationError.resourceHashMismatch(name: "catalog_overlay.json", expected: expectedCatalogHash, actual: catalogHash)
        }
        guard latentHash == expectedLatentHash else {
            throw ConfigurationError.resourceHashMismatch(name: "candidate_latent_policy_r004.json", expected: expectedLatentHash, actual: latentHash)
        }
        let catalog = try JSONDecoder().decode(GameCatalog.self, from: catalogData)
        try catalog.validate()
        guard catalog.gear.count == 33 else { throw ConfigurationError.wrongCatalogGearCount(catalog.gear.count) }
        let expectedOdds = ["Q0": 3_500, "Q1": 4_000, "Q2": 2_000, "Q3": 400, "Q4": 100]
        guard catalog.gachaOddsBasisPoints == expectedOdds else {
            throw ConfigurationError.unsupportedGachaOdds(catalog.gachaOddsBasisPoints)
        }
        guard catalog.dailyFreeTicketGrant == 5 else {
            throw ConfigurationError.unsupportedDailyFreeGrant(catalog.dailyFreeTicketGrant)
        }
        let latentPolicy = try CandidateLatentSlotPolicyR003.load(data: latentData)
        let overlay = CandidateCombatOverlay.r014LocalCandidate
        let growth = CandidateCharacterGrowth(strengthBP: growthStrengthBP)
        let orderedPoolIDs = catalog.gear.map(\.id)
        let sortedIDs = orderedPoolIDs.sorted()
        let sortedIDBytes = Data((sortedIDs.joined(separator: "\n") + "\n").utf8)
        let sortedIDHash = sha256(sortedIDBytes)
        let initial = try GameSnapshot.newCandidateGame(catalog: catalog, candidateLatentPolicy: latentPolicy)
        let initialHash = try canonicalInitialSnapshotSHA256(initial)
        let profileID = "app-candidate-r098-v1-growth-\(growthStrengthBP)bp"
        let payload = FingerprintPayload(
            schemaVersion: schemaVersion,
            profileID: profileID,
            profileVersion: 1,
            catalogSHA256: catalogHash,
            latentPolicySHA256: latentHash,
            overlayID: overlay.id,
            overlayStatus: overlay.status,
            overlayTargetEnemyID: overlay.targetEnemyID,
            overlayActionPattern: overlay.actionPattern,
            overlayMarkWindowMs: overlay.magnetParameters.markWindowMs,
            overlayStrikeWindupMs: overlay.magnetParameters.strikeWindupMs,
            overlayStrikeCoefficientBP: overlay.magnetParameters.strikeCoefficientBP,
            growthID: growth.id,
            growthStrengthBP: growth.strengthBP,
            summonPoolIDsInDrawOrder: orderedPoolIDs,
            sortedCatalogGearIDs: sortedIDs,
            sortedGearIDsSHA256: sortedIDHash,
            qualityOddsBasisPoints: catalog.gachaOddsBasisPoints,
            dailyFreeTicketGrant: catalog.dailyFreeTicketGrant,
            initialPartyActorIDs: initial.partyActorIDs,
            initialRegionID: initial.activeRegionID,
            initialUnlockedRegionIDs: initial.unlockedRegionIDs.sorted(),
            initialStarterGear: initial.gear.map { item in
                FingerprintPayload.StarterGear(
                    id: item.id.uuidString.lowercased(), templateID: item.definitionID,
                    ownerID: item.ownerID,
                    slot: catalog.gear.first(where: { $0.id == item.definitionID })?.slot ?? "unknown",
                    protected: item.protected)
            },
            initialCurrency: initial.currency,
            initialMaterials: initial.materials,
            initialGachaUnlocked: initial.gachaUnlocked,
            initialSnapshotSHA256: initialHash,
            initialFactory: "GameSnapshot.newCandidateGame/R004",
            legacySavePolicy: "decode-existing-bytes-without-latent-migration"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifest = try encoder.encode(payload)
        return GameRuntimeConfigurationR098(
            profileID: profileID,
            profileVersion: 1,
            catalog: catalog,
            latentPolicy: latentPolicy,
            combatOverlay: overlay,
            growth: growth,
            summonPoolIDs: orderedPoolIDs,
            sortedCatalogGearIDs: sortedIDs,
            catalogSHA256: catalogHash,
            latentPolicySHA256: latentHash,
            sortedGearIDsSHA256: sortedIDHash,
            initialSnapshotSHA256: initialHash,
            configurationFingerprint: sha256(manifest),
            canonicalManifest: manifest
        )
    }

    public func makeNewSnapshot() throws -> GameSnapshot {
        try GameSnapshot.newCandidateGame(catalog: catalog, candidateLatentPolicy: latentPolicy)
    }

    public func makeEngine(saves: SaveRepository, appearanceCatalog: GameCatalog? = nil,
                           firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179 = .disabled) throws -> GameEngine {
        let effectiveCatalog = appearanceCatalog ?? catalog
        if let appearanceCatalog {
            try appearanceCatalog.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            func gameplay(_ value: GameCatalog) throws -> Data {
                guard var object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] else {
                    throw CoreError.invalidCatalog("Catalog did not encode as an object")
                }
                object.removeValue(forKey: "version"); object.removeValue(forKey: "appearances")
                return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            }
            guard Array(appearanceCatalog.appearances.prefix(catalog.appearances.count)) == catalog.appearances,
                  try gameplay(appearanceCatalog) == gameplay(catalog) else {
                throw CoreError.invalidCatalog("Appearance extension changed gameplay or existing appearance definitions")
            }
        }
        return try GameEngine(catalog: effectiveCatalog, saves: saves,
                       candidateCombatOverlay: combatOverlay,
                       candidateCharacterGrowth: growth,
                       candidateLatentPolicy: latentPolicy,
                       firstCraftAidCapabilityR179: firstCraftAidCapabilityR179)
    }

    /// Run identity is deliberately outside configurationFingerprint.
    public static func runIdentity(seed: UInt64, virtualStartEpochSeconds: Int64,
                                   virtualDayCount: Int, operationIDPolicy: String,
                                   gearUUIDPolicy: String) -> GameRuntimeRunIdentityR098 {
        GameRuntimeRunIdentityR098(seed: seed, virtualStartEpochSeconds: virtualStartEpochSeconds,
                                   virtualDayCount: virtualDayCount,
                                   operationIDPolicy: operationIDPolicy, gearUUIDPolicy: gearUUIDPolicy)
    }

    private init(profileID: String, profileVersion: Int, catalog: GameCatalog,
                 latentPolicy: CandidateLatentSlotPolicyR003, combatOverlay: CandidateCombatOverlay,
                 growth: CandidateCharacterGrowth, summonPoolIDs: [String], sortedCatalogGearIDs: [String],
                 catalogSHA256: String, latentPolicySHA256: String, sortedGearIDsSHA256: String,
                 initialSnapshotSHA256: String, configurationFingerprint: String, canonicalManifest: Data) {
        self.profileID = profileID
        self.profileVersion = profileVersion
        self.catalog = catalog
        self.latentPolicy = latentPolicy
        self.combatOverlay = combatOverlay
        self.growth = growth
        self.summonPoolIDs = summonPoolIDs
        self.sortedCatalogGearIDs = sortedCatalogGearIDs
        self.catalogSHA256 = catalogSHA256
        self.latentPolicySHA256 = latentPolicySHA256
        self.sortedGearIDsSHA256 = sortedGearIDsSHA256
        self.initialSnapshotSHA256 = initialSnapshotSHA256
        self.configurationFingerprint = configurationFingerprint
        self.canonicalManifest = canonicalManifest
    }

    private static func resourceData(_ name: String, bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ConfigurationError.missingResource(name)
        }
        return try Data(contentsOf: url)
    }

    private static func canonicalInitialSnapshotSHA256(_ snapshot: GameSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        let root = try JSONSerialization.jsonObject(with: data)
        let normalized = normalizeInitialJSON(root)
        let canonical = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .withoutEscapingSlashes])
        return sha256(canonical)
    }

    private static func normalizeInitialJSON(_ value: Any, key: String? = nil) -> Any {
        if let object = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: object.keys.sorted().map { ($0, normalizeInitialJSON(object[$0]!, key: $0)) })
        }
        if let array = value as? [Any] {
            let normalized = array.map { normalizeInitialJSON($0) }
            let setLikeKeys: Set<String> = ["unlockedRegionIDs", "completedResearchIDs", "ownedCosmeticIDs", "ownedFurnitureIDs", "placedFurnitureIDs", "pendingPurchaseIDs", "completedEncounterIDs"]
            if let key, setLikeKeys.contains(key) {
                return normalized.sorted { String(describing: $0) < String(describing: $1) }
            }
            return normalized
        }
        return value
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct GameRuntimeRunIdentityR098: Sendable, Equatable, Codable {
    public let seed: UInt64
    public let virtualStartEpochSeconds: Int64
    public let virtualDayCount: Int
    public let operationIDPolicy: String
    public let gearUUIDPolicy: String
}
