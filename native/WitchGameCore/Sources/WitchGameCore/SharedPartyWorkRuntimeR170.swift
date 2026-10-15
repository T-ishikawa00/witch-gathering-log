import Foundation

/// Shared App/Core factory for the explicitly selected R144 development candidate.
/// The appearance equivalence guard and gameplay policy are unchanged.
@MainActor public extension GameRuntimeConfigurationR098 {
    func makeSharedPartyWorkEngineR146(saves: SaveRepository, appearanceCatalog: GameCatalog?,
                                       firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179 = .disabled) throws -> GameEngine {
        // Reuse the runtime's gameplay-equivalence guard for appearance catalog extensions.
        _ = try makeEngine(saves: saves, appearanceCatalog: appearanceCatalog,
                           firstCraftAidCapabilityR179: firstCraftAidCapabilityR179)
        let policy = try PartyWorkPolicyR144(baseProfileID: profileID,
                                             baseConfigurationFingerprint: configurationFingerprint)
        return try GameEngine(catalog: appearanceCatalog ?? catalog, saves: saves,
                              candidateCombatOverlay: combatOverlay,
                              candidateCharacterGrowth: growth,
                              candidateLatentPolicy: latentPolicy,
                              candidatePartyWorkPolicyR144: policy,
                              firstCraftAidCapabilityR179: firstCraftAidCapabilityR179)
    }
}

