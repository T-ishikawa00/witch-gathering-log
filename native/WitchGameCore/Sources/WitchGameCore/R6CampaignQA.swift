import Foundation

/// Additive test-only bridge from the small campaign overlay units to the
/// fixed-point units consumed by the R6 timeline. No save/catalog values change.
public enum R6CampaignQAAdapter {
    public static let profileID = "R6_CAMPAIGN_CANDIDATE_QA_R1"
    public static let fixedPointScale = 10_000

    public static func party(from snapshot: GameSnapshot, catalog: GameCatalog) throws -> [Combatant] {
        guard snapshot.partyActorIDs.count == 4,
              Set(snapshot.partyActorIDs) == Set(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]) else {
            throw CoreError.invalidCommand("R6 campaign QA requires the four canonical party actors")
        }
        return try snapshot.partyActorIDs.map { actorID in
            let instances = snapshot.equippedGearIDs
                .filter { $0.key.hasPrefix(actorID + "|") }
                .compactMap { _, instanceID in snapshot.gear.first(where: { $0.id == instanceID }) }
            var candidate = catalog.projectCombatant(for: actorID, with: instances,
                                                      completedResearchIDs: snapshot.completedResearchIDs)
            candidate.effectIDs.formUnion(intrinsicEffects(for: actorID))
            // Only the explicitly selected evolved campaign templates receive
            // these candidate handlers. The canonical R6 profile keeps its own
            // fixed source contract and does not infer effects from campaign IDs.
            for item in instances {
                switch item.definitionID {
                case "EQ_S_03": candidate.effectIDs.insert("SMITH_COVER_BARRIER")
                case "EQ_F_03": candidate.effectIDs.insert("FAMILIAR_CHASE_ICD_1500MS")
                default: break
                }
            }
            return try fixedPoint(candidate)
        }
    }

    public static func enemy(_ definition: EnemyDefinition, regionIndex: Int) throws -> Combatant {
        let hp = try scaled(definition.hp, label: "enemy hp")
        let attack = try scaled(definition.attack, label: "enemy attack")
        let defense = try scaled(definition.defense, label: "enemy defense")
        let level = min(60, max(1, (regionIndex + 1) * 3))
        let actions = actionCycle(for: definition.actionPattern ?? "standard")
        return Combatant(id: definition.id, maxHP: hp, attack: attack, defense: defense,
                         actionPattern: definition.actionPattern ?? "standard", level: level,
                         firstTelegraphMs: 1_800, enemyActions: actions)
    }

    public static func fixedPoint(_ candidate: Combatant) throws -> Combatant {
        var result = candidate
        result.maxHP = try scaled(candidate.maxHP, label: "party hp")
        result.attack = try scaled(candidate.attack, label: "party attack")
        result.defense = try scaled(candidate.defense, label: "party defense")
        if result.level == nil { result.level = 1 }
        return result
    }

    private static func scaled(_ value: Int, label: String) throws -> Int {
        guard value >= 0, value <= Int.max / fixedPointScale else {
            throw CoreError.invalidCommand("campaign QA (label) cannot be represented in R6 fixed-point units")
        }
        return value * fixedPointScale
    }

    private static func intrinsicEffects(for actorID: String) -> Set<String> {
        switch actorID {
        case "C_WITCH": ["POISON_STACK"]
        case "C_FAMILIAR": ["FAMILIAR_CHASE"]
        default: []
        }
    }

    /// These are explicitly provisional translations of campaign action
    /// labels, not authored canonical R6 enemy data.
    private static func actionCycle(for pattern: String) -> [EnemyActionDefinition] {
        func action(_ id: String, _ coefficient: Int, _ offsets: [Int] = [0], _ aoe: Bool = false, _ heavy: Bool = false, _ restMs: Int = 0) -> EnemyActionDefinition {
            EnemyActionDefinition(id: id, coefficientBP: coefficient, windupMs: heavy ? 1_800 : 1_000,
                                  hitOffsetsMs: offsets, recoveryMs: 1_500, restMs: restMs, aoe: aoe, heavy: heavy)
        }
        switch pattern {
        case "heavy": return [action("candidate_heavy", 20_000, [0], false, true)]
        case "multiHit": return [action("candidate_multihit", 6_000, [0, 350, 700])]
        case "multiHitRest": return [action("candidate_multihit_rest", 6_000, [0, 350, 700], false, false, 1_800)]
        case "aoe": return [action("candidate_aoe", 6_000, [0], true)]
        case "dot": return [action("candidate_dot", 10_000)]
        case "support": return [action("candidate_support", 8_500)]
        case "armor": return [action("candidate_armor", 10_000)]
        case "combined": return [action("candidate_single", 10_000), action("candidate_aoe", 6_000, [0], true)]
        default: return [action("candidate_standard", 10_000)]
        }
    }
}
