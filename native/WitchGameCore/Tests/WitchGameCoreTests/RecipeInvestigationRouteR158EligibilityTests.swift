import XCTest
@testable import WitchGameCore

final class RecipeInvestigationRouteR158EligibilityTests: XCTestCase {
    private struct Fixture {
        let catalog: GameCatalog
        let enemy: EnemyDefinition
        let recipeID: String
        let materialID: String
        let base: GameSnapshot
        let goal: RecipeGoalProjectionR035.Goal
    }

    private func fixture() throws -> Fixture {
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let catalog = profile.catalog
        let enemy = try XCTUnwrap(catalog.enemies.first { $0.id == "E_R01_02" })
        let material = try XCTUnwrap(enemy.dropMaterialID)
        let recipe = try XCTUnwrap(catalog.recipes.first {
            $0.id == "RC_EQ_F_01" && $0.gateID == "G_START" && ($0.costs[material] ?? 0) > 0
        }, "the current catalog must include the starter-gated recipe using the E2 drop")
        var state = try profile.makeNewSnapshot()
        state.trackedRecipeID = recipe.id
        state.completedEncounterIDs.insert(enemy.id) // Projection-only fixture; positive earned evidence is separate.
        state.materials[material] = 0
        let goal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: state))
        return Fixture(catalog: catalog, enemy: enemy, recipeID: recipe.id,
                       materialID: material, base: state, goal: goal)
    }

    func testClearedMatchingEnemyInUnlockedOtherRegionIsActionableWithoutMutation() throws {
        let f = try fixture()
        var crossRegionState = f.base
        let otherRegion = f.enemy.regionID == "R01" ? "R02" : "R01"
        crossRegionState.unlockedRegionIDs.insert(otherRegion)
        crossRegionState.activeRegionID = otherRegion
        XCTAssertNotEqual(crossRegionState.activeRegionID, f.enemy.regionID, "cross-region handoff is supported")
        let before = crossRegionState
        let routes = RecipeInvestigationRouteR158.available(goal: f.goal, catalog: f.catalog,
            state: crossRegionState, sharedWorkEnabled: true)
        XCTAssertTrue(routes.contains { $0.recipeID == f.recipeID && $0.materialID == f.materialID
            && $0.enemyID == f.enemy.id && $0.regionID == f.enemy.regionID && $0.missing > 0 })
        XCTAssertEqual(crossRegionState, before, "route discovery is read-only; no target/revision/material changes")
    }

    func testDisabledPolicyAndLockedRegionExposeNoInvestigationRoute() throws {
        let f = try fixture()
        XCTAssertTrue(RecipeInvestigationRouteR158.available(goal: f.goal, catalog: f.catalog,
            state: f.base, sharedWorkEnabled: false).isEmpty)
        let gatedGoal = RecipeGoalProjectionR035.Goal(recipeID: f.goal.recipeID, kind: f.goal.kind,
            parentTemplateID: f.goal.parentTemplateID, outputGearID: f.goal.outputGearID,
            gateID: f.goal.gateID ?? "G_R01_01", gateCleared: false,
            dustRequired: f.goal.dustRequired, dustOwned: f.goal.dustOwned,
            dustMissing: f.goal.dustMissing, requirements: f.goal.requirements,
            ready: false, parentOwned: f.goal.parentOwned, outputOwned: f.goal.outputOwned,
            dispatchCompatible: f.goal.dispatchCompatible,
            firstCraftAidApplied: f.goal.firstCraftAidApplied)
        XCTAssertTrue(RecipeInvestigationRouteR158.available(goal: gatedGoal, catalog: f.catalog,
            state: f.base, sharedWorkEnabled: true).isEmpty,
            "a stale or locked recipe gate must not expose investigation handoff")
        var locked = f.base
        locked.unlockedRegionIDs.remove(f.enemy.regionID)
        XCTAssertFalse(RecipeInvestigationRouteR158.available(goal: f.goal, catalog: f.catalog,
            state: locked, sharedWorkEnabled: true).contains { $0.enemyID == f.enemy.id })
    }

    func testUnclearedEnemyCannotBeOffered() throws {
        let f = try fixture()
        var uncleared = f.base
        uncleared.completedEncounterIDs.remove(f.enemy.id)
        XCTAssertFalse(RecipeInvestigationRouteR158.available(goal: f.goal, catalog: f.catalog,
            state: uncleared, sharedWorkEnabled: true).contains { $0.enemyID == f.enemy.id })
    }

    func testWrongMaterialAndUnknownEnemyCannotBeHandedOff() throws {
        let f = try fixture()
        let wrongID = f.catalog.enemies.first(where: { $0.id != f.enemy.id })!.id
        let forged = RecipeInvestigationHandoffR158(recipeID: f.recipeID, materialID: f.materialID,
            enemyID: wrongID, regionID: f.enemy.regionID, missing: f.goal.requirements.first { $0.materialID == f.materialID }!.missing)
        XCTAssertFalse(RecipeInvestigationRouteR158.contains(forged, goal: f.goal, catalog: f.catalog,
            state: f.base, sharedWorkEnabled: true))
        let unknown = RecipeInvestigationHandoffR158(recipeID: f.recipeID, materialID: f.materialID,
            enemyID: "E_UNKNOWN_R158", regionID: f.enemy.regionID, missing: 1)
        XCTAssertFalse(RecipeInvestigationRouteR158.contains(unknown, goal: f.goal, catalog: f.catalog,
            state: f.base, sharedWorkEnabled: true))
    }

    func testRequirementAlreadyFullHasNoActionableRoute() throws {
        let f = try fixture()
        var full = f.base
        let required = f.catalog.recipes.first { $0.id == f.recipeID }!.costs[f.materialID]!
        full.materials[f.materialID] = required
        let fullGoal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: f.catalog, state: full))
        XCTAssertEqual(fullGoal.requirements.first { $0.materialID == f.materialID }?.missing, 0)
        XCTAssertFalse(RecipeInvestigationRouteR158.available(goal: fullGoal, catalog: f.catalog,
            state: full, sharedWorkEnabled: true).contains { $0.materialID == f.materialID })
        XCTAssertFalse(RecipeInvestigationRouteR158.available(goal: f.goal, catalog: f.catalog,
            state: full, sharedWorkEnabled: true).contains { $0.materialID == f.materialID },
            "a stale shortage projection must not expose an actionable target")
    }

    func testStaleMissingCountRemainsValidWhileCurrentShortageExists() throws {
        let f = try fixture()
        let route = try XCTUnwrap(RecipeInvestigationRouteR158.available(goal: f.goal, catalog: f.catalog,
            state: f.base, sharedWorkEnabled: true).first { $0.materialID == f.materialID })
        let required = try XCTUnwrap(f.goal.requirements.first { $0.materialID == f.materialID }).required
        XCTAssertGreaterThan(required, 1, "fixture must leave room for a still-positive smaller shortage")
        var partiallySettled = f.base
        partiallySettled.materials[f.materialID] = required - 1
        let refreshedGoal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: f.catalog, state: partiallySettled))
        XCTAssertNotEqual(route.missing, 1, "fixture should prove route identity does not depend on the old missing count")
        XCTAssertTrue(RecipeInvestigationRouteR158.contains(route, goal: refreshedGoal, catalog: f.catalog,
            state: partiallySettled, sharedWorkEnabled: true),
            "a region-switch settlement may reduce, but not eliminate, the shortage before apply")
    }

}
