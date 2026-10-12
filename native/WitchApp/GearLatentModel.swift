import Foundation

struct GearStatsPresentation {
    let combatant: Combatant
    let latent: CandidateLatentActorProjectionR005?
}

extension GameModel {
    var candidateLatentPolicy: CandidateLatentSlotPolicyR003? { engine?.candidateLatentPolicy }

    func gearStats(for actorID: String, with gear: [GearInstance]) throws -> GearStatsPresentation {
        guard let catalog else { throw CoreError.invalidCommand("catalog is unavailable") }
        if let policy = candidateLatentPolicy {
            let projection = try catalog.projectCandidateCombatantR005(for: actorID, with: gear,
                completedResearchIDs: state.completedResearchIDs,
                totalXP: state.characterXP[actorID, default: 0], candidateGrowth: candidateCharacterGrowth,
                candidateLatentPolicy: policy)
            return GearStatsPresentation(combatant: projection.combatant, latent: projection.latent)
        }
        return GearStatsPresentation(combatant: catalog.projectCombatant(for: actorID, with: gear,
            completedResearchIDs: state.completedResearchIDs,
            totalXP: state.characterXP[actorID, default: 0], candidateGrowth: candidateCharacterGrowth), latent: nil)
    }

    func latentDisplay(for item: GearInstance) throws -> CandidateLatentItemDisplayR005 {
        guard let policy = candidateLatentPolicy else { throw CoreError.invalidCommand("latent policy is unavailable") }
        return try policy.slotPresentation(templateID: item.definitionID, qualityID: item.qualityID,
            actorID: selectedActor, candidateSlots: item.candidateLatentSlots)
    }

    func canEquip(_ item: GearInstance) -> Bool {
        guard canWearDefinition(item.definitionID) else { return false }
        guard item.candidateLatentSlots != nil else { return true }
        guard let display = try? latentDisplay(for: item) else { return false }
        return display.slots.allSatisfy(\.storedCompatible)
    }

    func canWearDefinition(_ templateID: String) -> Bool {
        guard let definition = catalog?.gear.first(where: { $0.id == templateID }) else { return false }
        return definition.actorIDs.isEmpty || definition.actorIDs.contains(selectedActor)
    }

    func comparisonStats(_ item: GearInstance) throws -> GearStatsPresentation {
        guard let catalog, let definition = catalog.gear.first(where: { $0.id == item.definitionID }),
              definition.actorIDs.isEmpty || definition.actorIDs.contains(selectedActor) else {
            throw CoreError.invalidCommand("actor cannot equip this gear")
        }
        let existing = state.equippedGearIDs.filter {
            $0.key.hasPrefix(selectedActor + "|") && $0.key != selectedActor + "|" + definition.slot
        }.values.compactMap { id in state.gear.first { $0.id == id } }
        var preview = item
        preview.ownerID = selectedActor
        return try gearStats(for: selectedActor, with: existing + [preview])
    }
}
