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
    public let candidatePartyWorkPolicyR144: PartyWorkPolicyR144?
    public let firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179
    public let enhancementProjectionPolicyR230: EnhancementProjectionPolicyR230
    public let naturalGearDiscoveryPolicyR350: NaturalGearDiscoveryPolicyR350?
    public let naturalGearRefinementPolicyR352: NaturalGearRefinementPolicyR352?
    public let gearDismantleRefundPolicyR353: GearDismantleRefundPolicyR353?
    public init(catalog: GameCatalog, saves: SaveRepository,
                candidateCombatOverlay: CandidateCombatOverlay? = nil,
                candidateCharacterGrowth: CandidateCharacterGrowth? = nil,
                candidateLatentPolicy: CandidateLatentSlotPolicyR003? = nil,
                candidatePartyWorkPolicyR144: PartyWorkPolicyR144? = nil,
                firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179 = .disabled,
                enhancementProjectionPolicyR230: EnhancementProjectionPolicyR230 = .legacy,
                naturalGearDiscoveryPolicyR350: NaturalGearDiscoveryPolicyR350? = nil,
                naturalGearRefinementPolicyR352: NaturalGearRefinementPolicyR352? = nil,
                gearDismantleRefundPolicyR353: GearDismantleRefundPolicyR353? = nil) throws {
        try catalog.validate()
        if naturalGearRefinementPolicyR352 != nil && naturalGearDiscoveryPolicyR350 == nil {
            throw CoreError.invalidCatalog("R352 refinement requires the opt-in R350 runtime")
        }
        if gearDismantleRefundPolicyR353 != nil && naturalGearRefinementPolicyR352 == nil {
            throw CoreError.invalidCatalog("R353 dismantle refund requires the opt-in R352 runtime")
        }
        if naturalGearDiscoveryPolicyR350 != nil {
            guard candidatePartyWorkPolicyR144 != nil, candidateLatentPolicy != nil,
                  catalog.regions.allSatisfy({ $0.workSeconds == NaturalGearDiscoveryPolicyR350.workSeconds }) else {
                throw CoreError.invalidCatalog("R350 requires R144/R098/latent runtime and exact 300-second region work cadence")
            }
        }
        if let policy = candidatePartyWorkPolicyR144 {
            guard let growth = candidateCharacterGrowth,
                  let overlay = candidateCombatOverlay,
                  let latentPolicy = candidateLatentPolicy else {
                throw CoreError.invalidCatalog("R144 requires the complete R098 runtime profile dependencies")
            }
            let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: growth.strengthBP)
            guard policy.baseProfileID == profile.profileID,
                  policy.baseConfigurationFingerprint == profile.configurationFingerprint,
                  policy.baseProfileID == PartyWorkPolicyR144.expectedBaseProfileID,
                  policy.baseConfigurationFingerprint == PartyWorkPolicyR144.expectedBaseConfigurationFingerprint,
                  growth == profile.growth,
                  overlay == profile.combatOverlay,
                  latentPolicy.sourceSHA256 == profile.latentPolicySHA256,
                  try Self.sameR098GameplayCatalog(catalog, expected: profile.catalog) else {
                throw CoreError.invalidCatalog("R144 policy does not match the actual R098 500bp runtime dependencies")
            }
        }
        self.catalog = catalog
        self.saves = saves
        self.candidateCombatOverlay = candidateCombatOverlay
        self.candidateCharacterGrowth = candidateCharacterGrowth
        self.candidateLatentPolicy = candidateLatentPolicy
        self.candidatePartyWorkPolicyR144 = candidatePartyWorkPolicyR144
        self.firstCraftAidCapabilityR179 = firstCraftAidCapabilityR179
        self.enhancementProjectionPolicyR230 = enhancementProjectionPolicyR230
        self.naturalGearDiscoveryPolicyR350 = naturalGearDiscoveryPolicyR350
        self.naturalGearRefinementPolicyR352 = naturalGearRefinementPolicyR352
        self.gearDismantleRefundPolicyR353 = gearDismantleRefundPolicyR353
    }

    private static func sameR098GameplayCatalog(_ actual: GameCatalog, expected: GameCatalog) throws -> Bool {
        guard actual.appearances.count >= expected.appearances.count,
              Array(actual.appearances.prefix(expected.appearances.count)) == expected.appearances else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func gameplayBytes(_ value: GameCatalog) throws -> Data {
            guard var object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] else {
                throw CoreError.invalidCatalog("R144 runtime catalog could not be canonicalized")
            }
            object.removeValue(forKey: "version")
            object.removeValue(forKey: "appearances")
            return try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        }
        return try gameplayBytes(actual) == gameplayBytes(expected)
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

    /// No-reward preview using the actual challenge scenario and current R6 party
    /// projection. It changes only a local snapshot copy and never saves or dispatches.
    public func previewChallengeGearSwapR131(challengeID: String, actorID: String,
                                              selectedGearID: UUID, seed: UInt64,
                                              snapshot: GameSnapshot) throws -> GearSwapCombatPreviewR131 {
        guard let challenge = catalog.challenges.first(where: { $0.id == challengeID }) else {
            throw GearSwapCombatPreviewErrorR131.unknownChallenge
        }
        do { try requireGate(challenge.unlockGate, state: snapshot) }
        catch { throw GearSwapCombatPreviewErrorR131.challengeLocked }
        let projection = try gearSwapSnapshotR131(actorID: actorID, selectedGearID: selectedGearID, snapshot: snapshot)
        let scenario = try catalog.challengeCombatScenario(challengeID)
        let result = try R6TimelineSimulator.run(
            party: makeCombatParty(state: projection.snapshot),
            enemies: scenario.enemies,
            seed: seed,
            challengeID: challengeID,
            entityPresentation: scenario.entityPresentation)
        return GearSwapCombatPreviewR131(challengeID: challengeID, actorID: actorID,
                                         currentGearID: projection.currentGearID, selectedGearID: selectedGearID,
                                         slot: projection.slot,
                                         seed: seed, result: result)
    }


    /// Runs two read-only full-party equipment projections through the existing
    /// challenge simulator. The supplied maps must cover exactly the occupied
    /// slots in the source snapshot and may reference only its existing items.
    public func previewChallengeOwnedPartyLoadoutsR181(
        challengeID: String, seed: UInt64, snapshot: GameSnapshot,
        loadouts: [OwnedPartyLoadoutR181]
    ) throws -> [OwnedPartyLoadoutPreviewR181] {
        guard let challenge = catalog.challenges.first(where: { $0.id == challengeID }) else {
            throw OwnedPartyLoadoutPreviewErrorR181.unknownChallenge
        }
        do { try requireGate(challenge.unlockGate, state: snapshot) }
        catch { throw OwnedPartyLoadoutPreviewErrorR181.challengeLocked }
        guard loadouts.count == 2 else {
            throw OwnedPartyLoadoutPreviewErrorR181.exactlyTwoLoadoutsRequired
        }
        guard loadouts.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(loadouts.map(\.id)).count == 2 else {
            throw OwnedPartyLoadoutPreviewErrorR181.duplicateOrEmptyLoadoutID
        }

        let expectedSlots = Set(snapshot.equippedGearIDs.keys)
        let expectedActors = Set(snapshot.partyActorIDs)
        guard expectedActors.count == snapshot.partyActorIDs.count,
              snapshot.partyActorIDs.allSatisfy({ expectedSlots.contains($0 + "|weapon") }) else {
            throw OwnedPartyLoadoutPreviewErrorR181.occupiedSlotSetMismatch
        }
        let scenario = try catalog.challengeCombatScenario(challengeID)
        return try loadouts.map { loadout in
            guard Set(loadout.gearByActorSlot.keys) == expectedSlots else {
                throw OwnedPartyLoadoutPreviewErrorR181.occupiedSlotSetMismatch
            }
            let assignedIDs = Array(loadout.gearByActorSlot.values)
            if Set(assignedIDs).count != assignedIDs.count {
                var counts: [UUID: Int] = [:]
                for id in assignedIDs { counts[id, default: 0] += 1 }
                guard let duplicate = counts.keys
                    .filter({ counts[$0, default: 0] > 1 })
                    .sorted(by: { $0.uuidString < $1.uuidString }).first else {
                    throw OwnedPartyLoadoutPreviewErrorR181.occupiedSlotSetMismatch
                }
                throw OwnedPartyLoadoutPreviewErrorR181.duplicateGearAssignment(duplicate)
            }

            var projected = snapshot
            for (slotKey, itemID) in loadout.gearByActorSlot {
                let parts = slotKey.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                    throw OwnedPartyLoadoutPreviewErrorR181.malformedSlotKey(slotKey)
                }
                let actorID = String(parts[0]), slot = String(parts[1])
                guard expectedActors.contains(actorID) else {
                    throw OwnedPartyLoadoutPreviewErrorR181.malformedSlotKey(slotKey)
                }
                let matches = snapshot.gear.filter { $0.id == itemID }
                guard matches.count == 1, let item = matches.first else {
                    throw OwnedPartyLoadoutPreviewErrorR181.missingOrDuplicateGear(itemID)
                }
                guard item.ownerID == nil || item.ownerID == actorID else {
                    throw OwnedPartyLoadoutPreviewErrorR181.wrongGearOwner(itemID)
                }
                guard let definition = catalog.gear.first(where: { $0.id == item.definitionID }),
                      definition.slot == slot else {
                    throw OwnedPartyLoadoutPreviewErrorR181.wrongGearSlot(itemID)
                }
                guard GearSwapCombatPreviewR131.isUsableByActorR131(definition, actorID: actorID) else {
                    throw OwnedPartyLoadoutPreviewErrorR181.gearNotUsableByActor(itemID)
                }
            }

            let previouslyEquipped = Set(snapshot.equippedGearIDs.values)
            projected.gear = projected.gear.map { item in
                var copy = item
                if previouslyEquipped.contains(item.id) { copy.ownerID = nil }
                return copy
            }
            projected.equippedGearIDs = loadout.gearByActorSlot
            for (slotKey, itemID) in loadout.gearByActorSlot {
                let actorID = String(slotKey.split(separator: "|", maxSplits: 1)[0])
                guard let index = projected.gear.firstIndex(where: { $0.id == itemID }) else {
                    throw OwnedPartyLoadoutPreviewErrorR181.missingOrDuplicateGear(itemID)
                }
                projected.gear[index].ownerID = actorID
            }
            let result = try R6TimelineSimulator.run(
                party: makeCombatParty(state: projected), enemies: scenario.enemies,
                seed: seed, challengeID: challengeID,
                entityPresentation: scenario.entityPresentation)
            return OwnedPartyLoadoutPreviewR181(challengeID: challengeID,
                loadoutID: loadout.id, seed: seed,
                gearByActorSlot: loadout.gearByActorSlot, result: result)
        }
    }


    /// Catalog-ordered campaign targets that are reachable from this exact snapshot.
    /// The list and preview share the same target predicate.
    public func availableCampaignGearTrialEnemiesR136(snapshot: GameSnapshot) -> [EnemyDefinition] {
        guard let regionID = snapshot.activeRegionID,
              snapshot.unlockedRegionIDs.contains(regionID),
              let region = catalog.regions.first(where: { $0.id == regionID }) else { return [] }
        return region.enemyIDs.compactMap { enemyID in
            try? requireCampaignTargetR136(enemyID: enemyID, snapshot: snapshot)
        }
    }

    /// No-reward campaign preview using the same party, enemy, overlay, and magnet
    /// projections as `.resolveEncounter`. It edits only an in-memory snapshot copy.
    public func previewCampaignGearSwapR136(enemyID: String, actorID: String,
                                             selectedGearID: UUID, seed: UInt64,
                                             snapshot: GameSnapshot) throws -> CampaignGearSwapPreviewR136 {
        let enemy = try requireCampaignTargetR136(enemyID: enemyID, snapshot: snapshot)
        let projection = try gearSwapSnapshotR131(actorID: actorID, selectedGearID: selectedGearID, snapshot: snapshot)
        let presentation = [enemy.id: CombatEntityPresentation(entityID: enemy.id, kind: "enemy",
            catalogID: enemy.id, label: enemy.name, assetKey: enemy.id)]
        let result = try R6TimelineSimulator.run(
            party: makeCombatParty(state: projection.snapshot),
            enemies: [campaignCombatant(enemy)], seed: seed,
            entityPresentation: presentation,
            candidateMagnetParameters: candidateParameters(for: enemy))
        return CampaignGearSwapPreviewR136(enemyID: enemy.id, actorID: actorID,
            currentGearID: projection.currentGearID, selectedGearID: selectedGearID,
            slot: projection.slot, seed: seed, result: result)
    }

    private func requireCampaignTargetR136(enemyID: String, snapshot: GameSnapshot) throws -> EnemyDefinition {
        guard let enemy = catalog.enemies.first(where: { $0.id == enemyID }) else {
            throw CampaignGearTrialErrorR136.unknownEnemy
        }
        guard let regionID = snapshot.activeRegionID,
              let region = catalog.regions.first(where: { $0.id == regionID }) else {
            throw CampaignGearTrialErrorR136.activeRegionUnavailable
        }
        guard snapshot.unlockedRegionIDs.contains(regionID) else {
            throw CampaignGearTrialErrorR136.activeRegionLocked
        }
        guard enemy.regionID == regionID else { throw CampaignGearTrialErrorR136.enemyOutsideActiveRegion }
        guard region.enemyIDs.contains(enemyID) else { throw CampaignGearTrialErrorR136.enemyNotListedInActiveRegion }
        if let prerequisite = enemy.prerequisiteEncounterID,
           !snapshot.completedEncounterIDs.contains(prerequisite) {
            throw CampaignGearTrialErrorR136.prerequisiteNotCleared(prerequisite)
        }
        return enemy
    }

    private func gearSwapSnapshotR131(actorID: String, selectedGearID: UUID,
                                      snapshot: GameSnapshot) throws -> (snapshot: GameSnapshot, currentGearID: UUID?, slot: String) {
        guard snapshot.partyActorIDs.contains(actorID) else {
            throw GearSwapCombatPreviewErrorR131.actorNotInParty
        }
        let matchingSelected = snapshot.gear.filter { $0.id == selectedGearID }
        guard matchingSelected.count == 1, let selected = matchingSelected.first else {
            throw GearSwapCombatPreviewErrorR131.missingOrDuplicateGear(selectedGearID)
        }
        guard selected.ownerID == nil || selected.ownerID == actorID else {
            throw GearSwapCombatPreviewErrorR131.wrongGearOwner(selectedGearID)
        }
        guard let selectedDefinition = catalog.gear.first(where: { $0.id == selected.definitionID }),
              GearSwapCombatPreviewR131.isUsableByActorR131(selectedDefinition, actorID: actorID) else {
            throw GearSwapCombatPreviewErrorR131.gearNotUsableByActor(selectedGearID)
        }
        let slotKey = actorID + "|" + selectedDefinition.slot
        let currentGearID = snapshot.equippedGearIDs[slotKey]
        if let currentGearID {
            let matchingCurrent = snapshot.gear.filter { $0.id == currentGearID }
            guard matchingCurrent.count == 1, let current = matchingCurrent.first else {
                throw GearSwapCombatPreviewErrorR131.missingOrDuplicateGear(currentGearID)
            }
            guard current.ownerID == nil || current.ownerID == actorID else {
                throw GearSwapCombatPreviewErrorR131.wrongGearOwner(currentGearID)
            }
            guard let currentDefinition = catalog.gear.first(where: { $0.id == current.definitionID }),
                  currentDefinition.slot == selectedDefinition.slot else {
                throw GearSwapCombatPreviewErrorR131.wrongGearSlot
            }
            guard GearSwapCombatPreviewR131.isUsableByActorR131(currentDefinition, actorID: actorID) else {
                throw GearSwapCombatPreviewErrorR131.gearNotUsableByActor(currentGearID)
            }
        }
        if snapshot.equippedGearIDs.contains(where: { $0.key != slotKey && $0.value == selectedGearID }) {
            throw GearSwapCombatPreviewErrorR131.selectedGearEquippedElsewhere(selectedGearID)
        }
        var copy = snapshot
        if let currentGearID, let index = copy.gear.firstIndex(where: { $0.id == currentGearID }) {
            copy.gear[index].ownerID = nil
        }
        copy.equippedGearIDs = copy.equippedGearIDs.filter { $0.key != slotKey && $0.value != selectedGearID }
        copy.equippedGearIDs[slotKey] = selectedGearID
        if let index = copy.gear.firstIndex(where: { $0.id == selectedGearID }) { copy.gear[index].ownerID = actorID }
        return (copy, currentGearID, selectedDefinition.slot)
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

    private func validateCurrentGearLoadoutR342(state: GameSnapshot) throws -> Set<UUID> {
        guard !state.equippedGearIDs.isEmpty else {
            throw CoreError.invalidCommand("R342 cannot save or apply an empty current loadout")
        }
        var assignedIDs = Set<UUID>()
        for (slotKey, gearID) in state.equippedGearIDs {
            let parts = slotKey.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw CoreError.invalidCommand("R342 current loadout has a malformed actor-slot key")
            }
            let actorID = String(parts[0]), slot = String(parts[1])
            guard state.partyActorIDs.contains(actorID), assignedIDs.insert(gearID).inserted else {
                throw CoreError.invalidCommand("R342 current loadout has an unknown actor or duplicate gear")
            }
            let matches = state.gear.filter { $0.id == gearID }
            guard matches.count == 1, let item = matches.first else {
                throw CoreError.invalidCommand("R342 current loadout gear is missing or duplicated: \(gearID)")
            }
            guard item.ownerID == nil || item.ownerID == actorID else {
                throw CoreError.invalidCommand("R342 current loadout owner does not match its equipped actor")
            }
            guard let definition = catalog.gear.first(where: { $0.id == item.definitionID }),
                  definition.slot == slot, GearSwapCombatPreviewR131.isUsableByActorR131(definition, actorID: actorID) else {
                throw CoreError.invalidCommand("R342 current loadout gear no longer matches its actor and slot")
            }
            try validateCandidatePayloadIfEnabled(item)
        }
        return assignedIDs
    }

    private func validateGearLoadoutR342(_ assignments: [String: UUID], state: GameSnapshot,
                                         currentlyEquippedIDs: Set<UUID>) throws {
        guard !assignments.isEmpty else { throw CoreError.invalidCommand("R342 cannot save or apply an empty loadout") }
        var assignedIDs = Set<UUID>()
        for (slotKey, gearID) in assignments {
            let parts = slotKey.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw CoreError.invalidCommand("R342 loadout has a malformed actor-slot key")
            }
            let actorID = String(parts[0]), slot = String(parts[1])
            guard state.partyActorIDs.contains(actorID) else {
                throw CoreError.invalidCommand("R342 loadout actor is not in the party: \(actorID)")
            }
            guard assignedIDs.insert(gearID).inserted else {
                throw CoreError.invalidCommand("R342 loadout assigns one gear instance more than once")
            }
            let matches = state.gear.filter { $0.id == gearID }
            guard matches.count == 1, let item = matches.first else {
                throw CoreError.invalidCommand("R342 loadout gear is missing or duplicated: \(gearID)")
            }
            let movingEquippedItem = currentlyEquippedIDs.contains(gearID)
            guard item.ownerID == nil || item.ownerID == actorID ||
                  (movingEquippedItem && state.equippedGearIDs.contains(where: { $0.value == gearID && $0.key.hasPrefix((item.ownerID ?? "") + "|") })) else {
                throw CoreError.invalidCommand("R342 loadout gear belongs to another, unequipped actor")
            }
            guard let definition = catalog.gear.first(where: { $0.id == item.definitionID }),
                  definition.slot == slot, GearSwapCombatPreviewR131.isUsableByActorR131(definition, actorID: actorID) else {
                throw CoreError.invalidCommand("R342 loadout gear no longer matches its current actor and slot")
            }
            try validateCandidatePayloadIfEnabled(item)
            guard state.equippedGearIDs.allSatisfy({ $0.value != gearID || $0.key == slotKey || movingEquippedItem }) else {
                throw CoreError.invalidCommand("R342 loadout gear is currently assigned to a different slot")
            }
        }
    }

    private func validateCandidatePayloadIfEnabled(_ item: GearInstance) throws {
        guard let candidateLatentPolicy, let slots = item.candidateLatentSlots else { return }
        try candidateLatentPolicy.validateStoredPayload(templateID: item.definitionID, slots: slots)
    }

    private func makeCombatParty(state: GameSnapshot) throws -> [Combatant] {
        try state.partyActorIDs.map { actorID in
            let instances = state.equippedGearIDs.filter { $0.key.hasPrefix(actorID + "|") }.compactMap { _, instanceID in state.gear.first(where: { $0.id == instanceID }) }
            if enhancementProjectionPolicyR230 == .r2SlotBudgetCandidate {
                for item in instances { try GearEnhancementGrowthR230.validatePersistedEnhancement(item, in: catalog) }
            }
            let projectedRanks = naturalGearRefinementPolicyR352 == nil ? [:] : (state.naturalGearRefinementR352?.ranksByUUID ?? [:])
            var projected: Combatant
            if let candidateLatentPolicy {
                projected = try catalog.projectCandidateCombatantR005(for: actorID, with: instances,
                    completedResearchIDs: state.completedResearchIDs,
                    totalXP: state.characterXP[actorID, default: 0], candidateGrowth: candidateCharacterGrowth,
                    candidateLatentPolicy: candidateLatentPolicy,
                    enhancementProjectionPolicyR230: enhancementProjectionPolicyR230,
                    refinementRanksR352: projectedRanks).combatant
            } else {
                projected = catalog.projectCombatant(for: actorID, with: instances, completedResearchIDs: state.completedResearchIDs,
                                                     totalXP: state.characterXP[actorID, default: 0],
                                                     candidateGrowth: candidateCharacterGrowth,
                                                     enhancementProjectionPolicyR230: enhancementProjectionPolicyR230,
                                                     refinementRanksR352: projectedRanks)
            }
            return projected
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

    private func clearNaturalGearLegacyPartialMarkerR350(state: inout GameSnapshot) {
        guard var ledger = state.naturalGearDiscoveryR350, ledger.skipLegacyPartialUnit else { return }
        ledger.skipLegacyPartialUnit = false
        state.naturalGearDiscoveryR350 = ledger
    }

    private func effectivePartyWorkTargetR144(state: GameSnapshot) -> PartyWorkTargetR144? {
        state.partyWorkTargetR144 ?? state.gatherTargetMaterialID.map { .gather($0) }
    }

    private func validatePartyWorkTimestampR144(_ now: Date, state: GameSnapshot) throws {
        guard now.timeIntervalSince1970.isFinite else {
            throw CoreError.invalidCommand("R144 target timestamp must be finite")
        }
        if let lastClaimAt = state.lastClaimAt, now < lastClaimAt {
            throw CoreError.invalidCommand("R144 work clock moved backward")
        }
    }

    /// First candidate mutations turn a valid legacy gather selection into an explicit
    /// opt-in target in the same transaction. Saves with no usable target fail closed.
    private func requireOrPersistPartyWorkMarkerR144(state: inout GameSnapshot) throws {
        guard candidatePartyWorkPolicyR144 != nil else { return }
        if let target = state.partyWorkTargetR144 {
            try validatePartyWorkTargetR144(target, state: state)
            return
        }
        guard let target = state.gatherTargetMaterialID.map(PartyWorkTargetR144.gather) else {
            throw CoreError.invalidCommand("R144 requires an explicit work target before mutating this save")
        }
        try validatePartyWorkTargetR144(target, state: state)
        state.partyWorkTargetR144 = target
    }

    private func validatePartyWorkTargetR144(_ target: PartyWorkTargetR144, state: GameSnapshot) throws {
        guard let regionID = state.activeRegionID,
              state.unlockedRegionIDs.contains(regionID),
              let region = catalog.regions.first(where: { $0.id == regionID }) else {
            throw CoreError.invalidCommand("R144 work target requires an unlocked active region")
        }
        switch target.kind {
        case .gather:
            guard region.gatherMaterialIDs.contains(target.targetID),
                  catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs,
                                                     completedEncounterIDs: state.completedEncounterIDs).contains(target.targetID) else {
                throw CoreError.invalidCommand("R144 gather target is unavailable in the active region")
            }
        case .investigate:
            guard let enemy = catalog.enemies.first(where: { $0.id == target.targetID }),
                  enemy.regionID == regionID, region.enemyIDs.contains(enemy.id),
                  state.completedEncounterIDs.contains(enemy.id),
                  enemy.prerequisiteEncounterID.map(state.completedEncounterIDs.contains) ?? true else {
                throw CoreError.invalidCommand("R144 investigation requires an already-cleared enemy in the active region")
            }
            _ = try PartyWorkR144Validation.declaredDropMaterialID(for: enemy, catalog: catalog)
        }
    }

    private func r350GateIsCleared(_ gateID: String, state: GameSnapshot) -> Bool {
        if gateID == "G_START" { return true }
        let parts = gateID.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { return false }
        return state.completedEncounterIDs.contains("B_\(parts[1])_\(parts[2])")
    }

    private func captureNaturalPoolR350(state: GameSnapshot, ledger: NaturalGearDiscoveryLedgerR350) throws -> NaturalGearPoolSnapshotR350 {
        guard let policy = naturalGearDiscoveryPolicyR350,
              let regionID = state.activeRegionID,
              state.unlockedRegionIDs.contains(regionID),
              let regionPool = NaturalGearDiscoveryPolicyR350.regionPools[regionID] else {
            throw CoreError.invalidCommand("R350 natural gear requires a currently unlocked R3 region pool")
        }
        let allIDs = Array(Set(NaturalGearDiscoveryPolicyR350.regionPools.values.flatMap{$0})).sorted()
        let evolvedIDs = Set(catalog.recipes.filter { $0.kind == "evolve_in_place" }.compactMap(\.outputGearID))
        func eligible(_ templateID: String) -> Bool {
            guard let definition = catalog.gear.first(where: { $0.id == templateID }),
                  definition.actorIDs.isEmpty || definition.actorIDs.contains(where: state.partyActorIDs.contains) else { return false }
            if evolvedIDs.contains(templateID), !ledger.discoveredCraftedTemplateIDs.contains(templateID) { return false }
            let recipes = catalog.recipes.filter { $0.outputGearID == templateID }
            if !recipes.isEmpty {
                let routeRecipes = recipes.filter { $0.kind != "evolve_in_place" || ledger.discoveredCraftedTemplateIDs.contains(templateID) }
                if !routeRecipes.isEmpty && !routeRecipes.contains(where: { $0.gateID.map { self.r350GateIsCleared($0, state: state) } ?? true }) { return false }
            }
            return true
        }
        let global = allIDs.filter(eligible)
        let local = regionPool.filter(eligible)
        guard !global.isEmpty else { throw CoreError.invalidCommand("R350 STORAGE_BLOCKED: no eligible natural gear template in the pinned global pool") }
        let discovered = global.filter { !evolvedIDs.contains($0) || ledger.discoveredCraftedTemplateIDs.contains($0) }
        let sourceRank = NaturalGearDiscoveryPolicyR350.regionRanks[regionID] ?? 1
        let unlockedRank = state.unlockedRegionIDs.compactMap { NaturalGearDiscoveryPolicyR350.regionRanks[$0] }.max() ?? 1
        let ranks = Dictionary(uniqueKeysWithValues: global.map { ($0, naturalAttunementRankR350(templateID: $0, regionID: regionID, highestUnlockedRank: unlockedRank, state: state)) })
        let desired = state.trackedRecipeID.flatMap { id in catalog.recipes.first(where: { $0.id == id })?.outputGearID }
        _ = policy
        return NaturalGearPoolSnapshotR350(regionID: regionID, sourceRegionRank: sourceRank, highestUnlockedRegionRank: unlockedRank, local: local, global: global,
            discovered: discovered, actors: state.partyActorIDs, attunementRanks: ranks, desiredTemplateID: desired)
    }

    private func naturalAttunementRankR350(templateID: String, regionID: String, highestUnlockedRank: Int, state: GameSnapshot) -> Int {
        let sourceRank = NaturalGearDiscoveryPolicyR350.regionRanks[regionID] ?? 1
        if naturalGearRefinementPolicyR352 == nil {
            // Preserve existing R350-only behavior when the separate rank system is off.
            let gates = catalog.recipes.filter { $0.outputGearID == templateID }.compactMap(\.gateID)
            let unlockedGateRanks = gates.filter { r350GateIsCleared($0, state: state) }.compactMap { gate -> Int? in
                if gate == "G_START" { return 1 }
                let parts = gate.split(separator: "_")
                guard parts.count == 3, parts[0] == "G", let rank = NaturalGearDiscoveryPolicyR350.regionRanks[String(parts[1])] else { return nil }
                return rank
            }
            return min(sourceRank, highestUnlockedRank, unlockedGateRanks.max() ?? highestUnlockedRank)
        }
        // R352 birth rank follows global cleared-boss progression, not a template's recipe gate.
        let globalRank = NaturalGearRefinementPolicyR352.globalRank(completedEncounterIDs: state.completedEncounterIDs)
        return min(sourceRank, highestUnlockedRank, globalRank)
    }

    private func naturalQualityR350(ledger: inout NaturalGearDiscoveryLedgerR350, rollIndex: Int) throws -> String {
        if ledger.missesSinceQ4 >= 99 { ledger.missesSinceQ4 = 0; return "Q4" }
        let roll = NaturalGearCounterRandomR350.bounded(seed: ledger.seedHex, index: rollIndex,
                                                        domain: "quality", upperBound: 10_000)
        var boundary = 0
        for (quality, weight) in NaturalGearDiscoveryPolicyR350.baseQualityWeights {
            boundary += weight
            if roll < boundary {
                if quality == "Q4" { ledger.missesSinceQ4 = 0 }
                else { ledger.missesSinceQ4 = try checkedAdd(ledger.missesSinceQ4, 1, label: "R350 Q4 pity") }
                return quality
            }
        }
        throw CoreError.invalidCommand("R350 quality table does not cover 10,000 basis points")
    }

    private func settleNaturalGearR350(units: Int, operationID: UUID, state: inout GameSnapshot) throws {
        guard naturalGearDiscoveryPolicyR350 != nil, units > 0,
              var ledger = state.naturalGearDiscoveryR350 else { return }
        for _ in 0..<units {
            if ledger.skipLegacyPartialUnit {
                // The shared R144 unit that finishes a legacy fractional remainder began
                // before R350 activation; preserve its ordinary payout but do not count it.
                ledger.skipLegacyPartialUnit = false
                continue
            }
            if ledger.workUnitsIntoDrop == 0 {
                ledger.pinnedPool = try captureNaturalPoolR350(state: state, ledger: ledger)
            }
            ledger.workUnitsIntoDrop += 1
            guard ledger.workUnitsIntoDrop <= NaturalGearDiscoveryPolicyR350.workUnitsPerDrop,
                  let pool = ledger.pinnedPool else {
                throw CoreError.invalidCommand("R350 pinned period state is incomplete")
            }
            guard ledger.workUnitsIntoDrop == NaturalGearDiscoveryPolicyR350.workUnitsPerDrop else { continue }
            guard state.gear.count < NaturalGearDiscoveryPolicyR350.inventorySafetyCeiling else {
                throw CoreError.invalidCommand("STORAGE_BLOCKED: R350 natural gear inventory ceiling reached; transaction was not credited")
            }
            let nextIndex = try checkedAdd(ledger.naturalRollIndex, 1, label: "R350 natural roll index")
            let quality = try naturalQualityR350(ledger: &ledger, rollIndex: nextIndex)
            let desired = pool.desiredTemplateID
            let chosenTemplate: String
            let useLocal = NaturalGearCounterRandomR350.bounded(seed: ledger.seedHex, index: nextIndex,
                domain: "pool-scope", upperBound: 10_000) < NaturalGearDiscoveryPolicyR350.localPoolBasisPoints
            let choices = useLocal && !pool.localEligibleTemplateIDs.isEmpty ? pool.localEligibleTemplateIDs : pool.globalEligibleTemplateIDs
            let templateIndex = NaturalGearCounterRandomR350.bounded(seed: ledger.seedHex, index: nextIndex,
                domain: "template", upperBound: choices.count)
            chosenTemplate = choices[templateIndex]
            guard let definition = catalog.gear.first(where: { $0.id == chosenTemplate }),
                  let latent = candidateLatentPolicy else {
                throw CoreError.invalidCommand("R350 selected a template without current catalog/latent support")
            }
            let gearID = NaturalGearCounterRandomR350.uuid(seed: ledger.seedHex, index: nextIndex,
                                                           templateID: chosenTemplate)
            guard !state.gear.contains(where: { $0.id == gearID }) else {
                throw CoreError.invalidCommand("R350 deterministic gear UUID collides with an existing instance")
            }
            let rawFloor = quality == "Q4" ? 600 : 0
            let slots = try latent.generateNewInstanceSlots(templateID: chosenTemplate,
                joinedActorIDs: Set(pool.joinedActorIDs), operationID: gearID,
                domainSalt: "natural-r350|\(nextIndex)|\(chosenTemplate)", minimumRawQ: rawFloor)
            let protect = !state.gear.contains(where: { $0.definitionID == chosenTemplate }) || quality == "Q4"
            state.gear.append(GearInstance(id: gearID, definitionID: definition.id, protected: protect,
                                           candidateLatentSlots: slots, qualityID: quality))
            guard let rank = pool.attunementRankByTemplateID[chosenTemplate] else {
                throw CoreError.invalidCommand("R350 pinned attunement rank missing for chosen template")
            }
            if naturalGearRefinementPolicyR352 != nil, rank > 1 {
                var ranks = state.naturalGearRefinementR352 ?? NaturalGearRefinementLedgerR352()
                ranks.setRank(rank, for: gearID)
                state.naturalGearRefinementR352 = ranks
            }
            ledger.naturalRollIndex = nextIndex
            ledger.acquisitionRecords.append(NaturalGearAcquisitionRecordR350(
                gearInstanceID: gearID, templateID: chosenTemplate, sourceRegionID: pool.regionID,
                attunementRank: rank, naturalRollIndex: nextIndex, qualityID: quality, operationID: operationID))
            if ledger.acquisitionRecords.count > NaturalGearDiscoveryPolicyR350.retainedAcquisitionRecords {
                ledger.acquisitionRecords.removeFirst(ledger.acquisitionRecords.count - NaturalGearDiscoveryPolicyR350.retainedAcquisitionRecords)
            }
            ledger.workUnitsIntoDrop = 0
            ledger.pinnedPool = nil
        }
        state.naturalGearDiscoveryR350 = ledger
    }

    /// A legacy save is settled under its existing R144 rules before the R350 seed is
    /// initialized. This prevents old elapsed work from being credited as retroactive gear.
    private typealias PartyWorkSettlementR144 = (units: Int, materialID: String?)

    /// Returns any R144 units settled before the R350 ledger existed. The caller may
    /// report these legacy units, but they are never replayed into the newly-created
    /// natural-gear ledger.
    @discardableResult
    private func initializeNaturalGearLedgerR350IfNeeded(now: Date, cap: TimeInterval = PartyWorkPolicyR144.offlineCapSeconds, operationID: UUID, state: inout GameSnapshot) throws -> PartyWorkSettlementR144 {
        guard naturalGearDiscoveryPolicyR350 != nil else { return (0, nil) }
        guard state.naturalGearDiscoveryR350 == nil else { return (0, nil) }
        let legacySettlement: PartyWorkSettlementR144
        if state.activeRegionID != nil, effectivePartyWorkTargetR144(state: state) != nil, state.lastClaimAt != nil {
            legacySettlement = try settlePartyWorkR144(now: now, secondsPerUnit: nil,
                cap: cap, operationID: operationID, state: &state)
        } else {
            guard now.timeIntervalSince1970.isFinite else { throw CoreError.invalidCommand("R350 activation timestamp must be finite") }
            state.lastClaimAt = now
            legacySettlement = (0, nil)
        }
        state.naturalGearDiscoveryR350 = NaturalGearDiscoveryLedgerR350(
            seedHex: NaturalGearCounterRandomR350.seed(operationID: operationID),
            skipLegacyPartialUnit: state.offlineRemainderSeconds > 0)
        return legacySettlement
    }

    /// Settles exactly one selected target from the one persisted party clock.
    /// No battle, clear, unlock, or combat-result state is written here.
    private func settlePartyWorkR144(now: Date, secondsPerUnit: TimeInterval?, cap: TimeInterval,
                                     operationID: UUID, state: inout GameSnapshot) throws -> (units: Int, materialID: String?) {
        guard candidatePartyWorkPolicyR144 != nil else {
            throw CoreError.invalidCommand("R144 shared party work policy is not enabled")
        }
        guard now.timeIntervalSince1970.isFinite, cap.isFinite, secondsPerUnit?.isFinite ?? true else {
            throw CoreError.invalidCommand("R144 work timestamp and limits must be finite")
        }
        guard let target = effectivePartyWorkTargetR144(state: state) else {
            throw CoreError.invalidCommand("R144 work target is missing")
        }
        try validatePartyWorkTargetR144(target, state: state)
        guard let regionID = state.activeRegionID,
              let region = catalog.regions.first(where: { $0.id == regionID }) else {
            throw CoreError.invalidCommand("R144 work requires a catalog region")
        }
        if let secondsPerUnit, secondsPerUnit != TimeInterval(max(1, region.workSeconds)) {
            throw CoreError.invalidCommand("R144 work cadence is fixed by the active region catalog")
        }
        let effectiveCap = min(cap, PartyWorkPolicyR144.offlineCapSeconds)
        guard effectiveCap > 0 else { throw CoreError.invalidCommand("R144 work cap must be positive") }
        let interval = secondsPerUnit ?? TimeInterval(max(1, region.workSeconds))
        guard interval.isFinite, interval > 0,
              state.offlineRemainderSeconds.isFinite, state.offlineRemainderSeconds >= 0,
              state.offlineRemainderSeconds <= interval else {
            throw CoreError.invalidCommand("R144 work interval or saved remainder is invalid")
        }
        let rawElapsed = state.lastClaimAt.map { now.timeIntervalSince($0) } ?? 0
        guard rawElapsed.isFinite, rawElapsed >= 0 else {
            throw CoreError.invalidCommand("R144 work clock moved backward")
        }
        let elapsed = min(effectiveCap, rawElapsed)
        let accrued = min(effectiveCap, elapsed + state.offlineRemainderSeconds)
        let rawUnits = accrued / interval
        guard rawUnits.isFinite, rawUnits >= 0, rawUnits < Double(Int.max) else {
            throw CoreError.invalidCommand("R144 work unit count exceeds supported range")
        }
        let units = Int(rawUnits)
        let materialID: String
        switch target.kind {
        case .gather:
            materialID = target.targetID
        case .investigate:
            guard let enemy = catalog.enemies.first(where: { $0.id == target.targetID }) else {
                throw CoreError.invalidCommand("R144 investigation material is unavailable")
            }
            materialID = try PartyWorkR144Validation.declaredDropMaterialID(for: enemy, catalog: catalog)
        }
        if units > 0 {
            try settleNaturalGearR350(units: units, operationID: operationID, state: &state)
            let amount = try checkedProduct(units, PartyWorkPolicyR144.materialPerCompletedUnit,
                                            label: "R144 work material")
            state.materials[materialID] = try checkedAdd(state.materials[materialID, default: 0], amount,
                                                          label: materialID)
            let xp = try checkedProduct(units, region.xpPerWork, label: "R144 work XP")
            let dust = try checkedProduct(units, region.dustPerWork, label: "R144 work dust")
            for actorID in state.partyActorIDs {
                state.characterXP[actorID] = try checkedAdd(state.characterXP[actorID, default: 0], xp,
                                                             label: "XP for \(actorID)")
            }
            state.materials["refine_dust"] = try checkedAdd(state.materials["refine_dust", default: 0], dust,
                                                              label: "refine dust")
            try accrueLocalAdWork(units: units, region: region, now: now, state: &state)
            // R144 investigation coin yield is explicitly zero. Gathering's
            // other work side-effects remain the existing party-work contract.
        }
        state.offlineRemainderSeconds = accrued.truncatingRemainder(dividingBy: interval)
        state.lastClaimAt = now
        return (units, units > 0 ? materialID : nil)
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

    private func selectExpedition(regionID: String, now: Date, operationID: UUID, state: inout GameSnapshot) throws -> String {
        guard state.unlockedRegionIDs.contains(regionID) else { throw CoreError.invalidCommand("region is locked") }
        guard catalog.regions.contains(where: { $0.id == regionID }) else { throw CoreError.invalidCommand("unknown region") }
        let available = catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs)
        guard !available.isEmpty else { throw CoreError.invalidCommand("no gather material has been unlocked for region") }
        let target = available.contains(state.gatherTargetMaterialID ?? "") ? state.gatherTargetMaterialID : available.first
        if candidatePartyWorkPolicyR144 != nil {
            try validatePartyWorkTimestampR144(now, state: state)
            guard let target else { throw CoreError.invalidCommand("R144 expedition has no gather target") }
            let desired = PartyWorkTargetR144.gather(target)
            let changed = state.activeRegionID != regionID || effectivePartyWorkTargetR144(state: state) != desired
            if state.activeRegionID == nil || effectivePartyWorkTargetR144(state: state) == nil || state.lastClaimAt == nil {
                state.lastClaimAt = now
                state.offlineRemainderSeconds = 0
                clearNaturalGearLegacyPartialMarkerR350(state: &state)
            } else {
                _ = try settlePartyWorkR144(now: now, secondsPerUnit: nil,
                                             cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
                if changed {
                    state.offlineRemainderSeconds = 0
                    clearNaturalGearLegacyPartialMarkerR350(state: &state)
                }
            }
            state.activeRegionID = regionID
            state.gatherTargetMaterialID = target
            state.partyWorkTargetR144 = desired
            return "expedition started: \(regionID); R144 gathering selected"
        }
        if state.lastClaimAt == nil { state.lastClaimAt = now }
        let changed = state.activeRegionID != regionID || target != state.gatherTargetMaterialID
        if changed {
            _ = try settleGathering(now: now, state: &state)
            state.offlineRemainderSeconds = 0 // fractional time cannot cross a material or region boundary
        }
        state.activeRegionID = regionID
        state.gatherTargetMaterialID = target
        return "expedition started: \(regionID)"
    }

    private func selectGatherTarget(resourceID: String, now: Date, operationID: UUID, state: inout GameSnapshot) throws -> String {
        guard let regionID = state.activeRegionID, let region = catalog.regions.first(where: { $0.id == regionID }), region.gatherMaterialIDs.contains(resourceID),
              catalog.availableGatherMaterialIDs(in: regionID, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs).contains(resourceID) else { throw CoreError.invalidCommand("gather target is unavailable in active region") }
        if candidatePartyWorkPolicyR144 != nil {
            try validatePartyWorkTimestampR144(now, state: state)
            let target = PartyWorkTargetR144.gather(resourceID)
            if effectivePartyWorkTargetR144(state: state) != target {
                try validatePartyWorkTargetR144(target, state: state)
                if effectivePartyWorkTargetR144(state: state) == nil || state.lastClaimAt == nil {
                    guard now.timeIntervalSince1970.isFinite else { throw CoreError.invalidCommand("R144 target timestamp must be finite") }
                    state.lastClaimAt = now
                } else {
                    _ = try settlePartyWorkR144(now: now, secondsPerUnit: nil,
                                                 cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
                }
                state.offlineRemainderSeconds = 0
                clearNaturalGearLegacyPartialMarkerR350(state: &state)
            } else if state.lastClaimAt != nil {
                _ = try settlePartyWorkR144(now: now, secondsPerUnit: nil,
                                             cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
            }
            if state.lastClaimAt == nil {
                guard now.timeIntervalSince1970.isFinite else { throw CoreError.invalidCommand("R144 target timestamp must be finite") }
                state.lastClaimAt = now
            }
            state.gatherTargetMaterialID = resourceID
            state.partyWorkTargetR144 = target
            return "gather target set: \(resourceID); R144 shared work selected"
        }
        if state.gatherTargetMaterialID != resourceID || state.lastClaimAt == nil {
            _ = try settleGathering(now: now, state: &state)
            state.gatherTargetMaterialID = resourceID
        }
        return "gather target set: \(resourceID)"
    }

    /// Changes the single persisted work target under the opt-in R144 policy.
    /// The old target is settled before switching; fractional work never crosses.
    public func setPartyWorkTargetR144(_ target: PartyWorkTargetR144, now: Date,
                                       operationID: UUID, expectedRevision: Int64) async throws -> CommandReceipt {
        guard let policy = candidatePartyWorkPolicyR144 else {
            throw CoreError.invalidCommand("R144 shared party work policy is not enabled")
        }
        var fingerprint = "\(PartyWorkPolicyR144.policyID)|\(target.kind.rawValue)|\(target.targetID)|\(now.timeIntervalSince1970)|\(policy.policyFingerprint)"
        if let r350 = naturalGearDiscoveryPolicyR350 { fingerprint += "|R350|\(r350.policyFingerprint)" }
        if let r352 = naturalGearRefinementPolicyR352 { fingerprint += "|R352|\(r352.policyFingerprint)" }
        if let r353 = gearDismantleRefundPolicyR353 { fingerprint += "|R353|\(r353.policyFingerprint)" }
        return try await saves.transact(expectedRevision: expectedRevision, operationID: operationID,
                                        requestFingerprint: fingerprint) { state in
            guard self.naturalGearDiscoveryPolicyR350 != nil || state.naturalGearDiscoveryR350 == nil else {
                throw CoreError.invalidCommand("R350 natural-gear save requires the matching opt-in policy")
            }
            guard self.naturalGearRefinementPolicyR352 != nil || state.naturalGearRefinementR352 == nil else {
                throw CoreError.invalidCommand("R352 refinement save requires the matching opt-in policy")
            }
            try self.validatePartyWorkTimestampR144(now, state: state)
            try self.validatePartyWorkTargetR144(target, state: state)
            if self.naturalGearDiscoveryPolicyR350 != nil {
                try self.initializeNaturalGearLedgerR350IfNeeded(now: now, operationID: operationID, state: &state)
            }
            let oldTarget = self.effectivePartyWorkTargetR144(state: state)
            if oldTarget != target {
                if oldTarget == nil || state.lastClaimAt == nil {
                    guard now.timeIntervalSince1970.isFinite else {
                        throw CoreError.invalidCommand("R144 switch timestamp must be finite")
                    }
                    state.lastClaimAt = now
                } else {
                    _ = try self.settlePartyWorkR144(now: now, secondsPerUnit: nil,
                                                     cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
                }
                state.offlineRemainderSeconds = 0
                clearNaturalGearLegacyPartialMarkerR350(state: &state)
            } else if state.lastClaimAt != nil {
                _ = try self.settlePartyWorkR144(now: now, secondsPerUnit: nil,
                                                  cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
            }
            if state.lastClaimAt == nil {
                guard now.timeIntervalSince1970.isFinite else {
                    throw CoreError.invalidCommand("R144 switch timestamp must be finite")
                }
                state.lastClaimAt = now
            }
            state.partyWorkTargetR144 = target
            if target.kind == .gather { state.gatherTargetMaterialID = target.targetID }
            return "R144 party work target selected: \(target.kind.rawValue) / \(target.targetID); candidate only"
        }
    }

    private func transactionDateR350(for command: GameCommand) -> Date? {
        switch command {
        case .startExpeditionAt(_, let now), .setGatherTargetAt(_, let now), .gather(_, let now), .dailyClaim(let now): return now
        default: return nil
        }
    }

    @discardableResult
    public func dispatch(_ command: GameCommand, operationID: UUID, expectedRevision: Int64,
                         transactionDate: Date? = nil) async throws -> CommandReceipt {
        let embeddedDate = self.transactionDateR350(for: command)
        if let transactionDate, let embeddedDate, transactionDate != embeddedDate {
            throw CoreError.invalidCommand("R350 transactionDate conflicts with the command's embedded date")
        }
        let resolvedTransactionDate = embeddedDate ?? transactionDate ?? Date()
        var requestFingerprint = command.requestFingerprint
        if let r144 = candidatePartyWorkPolicyR144 { requestFingerprint += "|R144|\(r144.policyFingerprint)" }
        if let r350 = naturalGearDiscoveryPolicyR350 { requestFingerprint += "|R350|\(r350.policyFingerprint)" }
        if let r352 = naturalGearRefinementPolicyR352 { requestFingerprint += "|R352|\(r352.policyFingerprint)" }
        if let r353 = gearDismantleRefundPolicyR353 { requestFingerprint += "|R353|\(r353.policyFingerprint)" }
        // Embedded command timestamps are already part of command.requestFingerprint.
        // An implicit wall clock must not make an idempotent retry look like a new request.
        if naturalGearDiscoveryPolicyR350 != nil, embeddedDate == nil, let transactionDate {
            requestFingerprint += "|R350-explicit-time|\(transactionDate.timeIntervalSince1970)"
        }
        return try await saves.transact(expectedRevision: expectedRevision, operationID: operationID, requestFingerprint: requestFingerprint) { state in
            guard self.candidatePartyWorkPolicyR144 != nil || state.partyWorkTargetR144 == nil else {
                throw CoreError.invalidCommand("R144 candidate save requires the matching opt-in policy")
            }
            guard self.naturalGearDiscoveryPolicyR350 != nil || state.naturalGearDiscoveryR350 == nil else {
                throw CoreError.invalidCommand("R350 natural-gear save requires the matching opt-in policy")
            }
            guard self.naturalGearRefinementPolicyR352 != nil || state.naturalGearRefinementR352 == nil else {
                throw CoreError.invalidCommand("R352 refinement save requires the matching opt-in policy")
            }
            if self.candidatePartyWorkPolicyR144 != nil {
                switch command {
                case .startExpedition(_), .startExpeditionAt(_, _), .setGatherTarget(_), .setGatherTargetAt(_, _):
                    // These are the only legacy-save entry points that may establish the typed target.
                    break
                default:
                    try self.requireOrPersistPartyWorkMarkerR144(state: &state)
                }
            }
            if self.naturalGearDiscoveryPolicyR350 != nil {
                try self.initializeNaturalGearLedgerR350IfNeeded(now: resolvedTransactionDate, operationID: operationID, state: &state)
                if state.activeRegionID != nil, self.effectivePartyWorkTargetR144(state: state) != nil {
                    _ = try self.settlePartyWorkR144(now: resolvedTransactionDate, secondsPerUnit: nil,
                        cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
                }
            }
            switch command {
            case .saveGearLoadoutR342(let slot):
                _ = try self.validateCurrentGearLoadoutR342(state: state)
                var payload = state.gearLoadoutsR342 ?? GearLoadoutsR342()
                payload.set(GearLoadoutR342(gearByActorSlot: state.equippedGearIDs), for: slot)
                state.gearLoadoutsR342 = payload
                return "R342 loadout saved: \(slot.rawValue)"
            case .applyGearLoadoutR342(let slot):
                guard let saved = state.gearLoadoutsR342?.loadout(for: slot) else {
                    throw CoreError.invalidCommand("R342 loadout slot is empty")
                }
                let currentlyEquippedIDs = try self.validateCurrentGearLoadoutR342(state: state)
                try self.validateGearLoadoutR342(saved.gearByActorSlot, state: state,
                                                 currentlyEquippedIDs: currentlyEquippedIDs)
                for index in state.gear.indices where state.equippedGearIDs.values.contains(state.gear[index].id) {
                    state.gear[index].ownerID = nil
                }
                state.equippedGearIDs = saved.gearByActorSlot
                for (slotKey, gearID) in saved.gearByActorSlot {
                    let actorID = String(slotKey.split(separator: "|", maxSplits: 1)[0])
                    guard let index = state.gear.firstIndex(where: { $0.id == gearID }) else {
                        throw CoreError.invalidCommand("R342 loadout gear disappeared during apply")
                    }
                    state.gear[index].ownerID = actorID
                }
                return "R342 loadout applied: \(slot.rawValue)"
            case .clearGearLoadoutR342(let slot):
                guard var payload = state.gearLoadoutsR342,
                      payload.loadout(for: slot) != nil else {
                    throw CoreError.invalidCommand("R342 loadout slot is empty")
                }
                payload.set(nil, for: slot)
                state.gearLoadoutsR342 = payload.first == nil && payload.second == nil ? nil : payload
                return "R342 loadout cleared: \(slot.rawValue)"
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
                if let policy = self.naturalGearRefinementPolicyR352 {
                    let rank = state.naturalGearRefinementR352?.rank(for: id) ?? 1
                    guard let rankCap = policy.maximumEnhancement(forRank: rank), nextLevel <= rankCap else {
                        throw CoreError.invalidCommand("R352 rank \(rank) enhancement cap is +\(policy.maximumEnhancement(forRank: rank) ?? 0)")
                    }
                }
                guard let recipe = catalog.recipes.first(where: { $0.id == "ENHANCE_\(nextLevel)" }), recipe.kind == "enhance" else { throw CoreError.invalidCommand("enhancement level is at catalog cap") }
                if let gateID = recipe.gateID, gateID != "G_START" { try requireGate(gateID, state: state) }
                try spend("refine_dust", recipe.dustCost, from: &state); state.gear[index].enhancement = nextLevel; state.gear[index].investmentDust = try checkedAdd(state.gear[index].investmentDust, recipe.dustCost, label: "gear investment"); return "enhanced to +\(nextLevel) for \(recipe.dustCost) dust [\(recipe.status)]"
            case .refine(let id):
                guard let index = state.gear.firstIndex(where: { $0.id == id }) else { throw CoreError.invalidCommand("unknown gear") }
                try validateCandidatePayloadIfEnabled(state.gear[index])
                if let policy = self.naturalGearRefinementPolicyR352 {
                    var ledger = state.naturalGearRefinementR352 ?? NaturalGearRefinementLedgerR352()
                    let currentRank = ledger.rank(for: id)
                    guard (1...5).contains(currentRank) else { throw CoreError.invalidCommand("R352 saved refinement rank is invalid") }
                    guard let step = policy.transition(from: currentRank) else { throw CoreError.invalidCommand("R352 refinement is already at rank V") }
                    try self.requireGate(step.gateID, state: state)
                    try spend("refine_dust", step.dustCost, from: &state)
                    for (materialID, amount) in step.materialCosts { try spend(materialID, amount, from: &state) }
                    ledger.setRank(step.toRank, for: id)
                    state.naturalGearRefinementR352 = ledger
                    // Preserve cumulative investment accounting; current dismantle grants one dust only.
                    state.gear[index].investmentDust = try checkedAdd(state.gear[index].investmentDust, step.dustCost, label: "R352 refinement investment")
                    return "R352 rank \(step.fromRank)→\(step.toRank); spent \(step.dustCost) dust"
                }
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
                let refundDust: Int
                let resultMessage: String
                if let refundPolicy = self.gearDismantleRefundPolicyR353 {
                    refundDust = try refundPolicy.refundBreakdown(gearID: item.id, qualityID: item.qualityID,
                                                                 investmentDust: item.investmentDust).totalDust
                    resultMessage = "gear dismantled for \(refundDust) refine_dust"
                } else {
                    // Preserve the legacy payout and receipt text unless R353 is explicitly enabled.
                    refundDust = 1
                    resultMessage = "gear dismantled"
                }
                let updatedDust = try checkedAdd(state.materials["refine_dust", default: 0], refundDust, label: "dismantle refund")
                state.gear.removeAll { $0.id == id }
                if self.naturalGearRefinementPolicyR352 != nil, var ranks = state.naturalGearRefinementR352 {
                    ranks.remove(id); state.naturalGearRefinementR352 = ranks.isEmpty ? nil : ranks
                }
                state.materials["refine_dust"] = updatedDust
                return resultMessage
            case .craftRecipe(let recipeID):
                let result = try applyRecipe(recipeID, gearID: nil, operationID: operationID, state: &state)
                if self.naturalGearDiscoveryPolicyR350 != nil, var ledger = state.naturalGearDiscoveryR350,
                   let recipe = self.catalog.recipes.first(where: { $0.id == recipeID }), let output = recipe.outputGearID {
                    ledger.discoveredCraftedTemplateIDs.insert(output); state.naturalGearDiscoveryR350 = ledger
                }
                return result
            case .evolveGear(let gearID, let recipeID):
                let result = try applyRecipe(recipeID, gearID: gearID, operationID: operationID, state: &state)
                if self.naturalGearDiscoveryPolicyR350 != nil, var ledger = state.naturalGearDiscoveryR350,
                   let recipe = self.catalog.recipes.first(where: { $0.id == recipeID }), let output = recipe.outputGearID {
                    ledger.discoveredCraftedTemplateIDs.insert(output); state.naturalGearDiscoveryR350 = ledger
                }
                return result
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
                return try selectExpedition(regionID: regionID, now: resolvedTransactionDate, operationID: operationID, state: &state)
            case .startExpeditionAt(let regionID, let now):
                return try selectExpedition(regionID: regionID, now: now, operationID: operationID, state: &state)
            case .setGatherTarget(let resourceID):
                return try selectGatherTarget(resourceID: resourceID, now: resolvedTransactionDate, operationID: operationID, state: &state)
            case .setGatherTargetAt(let resourceID, let now):
                return try selectGatherTarget(resourceID: resourceID, now: now, operationID: operationID, state: &state)
            case .gather(let resourceID, let now):
                if candidatePartyWorkPolicyR144 != nil {
                    guard effectivePartyWorkTargetR144(state: state) == PartyWorkTargetR144.gather(resourceID) else {
                        throw CoreError.invalidCommand("R144 gather command does not match selected party work target")
                    }
                    let settled = try settlePartyWorkR144(now: now, secondsPerUnit: nil,
                                                          cap: PartyWorkPolicyR144.offlineCapSeconds, operationID: operationID, state: &state)
                    guard settled.units > 0 else { throw CoreError.invalidCommand("no complete R144 work unit is ready") }
                    return "R144 gathered \(resourceID) x\(settled.units); candidate only"
                }
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
                let isFirstClear = !state.completedEncounterIDs.contains(enemyID)
                state.completedEncounterIDs.insert(enemyID)
                if candidatePartyWorkPolicyR144 == nil || isFirstClear {
                    if let dropID = enemy.dropMaterialID { state.materials[dropID] = try checkedAdd(state.materials[dropID, default: 0], enemy.boss ? 5 : 1, label: dropID) }
                    state.currency["coin"] = try checkedAdd(state.currency["coin", default: 0], enemy.boss ? 10 : 2, label: "coins")
                }
                if enemyID.hasSuffix("_B"), let index = catalog.regions.firstIndex(where: { $0.id == regionID }), catalog.regions.indices.contains(index + 1) { state.unlockedRegionIDs.insert(catalog.regions[index + 1].id) }
                if candidatePartyWorkPolicyR144 != nil && !isFirstClear {
                    return "VICTORY: \(enemyID), repeat battle; immediate rewards=0 under R144 candidate; ticks=\(result.ticks)"
                }
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
                    guard let appearance = catalog.appearances.first(where: { $0.id == cosmeticID && ($0.kind == "costume" || $0.kind == "accessory") }), appearance.actorIDs.contains(actorID), state.ownedCosmeticIDs.contains(cosmeticID) else { throw CoreError.invalidCommand("cosmetic appearance is unavailable for this actor or not owned") }
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
                return try settleLocalAdOpportunity(opportunityID: opportunityID, sessionID: result.sessionID, outcome: result.outcome, skip: false, now: resolvedTransactionDate, state: &state)
            case .claimMockAdSkip(let opportunityID):
                return try settleLocalAdOpportunity(opportunityID: opportunityID, sessionID: "LOCAL_SKIP_\(opportunityID)", outcome: .completed, skip: true, now: resolvedTransactionDate, state: &state)
            }
        }
    }

    /// Offline collection is capped and produces resources only; it never fabricates battle victory.
    public func claimOffline(now: Date, secondsPerUnit: TimeInterval? = nil, cap: TimeInterval = 48 * 3600, operationID: UUID, expectedRevision: Int64) async throws -> CommandReceipt {
        let ordinaryFingerprint = "offline|\(now.timeIntervalSince1970)|\(secondsPerUnit.map(String.init(describing:)) ?? "region")|\(cap)"
        var fingerprint = ordinaryFingerprint
        if let r144 = candidatePartyWorkPolicyR144 { fingerprint += "|R144|\(r144.policyFingerprint)" }
        if let r350 = naturalGearDiscoveryPolicyR350 { fingerprint += "|R350|\(r350.policyFingerprint)" }
        if let r352 = naturalGearRefinementPolicyR352 { fingerprint += "|R352|\(r352.policyFingerprint)" }
        return try await saves.transact(expectedRevision: expectedRevision, operationID: operationID, requestFingerprint: fingerprint) { state in
            guard self.candidatePartyWorkPolicyR144 != nil || state.partyWorkTargetR144 == nil else {
                throw CoreError.invalidCommand("R144 candidate save requires the matching opt-in policy")
            }
            guard self.naturalGearDiscoveryPolicyR350 != nil || state.naturalGearDiscoveryR350 == nil else {
                throw CoreError.invalidCommand("R350 natural-gear save requires the matching opt-in policy")
            }
            guard self.naturalGearRefinementPolicyR352 != nil || state.naturalGearRefinementR352 == nil else {
                throw CoreError.invalidCommand("R352 refinement save requires the matching opt-in policy")
            }
            if self.candidatePartyWorkPolicyR144 != nil {
                try self.requireOrPersistPartyWorkMarkerR144(state: &state)
            }
            guard now.timeIntervalSince1970.isFinite, cap.isFinite, secondsPerUnit?.isFinite ?? true else { throw CoreError.invalidCommand("offline timestamp and limits must be finite") }
            let effectiveCap = min(cap, 48 * 3600)
            guard effectiveCap > 0, let regionID = state.activeRegionID, let region = catalog.regions.first(where: { $0.id == regionID }) else { throw CoreError.invalidCommand("offline collection requires an active catalog region and positive cap") }
            var legacyActivationSettlement: PartyWorkSettlementR144 = (0, nil)
            if self.naturalGearDiscoveryPolicyR350 != nil {
                legacyActivationSettlement = try self.initializeNaturalGearLedgerR350IfNeeded(now: now, cap: effectiveCap, operationID: operationID, state: &state)
            }
            if self.candidatePartyWorkPolicyR144 != nil {
                let settled = try self.settlePartyWorkR144(now: now, secondsPerUnit: secondsPerUnit,
                                                           cap: effectiveCap, operationID: operationID, state: &state)
                let (totalUnits, overflow) = legacyActivationSettlement.units.addingReportingOverflow(settled.units)
                guard !overflow else { throw CoreError.invalidCommand("R144 reported work unit count overflow") }
                let materialID = settled.materialID ?? legacyActivationSettlement.materialID
                let activationDetail = legacyActivationSettlement.units > 0
                    ? "; legacyActivationUnits=\(legacyActivationSettlement.units); currentSettlementUnits=\(settled.units)"
                    : ""
                return "R144 offline work units=\(totalUnits); material=\(materialID ?? "none"); capSeconds=\(Int(effectiveCap)); remainingSeconds=\(Int(state.offlineRemainderSeconds)); no combat victory inferred; candidate only\(activationDetail)"
            }
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
        let materialCosts = try FirstCraftCostProjectionR179.validateCatalog(
            recipeID: recipe.id, declaredCosts: recipe.costs,
            snapshot: state, capability: firstCraftAidCapabilityR179).costs
        for (id, amount) in materialCosts.sorted(by: { $0.key < $1.key }) { try spend(id, amount, from: &state) }
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
