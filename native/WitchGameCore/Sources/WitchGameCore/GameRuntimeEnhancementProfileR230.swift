import CryptoKit
import Foundation

/// Separate runtime envelope for the unapproved R230 comparison profile.
/// It binds the exact existing R098 profile fingerprint without changing R098 defaults.
public struct GameRuntimeEnhancementProfileR230: Sendable {
    public let base: GameRuntimeConfigurationR098
    public let profileID: String
    public let configurationFingerprint: String
    public let canonicalManifest: Data

    public init(base: GameRuntimeConfigurationR098) throws {
        self.base = base
        profileID = "\(base.profileID)-enhancement-r230-v1"
        let payload = "{\"baseConfigurationFingerprint\":\"\(base.configurationFingerprint)\",\"enhancementPolicyID\":\"\(GearEnhancementGrowthR230.profileID)\",\"enhancementPolicySHA256\":\"\(GearEnhancementGrowthR230.policySHA256)\",\"profileID\":\"\(profileID)\",\"profileVersion\":1}"
        canonicalManifest = Data(payload.utf8)
        configurationFingerprint = SHA256.hash(data: canonicalManifest).map { String(format: "%02x", $0) }.joined()
    }

    public static func resolve(growthStrengthBP: Int = GameRuntimeConfigurationR098.defaultGrowthStrengthBP) throws -> Self {
        try Self(base: GameRuntimeConfigurationR098.resolve(growthStrengthBP: growthStrengthBP))
    }

    public func makeEngine(saves: SaveRepository, appearanceCatalog: GameCatalog? = nil,
                           candidatePartyWorkPolicyR144: PartyWorkPolicyR144? = nil,
                           firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179 = .disabled,
                           naturalGearDiscoveryPolicyR350: NaturalGearDiscoveryPolicyR350? = nil,
                           naturalGearRefinementPolicyR352: NaturalGearRefinementPolicyR352? = nil,
                           gearDismantleRefundPolicyR353: GearDismantleRefundPolicyR353? = nil) throws -> GameEngine {
        let effectiveCatalog = appearanceCatalog ?? base.catalog
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
            guard Array(appearanceCatalog.appearances.prefix(base.catalog.appearances.count)) == base.catalog.appearances,
                  try gameplay(appearanceCatalog) == gameplay(base.catalog) else {
                throw CoreError.invalidCatalog("Appearance extension changed gameplay or existing appearance definitions")
            }
        }
        return try GameEngine(catalog: effectiveCatalog, saves: saves, candidateCombatOverlay: base.combatOverlay,
                       candidateCharacterGrowth: base.growth, candidateLatentPolicy: base.latentPolicy,
                       candidatePartyWorkPolicyR144: candidatePartyWorkPolicyR144,
                       firstCraftAidCapabilityR179: firstCraftAidCapabilityR179,
                       enhancementProjectionPolicyR230: .r2SlotBudgetCandidate,
                       naturalGearDiscoveryPolicyR350: naturalGearDiscoveryPolicyR350,
                       naturalGearRefinementPolicyR352: naturalGearRefinementPolicyR352,
                       gearDismantleRefundPolicyR353: gearDismantleRefundPolicyR353)
    }
}

