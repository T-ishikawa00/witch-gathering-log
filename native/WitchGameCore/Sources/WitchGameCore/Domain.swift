import Foundation

/// Numeric values in this package are an implementation test overlay, not approved balance.
public enum BalanceAuthority: String, Codable, Sendable { case unapprovedTestOverlay = "UNAPPROVED_TEST_OVERLAY" }

public struct GearDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let rarity: String
    public let slot: String
    public let effects: [String]
    public let actorIDs: [String]
    public let guardChanceBonusBP: Int?
    public init(id: String, name: String, rarity: String, slot: String, effects: [String], actorIDs: [String] = [], guardChanceBonusBP: Int? = nil) { self.id = id; self.name = name; self.rarity = rarity; self.slot = slot; self.effects = effects; self.actorIDs = actorIDs; self.guardChanceBonusBP = guardChanceBonusBP }
}
public struct EnemyDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let regionID: String
    public let hp: Int
    public let attack: Int
    public let defense: Int
    public let boss: Bool
    public let actionPattern: String?
    public let dropMaterialID: String?
    public let prerequisiteEncounterID: String?
    public init(id: String, name: String, regionID: String, hp: Int, attack: Int, defense: Int, boss: Bool, dropMaterialID: String? = nil, prerequisiteEncounterID: String? = nil, actionPattern: String? = nil) { self.id = id; self.name = name; self.regionID = regionID; self.hp = hp; self.attack = attack; self.defense = defense; self.boss = boss; self.dropMaterialID = dropMaterialID; self.prerequisiteEncounterID = prerequisiteEncounterID; self.actionPattern = actionPattern }
}
public struct RegionDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let enemyIDs: [String]
    public let gatherMaterialIDs: [String]
    public let xpPerWork: Int
    public let dustPerWork: Int
    public let workSeconds: Int
    public init(id: String, name: String, enemyIDs: [String], gatherMaterialIDs: [String] = [], xpPerWork: Int = 0, dustPerWork: Int = 0, workSeconds: Int = 300) { self.id = id; self.name = name; self.enemyIDs = enemyIDs; self.gatherMaterialIDs = gatherMaterialIDs; self.xpPerWork = xpPerWork; self.dustPerWork = dustPerWork; self.workSeconds = workSeconds }
}
public struct ResearchDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let cost: [String: Int]
    public let effectID: String
    public init(id: String, name: String, cost: [String: Int], effectID: String) { self.id = id; self.name = name; self.cost = cost; self.effectID = effectID }
}
public struct ResearchStatEffect: Codable, Sendable, Equatable {
    public let partyAttack: Int
    public let partyMaxHP: Int
    public let partyDefense: Int
    enum CodingKeys: String, CodingKey { case partyAttack = "party_attack", partyMaxHP = "party_max_hp", partyDefense = "party_defense" }
}
public struct AppearanceDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let actorIDs: [String]
    public let status: String
    public init(id: String, kind: String, actorIDs: [String], status: String) {
        self.id = id; self.kind = kind; self.actorIDs = actorIDs; self.status = status
    }
}
/// Endgame proposals are kept distinct from the five R3 research ranks. Their rules remain design candidates.
public struct ChallengeDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let region: String
    public let name: String
    public let enemyIDs: [String]
    public let mechanic: String
    public let unlockGate: String
    public let firstClearPowder: Int
    public let status: String
    public let enemyHPScale: Int
    public let enemyAttackScale: Int
    public var actionPattern: String {
        switch id {
        case "CH_R01_01", "CH_R03_02", "CH_R04_01", "CH_R05_01": "heavy"
        case "CH_R01_02", "CH_R02_03", "CH_R04_02", "CH_R05_02": "support"
        case "CH_R01_03", "CH_R03_01": "multiHit"
        case "CH_R02_01", "CH_R03_03": "dot"
        case "CH_R02_02": "armor"
        case "CH_R04_03": "aoe"
        default: "combined"
        }
    }
    enum CodingKeys: String, CodingKey { case id, region, name, mechanic, status; case enemyIDs = "enemy_ids"; case unlockGate = "unlock_gate"; case firstClearPowder = "first_clear_powder"; case enemyHPScale = "enemy_hp_scale"; case enemyAttackScale = "enemy_attack_scale" }
}

/// Exact candidate combat inputs and stable render mapping shared by the engine and QA harness.
public struct ChallengeCombatScenario: Sendable, Equatable {
    public let challengeID: String
    public let enemies: [Combatant]
    public let entityPresentation: [String: CombatEntityPresentation]
    public init(challengeID: String, enemies: [Combatant], entityPresentation: [String: CombatEntityPresentation]) {
        self.challengeID = challengeID; self.enemies = enemies; self.entityPresentation = entityPresentation
    }
}

public struct RecipeDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let outputGearID: String?
    public let costs: [String: Int]
    public let status: String
    public let kind: String
    public let dustCost: Int
    public let parentTemplateID: String?
    public let gateID: String?
    public let qualityFrom: String?
    public let qualityTo: String?
    public init(id: String, outputGearID: String?, costs: [String: Int], status: String, kind: String = "craft_new", dustCost: Int = 0, parentTemplateID: String? = nil, gateID: String? = nil, qualityFrom: String? = nil, qualityTo: String? = nil) { self.id = id; self.outputGearID = outputGearID; self.costs = costs; self.status = status; self.kind = kind; self.dustCost = dustCost; self.parentTemplateID = parentTemplateID; self.gateID = gateID; self.qualityFrom = qualityFrom; self.qualityTo = qualityTo }
}
public struct GameCatalog: Codable, Sendable {
    public let version: String
    public let authority: BalanceAuthority
    public let regions: [RegionDefinition]
    public let enemies: [EnemyDefinition]
    public let gear: [GearDefinition]
    public let research: [ResearchDefinition]
    public let materialIDs: [String]
    public let materialAvailabilityGates: [String: String]
    public let recipes: [RecipeDefinition]
    public let actorIDs: [String]
    public let gearAttackBonuses: [String: Int]
    public let gearHPBonuses: [String: Int]
    public let gearDefenseBonuses: [String: Int]
    public let gachaOddsBasisPoints: [String: Int]
    public let challenges: [ChallengeDefinition]
    public let researchEffects: [String: ResearchStatEffect]
    public let appearances: [AppearanceDefinition]
    public let furnitureIDs: [String]
    public var dailyFreeTicketGrant: Int

    /// Content availability projection used by both gather UI and command validation.
    public func availableGatherMaterialIDs(in regionID: String, unlockedRegionIDs: Set<String>, completedEncounterIDs: Set<String>) -> [String] {
        guard unlockedRegionIDs.contains(regionID), let region = regions.first(where: { $0.id == regionID }) else { return [] }
        return region.gatherMaterialIDs.filter { materialID in
            guard let gate = materialAvailabilityGates[materialID] else { return materialAvailabilityGates.isEmpty }
            if gate == "G_START" { return true }
            let parts = gate.split(separator: "_")
            guard parts.count == 3, parts[0] == "G" else { return false }
            return completedEncounterIDs.contains("B_\(parts[1])_\(parts[2])")
        }
    }

    /// Pure candidate stat projection shared by inventory previews and battle setup.
    /// Values remain UNAPPROVED_TEST_OVERLAY until their source rules are approved.
    public func projectCombatant(for actorID: String, with gearInstances: [GearInstance], completedResearchIDs: Set<String> = [],
                                 totalXP: Int = 0, candidateGrowth: CandidateCharacterGrowth? = nil,
                                 enhancementProjectionPolicyR230: EnhancementProjectionPolicyR230 = .legacy,
                                 refinementRanksR352: [UUID: Int] = [:]) -> Combatant {
        let nativeBase: (hp: Int, attack: Int, defense: Int, guardChanceBP: Int) = switch actorID {
        case "C_WITCH": (80, 15, 3, 0)
        case "C_APPRENTICE": (90, 9, 4, 0)
        case "C_SMITH": (120, 8, 8, 1_000)
        default: (70, 12, 3, 0)
        }
        let projectedBase: CandidateCharacterGrowth.BaseStats
        if let candidateGrowth {
            projectedBase = candidateGrowth.projectBase(actorID: actorID, totalXP: totalXP,
                nativeHP: nativeBase.hp, nativeAttack: nativeBase.attack, nativeDefense: nativeBase.defense)
        } else {
            projectedBase = .init(hp: nativeBase.hp, attack: nativeBase.attack, defense: nativeBase.defense)
        }
        let base = (hp: projectedBase.hp, attack: projectedBase.attack, defense: projectedBase.defense,
                    guardChanceBP: nativeBase.guardChanceBP)
        let instances = gearInstances.filter { $0.ownerID == nil || $0.ownerID == actorID }
        func rankedBase(_ value: Int, item: GearInstance) -> Int {
            guard let rank = refinementRanksR352[item.id], rank > 1,
                  let multiplier = NaturalGearRefinementPolicyR352.multiplierBasisPointsForPersistedRank(rank) else { return value }
            return value + value * (multiplier - 10_000) / 10_000
        }
        let attack = instances.reduce(base.attack) { total, item in
            let quality = ["Q0": 0, "Q1": 3, "Q2": 6, "Q3": 10, "Q4": 15][item.qualityID, default: 0]
            let affix = item.affixIDs.filter { $0 == "AFFIX_POWER_TEST" }.count * 2
            // LATENT_TEST_01 was written by older Q3→Q4 saves. Preserve its
            // existing positive latent slot as the first registered candidate.
            let latent = ["LATENT_POWER_TEST", "LATENT_TEST_01"].contains(item.latentEffectID ?? "") ? 5 : 0
            let legacy = (rankedBase(gearAttackBonuses[item.definitionID, default: 0], item: item) + affix + latent) * (100 + 3 * item.enhancement + quality + 2 * item.refinement) / 100
            guard enhancementProjectionPolicyR230 == .r2SlotBudgetCandidate else { return total + legacy }
            let baseBonus = rankedBase(gearAttackBonuses[item.definitionID, default: 0], item: item)
            let factorAtZero = 100 + quality + 2 * item.refinement
            let baseEnhancementUplift = baseBonus * (factorAtZero + 3 * item.enhancement) / 100 - baseBonus * factorAtZero / 100
            let slot = gear.first(where: { $0.id == item.definitionID })?.slot ?? ""
            guard let growth = GearEnhancementGrowthR230.delta(slot: slot, enhancement: item.enhancement, refinement: item.refinement) else {
                return total + legacy
            }
            return total + legacy - baseEnhancementUplift + growth.attack
        }
        let hp = instances.reduce(base.hp) { total, item in
            let quality = ["Q0": 0, "Q1": 3, "Q2": 6, "Q3": 10, "Q4": 15][item.qualityID, default: 0]
            let affix = item.affixIDs.filter { $0 == "AFFIX_VITALITY_TEST" }.count * 10 + (item.latentEffectID == "LATENT_VITALITY_TEST" ? 20 : 0)
            let legacy = (rankedBase(gearHPBonuses[item.definitionID, default: 0], item: item) + affix) * (100 + quality + 2 * item.refinement) / 100
            guard enhancementProjectionPolicyR230 == .r2SlotBudgetCandidate else { return total + legacy }
            let slot = gear.first(where: { $0.id == item.definitionID })?.slot ?? ""
            return total + legacy + (GearEnhancementGrowthR230.delta(slot: slot, enhancement: item.enhancement, refinement: item.refinement)?.hp ?? 0)
        }
        let defense = instances.reduce(base.defense) { total, item in
            let quality = ["Q0": 0, "Q1": 3, "Q2": 6, "Q3": 10, "Q4": 15][item.qualityID, default: 0]
            let affix = item.affixIDs.filter { $0 == "AFFIX_GUARD_TEST" }.count + (item.latentEffectID == "LATENT_GUARD_TEST" ? 3 : 0)
            let legacy = (rankedBase(gearDefenseBonuses[item.definitionID, default: 0], item: item) + affix) * (100 + quality + 2 * item.refinement) / 100
            guard enhancementProjectionPolicyR230 == .r2SlotBudgetCandidate else { return total + legacy }
            let slot = gear.first(where: { $0.id == item.definitionID })?.slot ?? ""
            return total + legacy + (GearEnhancementGrowthR230.delta(slot: slot, enhancement: item.enhancement, refinement: item.refinement)?.defense ?? 0)
        }
        let guardChance = instances.reduce(base.guardChanceBP) { total, item in
            total + (gear.first(where: { $0.id == item.definitionID })?.guardChanceBonusBP ?? 0)
        }
        var effects = Set(instances.compactMap { item in gear.first(where: { $0.id == item.definitionID }) }.flatMap(\.effects))
        for item in instances {
            effects.formUnion(item.affixIDs)
            if let latent = item.latentEffectID { effects.insert(latent) }
        }
        let research = research.filter { completedResearchIDs.contains($0.id) }.compactMap { researchEffects[$0.effectID] }
        return Combatant(id: actorID,
                         maxHP: hp + research.reduce(0) { $0 + $1.partyMaxHP },
                         attack: attack + research.reduce(0) { $0 + $1.partyAttack },
                         defense: defense + research.reduce(0) { $0 + $1.partyDefense },
                         effectIDs: effects,
                         guardChanceBP: guardChance,
                         guardReductionBP: 3_500)
    }

    /// Candidate payload projection for the normal candidate battle path. Existing
    /// items with nil payload use the legacy projection byte-for-byte; payload-backed
    /// items use stored slots and do not also apply legacy affix/latent numeric aliases.
    /// Quality changes slot activation/floor only on this candidate route.
    public func projectCandidateCombatantR005(for actorID: String, with gearInstances: [GearInstance],
                                               completedResearchIDs: Set<String> = [], totalXP: Int = 0,
                                               candidateGrowth: CandidateCharacterGrowth? = nil,
                                               candidateLatentPolicy: CandidateLatentSlotPolicyR003,
                                               enhancementProjectionPolicyR230: EnhancementProjectionPolicyR230 = .legacy,
                                               refinementRanksR352: [UUID: Int] = [:]) throws -> CandidateLatentCombatantProjectionR005 {
        let instances = gearInstances.filter { $0.ownerID == nil || $0.ownerID == actorID }
        let legacyItems = instances.filter { $0.candidateLatentSlots == nil }
        let candidateItems = instances.filter { $0.candidateLatentSlots != nil }
        var combatant = projectCombatant(for: actorID, with: legacyItems,
                                         completedResearchIDs: completedResearchIDs,
                                         totalXP: totalXP, candidateGrowth: candidateGrowth,
                                         enhancementProjectionPolicyR230: enhancementProjectionPolicyR230,
                                         refinementRanksR352: refinementRanksR352)
        // Loading a policy must not move an all-legacy loadout onto the candidate
        // combat path. Preserve the exact historical projection and leave the
        // typed timeline modifier absent until at least one item has versioned data.
        guard !candidateItems.isEmpty else {
            return CandidateLatentCombatantProjectionR005(combatant: combatant, latent: nil)
        }

        func add(_ lhs: Int, _ rhs: Int, _ label: String) throws -> Int {
            let (value, overflow) = lhs.addingReportingOverflow(rhs)
            guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            return value
        }
        func scaled(_ amount: Int, _ percent: Int, _ label: String) throws -> Int {
            guard amount >= 0, percent >= 0 else { throw CandidateLatentPolicyErrorR003.invalidRange }
            let (product, overflow) = amount.multipliedReportingOverflow(by: percent)
            guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            return product / 100
        }
        func multiplied(_ lhs: Int, _ rhs: Int) throws -> Int {
            let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
            guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            return value
        }
        func percentApplied(_ amount: Int, _ basisPoints: Int) throws -> Int {
            let (factor, factorOverflow) = 10_000.addingReportingOverflow(basisPoints)
            guard !factorOverflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            let (product, productOverflow) = amount.multipliedReportingOverflow(by: factor)
            guard !productOverflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            return product / 10_000
        }

        func rankedBase(_ value: Int, item: GearInstance) throws -> Int {
            guard let rank = refinementRanksR352[item.id], rank > 1,
                  let multiplier = NaturalGearRefinementPolicyR352.multiplierBasisPointsForPersistedRank(rank) else { return value }
            let (product, overflow) = value.multipliedReportingOverflow(by: multiplier - 10_000)
            guard !overflow else { throw CandidateLatentPolicyErrorR003.arithmeticOverflow }
            return try add(value, product / 10_000, "R352 ranked gear base")
        }
        var candidateGuardBase = combatant.guardChanceBP
        var effects = combatant.effectIDs
        var latentItems: [CandidateLatentEquippedItemR005] = []
        for item in candidateItems {
            guard item.enhancement >= 0, item.refinement >= 0,
                  let definition = gear.first(where: { $0.id == item.definitionID }) else {
                throw CandidateLatentPolicyErrorR003.invalidRange
            }
            let attackEnhancement = try multiplied(3, item.enhancement)
            let attackRefinement = try multiplied(2, item.refinement)
            let hpDefensePercent = try add(100, try multiplied(2, item.refinement), "refinement factor")
            let attackPercent = try add(100, try add(attackEnhancement, attackRefinement, "attack factor"), "attack factor")
            if enhancementProjectionPolicyR230 == .legacy {
                combatant.attack = try add(combatant.attack,
                    scaled(try rankedBase(gearAttackBonuses[item.definitionID, default: 0], item: item), attackPercent, "attack"), "attack")
                combatant.maxHP = try add(combatant.maxHP,
                    scaled(try rankedBase(gearHPBonuses[item.definitionID, default: 0], item: item), hpDefensePercent, "hp"), "hp")
                combatant.defense = try add(combatant.defense,
                    scaled(try rankedBase(gearDefenseBonuses[item.definitionID, default: 0], item: item), hpDefensePercent, "defense"), "defense")
            } else {
                guard let growth = GearEnhancementGrowthR230.delta(slot: definition.slot, enhancement: item.enhancement, refinement: item.refinement) else {
                    throw CandidateLatentPolicyErrorR003.invalidRange
                }
                combatant.attack = try add(combatant.attack,
                    try add(scaled(try rankedBase(gearAttackBonuses[item.definitionID, default: 0], item: item), hpDefensePercent, "attack"), growth.attack, "attack growth"), "attack")
                combatant.maxHP = try add(combatant.maxHP,
                    try add(scaled(try rankedBase(gearHPBonuses[item.definitionID, default: 0], item: item), hpDefensePercent, "hp"), growth.hp, "hp growth"), "hp")
                combatant.defense = try add(combatant.defense,
                    try add(scaled(try rankedBase(gearDefenseBonuses[item.definitionID, default: 0], item: item), hpDefensePercent, "defense"), growth.defense, "defense growth"), "defense")
            }
            candidateGuardBase = try add(candidateGuardBase, definition.guardChanceBonusBP ?? 0, "guard chance")
            effects.formUnion(definition.effects)
            latentItems.append(CandidateLatentEquippedItemR005(id: item.id, templateID: item.definitionID,
                                                               qualityID: item.qualityID,
                                                               candidateSlots: item.candidateLatentSlots))
        }
        let baseline = CandidateLatentCombatModifiersR005.baseValuesBP(actorID: actorID,
                                                                       existingGuardChanceBP: candidateGuardBase)
        let latent = try candidateLatentPolicy.projectActorModifiers(actorID: actorID,
                                                                      baseValuesBP: baseline,
                                                                      equippedItems: latentItems)
        combatant.maxHP = try percentApplied(combatant.maxHP, latent.modifiers.hpPercentBP)
        combatant.attack = try percentApplied(combatant.attack, latent.modifiers.powerPercentBP)
        combatant.defense = try percentApplied(combatant.defense, latent.modifiers.defensePercentBP)
        combatant.guardChanceBP = latent.modifiers.guardChanceBP
        combatant.effectIDs = effects
        combatant.candidateLatentModifiersR004 = latent.modifiers
        return CandidateLatentCombatantProjectionR005(combatant: combatant, latent: latent)
    }

    public init(version: String, regions: [RegionDefinition], enemies: [EnemyDefinition], gear: [GearDefinition], research: [ResearchDefinition], materialIDs: [String] = [], materialAvailabilityGates: [String: String] = [:], recipes: [RecipeDefinition] = [], actorIDs: [String] = [], challenges: [ChallengeDefinition] = [], researchEffects: [String: ResearchStatEffect] = [:], appearances: [AppearanceDefinition] = [], furnitureIDs: [String] = [], dailyFreeTicketGrant: Int = 5, authority: BalanceAuthority = .unapprovedTestOverlay, gearAttackBonuses: [String: Int] = [:], gearHPBonuses: [String: Int] = [:], gearDefenseBonuses: [String: Int] = [:], gachaOddsBasisPoints: [String: Int] = ["Q0": 3_500, "Q1": 4_000, "Q2": 2_000, "Q3": 400, "Q4": 100]) {
        self.version = version; self.authority = authority
        self.regions = regions; self.enemies = enemies; self.gear = gear; self.research = research; self.materialIDs = materialIDs; self.materialAvailabilityGates = materialAvailabilityGates; self.recipes = recipes; self.actorIDs = actorIDs
        self.gearAttackBonuses = gearAttackBonuses; self.gearHPBonuses = gearHPBonuses; self.gearDefenseBonuses = gearDefenseBonuses
        self.gachaOddsBasisPoints = gachaOddsBasisPoints
        self.challenges = challenges
        self.researchEffects = researchEffects
        self.appearances = appearances
        self.furnitureIDs = furnitureIDs
        self.dailyFreeTicketGrant = dailyFreeTicketGrant
    }
    /// Returns a test-only balance variant without changing the bundled candidate catalog.
    public func withDailyFreeTicketGrant(_ amount: Int) -> GameCatalog {
        var copy = self
        copy.dailyFreeTicketGrant = amount
        return copy
    }
    public func challengeCombatScenario(_ challengeID: String) throws -> ChallengeCombatScenario {
        guard let challenge = challenges.first(where: { $0.id == challengeID }) else { throw CoreError.invalidCommand("unknown challenge") }
        let definitions = challenge.enemyIDs.compactMap { id in enemies.first(where: { $0.id == id }) }
        guard !definitions.isEmpty, definitions.count == challenge.enemyIDs.count else { throw CoreError.invalidCatalog("challenge references unresolved enemy IDs: \(challengeID)") }
        var foes = definitions.map { definition in
            // CH_R02_01 explicitly requires the candidate DoT mechanic. Its first authored
            // enemy's general-purpose drowse pattern otherwise overrides the challenge pattern.
            let actionPattern = challengeID == "CH_R02_01" && definition.id == "E_R02_01"
                ? challenge.actionPattern
                : (definition.actionPattern ?? challenge.actionPattern)
            return Combatant(id: definition.id, maxHP: definition.hp * challenge.enemyHPScale,
                             attack: definition.attack * challenge.enemyAttackScale,
                             defense: definition.defense, actionPattern: actionPattern)
        }
        var presentation = Dictionary(uniqueKeysWithValues: definitions.map { enemy in
            (enemy.id, CombatEntityPresentation(entityID: enemy.id, kind: "enemy", catalogID: enemy.id, label: enemy.name, assetKey: enemy.id))
        })
        if ["CH_R01_02", "CH_R02_03", "CH_R03_03"].contains(challengeID) {
            let base = definitions[0]
            // R220 candidate consistency: two authored enemies plus one support add.
            let additionalCount = challengeID == "CH_R01_02" ? 1 : 2
            for index in 1...additionalCount {
                let addID = "\(challengeID)_ADD_\(index)"
                foes.append(Combatant(id: addID, maxHP: max(1, base.hp * challenge.enemyHPScale / 4), attack: max(1, base.attack * challenge.enemyAttackScale / 2), defense: base.defense, actionPattern: index == 1 ? "support" : "multiHit"))
                presentation[addID] = CombatEntityPresentation(entityID: addID, kind: "add", catalogID: base.id, label: index == 1 ? "小型支援個体" : "小型追撃個体", assetKey: base.id)
            }
        }
        if challengeID == "CH_R05_02", let guardian = definitions.first {
            let lampID = "LAMP_VESSEL_\(challengeID)"
            foes.insert(Combatant(id: lampID, maxHP: max(1, guardian.hp * challenge.enemyHPScale * 3 / 2), attack: 0, defense: 0, actionPattern: "stationary"), at: 0)
            presentation[lampID] = CombatEntityPresentation(entityID: lampID, kind: "prop", label: "灯瓶", assetKey: "PROP_LAMP_VESSEL")
        }
        return ChallengeCombatScenario(challengeID: challengeID, enemies: foes, entityPresentation: presentation)
    }
    public func validate() throws {
        guard dailyFreeTicketGrant >= 0 else { throw CoreError.invalidCatalog("daily free ticket grant cannot be negative") }
        func unique(_ ids: [String], _ label: String) throws {
            guard Set(ids).count == ids.count, ids.allSatisfy({ !$0.isEmpty }) else { throw CoreError.invalidCatalog("duplicate/empty \(label) ID") }
        }
        try unique(regions.map(\.id), "region"); try unique(enemies.map(\.id), "enemy")
        try unique(gear.map(\.id), "gear"); try unique(research.map(\.id), "research")
        try unique(challenges.map(\.id), "challenge")
        try unique(appearances.map(\.id), "appearance")
        try unique(furnitureIDs, "furniture")
        guard materialAvailabilityGates.keys.allSatisfy(materialIDs.contains), materialAvailabilityGates.values.allSatisfy({ gate in
            if gate == "G_START" { return true }
            let parts = gate.split(separator: "_")
            return parts.count == 3 && parts[0] == "G" && enemies.contains(where: { $0.id == "B_\(parts[1])_\(parts[2])" })
        }) else { throw CoreError.invalidCatalog("material availability gate references are invalid") }
        guard materialAvailabilityGates.isEmpty || regions.flatMap(\.gatherMaterialIDs).allSatisfy(materialAvailabilityGates.keys.contains) else { throw CoreError.invalidCatalog("gatherable content is missing its source availability gate") }
        guard appearances.allSatisfy({ ["costume", "weapon", "accessory"].contains($0.kind) && !$0.actorIDs.isEmpty && $0.actorIDs.allSatisfy(Set(actorIDs).contains) }) else { throw CoreError.invalidCatalog("invalid appearance definition") }
        guard researchEffects.keys.allSatisfy({ key in research.contains(where: { $0.effectID == key }) }), researchEffects.values.allSatisfy({ $0.partyAttack >= 0 && $0.partyMaxHP >= 0 && $0.partyDefense >= 0 }) else { throw CoreError.invalidCatalog("research effect references or values invalid") }
        guard Set(gachaOddsBasisPoints.keys) == Set(["Q0", "Q1", "Q2", "Q3", "Q4"]), gachaOddsBasisPoints.values.allSatisfy({ $0 >= 0 }), gachaOddsBasisPoints.values.reduce(0, +) == 10_000 else { throw CoreError.invalidCatalog("gacha quality profile must contain Q0...Q4 and sum to 10000 basis points") }
        guard gear.allSatisfy({ $0.actorIDs.allSatisfy(Set(actorIDs).contains) }) else { throw CoreError.invalidCatalog("gear references unknown actor") }
        guard recipes.allSatisfy({ recipe in recipe.outputGearID == nil || gear.contains(where: { $0.id == recipe.outputGearID }) }) else { throw CoreError.invalidCatalog("recipe output is unknown") }
        guard recipes.allSatisfy({ recipe in recipe.costs.allSatisfy { materialIDs.contains($0.key) && $0.value > 0 } }) else { throw CoreError.invalidCatalog("recipe references unknown material or nonpositive cost") }
        let regionIDs = Set(regions.map(\.id)), enemyIDs = Set(enemies.map(\.id))
        guard enemies.allSatisfy({ regionIDs.contains($0.regionID) }), regions.allSatisfy({ $0.enemyIDs.allSatisfy(enemyIDs.contains) }) else { throw CoreError.invalidCatalog("broken region/enemy reference") }
        guard challenges.allSatisfy({ challenge in regions.contains(where: { $0.id == challenge.region }) && !challenge.enemyIDs.isEmpty && challenge.enemyIDs.allSatisfy(enemyIDs.contains) && challenge.firstClearPowder >= 0 && challenge.enemyHPScale > 0 && challenge.enemyAttackScale > 0 }) else { throw CoreError.invalidCatalog("broken challenge references") }
    }
    public static func bundledTestOverlay() throws -> GameCatalog {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "catalog_overlay", withExtension: "json") else { throw CoreError.invalidCatalog("bundled overlay missing") }
        let value = try JSONDecoder().decode(GameCatalog.self, from: Data(contentsOf: url)); try value.validate(); return value
    }
}

public struct GearInstance: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var definitionID: String
    public var ownerID: String?
    public var protected: Bool
    public var enhancement: Int
    public var refinement: Int
    public var latentEffectID: String?
    /// Optional candidate-only payload. Nil preserves legacy bytes/semantics; it is never
    /// synthesized while decoding an existing save.
    public var candidateLatentSlots: CandidateLatentSlotsR003?
    public var qualityID: String
    public var affixIDs: [String]
    public var investmentDust: Int
    public init(id: UUID = UUID(), definitionID: String, ownerID: String? = nil, protected: Bool = false, enhancement: Int = 0, refinement: Int = 0, latentEffectID: String? = nil, candidateLatentSlots: CandidateLatentSlotsR003? = nil, qualityID: String = "Q0", affixIDs: [String] = [], investmentDust: Int = 0) {
        self.id = id; self.definitionID = definitionID; self.ownerID = ownerID; self.protected = protected; self.enhancement = enhancement; self.refinement = refinement; self.latentEffectID = latentEffectID; self.candidateLatentSlots = candidateLatentSlots; self.qualityID = qualityID; self.affixIDs = affixIDs; self.investmentDust = investmentDust
    }
    enum CodingKeys: String, CodingKey { case id, definitionID, ownerID, protected, enhancement, refinement, latentEffectID, candidateLatentSlots, qualityID, affixIDs, investmentDust }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        definitionID = try c.decode(String.self, forKey: .definitionID)
        ownerID = try c.decodeIfPresent(String.self, forKey: .ownerID)
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        enhancement = try c.decodeIfPresent(Int.self, forKey: .enhancement) ?? 0
        refinement = try c.decodeIfPresent(Int.self, forKey: .refinement) ?? 0
        latentEffectID = try c.decodeIfPresent(String.self, forKey: .latentEffectID)
        candidateLatentSlots = try c.decodeIfPresent(CandidateLatentSlotsR003.self, forKey: .candidateLatentSlots)
        qualityID = try c.decodeIfPresent(String.self, forKey: .qualityID) ?? "Q0"
        affixIDs = try c.decodeIfPresent([String].self, forKey: .affixIDs) ?? []
        investmentDust = try c.decodeIfPresent(Int.self, forKey: .investmentDust) ?? 0
    }
}

public struct GachaPityState: Codable, Sendable, Equatable {
    public var drawsSinceTop: Int = 0
    public var drawsSinceMid: Int = 0
    public var targetTemplateID: String?
    public var guaranteeTargetOnNextTop = false
    public init(drawsSinceTop: Int = 0, drawsSinceMid: Int = 0, targetTemplateID: String? = nil, guaranteeTargetOnNextTop: Bool = false) { self.drawsSinceTop = drawsSinceTop; self.drawsSinceMid = drawsSinceMid; self.targetTemplateID = targetTemplateID; self.guaranteeTargetOnNextTop = guaranteeTargetOnNextTop }
    enum CodingKeys: String, CodingKey { case drawsSinceTop, drawsSinceMid, targetTemplateID, guaranteeTargetOnNextTop }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drawsSinceTop = try c.decodeIfPresent(Int.self, forKey: .drawsSinceTop) ?? 0
        drawsSinceMid = try c.decodeIfPresent(Int.self, forKey: .drawsSinceMid) ?? 0
        targetTemplateID = try c.decodeIfPresent(String.self, forKey: .targetTemplateID)
        guaranteeTargetOnNextTop = try c.decodeIfPresent(Bool.self, forKey: .guaranteeTargetOnNextTop) ?? false
    }
}
public enum MockPurchaseStatus: String, Codable, Sendable, CaseIterable { case pending, interrupted, cancelled, restored, refunded, revoked }
public struct MockPurchaseRecord: Codable, Sendable, Equatable, Identifiable {
    public let transactionID: String
    public let productID: String
    public var status: MockPurchaseStatus
    public let updatedAt: Date
    public var id: String { transactionID }
    public init(transactionID: String, productID: String, status: MockPurchaseStatus, updatedAt: Date) { self.transactionID = transactionID; self.productID = productID; self.status = status; self.updatedAt = updatedAt }
}
/// Local StoreKit bridge QA evidence only. It does not grant production entitlements.
public enum LocalStoreKitQAEventKind: String, Codable, Sendable { case purchase, revocation }
public struct LocalStoreKitQARecord: Codable, Sendable, Equatable, Identifiable {
    public let productID: String
    public let kind: LocalStoreKitQAEventKind
    public let transactionID: String
    public let recordedAt: Date
    public var id: String { transactionID }
    public init(productID: String, kind: LocalStoreKitQAEventKind, transactionID: String, recordedAt: Date) {
        self.productID = productID; self.kind = kind; self.transactionID = transactionID; self.recordedAt = recordedAt
    }
}
/// Candidate R3 optional reward. This local QA model is not a verified ad-provider receipt.
public enum LocalAdAttemptOutcome: String, Codable, Sendable { case completed, cancelled, failed }
/// Constructed by the explicit local QA adapter; never accepted as a production-provider receipt.
public struct LocalRewardedAdQAResult: Sendable, Equatable {
    public let sessionID: String
    public let outcome: LocalAdAttemptOutcome
    let validationSource: String
    private init(sessionID: String, outcome: LocalAdAttemptOutcome, validationSource: String) {
        self.sessionID = sessionID; self.outcome = outcome; self.validationSource = validationSource
    }
    public static func simulate(sessionID: String, outcome: LocalAdAttemptOutcome) -> Self {
        Self(sessionID: sessionID, outcome: outcome, validationSource: "LOCAL_QA_SIMULATOR")
    }
}
public struct LocalAdRewardOpportunity: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let baseXPByActor: [String: Int]
    public let baseDust: Int
    public let rewardXPByActor: [String: Int]
    public let rewardDust: Int
    public let createdAt: Date
    public let rewardXPRemainderSixteenths: [String: Int]
    public let rewardDustRemainderSixteenths: Int
    public init(id: String, baseXPByActor: [String: Int], baseDust: Int, createdAt: Date) {
        self.id = id; self.baseXPByActor = baseXPByActor; self.baseDust = baseDust
        self.rewardXPByActor = baseXPByActor.mapValues { $0 / 16 }; self.rewardDust = baseDust / 16
        self.createdAt = createdAt; self.rewardXPRemainderSixteenths = baseXPByActor.mapValues { $0 % 16 }; self.rewardDustRemainderSixteenths = baseDust % 16
    }
}
public struct LocalAdAttemptRecord: Codable, Sendable, Equatable, Identifiable {
    public let sessionID: String
    public let opportunityID: String
    public let outcome: LocalAdAttemptOutcome
    public let claimedByAdSkip: Bool
    public let recordedAt: Date
    public let rewardXPByActor: [String: Int]
    public let rewardDust: Int
    public var id: String { sessionID }
    public init(sessionID: String, opportunityID: String, outcome: LocalAdAttemptOutcome, claimedByAdSkip: Bool, recordedAt: Date, rewardXPByActor: [String: Int], rewardDust: Int) {
        self.sessionID = sessionID; self.opportunityID = opportunityID; self.outcome = outcome; self.claimedByAdSkip = claimedByAdSkip; self.recordedAt = recordedAt; self.rewardXPByActor = rewardXPByActor; self.rewardDust = rewardDust
    }
}
/// Persisted, typed selector for the single R144 comparison-policy work slot.
/// A missing value is a legacy save and falls back to gatherTargetMaterialID.
public struct PartyWorkTargetR144: Codable, Sendable, Equatable {
    /// Nested marker makes older readers reject candidate saves rather than
    /// interpreting investigation as the legacy gather target.
    public let futureVersion: Int
    public enum Kind: String, Codable, Sendable { case gather, investigate }
    public let kind: Kind
    public let targetID: String
    public init(kind: Kind, targetID: String) { self.futureVersion = 2; self.kind = kind; self.targetID = targetID }
    public static func gather(_ materialID: String) -> Self { Self(kind: .gather, targetID: materialID) }
    public static func investigate(_ enemyID: String) -> Self { Self(kind: .investigate, targetID: enemyID) }
}

/// Captures every JSON key, including fields unknown to the typed model.
private struct GearLoadoutJSONKeyR342: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public enum GearLoadoutSlotR342: Int, Codable, Sendable, CaseIterable {
    case first = 1
    case second = 2
}

/// A saved loadout records only owned gear instance IDs and actor-slot assignments.
/// It deliberately does not snapshot stats, enhancement, quality, or latent payloads.
public struct GearLoadoutR342: Codable, Sendable, Equatable {
    public let gearByActorSlot: [String: UUID]
    public init(gearByActorSlot: [String: UUID]) { self.gearByActorSlot = gearByActorSlot }

    private enum CodingKeys: String, CodingKey { case gearByActorSlot }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: GearLoadoutJSONKeyR342.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(raw.allKeys.map(\.stringValue)) == Set(["gearByActorSlot"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "R342 loadout has unknown fields"))
        }
        let map = try c.decode([String: UUID].self, forKey: .gearByActorSlot)
        let validKeys = map.keys.allSatisfy { key in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
        }
        guard !map.isEmpty, validKeys, Set(map.values).count == map.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "R342 loadout assignments are malformed"))
        }
        self.gearByActorSlot = map
    }
}

/// Opt-in, versioned R342 payload. The futureVersion marker makes older readers reject
/// this save instead of silently ignoring the loadout while continuing to write it.
public struct GearLoadoutsR342: Codable, Sendable, Equatable {
    public let futureVersion: Int
    public private(set) var first: GearLoadoutR342?
    public private(set) var second: GearLoadoutR342?

    init(first: GearLoadoutR342? = nil, second: GearLoadoutR342? = nil) {
        self.futureVersion = 2
        self.first = first
        self.second = second
    }

    public func loadout(for slot: GearLoadoutSlotR342) -> GearLoadoutR342? {
        switch slot { case .first: first; case .second: second }
    }

    /// Gear referenced by either saved set remains valuable even while unequipped.
    public var referencedGearIDs: Set<UUID> {
        Set([first, second].compactMap { $0 }.flatMap { $0.gearByActorSlot.values })
    }

    mutating func set(_ loadout: GearLoadoutR342?, for slot: GearLoadoutSlotR342) {
        switch slot { case .first: first = loadout; case .second: second = loadout }
    }

    enum CodingKeys: String, CodingKey { case futureVersion, first, second }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: GearLoadoutJSONKeyR342.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let keys = Set(raw.allKeys.map(\.stringValue))
        guard keys.isSubset(of: Set(["futureVersion", "first", "second"])), keys.contains("futureVersion") else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "R342 payload has unknown fields or is missing its marker"))
        }
        let version = try c.decode(Int.self, forKey: .futureVersion)
        guard version == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .futureVersion, in: c,
                debugDescription: "Unsupported R342 gear-loadout payload version")
        }
        for key in [CodingKeys.first, .second] where c.contains(key) {
            guard try !c.decodeNil(forKey: key) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c,
                    debugDescription: "An absent gear-loadout slot must be omitted, not null")
            }
        }
        let first = try c.decodeIfPresent(GearLoadoutR342.self, forKey: .first)
        let second = try c.decodeIfPresent(GearLoadoutR342.self, forKey: .second)
        guard first != nil || second != nil else {
            throw DecodingError.dataCorruptedError(forKey: .first, in: c,
                debugDescription: "An empty gear-loadout payload must be omitted")
        }
        for loadout in [first, second].compactMap({ $0 }) {
            let map = loadout.gearByActorSlot
            guard !map.isEmpty,
                  map.keys.allSatisfy({ key in
                      let parts = key.split(separator: "|", omittingEmptySubsequences: false)
                      return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
                  }),
                  Set(map.values).count == map.count else {
                throw DecodingError.dataCorruptedError(forKey: .first, in: c,
                    debugDescription: "Malformed or duplicate gear assignment in R342 loadout")
            }
        }
        self.futureVersion = version
        self.first = first
        self.second = second
    }
}

public struct GameSnapshot: Codable, Sendable, Equatable {
    public var revision: Int64
    public var currency: [String: Int]
    public var materials: [String: Int]
    public var characterXP: [String: Int]
    public var gear: [GearInstance]
    public var unlockedRegionIDs: Set<String>
    public var completedResearchIDs: Set<String>
    public var equippedGearIDs: [String: UUID]
    /// Missing in legacy saves; the opt-in R342 profile alone writes this future payload.
    public var gearLoadoutsR342: GearLoadoutsR342?
    public var ownedCosmeticIDs: Set<String>
    /// Provenance is nil in legacy saves; existing owned IDs then remain free-owned.
    public var commerceOwnershipR1: CommerceOwnershipProvenanceR1?
    public var selectedCosmeticIDs: [String: String]
    public var ownedFurnitureIDs: Set<String>
    public var placedFurnitureIDs: Set<String>
    public var lastClaimAt: Date?
    public var offlineRemainderSeconds: TimeInterval
    public var pendingPurchaseIDs: Set<String>
    public var lastDailyClaimKey: String?
    public var lastDailyClaimAt: Date?
    public var partyActorIDs: [String]
    public var activeRegionID: String?
    public var gatherTargetMaterialID: String?
    /// Optional R144 single-work-slot selector; absent in old saves uses legacy gather target.
    public var partyWorkTargetR144: PartyWorkTargetR144?
    /// Explicitly opted-in R350 natural discovery state; absent legacy saves stay unchanged.
    public var naturalGearDiscoveryR350: NaturalGearDiscoveryLedgerR350?
    /// R352 opt-in per-instance refinement rank; absent entries mean rank I.
    public var naturalGearRefinementR352: NaturalGearRefinementLedgerR352?
    public var completedEncounterIDs: Set<String>
    public var lastCombatResult: CombatResult?
    public var lastEncounterID: String?
    /// Optional player-selected recipe goal; absent in legacy saves means no goal.
    public var trackedRecipeID: String?
    /// R179 development-only first-craft eligibility; absent old saves decode safely to false.
    public var firstCraftAidEligibleR179: Bool?
    public var craftedGearOnce: Bool
    public var gearComparisonSeen: Bool
    public var gachaUnlocked: Bool
    public var gachaPity: GachaPityState
    public var mockPurchaseRecords: [String: MockPurchaseRecord]
    public var selectedWeaponAppearanceIDs: [String: String]
    public var localStoreKitQARecords: [String: LocalStoreKitQARecord]
    public var localStoreKitQAOwnedProductIDs: Set<String>
    public var localAdSkipEntitledForQA: Bool
    public var localAdWorkBlockSeconds: Int
    public var localAdWorkBlockXPByActor: [String: Int]
    public var localAdWorkBlockDust: Int
    public var localAdXPFractionalCarry: [String: Int]
    public var localAdDustFractionalCarry: Int
    public var localAdNextOpportunitySequence: Int
    public var localAdRewardOpportunities: [String: LocalAdRewardOpportunity]
    public var localAdAttemptRecords: [String: LocalAdAttemptRecord]
    public init(revision: Int64 = 0, currency: [String: Int] = ["coin": 0, "ticket_free": 0, "ticket_paid_mock": 0], materials: [String: Int] = [:], characterXP: [String: Int] = [:], gear: [GearInstance] = [], unlockedRegionIDs: Set<String> = [], completedResearchIDs: Set<String> = [], equippedGearIDs: [String: UUID] = [:], gearLoadoutsR342: GearLoadoutsR342? = nil, ownedCosmeticIDs: Set<String> = [], commerceOwnershipR1: CommerceOwnershipProvenanceR1? = nil, selectedCosmeticIDs: [String: String] = [:], selectedWeaponAppearanceIDs: [String: String] = [:], ownedFurnitureIDs: Set<String> = [], placedFurnitureIDs: Set<String> = [], lastClaimAt: Date? = nil, offlineRemainderSeconds: TimeInterval = 0, pendingPurchaseIDs: Set<String> = [], mockPurchaseRecords: [String: MockPurchaseRecord] = [:], lastDailyClaimKey: String? = nil, lastDailyClaimAt: Date? = nil, partyActorIDs: [String] = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"], activeRegionID: String? = nil, gatherTargetMaterialID: String? = nil, partyWorkTargetR144: PartyWorkTargetR144? = nil, naturalGearDiscoveryR350: NaturalGearDiscoveryLedgerR350? = nil, naturalGearRefinementR352: NaturalGearRefinementLedgerR352? = nil, completedEncounterIDs: Set<String> = [], lastCombatResult: CombatResult? = nil, lastEncounterID: String? = nil, trackedRecipeID: String? = nil, firstCraftAidEligibleR179: Bool? = nil, craftedGearOnce: Bool = false, gearComparisonSeen: Bool = false, gachaUnlocked: Bool = false, gachaPity: GachaPityState = GachaPityState(), localStoreKitQARecords: [String: LocalStoreKitQARecord] = [:], localStoreKitQAOwnedProductIDs: Set<String> = [], localAdSkipEntitledForQA: Bool = false, localAdWorkBlockSeconds: Int = 0, localAdWorkBlockXPByActor: [String: Int] = [:], localAdWorkBlockDust: Int = 0, localAdXPFractionalCarry: [String: Int] = [:], localAdDustFractionalCarry: Int = 0, localAdNextOpportunitySequence: Int = 1, localAdRewardOpportunities: [String: LocalAdRewardOpportunity] = [:], localAdAttemptRecords: [String: LocalAdAttemptRecord] = [:]) {
        self.revision = revision; self.currency = currency; self.materials = materials; self.characterXP = characterXP; self.gear = gear; self.unlockedRegionIDs = unlockedRegionIDs; self.completedResearchIDs = completedResearchIDs; self.equippedGearIDs = equippedGearIDs; self.gearLoadoutsR342 = gearLoadoutsR342; self.ownedCosmeticIDs = ownedCosmeticIDs; self.commerceOwnershipR1 = commerceOwnershipR1; self.selectedCosmeticIDs = selectedCosmeticIDs; self.selectedWeaponAppearanceIDs = selectedWeaponAppearanceIDs; self.ownedFurnitureIDs = ownedFurnitureIDs; self.placedFurnitureIDs = placedFurnitureIDs; self.lastClaimAt = lastClaimAt; self.offlineRemainderSeconds = offlineRemainderSeconds; self.pendingPurchaseIDs = pendingPurchaseIDs; self.mockPurchaseRecords = mockPurchaseRecords; self.lastDailyClaimKey = lastDailyClaimKey; self.lastDailyClaimAt = lastDailyClaimAt; self.partyActorIDs = partyActorIDs; self.activeRegionID = activeRegionID; self.gatherTargetMaterialID = gatherTargetMaterialID; self.partyWorkTargetR144 = partyWorkTargetR144; self.naturalGearDiscoveryR350 = naturalGearDiscoveryR350; self.naturalGearRefinementR352 = naturalGearRefinementR352; self.completedEncounterIDs = completedEncounterIDs; self.lastCombatResult = lastCombatResult; self.lastEncounterID = lastEncounterID; self.trackedRecipeID = trackedRecipeID; self.firstCraftAidEligibleR179 = firstCraftAidEligibleR179; self.craftedGearOnce = craftedGearOnce; self.gearComparisonSeen = gearComparisonSeen; self.gachaUnlocked = gachaUnlocked; self.gachaPity = gachaPity; self.localStoreKitQARecords = localStoreKitQARecords; self.localStoreKitQAOwnedProductIDs = localStoreKitQAOwnedProductIDs; self.localAdSkipEntitledForQA = localAdSkipEntitledForQA; self.localAdWorkBlockSeconds = localAdWorkBlockSeconds; self.localAdWorkBlockXPByActor = localAdWorkBlockXPByActor; self.localAdWorkBlockDust = localAdWorkBlockDust; self.localAdXPFractionalCarry = localAdXPFractionalCarry; self.localAdDustFractionalCarry = localAdDustFractionalCarry; self.localAdNextOpportunitySequence = localAdNextOpportunitySequence; self.localAdRewardOpportunities = localAdRewardOpportunities; self.localAdAttemptRecords = localAdAttemptRecords
    }
    enum CodingKeys: String, CodingKey { case revision, currency, materials, characterXP, gear, unlockedRegionIDs, completedResearchIDs, equippedGearIDs, gearLoadoutsR342, ownedCosmeticIDs, commerceOwnershipR1, selectedCosmeticIDs, selectedWeaponAppearanceIDs, ownedFurnitureIDs, placedFurnitureIDs, lastClaimAt, offlineRemainderSeconds, pendingPurchaseIDs, mockPurchaseRecords, localStoreKitQARecords, localStoreKitQAOwnedProductIDs, localAdSkipEntitledForQA, localAdWorkBlockSeconds, localAdWorkBlockXPByActor, localAdWorkBlockDust, localAdXPFractionalCarry, localAdDustFractionalCarry, localAdNextOpportunitySequence, localAdRewardOpportunities, localAdAttemptRecords, lastDailyClaimKey, lastDailyClaimAt, partyActorIDs, activeRegionID, gatherTargetMaterialID, partyWorkTargetR144, naturalGearDiscoveryR350, naturalGearRefinementR352, completedEncounterIDs, lastCombatResult, lastEncounterID, trackedRecipeID, firstCraftAidEligibleR179, craftedGearOnce, gearComparisonSeen, gachaUnlocked, gachaPity }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
        currency = try c.decodeIfPresent([String: Int].self, forKey: .currency) ?? ["coin": 0, "ticket_free": 0, "ticket_paid_mock": 0]
        materials = try c.decodeIfPresent([String: Int].self, forKey: .materials) ?? [:]
        characterXP = try c.decodeIfPresent([String: Int].self, forKey: .characterXP) ?? [:]
        gear = try c.decodeIfPresent([GearInstance].self, forKey: .gear) ?? []
        unlockedRegionIDs = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedRegionIDs) ?? []
        completedResearchIDs = try c.decodeIfPresent(Set<String>.self, forKey: .completedResearchIDs) ?? []
        equippedGearIDs = try c.decodeIfPresent([String: UUID].self, forKey: .equippedGearIDs) ?? [:]
        gearLoadoutsR342 = try c.decodeIfPresent(GearLoadoutsR342.self, forKey: .gearLoadoutsR342)
        ownedCosmeticIDs = try c.decodeIfPresent(Set<String>.self, forKey: .ownedCosmeticIDs) ?? []
        commerceOwnershipR1 = try c.decodeIfPresent(CommerceOwnershipProvenanceR1.self, forKey: .commerceOwnershipR1)
        selectedCosmeticIDs = try c.decodeIfPresent([String: String].self, forKey: .selectedCosmeticIDs) ?? [:]
        selectedWeaponAppearanceIDs = try c.decodeIfPresent([String: String].self, forKey: .selectedWeaponAppearanceIDs) ?? [:]
        ownedFurnitureIDs = try c.decodeIfPresent(Set<String>.self, forKey: .ownedFurnitureIDs) ?? []
        placedFurnitureIDs = try c.decodeIfPresent(Set<String>.self, forKey: .placedFurnitureIDs) ?? []
        lastClaimAt = try c.decodeIfPresent(Date.self, forKey: .lastClaimAt)
        offlineRemainderSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .offlineRemainderSeconds) ?? 0
        pendingPurchaseIDs = try c.decodeIfPresent(Set<String>.self, forKey: .pendingPurchaseIDs) ?? []
        mockPurchaseRecords = try c.decodeIfPresent([String: MockPurchaseRecord].self, forKey: .mockPurchaseRecords) ?? [:]
        localStoreKitQARecords = try c.decodeIfPresent([String: LocalStoreKitQARecord].self, forKey: .localStoreKitQARecords) ?? [:]
        localStoreKitQAOwnedProductIDs = try c.decodeIfPresent(Set<String>.self, forKey: .localStoreKitQAOwnedProductIDs) ?? []
        localAdSkipEntitledForQA = try c.decodeIfPresent(Bool.self, forKey: .localAdSkipEntitledForQA) ?? false
        localAdWorkBlockSeconds = try c.decodeIfPresent(Int.self, forKey: .localAdWorkBlockSeconds) ?? 0
        localAdWorkBlockXPByActor = try c.decodeIfPresent([String: Int].self, forKey: .localAdWorkBlockXPByActor) ?? [:]
        localAdWorkBlockDust = try c.decodeIfPresent(Int.self, forKey: .localAdWorkBlockDust) ?? 0
        localAdXPFractionalCarry = try c.decodeIfPresent([String: Int].self, forKey: .localAdXPFractionalCarry) ?? [:]
        localAdDustFractionalCarry = try c.decodeIfPresent(Int.self, forKey: .localAdDustFractionalCarry) ?? 0
        localAdNextOpportunitySequence = try c.decodeIfPresent(Int.self, forKey: .localAdNextOpportunitySequence) ?? 1
        localAdRewardOpportunities = try c.decodeIfPresent([String: LocalAdRewardOpportunity].self, forKey: .localAdRewardOpportunities) ?? [:]
        localAdAttemptRecords = try c.decodeIfPresent([String: LocalAdAttemptRecord].self, forKey: .localAdAttemptRecords) ?? [:]
        lastDailyClaimKey = try c.decodeIfPresent(String.self, forKey: .lastDailyClaimKey)
        lastDailyClaimAt = try c.decodeIfPresent(Date.self, forKey: .lastDailyClaimAt)
        partyActorIDs = try c.decodeIfPresent([String].self, forKey: .partyActorIDs) ?? ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        activeRegionID = try c.decodeIfPresent(String.self, forKey: .activeRegionID)
        gatherTargetMaterialID = try c.decodeIfPresent(String.self, forKey: .gatherTargetMaterialID)
        partyWorkTargetR144 = try c.decodeIfPresent(PartyWorkTargetR144.self, forKey: .partyWorkTargetR144)
        naturalGearDiscoveryR350 = try c.decodeIfPresent(NaturalGearDiscoveryLedgerR350.self, forKey: .naturalGearDiscoveryR350)
        naturalGearRefinementR352 = try c.decodeIfPresent(NaturalGearRefinementLedgerR352.self, forKey: .naturalGearRefinementR352)
        completedEncounterIDs = try c.decodeIfPresent(Set<String>.self, forKey: .completedEncounterIDs) ?? []
        lastCombatResult = try c.decodeIfPresent(CombatResult.self, forKey: .lastCombatResult)
        lastEncounterID = try c.decodeIfPresent(String.self, forKey: .lastEncounterID)
        trackedRecipeID = try c.decodeIfPresent(String.self, forKey: .trackedRecipeID)
        firstCraftAidEligibleR179 = try c.decodeIfPresent(Bool.self, forKey: .firstCraftAidEligibleR179)
        craftedGearOnce = try c.decodeIfPresent(Bool.self, forKey: .craftedGearOnce) ?? false
        gearComparisonSeen = try c.decodeIfPresent(Bool.self, forKey: .gearComparisonSeen) ?? false
        gachaUnlocked = try c.decodeIfPresent(Bool.self, forKey: .gachaUnlocked) ?? false
        gachaPity = try c.decodeIfPresent(GachaPityState.self, forKey: .gachaPity) ?? GachaPityState()
    }
    public static func newGame(catalog: GameCatalog) -> GameSnapshot {
        let actors = catalog.actorIDs.count == 4 ? catalog.actorIDs : ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        let ids = ["10000000-0000-4000-8000-000000000001", "10000000-0000-4000-8000-000000000002", "10000000-0000-4000-8000-000000000003", "10000000-0000-4000-8000-000000000004"]
        let starts = ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"].enumerated().compactMap { index, definitionID -> GearInstance? in
            guard catalog.gear.contains(where: { $0.id == definitionID }), let uuid = UUID(uuidString: ids[index]) else { return nil }
            return GearInstance(id: uuid, definitionID: definitionID, ownerID: actors[index])
        }
        let equipped = Dictionary(uniqueKeysWithValues: zip(starts, actors).map { item, actor in
            let slot = catalog.gear.first(where: { $0.id == item.definitionID })?.slot ?? "unknown"
            return (actor + "|" + slot, item.id)
        })
        let firstRegion = catalog.regions.first
        return GameSnapshot(currency: ["coin": 0, "ticket_free": 5, "ticket_paid_mock": 0], gear: starts.map { GearInstance(id: $0.id, definitionID: $0.definitionID, ownerID: $0.ownerID, protected: true) }, unlockedRegionIDs: Set(firstRegion.map { [$0.id] } ?? []), equippedGearIDs: equipped, partyActorIDs: actors, activeRegionID: firstRegion?.id, gatherTargetMaterialID: firstRegion?.gatherMaterialIDs.first)
    }

    public static func newCandidateGame(catalog: GameCatalog,
                                        candidateLatentPolicy: CandidateLatentSlotPolicyR003) throws -> GameSnapshot {
        var state = newGame(catalog: catalog)
        let joinedActors = Set(state.partyActorIDs)
        for index in state.gear.indices {
            state.gear[index].candidateLatentSlots = try candidateLatentPolicy.generateNewInstanceSlots(
                templateID: state.gear[index].definitionID, joinedActorIDs: joinedActors,
                operationID: state.gear[index].id, domainSalt: "starter-new-game:\(state.gear[index].ownerID ?? "unowned")")
        }
        return state
    }
}
public enum GameCommand: Sendable {
    case equip(gearID: UUID, actorID: String), protect(gearID: UUID, protected: Bool)
    case saveGearLoadoutR342(slot: GearLoadoutSlotR342), applyGearLoadoutR342(slot: GearLoadoutSlotR342), clearGearLoadoutR342(slot: GearLoadoutSlotR342)
    case enhance(gearID: UUID), refine(gearID: UUID), dismantle(gearID: UUID)
    case promoteQuality(gearID: UUID)
    case craftRecipe(String), evolveGear(gearID: UUID, recipeID: String), completeResearch(String)
    case setTrackedRecipe(String?)
    case mockSummon(poolDefinitionIDs: [String], count: Int, costCurrencyID: String, seed: UInt64)
    case setGachaTarget(templateID: String)
    case startExpedition(regionID: String), startExpeditionAt(regionID: String, now: Date)
    case gather(resourceID: String, now: Date), setGatherTarget(resourceID: String), setGatherTargetAt(resourceID: String, now: Date)
    case resolveEncounter(enemyID: String, seed: UInt64)
    case resolveChallenge(challengeID: String, seed: UInt64)
    case dailyClaim(now: Date)
    case setCosmetic(String, owned: Bool), setFurniture(String, owned: Bool), placeFurniture(String, placed: Bool)
    case applyVerifiedCommerceOwnershipR1(VerifiedCommerceOwnershipMutationR1, nowEpochSeconds: Int64)
    case reconcileCommerceOwnershipR1(nowEpochSeconds: Int64)
    case selectCosmetic(actorID: String, cosmeticID: String?)
    case selectWeaponAppearance(actorID: String, appearanceID: String?)
    case markGearComparisonSeen(firstGearID: UUID, secondGearID: UUID)
    case recordMockPurchase(transactionID: String, productID: String), restoreMockPurchase(transactionID: String, productID: String)
    case updateMockPurchase(transactionID: String, productID: String, status: MockPurchaseStatus)
    case setLocalAdSkipEntitlementForQA(enabled: Bool)
    case recordMockRewardedAdAttempt(opportunityID: String, result: LocalRewardedAdQAResult)
    case claimMockAdSkip(opportunityID: String)

    public var requestFingerprint: String {
        let tag: String
        let fields: [String]
        switch self {
        case .equip(let gearID, let actorID): tag = "equip"; fields = [gearID.uuidString, actorID]
        case .saveGearLoadoutR342(let slot): tag = "saveGearLoadoutR342"; fields = [String(slot.rawValue)]
        case .applyGearLoadoutR342(let slot): tag = "applyGearLoadoutR342"; fields = [String(slot.rawValue)]
        case .clearGearLoadoutR342(let slot): tag = "clearGearLoadoutR342"; fields = [String(slot.rawValue)]
        case .protect(let gearID, let protected): tag = "protect"; fields = [gearID.uuidString, String(protected)]
        case .enhance(let gearID): tag = "enhance"; fields = [gearID.uuidString]
        case .refine(let gearID): tag = "refine"; fields = [gearID.uuidString]
        case .dismantle(let gearID): tag = "dismantle"; fields = [gearID.uuidString]
        case .promoteQuality(let gearID): tag = "quality"; fields = [gearID.uuidString]
        case .craftRecipe(let recipeID): tag = "recipe"; fields = [recipeID]
        case .evolveGear(let gearID, let recipeID): tag = "evolveGear"; fields = [gearID.uuidString, recipeID]
        case .setTrackedRecipe(let recipeID): tag = "setTrackedRecipe"; fields = recipeID.map { ["some", $0] } ?? ["nil"]
        case .completeResearch(let id): tag = "research"; fields = [id]
        case .mockSummon(let pool, let count, let currency, let seed): tag = "summon"; fields = pool.sorted() + [String(count), currency, String(seed)]
        case .setGachaTarget(let id): tag = "target"; fields = [id]
        case .startExpedition(let region): tag = "expedition"; fields = [region]
        case .startExpeditionAt(let region, let date): tag = "expeditionAt"; fields = [region, String(date.timeIntervalSince1970)]
        case .gather(let material, let date): tag = "gather"; fields = [material, String(date.timeIntervalSince1970)]
        case .setGatherTarget(let resource): tag = "gatherTarget"; fields = [resource]
        case .setGatherTargetAt(let resource, let date): tag = "gatherTargetAt"; fields = [resource, String(date.timeIntervalSince1970)]
        case .resolveEncounter(let enemy, let seed): tag = "encounter"; fields = [enemy, String(seed)]
        case .resolveChallenge(let challenge, let seed): tag = "challenge"; fields = [challenge, String(seed)]
        case .dailyClaim(let date): tag = "daily"; fields = [String(date.timeIntervalSince1970)]
        case .setCosmetic(let id, let owned): tag = "cosmetic"; fields = [id, String(owned)]
        case .setFurniture(let id, let owned): tag = "furniture"; fields = [id, String(owned)]
        case .applyVerifiedCommerceOwnershipR1(let mutation, _): tag = "commerceOwnershipR1"; fields = [mutation.operationID, mutation.receiptFingerprint, mutation.transactionID, String(mutation.authorityRevision), mutation.event.rawValue]
        case .reconcileCommerceOwnershipR1(let now): tag = "commerceOwnershipR1Reconcile"; fields = [String(now)]
        case .placeFurniture(let id, let placed): tag = "place"; fields = [id, String(placed)]
        case .selectCosmetic(let actor, let id): tag = "selectCosmetic"; fields = id.map { [actor, "some", $0] } ?? [actor, "nil"]
        case .selectWeaponAppearance(let actor, let id): tag = "selectWeaponAppearance"; fields = id.map { [actor, "some", $0] } ?? [actor, "nil"]
        case .markGearComparisonSeen(let first, let second): tag = "compare"; fields = [first.uuidString, second.uuidString]
        case .recordMockPurchase(let transaction, let product): tag = "recordMockPurchase"; fields = [transaction, product]
        case .restoreMockPurchase(let transaction, let product): tag = "restoreMockPurchase"; fields = [transaction, product]
        case .updateMockPurchase(let transaction, let product, let status): tag = "updateMockPurchase"; fields = [transaction, product, status.rawValue]
        case .setLocalAdSkipEntitlementForQA(let enabled): tag = "setLocalAdSkipEntitlementForQA"; fields = [String(enabled)]
        case .recordMockRewardedAdAttempt(let opportunity, let result): tag = "recordMockRewardedAdAttempt"; fields = [opportunity, result.sessionID, result.outcome.rawValue, result.validationSource]
        case .claimMockAdSkip(let opportunity): tag = "claimMockAdSkip"; fields = [opportunity]
        }
        return tag + fields.map { "|\($0.utf8.count):\($0)" }.joined()
    }
}
public struct CommandReceipt: Codable, Sendable, Equatable { public let operationID: UUID; public let revision: Int64; public let result: String; public let requestFingerprint: String? }
public enum CoreError: Error, Equatable, LocalizedError {
    case revisionConflict(expected: Int64, actual: Int64), duplicateOperation, invalidCatalog(String), invalidCommand(String), insufficientResource(String), protectedGear, gearInUse, unsupported(String)
    public var errorDescription: String? { switch self {
    case .revisionConflict(let e, let a): "revision conflict (expected \(e), actual \(a))"
    case .duplicateOperation: "operation ID already applied"
    case .invalidCatalog(let s), .invalidCommand(let s), .insufficientResource(let s), .unsupported(let s): s
    case .protectedGear: "protected gear cannot be dismantled"
    case .gearInUse: "equipped gear cannot be dismantled"
    } }
}


/// Local-only wardrobe preview state. It has no GameSnapshot or dispatch access.
public struct WardrobePreviewSelectionR094: Codable, Equatable, Sendable {
    public private(set) var appearanceID: String?
    public private(set) var kind: String?

    public init() { appearanceID = nil; kind = nil }

    public mutating func show(appearanceID: String, kind: String) {
        self.appearanceID = appearanceID
        self.kind = kind
    }

    public mutating func clear() { appearanceID = nil; kind = nil }

    public func applying(to base: [String: String], actorID: String = "C_WITCH") -> [String: String] {
        var result = base
        guard let appearanceID else { return result }
        switch kind {
        case "costume": result[actorID] = appearanceID
        case "weapon" where actorID == "C_WITCH": result["WITCH_WEAPON"] = appearanceID
        default: break
        }
        return result
    }
}

/// Only a specifically placed botanical desk changes home character staging.
public enum FurniturePresentationR094 {
    public static let botanicalDeskID = "FURN_DESK_BOTANICAL"
    public static func hasBotanicalDesk(_ furniture: Set<String>) -> Bool {
        furniture.contains(botanicalDeskID)
    }
}
