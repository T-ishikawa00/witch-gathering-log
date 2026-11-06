import Foundation

/// Compile-time gate for the local development candidate only.
enum NaturalGearRefinementBuildPolicyR352 {
    static var enabled: Bool {
        #if STANDARD_PLAY_R169 && NATURAL_GEAR_REFINEMENT_R352
        true
        #else
        false
        #endif
    }
}

/// Labels the opt-in UUID rank separately from GearInstance.refinement history.
enum GearRefinementPresentationR352 {
    static func rankName(_ rank: Int) -> String {
        switch rank {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        default: return "不明"
        }
    }
}

extension GameModel {
    /// Nil outside the R352-enabled engine. The view never infers enablement from save data.
    var naturalGearRefinementPolicyR352: NaturalGearRefinementPolicyR352? {
        guard NaturalGearRefinementBuildPolicyR352.enabled else { return nil }
        return engine?.naturalGearRefinementPolicyR352
    }
}

@MainActor extension GameModel {
    /// Actor-specific preview that forwards the exact UUID-rank map consumed by Core combat projection.
    func comparisonStatsR352(_ item: GearInstance, actorID: String, rank: Int) throws -> GearStatsPresentation {
        guard let catalog, let definition = catalog.gear.first(where: { $0.id == item.definitionID }),
              definition.actorIDs.isEmpty || definition.actorIDs.contains(actorID) else {
            throw CoreError.invalidCommand("actor cannot equip this gear")
        }
        let existing = state.equippedGearIDs.filter {
            $0.key.hasPrefix(actorID + "|") && $0.key != actorID + "|" + definition.slot
        }.values.compactMap { id in state.gear.first { $0.id == id } }
        var preview = item
        preview.ownerID = actorID
        var ranks = state.naturalGearRefinementR352?.ranksByUUID ?? [:]
        if rank <= 1 { ranks.removeValue(forKey: item.id) } else { ranks[item.id] = rank }

        if let latentPolicy = candidateLatentPolicy {
            let projection = try catalog.projectCandidateCombatantR005(for: actorID, with: existing + [preview],
                completedResearchIDs: state.completedResearchIDs,
                totalXP: state.characterXP[actorID, default: 0],
                candidateGrowth: candidateCharacterGrowth,
                candidateLatentPolicy: latentPolicy,
                enhancementProjectionPolicyR230: enhancementProjectionPolicyR230,
                refinementRanksR352: ranks)
            return GearStatsPresentation(combatant: projection.combatant, latent: projection.latent)
        }
        return GearStatsPresentation(combatant: catalog.projectCombatant(for: actorID, with: existing + [preview],
            completedResearchIDs: state.completedResearchIDs,
            totalXP: state.characterXP[actorID, default: 0],
            candidateGrowth: candidateCharacterGrowth,
            enhancementProjectionPolicyR230: enhancementProjectionPolicyR230,
            refinementRanksR352: ranks), latent: nil)
    }
}
