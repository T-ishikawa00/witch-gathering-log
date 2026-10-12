import Foundation

public extension RecipeGoalProjectionR035 {
    static func goals(catalog: GameCatalog, state: GameSnapshot) -> [Goal] {
        goals(catalog: catalog, materialCounts: state.materials,
              ownedGearTemplateIDs: Set(state.gear.map(\.definitionID)),
              unlockedRegionIDs: state.unlockedRegionIDs,
              completedEncounterIDs: state.completedEncounterIDs)
    }

    /// Resolves the saved goal directly even if its parent gear was later evolved
    /// or dismantled. Ownership is surfaced as status; it never clears the goal.
    static func trackedGoal(catalog: GameCatalog, state: GameSnapshot) -> Goal? {
        guard let trackedID = state.trackedRecipeID,
              let recipe = catalog.recipes.first(where: { $0.id == trackedID }),
              recipe.kind == "craft_new" || recipe.kind == "evolve_in_place" else { return nil }
        let owned = Set(state.gear.map(\.definitionID))
        let projectionParents = owned.union(recipe.parentTemplateID.map { [$0] } ?? [])
        guard let projected = goals(catalog: catalog, materialCounts: state.materials,
                                    ownedGearTemplateIDs: projectionParents,
                                    unlockedRegionIDs: state.unlockedRegionIDs,
                                    completedEncounterIDs: state.completedEncounterIDs)
            .first(where: { $0.recipeID == trackedID }) else { return nil }
        let parentOwned = recipe.parentTemplateID.map(owned.contains)
        // The projection is seeded with a synthetic parent so it can still report
        // costs and source availability after evolution/dismantling. Readiness,
        // however, must reflect the real inventory: an absent evolve parent cannot
        // be crafted/evolved even when its gate and costs are satisfied.
        let parentRequirementSatisfied = parentOwned ?? true
        return Goal(recipeID: projected.recipeID, kind: projected.kind,
                    parentTemplateID: projected.parentTemplateID, outputGearID: projected.outputGearID,
                    gateID: projected.gateID, gateCleared: projected.gateCleared,
                    dustRequired: projected.dustRequired, dustOwned: projected.dustOwned,
                    dustMissing: projected.dustMissing, requirements: projected.requirements,
                    ready: projected.ready && parentRequirementSatisfied,
                    parentOwned: parentOwned,
                    outputOwned: owned.contains(projected.outputGearID))
    }
}
