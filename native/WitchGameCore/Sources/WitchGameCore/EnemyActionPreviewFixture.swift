import Foundation

/// Read-only, deterministic presentation fixture for candidate multi-enemy action cues.
/// It calls the timeline simulator directly and has no GameEngine, save, or reward path.
public enum EnemyActionPreviewFixture {
    private static func previewParty(attack: Int = 1) -> [Combatant] {
        ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 20_000, attack: attack, defense: 0)
        }
    }

    private static func bossPreview(id: String, label: String, effectKey: String, pattern: String,
                                    seed: UInt64, maxDurationMs: Int, partyAttack: Int = 1) throws -> CombatResult {
        let enemy = Combatant(id: id, maxHP: 100_000, attack: 100, defense: 0,
                              actionPattern: pattern, firstTelegraphMs: 0)
        let presentation = [id: CombatEntityPresentation(entityID: id, kind: "enemy", catalogID: id,
                                                           label: label, assetKey: effectKey)]
        return try R6TimelineSimulator.run(party: previewParty(attack: partyAttack), enemies: [enemy],
                                           seed: seed, maxDurationMs: maxDurationMs,
                                           entityPresentation: presentation)
    }

    private static func magnetPreview(seed: UInt64, maxDurationMs: Int, challengeID: String?) throws -> CombatResult {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 20_000, attack: 1, defense: 0)
        }
        let enemy = Combatant(id: "E_R03_04", maxHP: 100_000, attack: 400, defense: 0,
                              actionPattern: "magnetMarkStrike", firstTelegraphMs: 0)
        let presentation = ["E_R03_04": CombatEntityPresentation(entityID: "E_R03_04", kind: "enemy",
            catalogID: "E_R03_04", label: "磁紋とかげ", assetKey: "ACT_E_R03_04")]
        return try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: seed,
            maxDurationMs: maxDurationMs, challengeID: challengeID,
            entityPresentation: presentation,
            candidateMagnetParameters: MagnetMechanicParameters(markWindowMs: 800,
                strikeWindupMs: 1_200, strikeCoefficientBP: 12_500))
    }

    /// Read-only candidate action preview. No command, reward, or save mutation.
    public static func magnetMarkStrike(seed: UInt64 = 1_304, maxDurationMs: Int = 12_000) throws -> CombatResult {
        try magnetPreview(seed: seed, maxDurationMs: maxDurationMs, challengeID: nil)
    }

    /// Uses only the already-authored CH_R03_03 typed interruption pathway.
    public static func magnetMarkStrikeInterrupted(seed: UInt64 = 1_304,
                                                     maxDurationMs: Int = 12_000) throws -> CombatResult {
        try magnetPreview(seed: seed, maxDurationMs: maxDurationMs, challengeID: "CH_R03_03")
    }

    public static func dreamMushroomBoss(seed: UInt64 = 811, maxDurationMs: Int = 14_000) throws -> CombatResult {
        try bossPreview(id: "B_R02_A", label: "夢茸の歩き主", effectKey: "ACT_B_R02_A",
                        pattern: "sporeRest", seed: seed, maxDurationMs: maxDurationMs)
    }

    public static func mirrorLizardBoss(seed: UInt64 = 811, maxDurationMs: Int = 15_000) throws -> CombatResult {
        try bossPreview(id: "B_R02_B", label: "水鏡の大蜥蜴", effectKey: "ACT_B_R02_B",
                        pattern: "mirrorCycle", seed: seed, maxDurationMs: maxDurationMs, partyAttack: 1_000)
    }

    public static func hammerTrooperBoss(seed: UInt64 = 811, maxDurationMs: Int = 15_000) throws -> CombatResult {
        try bossPreview(id: "B_R03_A", label: "晶洞の連槌兵", effectKey: "ACT_B_R03_A",
                        pattern: "hammerCombo", seed: seed, maxDurationMs: maxDurationMs)
    }

    public static func forgeGuardianBoss(seed: UInt64 = 811, maxDurationMs: Int = 15_000) throws -> CombatResult {
        try bossPreview(id: "B_R03_B", label: "炉守りの鉱巨人", effectKey: "ACT_B_R03_B",
                        pattern: "heatCycle", seed: seed, maxDurationMs: maxDurationMs)
    }

    public static func mountainDragonBoss(seed: UInt64 = 811, maxDurationMs: Int = 18_000) throws -> CombatResult {
        try bossPreview(id: "B_R04_B", label: "月氷の山竜", effectKey: "ACT_B_R04_B",
                        pattern: "iceBreathCycle", seed: seed, maxDurationMs: maxDurationMs)
    }

    public static func pruningMachineBoss(seed: UInt64 = 811, maxDurationMs: Int = 18_000) throws -> CombatResult {
        try bossPreview(id: "B_R05_A", label: "月環の剪定機", effectKey: "ACT_B_R05_A",
                        pattern: "pruningCycle", seed: seed, maxDurationMs: maxDurationMs)
    }

    public static func moonDeerBoss(seed: UInt64 = 811, maxDurationMs: Int = 18_000) throws -> CombatResult {
        try bossPreview(id: "B_R05_B", label: "庭守りの月鹿", effectKey: "ACT_B_R05_B",
                        pattern: "seedGuardUltimate", seed: seed, maxDurationMs: maxDurationMs)
    }

    /// Read-only R4 shell-defense trace: the shell reduces incoming player damage to the enemy,
    /// while its ordinary strike remains unmodified. There is no save, command, or reward path.
    public static func armorDefense(seed: UInt64 = 1_202, maxDurationMs: Int = 4_000) throws -> CombatResult {
        let enemy = Combatant(id: "E_R01_04", maxHP: 10_000, attack: 50, defense: 0,
                              actionPattern: "armor", firstTelegraphMs: 0)
        let presentation = ["E_R01_04": CombatEntityPresentation(entityID: "E_R01_04", kind: "enemy",
            catalogID: "E_R01_04", label: "樹脂ころがし", assetKey: "ACT_E_R01_04")]
        return try R6TimelineSimulator.run(party: previewParty(attack: 100), enemies: [enemy], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: presentation)
    }

    /// Read-only candidate comparison for R4's front-facing shell. Attack side
    /// is explicit test input because the current campaign has no flank action.
    public static func pincerOrientation(side: CandidateAttackSide, seed: UInt64 = 1_303,
                                         maxDurationMs: Int = 12_000) throws -> CombatResult {
        let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: 20_000, attack: 1_000, defense: 0,
                      candidateAttackSide: side)
        }
        let enemy = Combatant(id: "E_R03_01", maxHP: 100_000, attack: 100, defense: 0,
                              actionPattern: "armor", firstTelegraphMs: 0)
        let presentation = ["E_R03_01": CombatEntityPresentation(entityID: "E_R03_01", kind: "enemy",
            catalogID: "E_R03_01", label: "銅殻やどかり", assetKey: "ACT_E_R03_01")]
        return try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: presentation)
    }

    public static func lightTransfer(seed: UInt64 = 813, maxDurationMs: Int = 8_000) throws -> CombatResult {
        let party = [
            Combatant(id: "C_WITCH", maxHP: 20_000, attack: 1, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 20_000, attack: 1, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 20_000, attack: 1, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 20_000, attack: 1, defense: 0)
        ]
        let enemies = [
            Combatant(id: "E_R05_03", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "lightTransfer", firstTelegraphMs: 1_500),
            Combatant(id: "E_R05_02", maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "support", firstTelegraphMs: 1_500)
        ]
        let presentation = [
            "E_R05_03": CombatEntityPresentation(entityID: "E_R05_03", kind: "enemy", catalogID: "E_R05_03",
                                                   label: "灯瓶の使い魔", assetKey: "ACT_E_R05_03"),
            "E_R05_02": CombatEntityPresentation(entityID: "E_R05_02", kind: "enemy", catalogID: "E_R05_02",
                                                   label: "月面の庭衛", assetKey: "ACT_E_R05_02")
        ]
        return try R6TimelineSimulator.run(party: party, enemies: enemies, seed: seed,
                                           maxDurationMs: maxDurationMs,
                                           entityPresentation: presentation)
    }

    /// Render-only R05 guard posture with a real hit absorbed during the stance.
    public static func guardPosture(seed: UInt64 = 811, maxDurationMs: Int = 8_000) throws -> CombatResult {
        let enemy = Combatant(id: "E_R05_02", maxHP: 100_000, attack: 100, defense: 0,
                              actionPattern: "guardAlternating", firstTelegraphMs: 0)
        let presentation = ["E_R05_02": CombatEntityPresentation(entityID: "E_R05_02", kind: "enemy",
            catalogID: "E_R05_02", label: "月面の庭衛", assetKey: "ACT_E_R05_02")]
        return try R6TimelineSimulator.run(party: previewParty(attack: 1_000), enemies: [enemy], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: presentation)
    }

    /// Render-only R05 duration-disruption trace. Initial barriers are fixture state, not a save mutation.
    public static func supportDurationReduction(seed: UInt64 = 811, maxDurationMs: Int = 6_000) throws -> CombatResult {
        let party = previewParty()
        let enemy = Combatant(id: "E_R05_01", maxHP: 100_000, attack: 100, defense: 0,
                              actionPattern: "supportDisrupt", firstTelegraphMs: 0)
        let barriers = Dictionary(uniqueKeysWithValues: party.map { ($0.id, (amount: 10, expiryMs: 10_000)) })
        let presentation = ["E_R05_01": CombatEntityPresentation(entityID: "E_R05_01", kind: "enemy",
            catalogID: "E_R05_01", label: "蔓綴じの書霊", assetKey: "ACT_E_R05_01")]
        return try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: presentation,
                                           initialBarriers: barriers)
    }

    /// Render-only R05 poison/regen trace; a weak party attack first makes actual enemy healing observable.
    public static func poisonRegeneration(seed: UInt64 = 811, maxDurationMs: Int = 8_000) throws -> CombatResult {
        let enemy = Combatant(id: "E_R05_04", maxHP: 100_000, attack: 100, defense: 0,
                              actionPattern: "regenPoison", firstTelegraphMs: 0)
        let presentation = ["E_R05_04": CombatEntityPresentation(entityID: "E_R05_04", kind: "enemy",
            catalogID: "E_R05_04", label: "夜咲きの花獣", assetKey: "ACT_E_R05_04")]
        return try R6TimelineSimulator.run(party: previewParty(attack: 1), enemies: [enemy], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: presentation)
    }

    /// Read-only multi-enemy R04 follow-up trace. The first enemy lands a three-hit
    /// action; E_R04_01 should follow that same target once for the whole root.
    public static func allyFollowup(seed: UInt64 = 814, maxDurationMs: Int = 4_000) throws -> CombatResult {
        let trigger = Combatant(id: "E_R04_04", maxHP: 100_000, attack: 80, defense: 0,
                                actionPattern: "multiHit", firstTelegraphMs: 0)
        let follower = Combatant(id: "E_R04_01", maxHP: 100_000, attack: 80, defense: 0,
                                 actionPattern: "allyFollowup", firstTelegraphMs: 7_000)
        let presentation = [
            "E_R04_04": CombatEntityPresentation(entityID: "E_R04_04", kind: "enemy", catalogID: "E_R04_04",
                label: "霜晶の削り偶", assetKey: "ACT_E_R04_04"),
            "E_R04_01": CombatEntityPresentation(entityID: "E_R04_01", kind: "enemy", catalogID: "E_R04_01",
                label: "霜毛おおかみ", assetKey: "ACT_E_R04_01")
        ]
        return try R6TimelineSimulator.run(party: previewParty(), enemies: [trigger, follower], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: presentation)
    }
}
