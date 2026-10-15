import Foundation

/// Read-only, catalog-backed handoff target for a recipe material that can be
/// accumulated by re-investigating an already-cleared enemy under R144.
public struct RecipeInvestigationHandoffR158: Equatable, Sendable {
    public let recipeID: String
    public let materialID: String
    public let enemyID: String
    public let regionID: String
    public let missing: Int

    public init(recipeID: String, materialID: String, enemyID: String,
                regionID: String, missing: Int) {
        self.recipeID = recipeID
        self.materialID = materialID
        self.enemyID = enemyID
        self.regionID = regionID
        self.missing = missing
    }
}

public enum RecipeInvestigationRouteR158 {
    /// This is presentation eligibility only. The caller must re-run it before
    /// applying because region, ownership, and recipe deficit can change.
    public static func available(goal: RecipeGoalProjectionR035.Goal,
                                 catalog: GameCatalog,
                                 state: GameSnapshot,
                                 sharedWorkEnabled: Bool) -> [RecipeInvestigationHandoffR158] {
        guard sharedWorkEnabled, goal.gateCleared else { return [] }
        return goal.requirements.flatMap { requirement -> [RecipeInvestigationHandoffR158] in
            let currentMissing = max(0, requirement.required - state.materials[requirement.materialID, default: 0])
            guard currentMissing > 0,
                  catalog.materialIDs.contains(requirement.materialID) else { return [] }
            return catalog.enemies.compactMap { enemy in
                guard enemy.dropMaterialID == requirement.materialID,
                      catalog.materialIDs.contains(requirement.materialID),
                      let region = catalog.regions.first(where: { $0.id == enemy.regionID }),
                      region.enemyIDs.contains(enemy.id),
                      state.unlockedRegionIDs.contains(enemy.regionID),
                      state.completedEncounterIDs.contains(enemy.id),
                      enemy.prerequisiteEncounterID.map(state.completedEncounterIDs.contains) ?? true
                else { return nil }
                return RecipeInvestigationHandoffR158(recipeID: goal.recipeID,
                    materialID: requirement.materialID, enemyID: enemy.id,
                    regionID: enemy.regionID, missing: currentMissing)
            }
        }
    }

    public static func contains(_ route: RecipeInvestigationHandoffR158,
                                goal: RecipeGoalProjectionR035.Goal,
                                catalog: GameCatalog,
                                state: GameSnapshot,
                                sharedWorkEnabled: Bool) -> Bool {
        guard goal.recipeID == route.recipeID else { return false }
        return available(goal: goal, catalog: catalog, state: state,
                  sharedWorkEnabled: sharedWorkEnabled).contains {
            $0.recipeID == route.recipeID
                && $0.materialID == route.materialID
                && $0.enemyID == route.enemyID
                && $0.regionID == route.regionID
        }
    }
}
