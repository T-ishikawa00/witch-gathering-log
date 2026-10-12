import Foundation

struct GachaSeedGenerator {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func bounded(_ upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0)
        let rejectionThreshold = (0 &- upperBound) % upperBound
        while true {
            let value = nextUInt64()
            if value >= rejectionThreshold { return value % upperBound }
        }
    }
}

public struct GameEngine: Sendable {
    public let catalog: GameCatalog
    public let saves: SaveRepository
    public let candidateCombatOverlay: CandidateCombatOverlay?
    public let candidateCharacterGrowth: CandidateCharacterGrowth?
    public let candidateLatentPolicy: CandidateLatentSlotPolicyR003?
    public init(catalog: GameCatalog, saves: SaveRepository,
                candidateCombatOverlay: CandidateCombatOverlay? = nil,
                candidateCharacterGrowth: CandidateCharacterGrowth? = nil,
                candidateLatentPolicy: CandidateLatentSlotPolicyR003? = nil) throws {
        try catalog.validate()
        self.catalog = catalog
        self.saves = saves
        self.candidateCombatOverlay = candidateCombatOverlay
        self.candidateCharacterGrowth = candidateCharacterGrowth
        self.candidateLatentPolicy = candidateLatentPolicy
    }
    public func snapshot() async -> GameSnapshot { await saves.snapshot() }

    /// Runs a read-only R6-mechanics preview over the campaign's actual party,
    /// gear, research, and enemy definition. It does not dispatch a command,
    /// mutate a snapshot, grant rewards, or persist a battle receipt.
    public func previewCampaignEncounterR6QA(enemyID: String, seed: UInt64, snapshot suppliedSnapshot: GameSnapshot? = nil,
                                             maxDurationMs: Int = 120_000) async throws -> CombatResult {
        let state: GameSnapshot
        if let suppliedSnapshot { state = suppliedSnapshot }
        else { state = await saves.snapshot() }
        guard let enemy = catalog.enemies.first(where: { $0.id == enemyID }),
              let regionIndex = catalog.regions.firstIndex(where: { $0.id == enemy.regionID }) else {
            throw CoreError.invalidCommand("unknown campaign QA enemy")
        }
        let party = try R6CampaignQAAdapter.party(from: state, catalog: catalog)
        let scaledEnemy = try R6CampaignQAAdapter.enemy(enemy, regionIndex: regionIndex)
        let mapping = [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy", catalogID: enemy.id,
                                                          label: enemy.name, assetKey: enemy.id)]
        return try R6TimelineSimulator.run(party: party, enemies: [scaledEnemy], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: mapping,
                                           sourceProfileSeed: String(seed))
    }

    /// Read-only reproduction of the existing campaign encounter path. This
    /// is the paired baseline for the explicitly labeled fixed-point preview.
    public func previewCampaignEncounterDefaultQA(enemyID: String, seed: UInt64, snapshot suppliedSnapshot: GameSnapshot? = nil,
                                                   maxDurationMs: Int = 120_000) async throws -> CombatResult {
        let state: GameSnapshot
        if let suppliedSnapshot { state = suppliedSnapshot }
        else { state = await saves.snapshot() }
        guard let enemy = catalog.enemies.first(where: { $0.id == enemyID }) else {
            throw CoreError.invalidCommand("unknown campaign QA enemy")
        }
        let party = try makeCombatParty(state: state)
        let foe = campaignCombatant(enemy)
        let mapping = [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy", catalogID: enemy.id,
                                                          label: enemy.name, assetKey: enemy.id)]
        return try R6TimelineSimulator.run(party: party, enemies: [foe], seed: seed,
                                           maxDurationMs: maxDurationMs, entityPresentation: mapping,
                                           candidateMagnetParameters: candidateParameters(for: enemy))
    }

    private func candidateParameters(for enemy: EnemyDefinition) -> MagnetMechanicParameters? {
        guard let overlay = candidateCombatOverlay, overlay.applies(to: enemy.id) else { return nil }
        return overlay.magnetParameters
    }

    private func campaignCombatant(_ enemy: EnemyDefinition) -> Combatant {
        let candidate = candidateCombatOverlay.flatMap { $0.applies(to: enemy.id) ? $0 : nil }
        return Combatant(id: enemy.id, maxHP: enemy.hp, attack: enemy.attack, defense: enemy.defense,
                         actionPattern: candidate?.actionPattern ?? enemy.actionPattern ?? "standard")
    }

    public func availableGatherMaterials(in regionID: String) async -> [String] {
        let state = await saves.snapshot()
        return catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs)
    }

    private func requireGate(_ gateID: String, state: GameSnapshot) throws {
        let parts = gateID.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { throw CoreError.invalidCommand("unrecognized catalog gate: \(gateID)") }
        let encounterID = "B_\(parts[1])_\(parts[2])"
        guard state.completedEncounterIDs.contains(encounterID) else { throw CoreError.invalidCommand("catalog gate not cleared: \(gateID)") }
    }

    private func validateCandidatePayloadIfEnabled(_ item: GearInstance) throws {
        guard let candidateLatentPolicy, let slots = item.candidateLatentSlots else { return }
        try candidateLatentPolicy.validateStoredPayload(templateID: item.definitionID, slots: slots)
    }

    private func makeCombatParty(state: GameSnapshot) throws -> [Combatant] {
        try state.partyActorIDs.map { actorID in
            let instances = state.equippedGearIDs.filter { $0.key.hasPrefix(actorID + "|") }.compactMap { _, instanceID in state.gear.first(where: { $0.id == instanceID }) }
            if let candidateLatentPolicy {
                return try catalog.projectCandidateCombatantR005(for: actorID, with: instances,
                    completedResearchIDs: state.completedResearchIDs,
                    totalXP: state.characterXP[actorID, default: 0], candidateGrowth: candidateCharacterGrowth,
                    candidateLatentPolicy: candidateLatentPolicy).combatant
            }
            return catalog.projectCombatant(for: actorID, with: instances, completedResearchIDs: state.completedResearchIDs,
                                            totalXP: state.characterXP[actorID, default: 0],
                                            candidateGrowth: candidateCharacterGrowth)
        }
    }

    private func checkedAdd(_ lhs: Int, _ rhs: Int, label: String) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw CoreError.invalidCommand("numeric overflow while updating \(label)") }
        return value
    }

    private func checkedProduct(_ lhs: Int, _ rhs: Int, label: String) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw CoreError.invalidCommand("numeric overflow while calculating \(label)") }
        return value
    }

    @discardableResult
    private func settleGathering(now: Date, state: inout GameSnapshot) throws -> (units: Int, materialID: String?) {
        guard now.timeIntervalSince1970.isFinite else { throw CoreError.invalidCommand("gathering timestamp must be finite") }
        guard let regionID = state.activeRegionID, let region = catalog.regions.first(where: { $0.id == regionID }) else {
            return (0, nil)
        }
        let rawElapsed = state.lastClaimAt.map { now.timeIntervalSince($0) } ?? 0
        guard rawElapsed >= 0 else { throw CoreError.invalidCommand("gathering clock moved backward") }
        let interval = TimeInterval(max(1, region.workSeconds))
        guard state.offlineRemainderSeconds.isFinite, state.offlineRemainderSeconds >= 0,
              state.offlineRemainderSeconds <= interval else { throw CoreError.invalidCommand("saved gathering remainder is invalid") }
        let elapsed = min(48 * 3600, rawElapsed)
        let accrued = min(48 * 3600, elapsed + max(0, state.offlineRemainderSeconds))
        let units = Int(accrued / interval)
        let available = catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs)
        let materialID = available.contains(state.gatherTargetMaterialID ?? "") ? state.gatherTargetMaterialID : available.first
        if units > 0 {
            let xp = try checkedProduct(units, region.xpPerWork, label: "gathering XP")
            let dust = try checkedProduct(units, region.dustPerWork, label: "gathering dust")
            if let materialID { state.materials[materialID] = try checkedAdd(state.materials[materialID, default: 0], units, label: materialID) }
            for actorID in state.partyActorIDs { state.characterXP[actorID] = try checkedAdd(state.characterXP[actorID, default: 0], xp, label: "XP for \(actorID)") }
            state.materials["refine_dust"] = try checkedAdd(state.materials["refine_dust", default: 0], dust, label: "refine dust")
            try accrueLocalAdWork(units: units, region: region, now: now, state: &state)
        }
        state.offlineRemainderSeconds = accrued.truncatingRemainder(dividingBy: interval)
        state.lastClaimAt = now
        return (units, materialID)
    }

    /// R3 candidate: actual settled work fills eight-hour blocks; the unclaimed queue is capped at six.
    private func accrueLocalAdWork(units: Int, region: RegionDefinition, now: Date, state: inout GameSnapshot) throws {
        guard units > 0, region.workSeconds > 0 else { return }
        for _ in 0..<units {
            if state.localAdRewardOpportunities.count < 6 {
                for actorID in state.partyActorIDs { state.localAdWorkBlockXPByActor[actorID] = try checkedAdd(state.localAdWorkBlockXPByActor[actorID, default: 0], max(0, region.xpPerWork), label: "local ad work XP") }
                state.localAdWorkBlockDust = try checkedAdd(state.localAdWorkBlockDust, max(0, region.dustPerWork), label: "local ad work dust")
            }
            state.localAdWorkBlockSeconds = try checkedAdd(state.localAdWorkBlockSeconds, region.workSeconds, label: "local ad work seconds")
            if state.localAdWorkBlockSeconds >= 8 * 3600 {
                if state.localAdRewardOpportunities.count < 6 {
                    let id = "ADWORK_\(state.localAdNextOpportunitySequence)"
                    state.localAdRewardOpportunities[id] = LocalAdRewardOpportunity(id: id, baseXPByActor: state.localAdWorkBlockXPByActor, baseDust: state.localAdWorkBlockDust, createdAt: now)
                    state.localAdNextOpportunitySequence = try checkedAdd(state.localAdNextOpportunitySequence, 1, label: "local ad opportunity sequence")
                }
                state.localAdWorkBlockSeconds %= 8 * 3600
                state.localAdWorkBlockXPByActor = [:]
                state.localAdWorkBlockDust = 0
            }
        }
    }

    private func settleLocalAdOpportunity(opportunityID: String, sessionID: String, outcome: LocalAdAttemptOutcome, skip: Bool, now: Date, state: inout GameSnapshot) throws -> String {
        guard !sessionID.isEmpty else { throw CoreError.invalidCommand("local ad session ID required") }
        if state.localAdAttemptRecords[sessionID] != nil { return "LOCAL_QA duplicate ad callback ignored" }
        guard let opportunity = state.localAdRewardOpportunities[opportunityID] else { throw CoreError.invalidCommand("local ad reward opportunity is unavailable") }
        if skip { guard state.localAdSkipEntitledForQA else { throw CoreError.invalidCommand("local QA ad-skip entitlement is not enabled") } }
        var appliedXP: [String: Int] = [:]
        var appliedDust = 0
        if skip || outcome == .completed {
            state.localAdRewardOpportunities.removeValue(forKey: opportunityID)
            for (actorID, baseXP) in opportunity.baseXPByActor {
                let total = try checkedAdd(max(0, baseXP), state.localAdXPFractionalCarry[actorID, default: 0], label: "local ad XP reward")
                let earned = total / 16
                state.localAdXPFractionalCarry[actorID] = total % 16
                if earned > 0 { state.characterXP[actorID] = try checkedAdd(state.characterXP[actorID, default: 0], earned, label: "local ad XP"); appliedXP[actorID] = earned }
            }
            let totalDust = try checkedAdd(max(0, opportunity.baseDust), state.localAdDustFractionalCarry, label: "local ad dust reward")
            appliedDust = totalDust / 16
            state.localAdDustFractionalCarry = totalDust % 16
            if appliedDust > 0 { state.materials["refine_dust"] = try checkedAdd(state.materials["refine_dust", default: 0], appliedDust, label: "local ad refine dust") }
        }
        state.localAdAttemptRecords[sessionID] = LocalAdAttemptRecord(sessionID: sessionID, opportunityID: opportunityID, outcome: skip ? .completed : outcome, claimedByAdSkip: skip, recordedAt: now, rewardXPByActor: appliedXP, rewardDust: appliedDust)
        return skip ? "LOCAL_QA ad-skip reward claimed; XP=\(appliedXP.values.reduce(0, +)), dust=\(appliedDust)" : "LOCAL_QA ad attempt \(outcome.rawValue); rewards only on completed callback; XP=\(appliedXP.values.reduce(0, +)), dust=\(appliedDust)"
    }

    private func selectExpedition(regionID: String, now: Date, state: inout GameSnapshot) throws -> String {
        guard state.unlockedRegionIDs.contains(regionID) else { throw CoreError.invalidCommand("region is locked") }
        guard catalog.regions.contains(where: { $0.id == regionID }) else { throw CoreError.invalidCommand("unknown region") }
        if state.lastClaimAt == nil { state.lastClaimAt = now }
        let available = catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs)
        guard !available.isEmpty else { throw CoreError.invalidCommand("no gather material has been unlocked for region") }
        let target = available.contains(state.gatherTargetMaterialID ?? "") ? state.gatherTargetMaterialID : available.first
        let changed = state.activeRegionID != regionID || target != state.gatherTargetMaterialID
        if changed {
            _ = try settleGathering(now: now, state: &state)
            state.offlineRemainderSeconds = 0 // fractional time cannot cross a material or region boundary
        }
        state.activeRegionID = regionID
        state.gatherTargetMaterialID = target
        return "expedition started: \(regionID)"
    }

    private func selectGatherTarget(resourceID: String, now: Date, state: inout GameSnapshot) throws -> String {
        guard let regionID = state.activeRegionID, let region = catalog.regions.first(where: { $0.id == regionID }), region.gatherMaterialIDs.contains(resourceID),
              catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs).contains(resourceID) else { throw CoreError.invalidCommand("gather target is unavailable in active region") }
        if state.gatherTargetMaterialID != resourceID || state.lastClaimAt == nil {
            _ = try settleGathering(now: now, state: &state)
            state.gatherTargetMaterialID = resourceID
        }
        return "gather target set: \(resourceID)"
    }

    @discardableResult
    public func dispatch(_ command: GameCommand, operationID: UUID, expectedRevision: Int64) async throws -> CommandReceipt {
        try await saves.transact(expectedRevision: expectedRevision, operationID: operationID, requestFingerprint: command.requestFingerprint) { state in
            switch command {
            case .equip(let id, let actor):
                guard let item = state.gear.first(where: { $0.id == id }), let definition = catalog.gear.first(where: { $0.id == item.definitionID }) else { throw CoreError.invalidCommand("unknown gear instance") }
                try validateCandidatePayloadIfEnabled(item)
                guard state.partyActorIDs.contains(actor), definition.actorIDs.isEmpty || definition.actorIDs.contains(actor) else { throw CoreError.invalidCommand("actor is not eligible for this gear") }
                let key = "\(actor)|\(definition.slot)"
                if let replacedID = state.equippedGearIDs[key], let oldIndex = state.gear.firstIndex(where: { $0.id == replacedID }) { state.gear[oldIndex].ownerID = nil }
                state.equippedGearIDs = state.equippedGearIDs.filter { $0.key != key && $0.value != id }
                state.equippedGearIDs[key] = id
                if let index = state.gear.firstIndex(where: { $0.id == id }) { state.gear[index].ownerID = actor }
                return "equipped: \(actor) / \(definition.id)"
            case .protect(let id, let protected):
                guard let index = state.gear.firstIndex(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown gear") }
                state.gear[index].protected = protected; return protected ? "gear protected" : "gear unprotected"
            case .enhance(let id):
                guard let index = state.gear.firstIndex(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown gear") }
                try validateCandidatePayloadIfEnabled(state.gear[index])
                let nextLevel = state.gear[index].enhancement + 1
                guard let recipe = catalog.recipes.first(where: { $0.id == "ENHANCE_\(nextLevel)" }), recipe.kind == "enhance" else { throw CoreError.invalidCommand("enhancement level is at catalog cap") }
                if let gateID = recipe.gateID, gateID != "G_START" { try requireGate(gateID, state: state) }
                try spend("refine_dust", recipe.dustCost, from: &state); state.gear[index].enhancement = nextLevel; state.gear[index].investmentDust = try checkedAdd(state.gear[index].investmentDust, recipe.dustCost, label: "gear investment"); return "enhanced to +\(nextLevel) for \(recipe.dustCost) dust [\(recipe.status)]"
            case .refine(let id):
                guard let index = state.gear.firstIndex(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown gear") }
                try validateCandidatePayloadIfEnabled(state.gear[index])
                try spend("refine_dust", 5, from: &state); state.gear[index].refinement = try checkedAdd(state.gear[index].refinement, 1, label: "gear refinement"); state.gear[index].investmentDust = try checkedAdd(state.gear[index].investmentDust, 5, label: "gear investment"); return "refined to \(state.gear[index].refinement)"
            case .promoteQuality(let id):
                guard let index = state.gear.firstIndex(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown gear") }
                try validateCandidatePayloadIfEnabled(state.gear[index])
                let order = ["Q0", "Q1", "Q2", "Q3", "Q4"]
                guard let current = order.firstIndex(of: state.gear[index].qualityID), current < 4 else { throw CoreError.invalidCommand("quality is already at cap") }
                let recipeID = ["QUALITY_Q0_Q1", "QUALITY_Q1_Q2", "QUALITY_Q2_Q3", "QUALITY_Q3_Q4"][current]
                guard let recipe = catalog.recipes.first(where: { $0.id == recipeID }), recipe.kind == "quality" else { throw CoreError.invalidCommand("quality recipe missing from catalog") }
                if let gateID = recipe.gateID, gateID != "G_START" { try requireGate(gateID, state: state) }
                let cost = recipe.dustCost
                try spend("refine_dust", cost, from: &state)
                state.gear[index].qualityID = order[current + 1]; state.gear[index].investmentDust = try checkedAdd(state.gear[index].investmentDust, cost, label: "gear investment")
                if current == 3 {
                    state.gear[index].protected = true
                    // Preserve historical alias behavior only for legacy mode. A
                    // versioned candidate payload is never rerolled or supplemented.
                    if candidateLatentPolicy == nil, state.gear[index].latentEffectID == nil {
                        state.gear[index].latentEffectID = "LATENT_POWER_TEST"
                    }
                }
                return "quality promoted to \(order[current + 1]) for \(cost) dust [UNAPPROVED_TEST_OVERLAY]"
            case .dismantle(let id):
                guard let item = state.gear.first(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown gear") }
                guard !item.protected else { throw CoreError.protectedGear }
                guard !state.equippedGearIDs.values.contains(id) else { throw CoreError.gearInUse }
                guard state.gear.filter({ $0.definitionID == item.definitionID }).count > 1 else { throw CoreError.protectedGear }
                state.gear.removeAll { $0.id == id }; state.materials["refine_dust"] = try checkedAdd(state.materials["refine_dust", default: 0], 1, label: "refine dust"); return "gear dismantled"
            case .craftRecipe(let recipeID):
                return try applyRecipe(recipeID, gearID: nil, operationID: operationID, state: &state)
            case .evolveGear(let gearID, let recipeID):
                return try applyRecipe(recipeID, gearID: gearID, operationID: operationID, state: &state)
            case .setTrackedRecipe(let recipeID):
                if let recipeID {
                    guard let recipe = catalog.recipes.first(where: { $0.id == recipeID }),
                          recipe.kind == "craft_new" || recipe.kind == "evolve_in_place" else {
                        throw CoreError.invalidCommand("tracked goal must reference an existing craft/evolution recipe")
                    }
                    state.trackedRecipeID = recipeID
                    return "tracked recipe goal set: \(recipeID)"
                }
                state.trackedRecipeID = nil
                return "tracked recipe goal cleared"
            case .completeResearch(let id):
                guard catalog.research.contains(where: { $0.id == id }), !state.completedResearchIDs.contains(id) else { throw CoreError.invalidCommand("unknown or completed research") }
                guard let research = catalog.research.first(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown research") }
                if let recipe = catalog.recipes.first(where: { $0.id == id }), let gateID = recipe.gateID, gateID != "G_START" { try requireGate(gateID, state: state) }
                for (resource, amount) in research.cost.sorted(by: { $0.key < $1.key }) { try spend(resource, amount, from: &state) }
                state.completedResearchIDs.insert(id); return "research completed: \(id)"
            case .mockSummon(let pool, let count, let currencyID, let seed):
                guard state.gachaUnlocked else { throw CoreError.invalidCommand("gacha remains locked until gear comparison tutorial is completed") }
                let allowedGear = Set(catalog.gear.map(\.id))
                guard [1, 5, 50].contains(count), !pool.isEmpty, Set(pool).count == pool.count, pool.allSatisfy({ allowedGear.contains($0) }) else { throw CoreError.invalidCommand("count must be 1/5/50 and pool valid") }
                guard state.gachaPity.targetTemplateID.map({ pool.contains($0) }) ?? true else { throw CoreError.invalidCommand("selected target is outside this summon pool") }
                guard state.currency[currencyID, default: 0] >= count else { throw CoreError.insufficientResource("insufficient \(currencyID)") }
                state.currency[currencyID, default: 0] -= count
                let stablePool = pool.sorted(); var random = GachaSeedGenerator(seed: seed); var draws: [String] = []
                func choose(_ candidates: [String], rng: inout GachaSeedGenerator) -> String { candidates[Int(rng.bounded(UInt64(candidates.count)))] }
                for _ in 0..<count {
                    var qualityRoll = Int(random.bounded(10_000))
                    if state.gachaPity.drawsSinceTop >= 99 { qualityRoll = 9_999 }
                    var cumulative = 0; var quality = "Q4"
                    for candidate in ["Q0", "Q1", "Q2", "Q3", "Q4"] { cumulative += catalog.gachaOddsBasisPoints[candidate, default: 0]; if qualityRoll < cumulative { quality = candidate; break } }
                    if quality == "Q0" || quality == "Q1" || quality == "Q2", state.gachaPity.drawsSinceMid >= 19 { quality = "Q3" }
                    let isTop = quality == "Q4"
                    if isTop { state.gachaPity.drawsSinceTop = 0 } else { state.gachaPity.drawsSinceTop = try checkedAdd(state.gachaPity.drawsSinceTop, 1, label: "top-tier pity") }
                    if quality == "Q3" || quality == "Q4" { state.gachaPity.drawsSinceMid = 0 } else { state.gachaPity.drawsSinceMid = try checkedAdd(state.gachaPity.drawsSinceMid, 1, label: "mid-tier pity") }
                    var chosenID: String
                    if isTop, let target = state.gachaPity.targetTemplateID {
                        let targetNext = state.gachaPity.guaranteeTargetOnNextTop || random.bounded(10_000) < 5_000
                        if targetNext { chosenID = target; state.gachaPity.guaranteeTargetOnNextTop = false }
                        else { chosenID = choose(stablePool.filter { $0 != target }.isEmpty ? stablePool : stablePool.filter { $0 != target }, rng: &random); state.gachaPity.guaranteeTargetOnNextTop = true }
                    } else { chosenID = choose(stablePool, rng: &random) }
                    let affixCount = ["Q0": 0, "Q1": 1, "Q2": 2, "Q3": 3, "Q4": 3][quality]!
                    var affixes: [String] = []
                    let available = ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"]
                    while affixes.count < affixCount { let id = choose(available, rng: &random); if !affixes.contains(id) { affixes.append(id) } }
                    let latent = quality == "Q4" ? choose(["LATENT_POWER_TEST", "LATENT_VITALITY_TEST", "LATENT_GUARD_TEST"], rng: &random) : nil
                    let first = !state.gear.contains(where: { $0.definitionID == chosenID })
                    let candidateSlots = try candidateLatentPolicy?.generateNewInstanceSlots(
                        templateID: chosenID, joinedActorIDs: Set(state.partyActorIDs), operationID: operationID,
                        domainSalt: "summon:\(draws.count):\(chosenID)")
                    state.gear.append(GearInstance(definitionID: chosenID, protected: first || quality == "Q4",
                                                   latentEffectID: latent, candidateLatentSlots: candidateSlots,
                                                   qualityID: quality, affixIDs: affixes))
                    draws.append("\(quality):\(chosenID)")
                }
                let oddsText = ["Q0", "Q1", "Q2", "Q3", "Q4"].map { "\($0)=\(catalog.gachaOddsBasisPoints[$0, default: 0])bp" }.joined(separator: "/")
                return "MOCK_ONLY R3 test draw x\(count): \(draws.joined(separator: ",")); base quality odds before pity \(oddsText); Q4 pity at 100 rolls; Q3 minimum on 20th consecutive Q0-Q2 roll; target top guarantee is 50/50 then guarantee after a miss; candidate only"
            case .setGachaTarget(let id):
                guard state.gachaUnlocked else { throw CoreError.invalidCommand("gacha target selection unlocks after the gear comparison tutorial") }
                guard catalog.gear.contains(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown target template") }
                guard state.gachaPity.targetTemplateID != id else { return "test target unchanged: \(id)" }
                state.gachaPity.targetTemplateID = id; state.gachaPity.guaranteeTargetOnNextTop = false; return "test target selected: \(id); next-top target guarantee reset; candidate only"
            case .startExpedition(let regionID):
                return try selectExpedition(regionID: regionID, now: Date(), state: &state)
            case .startExpeditionAt(let regionID, let now):
                return try selectExpedition(regionID: regionID, now: now, state: &state)
            case .setGatherTarget(let resourceID):
                return try selectGatherTarget(resourceID: resourceID, now: Date(), state: &state)
            case .setGatherTargetAt(let resourceID, let now):
                return try selectGatherTarget(resourceID: resourceID, now: now, state: &state)
            case .gather(let resourceID, let now):
                guard let regionID = state.activeRegionID, let region = catalog.regions.first(where: { $0.id == regionID }), region.gatherMaterialIDs.contains(resourceID), state.gatherTargetMaterialID == resourceID,
                      catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs).contains(resourceID) else { throw CoreError.invalidCommand("select an available active-region resource") }
                let settled = try settleGathering(now: now, state: &state)
                guard settled.units > 0 else { throw CoreError.invalidCommand("no complete gathering unit is ready") }
                return "gathered \(resourceID) x\(settled.units); party XP +\(settled.units * region.xpPerWork), dust +\(settled.units * region.dustPerWork)"
            case .resolveEncounter(let enemyID, let seed):
                guard let regionID = state.activeRegionID, let enemy = catalog.enemies.first(where: { $0.id == enemyID }), enemy.regionID == regionID else { throw CoreError.invalidCommand("encounter must match active region") }
                guard enemy.prerequisiteEncounterID.map({ state.completedEncounterIDs.contains($0) }) ?? true else { throw CoreError.invalidCommand("required previous encounter is not cleared") }
                let party = try makeCombatParty(state: state)
                let presentation = [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy", catalogID: enemy.id, label: enemy.name, assetKey: enemy.id)]
                let result = try R6TimelineSimulator.run(party: party, enemies: [campaignCombatant(enemy)], seed: seed,
                    entityPresentation: presentation, candidateMagnetParameters: candidateParameters(for: enemy))
                state.lastCombatResult = result; state.lastEncounterID = enemyID
                guard result.won else { return "DEFEAT: \(enemyID), ticks=\(result.ticks)" }
                state.completedEncounterIDs.insert(enemyID)
                if let dropID = enemy.dropMaterialID { state.materials[dropID] = try checkedAdd(state.materials[dropID, default: 0], enemy.boss ? 5 : 1, label: dropID) }
                state.currency["coin"] = try checkedAdd(state.currency["coin", default: 0], enemy.boss ? 10 : 2, label: "coins")
                if enemyID.hasSuffix("_B"), let index = catalog.regions.firstIndex(where: { $0.id == regionID }), catalog.regions.indices.contains(index + 1) { state.unlockedRegionIDs.insert(catalog.regions[index + 1].id) }
                return "VICTORY: \(enemyID), rewards committed atomically; ticks=\(result.ticks)"
            case .resolveChallenge(let challengeID, let seed):
                guard let challenge = catalog.challenges.first(where: { $0.id == challengeID }) else { throw CoreError.invalidCommand("unknown challenge") }
                try requireGate(challenge.unlockGate, state: state)
                let scenario = try catalog.challengeCombatScenario(challengeID)
                let result = try R6TimelineSimulator.run(party: try makeCombatParty(state: state), enemies: scenario.enemies, seed: seed, challengeID: challengeID, entityPresentation: scenario.entityPresentation)
                state.lastCombatResult = result; state.lastEncounterID = challengeID
                let executionStatus = result.won ? "SIMULATED_VICTORY" : "SIMULATED_DEFEAT"
                guard result.won else { return "CHALLENGE \(executionStatus): \(challengeID), ticks=\(result.ticks); designStatus=\(challenge.status)" }
                let clearKey = "CHALLENGE_CLEAR|\(challengeID)"
                let isFirstClear = !state.completedEncounterIDs.contains(clearKey)
                state.completedEncounterIDs.insert(clearKey)
                if isFirstClear { state.materials["refine_dust"] = try checkedAdd(state.materials["refine_dust", default: 0], challenge.firstClearPowder, label: "challenge powder") }
                return "CHALLENGE \(executionStatus): \(challengeID), firstClearPowder=\(isFirstClear ? challenge.firstClearPowder : 0), ticks=\(result.ticks); designStatus=\(challenge.status)"
            case .dailyClaim(let now):
                guard state.gachaUnlocked else { throw CoreError.invalidCommand("daily reward unlocks after the onboarding comparison") }
                guard now.timeIntervalSince1970.isFinite else { throw CoreError.invalidCommand("daily claim timestamp must be finite") }
                let calendar = Calendar(identifier: .gregorian)
                var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
                if let prior = state.lastDailyClaimAt {
                    guard now >= prior, !utc.isDate(prior, inSameDayAs: now) else { throw CoreError.invalidCommand("daily claim already used or clock moved backward") }
                }
                state.currency["ticket_free"] = try checkedAdd(state.currency["ticket_free", default: 0], catalog.dailyFreeTicketGrant, label: "free tickets"); state.lastDailyClaimAt = now; return "daily test reward: \(catalog.dailyFreeTicketGrant) free tickets [UNAPPROVED_TEST_OVERLAY]"
            case .markGearComparisonSeen(let firstID, let secondID):
                guard state.partyActorIDs.count == 4, state.craftedGearOnce, firstID != secondID,
                      let first = state.gear.first(where: { $0.id == firstID }), let second = state.gear.first(where: { $0.id == secondID }),
                      let firstDef = catalog.gear.first(where: { $0.id == first.definitionID }),
                      let secondDef = catalog.gear.first(where: { $0.id == second.definitionID }), firstDef.slot == secondDef.slot else { throw CoreError.invalidCommand("compare two owned items of the same slot after crafting with the full party") }
                state.gearComparisonSeen = true; state.gachaUnlocked = true; return "gear comparison tutorial complete; 5 initial tickets unlocked [UNAPPROVED_TEST_OVERLAY]"
            case .setCosmetic(let id, let owned):
                guard catalog.appearances.contains(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown appearance") }
                if owned { state.ownedCosmeticIDs.insert(id) } else {
                    state.ownedCosmeticIDs.remove(id)
                    state.selectedCosmeticIDs = state.selectedCosmeticIDs.filter { $0.value != id }
                    state.selectedWeaponAppearanceIDs = state.selectedWeaponAppearanceIDs.filter { $0.value != id }
                }
                return "appearance ownership updated; gameplay stats unchanged"
            case .selectCosmetic(let actorID, let cosmeticID):
                guard state.partyActorIDs.contains(actorID) else { throw CoreError.invalidCommand("unknown party actor") }
                if let cosmeticID {
                    guard let appearance = catalog.appearances.first(where: { $0.id == cosmeticID && $0.kind == "costume" }), appearance.actorIDs.contains(actorID), state.ownedCosmeticIDs.contains(cosmeticID) else { throw CoreError.invalidCommand("costume is unavailable for this actor or not owned") }
                    state.selectedCosmeticIDs[actorID] = cosmeticID
                }
                else { state.selectedCosmeticIDs.removeValue(forKey: actorID) }
                return "cosmetic appearance selection updated"
            case .selectWeaponAppearance(let actorID, let appearanceID):
                guard state.partyActorIDs.contains(actorID) else { throw CoreError.invalidCommand("unknown party actor") }
                if let appearanceID {
                    guard let appearance = catalog.appearances.first(where: { $0.id == appearanceID && $0.kind == "weapon" }), appearance.actorIDs.contains(actorID), state.ownedCosmeticIDs.contains(appearanceID) else { throw CoreError.invalidCommand("weapon appearance is unavailable for this actor or not owned") }
                    state.selectedWeaponAppearanceIDs[actorID] = appearanceID
                }
                else { state.selectedWeaponAppearanceIDs.removeValue(forKey: actorID) }
                return "weapon appearance selection updated; gameplay stats unchanged"
            case .setFurniture(let id, let owned):
                guard catalog.furnitureIDs.contains(id) else { throw CoreError.invalidCommand("unknown furniture") }
                if owned { state.ownedFurnitureIDs.insert(id) } else { state.ownedFurnitureIDs.remove(id); state.placedFurnitureIDs.remove(id) }; return "furniture ownership updated"
            case .placeFurniture(let id, let placed):
                guard state.ownedFurnitureIDs.contains(id) else { throw CoreError.invalidCommand("furniture is not owned") }
                if placed { state.placedFurnitureIDs.insert(id) } else { state.placedFurnitureIDs.remove(id) }; return "furniture placement updated"
            case .recordMockPurchase(let transactionID, let productID):
                guard !transactionID.isEmpty, !productID.isEmpty else { throw CoreError.invalidCommand("mock transaction/product ID required") }
                if let existing = state.mockPurchaseRecords[transactionID] {
                    guard existing.productID == productID else { throw CoreError.invalidCommand("mock transaction ID reused for another product") }
                    return "MOCK_ONLY duplicate callback ignored: \(existing.status.rawValue)"
                }
                state.mockPurchaseRecords[transactionID] = MockPurchaseRecord(transactionID: transactionID, productID: productID, status: .pending, updatedAt: Date())
                state.pendingPurchaseIDs.insert(transactionID)
                return "MOCK_ONLY purchase pending: \(productID)"
            case .restoreMockPurchase(let transactionID, let productID):
                guard !transactionID.isEmpty, !productID.isEmpty else { throw CoreError.invalidCommand("mock transaction/product ID required") }
                try updateMockPurchase(transactionID, productID: productID, status: .restored, state: &state)
                return "MOCK_ONLY restore recorded; no entitlement granted"
            case .updateMockPurchase(let transactionID, let productID, let status):
                try updateMockPurchase(transactionID, productID: productID, status: status, state: &state)
                return "MOCK_ONLY purchase status: \(status.rawValue); no entitlement granted"
            case .setLocalAdSkipEntitlementForQA(let enabled):
                state.localAdSkipEntitledForQA = enabled
                return "LOCAL_QA ad-skip entitlement set to \(enabled); no purchase or production entitlement"
            case .recordMockRewardedAdAttempt(let opportunityID, let result):
                guard result.validationSource == "LOCAL_QA_SIMULATOR" else { throw CoreError.invalidCommand("rewarded-ad result is not from the local QA adapter") }
                return try settleLocalAdOpportunity(opportunityID: opportunityID, sessionID: result.sessionID, outcome: result.outcome, skip: false, now: Date(), state: &state)
            case .claimMockAdSkip(let opportunityID):
                return try settleLocalAdOpportunity(opportunityID: opportunityID, sessionID: "LOCAL_SKIP_\(opportunityID)", outcome: .completed, skip: true, now: Date(), state: &state)
            }
        }
    }

    /// Offline collection is capped and produces resources only; it never fabricates battle victory.
    public func claimOffline(now: Date, secondsPerUnit: TimeInterval? = nil, cap: TimeInterval = 48 * 3600, operationID: UUID, expectedRevision: Int64) async throws -> CommandReceipt {
        try await saves.transact(expectedRevision: expectedRevision, operationID: operationID, requestFingerprint: "offline|\(now.timeIntervalSince1970)|\(secondsPerUnit.map(String.init(describing:)) ?? "region")|\(cap)") { state in
            guard now.timeIntervalSince1970.isFinite, cap.isFinite, secondsPerUnit?.isFinite ?? true else { throw CoreError.invalidCommand("offline timestamp and limits must be finite") }
            let effectiveCap = min(cap, 48 * 3600)
            guard effectiveCap > 0, let regionID = state.activeRegionID, let region = catalog.regions.first(where: { $0.id == regionID }) else { throw CoreError.invalidCommand("offline collection requires an active catalog region and positive cap") }
            let interval = secondsPerUnit ?? TimeInterval(max(1, region.workSeconds))
            guard interval.isFinite, interval > 0,
                  state.offlineRemainderSeconds.isFinite, state.offlineRemainderSeconds >= 0,
                  state.offlineRemainderSeconds <= interval else { throw CoreError.invalidCommand("invalid offline limits or saved remainder") }
            let rawElapsed = state.lastClaimAt.map { now.timeIntervalSince($0) } ?? 0
            let elapsed = rawElapsed > 0 ? min(effectiveCap, rawElapsed) : 0
            let accrued = min(effectiveCap, elapsed + max(0, state.offlineRemainderSeconds))
            let rawUnits = accrued / interval
            guard rawUnits.isFinite, rawUnits < Double(Int.max) else { throw CoreError.invalidCommand("offline unit count exceeds supported range") }
            let units = Int(rawUnits)
            let available = catalog.materialAvailabilityGates.isEmpty
                ? region.gatherMaterialIDs
                : catalog.availableGatherMaterialIDs(in: regionID,
                                                     unlockedRegionIDs: state.unlockedRegionIDs,
                                                     completedEncounterIDs: state.completedEncounterIDs)
            let materialID = available.contains(state.gatherTargetMaterialID ?? "")
                ? state.gatherTargetMaterialID
                : available.first
            if units > 0, materialID == nil {
                throw CoreError.invalidCommand("offline collection has no unlocked material in the active region")
            }
            if units > 0 {
                let xp = try checkedProduct(units, region.xpPerWork, label: "offline XP")
                let dust = try checkedProduct(units, region.dustPerWork, label: "offline dust")
                state.materials[materialID!] = try checkedAdd(state.materials[materialID!, default: 0], units, label: materialID!)
                for actorID in state.partyActorIDs { state.characterXP[actorID] = try checkedAdd(state.characterXP[actorID, default: 0], xp, label: "XP for \(actorID)") }
                state.materials["refine_dust"] = try checkedAdd(state.materials["refine_dust", default: 0], dust, label: "refine dust")
                try accrueLocalAdWork(units: units, region: region, now: now, state: &state)
            }
            state.offlineRemainderSeconds = accrued.truncatingRemainder(dividingBy: interval)
            if state.lastClaimAt == nil || rawElapsed >= 0 { state.lastClaimAt = now }
            return "offline units=\(units); material=\(materialID ?? "none"); capSeconds=\(Int(effectiveCap)); remainingSeconds=\(Int(state.offlineRemainderSeconds)); no combat victory inferred"
        }
    }
    private func spend(_ id: String, _ amount: Int, from state: inout GameSnapshot) throws {
        guard amount >= 0, state.materials[id, default: 0] >= amount else { throw CoreError.insufficientResource("insufficient \(id)") }
        state.materials[id, default: 0] -= amount
    }

    private func applyRecipe(_ recipeID: String, gearID: UUID?, operationID: UUID, state: inout GameSnapshot) throws -> String {
        guard let recipe = catalog.recipes.first(where: { $0.id == recipeID }) else { throw CoreError.invalidCommand("unknown recipe") }
        guard gearID == nil ? recipe.kind == "craft_new" : recipe.kind == "evolve_in_place" else { throw CoreError.invalidCommand("recipe kind does not match requested operation") }
        if let gateID = recipe.gateID, gateID != "G_START" { try requireGate(gateID, state: state) }
        guard let outputID = recipe.outputGearID else { throw CoreError.invalidCommand("recipe has no gear output") }
        var itemIndex: Int?
        if recipe.kind == "evolve_in_place" {
            guard let parentID = recipe.parentTemplateID else { throw CoreError.invalidCatalog("evolution recipe missing parent") }
            itemIndex = gearID.flatMap { id in state.gear.firstIndex(where: { $0.id == id && $0.definitionID == parentID }) } ?? (gearID == nil ? state.gear.firstIndex(where: { $0.definitionID == parentID }) : nil)
            guard itemIndex != nil else { throw CoreError.invalidCommand("evolution requires the selected parent gear instance") }
            guard let input = catalog.gear.first(where: { $0.id == parentID }), let output = catalog.gear.first(where: { $0.id == outputID }), input.slot == output.slot,
                  state.gear[itemIndex!].ownerID.map({ output.actorIDs.isEmpty || output.actorIDs.contains($0) }) ?? true else { throw CoreError.invalidCommand("evolution actor/slot compatibility failed") }
            if let candidateLatentPolicy {
                let existing = state.gear[itemIndex!]
                _ = try candidateLatentPolicy.validateEvolution(
                    from: parentID, to: outputID,
                    legacyEnvelope: CandidateLatentItemEnvelopeR003(latentEffectID: existing.latentEffectID,
                                                                      candidateLatentSlots: existing.candidateLatentSlots))
            }
        }
        for (id, amount) in recipe.costs.sorted(by: { $0.key < $1.key }) { try spend(id, amount, from: &state) }
        if recipe.dustCost > 0 { try spend("refine_dust", recipe.dustCost, from: &state) }
        if let itemIndex {
            state.gear[itemIndex].definitionID = outputID
            return "evolved instance \(state.gear[itemIndex].id): \(recipe.parentTemplateID ?? "") -> \(outputID); investment preserved [\(recipe.status)]"
        }
        let protect = !state.gear.contains(where: { $0.definitionID == outputID })
        let quality = candidateLatentPolicy == nil ? "Q0" : (recipe.qualityTo ?? "Q2")
        let candidateSlots: CandidateLatentSlotsR003?
        if let candidateLatentPolicy {
            let generated = try candidateLatentPolicy.generateNewInstanceSlots(
                templateID: outputID, joinedActorIDs: Set(state.partyActorIDs), operationID: operationID,
                domainSalt: "craft:\(recipeID):\(outputID)", minimumRawQ: 250)
            try candidateLatentPolicy.validateCraftNewCandidate(templateID: outputID,
                                                                 joinedActorIDs: Set(state.partyActorIDs),
                                                                 slots: generated)
            candidateSlots = generated
        } else {
            candidateSlots = nil
        }
        state.gear.append(GearInstance(definitionID: outputID, protected: protect,
                                       candidateLatentSlots: candidateSlots, qualityID: quality)); state.craftedGearOnce = true
        return "crafted: \(outputID) [\(recipe.status)]"
    }

    private func updateMockPurchase(_ transactionID: String, productID: String, status: MockPurchaseStatus, state: inout GameSnapshot) throws {
        guard !transactionID.isEmpty, !productID.isEmpty else { throw CoreError.invalidCommand("mock transaction/product ID required") }
        guard let existing = state.mockPurchaseRecords[transactionID] else {
            guard status == .pending || status == .interrupted || status == .restored else { throw CoreError.invalidCommand("mock transaction must exist before terminal status") }
            state.mockPurchaseRecords[transactionID] = MockPurchaseRecord(transactionID: transactionID, productID: productID, status: status, updatedAt: Date())
            if status == .pending || status == .interrupted { state.pendingPurchaseIDs.insert(transactionID) }
            return
        }
        guard existing.productID == productID else { throw CoreError.invalidCommand("mock transaction product mismatch") }
        let allowed: [MockPurchaseStatus: Set<MockPurchaseStatus>] = [
            .pending: [.pending, .interrupted, .cancelled, .restored, .refunded, .revoked],
            .interrupted: [.pending, .interrupted, .cancelled, .restored, .refunded, .revoked],
            .restored: [.restored, .refunded, .revoked],
            .cancelled: [.cancelled], .refunded: [.refunded], .revoked: [.revoked]
        ]
        guard allowed[existing.status, default: []].contains(status) else { throw CoreError.invalidCommand("invalid mock purchase transition \(existing.status.rawValue) -> \(status.rawValue)") }
        state.mockPurchaseRecords[transactionID] = MockPurchaseRecord(transactionID: transactionID, productID: productID, status: status, updatedAt: Date())
        if status == .pending || status == .interrupted { state.pendingPurchaseIDs.insert(transactionID) }
        else { state.pendingPurchaseIDs.remove(transactionID) }
    }
}
