import Foundation

/// Read-only preview of the catalog-defined part of one selected in-place evolution.
/// It deliberately does not create a target GearInstance or predict latent rolls,
/// quality, affix totals, or the actor's final combat stats.
public enum RecipeEvolutionOutcomeProjectionR129 {
    public enum ProjectionError: Error, Equatable {
        case recipeNotFound
        case recipeIsNotEvolution
        case parentTemplateMissing
        case outputTemplateMissing
        case selectedParentMissing
        case selectedParentIDAmbiguous
        case selectedParentHasWrongTemplate
        case inputDefinitionMissing
        case outputDefinitionMissing
        case slotMismatch
        case ownerIneligibleForOutput
    }

    public struct Outcome: Equatable, Sendable {
        public let recipeID: String
        /// The exact existing item selected by the player. Evolution keeps this instance.
        public let retainedParent: GearInstance
        public let parentDefinition: GearDefinition
        /// Catalog template only; this is not a fabricated or predicted gear instance.
        public let outputDefinition: GearDefinition
        public let catalogAttackBonusBefore: Int
        public let catalogAttackBonusAfter: Int
        public let addedInherentEffectIDs: [String]
        public let removedInherentEffectIDs: [String]
        public let latentOutcomeKnown = false
        public let totalActorCombatStatsProjected = false
    }

    public static func project(catalog: GameCatalog,
                               state: GameSnapshot,
                               recipeID: String,
                               selectedParentGearID: UUID) throws -> Outcome {
        guard let recipe = catalog.recipes.first(where: { $0.id == recipeID }) else {
            throw ProjectionError.recipeNotFound
        }
        guard recipe.kind == "evolve_in_place" else { throw ProjectionError.recipeIsNotEvolution }
        guard let parentID = recipe.parentTemplateID else { throw ProjectionError.parentTemplateMissing }
        guard let outputID = recipe.outputGearID else { throw ProjectionError.outputTemplateMissing }

        let matches = state.gear.filter { $0.id == selectedParentGearID }
        guard !matches.isEmpty else { throw ProjectionError.selectedParentMissing }
        guard matches.count == 1, let parent = matches.first else { throw ProjectionError.selectedParentIDAmbiguous }
        guard parent.definitionID == parentID else { throw ProjectionError.selectedParentHasWrongTemplate }
        guard let parentDefinition = catalog.gear.first(where: { $0.id == parentID }) else {
            throw ProjectionError.inputDefinitionMissing
        }
        guard let outputDefinition = catalog.gear.first(where: { $0.id == outputID }) else {
            throw ProjectionError.outputDefinitionMissing
        }
        guard parentDefinition.slot == outputDefinition.slot else { throw ProjectionError.slotMismatch }
        if let ownerID = parent.ownerID,
           !outputDefinition.actorIDs.isEmpty,
           !outputDefinition.actorIDs.contains(ownerID) {
            throw ProjectionError.ownerIneligibleForOutput
        }

        let beforeCounts = Dictionary(parentDefinition.effects.map { ($0, 1) }, uniquingKeysWith: +)
        let afterCounts = Dictionary(outputDefinition.effects.map { ($0, 1) }, uniquingKeysWith: +)
        let added = afterCounts.keys.sorted().flatMap { id in
            Array(repeating: id, count: max(0, afterCounts[id, default: 0] - beforeCounts[id, default: 0]))
        }
        let removed = beforeCounts.keys.sorted().flatMap { id in
            Array(repeating: id, count: max(0, beforeCounts[id, default: 0] - afterCounts[id, default: 0]))
        }
        return Outcome(recipeID: recipeID, retainedParent: parent,
                       parentDefinition: parentDefinition, outputDefinition: outputDefinition,
                       catalogAttackBonusBefore: catalog.gearAttackBonuses[parentID, default: 0],
                       catalogAttackBonusAfter: catalog.gearAttackBonuses[outputID, default: 0],
                       addedInherentEffectIDs: added, removedInherentEffectIDs: removed)
    }
}
