import Foundation

/// Read-only projection for existing catalog recipes. This is an isolated candidate,
/// not a saved goal, new recipe, unlock, or balance rule.
public enum RecipeGoalProjectionR035 {
    public struct Requirement: Equatable, Sendable {
        public let materialID: String
        public let required: Int
        public let owned: Int
        public let missing: Int
        public let availableGatherRegions: [String]
        public let lockedGatherRegions: [String]
        public let availableEnemyDropRegions: [String]
        public let lockedEnemyDropRegions: [String]
    }

    public struct Goal: Equatable, Sendable {
        public let recipeID: String
        public let kind: String
        public let parentTemplateID: String?
        public let outputGearID: String
        public let gateID: String?
        public let gateCleared: Bool
        public let dustRequired: Int
        public let dustOwned: Int
        public let dustMissing: Int
        public let requirements: [Requirement]
        public let ready: Bool
        public let parentOwned: Bool?
        public let outputOwned: Bool
        public let dispatchCompatible: Bool
        public let firstCraftAidApplied: Bool
    }

    /// Lists new-craft recipes and only the next evolution steps for parent gear the
    /// player actually owns. Region availability is calculated with the same catalog
    /// gate projection used by gather selection.
    public static func goals(catalog: GameCatalog,
                             materialCounts: [String: Int],
                             ownedGearTemplateIDs: Set<String>,
                             unlockedRegionIDs: Set<String>,
                             completedEncounterIDs: Set<String>,
                             firstCraftAidEligibleR179: Bool = false, craftedGearOnce: Bool = false,
                             firstCraftAidCapabilityR179: FirstCraftAidCapabilityR179 = .disabled) -> [Goal] {
        catalog.recipes.compactMap { recipe in
            guard recipe.kind == "craft_new" || recipe.kind == "evolve_in_place",
                  let output = recipe.outputGearID else { return nil }
            if recipe.kind == "evolve_in_place",
               recipe.parentTemplateID.map({ !ownedGearTemplateIDs.contains($0) }) ?? true {
                return nil
            }
            let gateCleared = recipe.gateID.map {
                $0 == "G_START" || completedEncounterIDs.contains(encounterID(for: $0))
            } ?? true
            let costResolution = FirstCraftCostProjectionR179.resolve(
                recipeID: recipe.id, declaredCosts: recipe.costs,
                firstCraftAidEligible: firstCraftAidEligibleR179, craftedGearOnce: craftedGearOnce,
                capability: firstCraftAidCapabilityR179)
            let requirements = costResolution.costs.sorted { $0.key < $1.key }.map { materialID, required in
                let owned = max(0, materialCounts[materialID, default: 0])
                let available = catalog.regions.compactMap { region -> String? in
                    guard unlockedRegionIDs.contains(region.id),
                          catalog.availableGatherMaterialIDs(in: region.id,
                                                             unlockedRegionIDs: unlockedRegionIDs,
                                                             completedEncounterIDs: completedEncounterIDs).contains(materialID)
                    else { return nil }
                    return region.id
                }
                let locked = catalog.regions.compactMap { region -> String? in
                    guard region.gatherMaterialIDs.contains(materialID), !available.contains(region.id) else { return nil }
                    return region.id
                }
                let dropEnemies = catalog.enemies.filter { $0.dropMaterialID == materialID }
                let availableDrops = Set(dropEnemies.compactMap { enemy -> String? in
                    guard unlockedRegionIDs.contains(enemy.regionID),
                          enemy.prerequisiteEncounterID.map(completedEncounterIDs.contains) ?? true else { return nil }
                    return enemy.regionID
                }).sorted()
                let lockedDrops = Set(dropEnemies.compactMap { enemy -> String? in
                    guard !availableDrops.contains(enemy.regionID) else { return nil }
                    return enemy.regionID
                }).sorted()
                return Requirement(materialID: materialID, required: required, owned: owned,
                                   missing: max(0, required - owned),
                                   availableGatherRegions: available, lockedGatherRegions: locked,
                                   availableEnemyDropRegions: availableDrops, lockedEnemyDropRegions: lockedDrops)
            }
            let dustOwned = max(0, materialCounts["refine_dust", default: 0])
            let dustMissing = max(0, recipe.dustCost - dustOwned)
            return Goal(recipeID: recipe.id, kind: recipe.kind,
                        parentTemplateID: recipe.parentTemplateID, outputGearID: output,
                        gateID: recipe.gateID, gateCleared: gateCleared,
                        dustRequired: recipe.dustCost, dustOwned: dustOwned, dustMissing: dustMissing,
                        requirements: requirements,
                        ready: costResolution.dispatchCompatible && gateCleared && dustMissing == 0 && requirements.allSatisfy { $0.missing == 0 },
                        parentOwned: recipe.parentTemplateID.map(ownedGearTemplateIDs.contains),
                        outputOwned: ownedGearTemplateIDs.contains(output),
                        dispatchCompatible: costResolution.dispatchCompatible,
                        firstCraftAidApplied: costResolution.aidApplied)
        }
    }

    private static func encounterID(for gateID: String) -> String {
        let parts = gateID.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { return "__invalid_gate__" }
        return "B_\(parts[1])_\(parts[2])"
    }
}
