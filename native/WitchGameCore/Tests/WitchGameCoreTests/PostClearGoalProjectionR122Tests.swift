import XCTest
@testable import WitchGameCore

final class PostClearGoalProjectionR122Tests: XCTestCase {
    private func catalog() throws -> GameCatalog { try GameCatalog.bundledTestOverlay() }

    func testFreshStateShowsRealCampaignAndLockedChallengesWithoutMutation() throws {
        let catalog = try catalog()
        let state = GameSnapshot.newGame(catalog: catalog)
        let before = state
        let result = PostClearGoalProjectionR122.project(catalog: catalog, state: state)

        XCTAssertEqual(result.campaignCleared, 0)
        XCTAssertEqual(result.campaignTotal, catalog.enemies.count)
        XCTAssertFalse(result.campaignComplete)
        XCTAssertEqual(result.challenges.count, catalog.challenges.count)
        XCTAssertTrue(result.challenges.allSatisfy { $0.availability == .locked })
        XCTAssertNil(result.trackedRecipe)
        XCTAssertEqual(state, before, "projection is read-only")
    }

    func testChallengeProgressKeepsAvailableAndClearedEntriesVisible() throws {
        let catalog = try catalog()
        let first = try XCTUnwrap(catalog.challenges.first)
        let firstGateBoss = try XCTUnwrap(bossID(for: first.unlockGate))
        var state = GameSnapshot.newGame(catalog: catalog)
        state.completedEncounterIDs.insert(firstGateBoss)

        let beforeClear = PostClearGoalProjectionR122.project(catalog: catalog, state: state)
        XCTAssertEqual(beforeClear.challenges.first(where: { $0.id == first.id })?.availability, .available)

        state.completedEncounterIDs.insert("CHALLENGE_CLEAR|\(first.id)")
        let afterClear = PostClearGoalProjectionR122.project(catalog: catalog, state: state)
        XCTAssertEqual(afterClear.challenges.first(where: { $0.id == first.id })?.availability, .cleared)
        XCTAssertEqual(afterClear.challengesCleared, 1)
        XCTAssertTrue(afterClear.challenges.contains { $0.id == first.id && $0.availability == .cleared }, "the list exposes the cleared challenge for replay")
    }

    func testAllCampaignAndChallengesRemainVisibleAfterClear() throws {
        let catalog = try catalog()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.completedEncounterIDs.formUnion(catalog.enemies.map(\.id))
        state.completedEncounterIDs.formUnion(catalog.challenges.map { "CHALLENGE_CLEAR|\($0.id)" })

        let result = PostClearGoalProjectionR122.project(catalog: catalog, state: state)
        XCTAssertEqual(result.campaignCleared, catalog.enemies.count)
        XCTAssertTrue(result.campaignComplete)
        XCTAssertEqual(result.challengesCleared, catalog.challenges.count)
        XCTAssertTrue(result.challenges.allSatisfy { $0.availability == .cleared })
    }

    func testTrackedRecipeShortageShowsUnlockedAndLockedGatherSources() throws {
        let catalog = try catalog()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.trackedRecipeID = "RC_EQ_FEET_03"
        state.gear = [GearInstance(definitionID: "EQ_FEET_02")]
        state.unlockedRegionIDs = ["R01"]

        let result = PostClearGoalProjectionR122.project(catalog: catalog, state: state)
        let goal = try XCTUnwrap(result.trackedRecipe)
        XCTAssertFalse(goal.ready)
        XCTAssertFalse(goal.gateCleared)
        let target = try XCTUnwrap(goal.requirements.first { $0.materialID == "M_R04_G3" })
        XCTAssertGreaterThan(target.missing, 0)
        XCTAssertTrue(target.lockedGatherRegions.contains("R04"))
        XCTAssertFalse(target.availableGatherRegions.contains("R04"))
    }

    func testTrackedRecipeShortageShowsAnActuallyAvailableGatherSource() throws {
        let catalog = try catalog()
        let region = try XCTUnwrap(catalog.regions.first)
        let gatherable = Set(catalog.availableGatherMaterialIDs(in: region.id,
            unlockedRegionIDs: [region.id], completedEncounterIDs: []))
        let recipe = try XCTUnwrap(catalog.recipes.first { candidate in
            candidate.kind == "craft_new" && candidate.costs.keys.contains(where: gatherable.contains)
        }, "bundled content should connect a craft recipe to a currently gatherable material")
        var state = GameSnapshot.newGame(catalog: catalog)
        state.trackedRecipeID = recipe.id
        state.unlockedRegionIDs = [region.id]

        let summary = PostClearGoalProjectionR122.project(catalog: catalog, state: state)
        let goal = try XCTUnwrap(summary.trackedRecipe)
        let requirement = try XCTUnwrap(goal.requirements.first { gatherable.contains($0.materialID) })
        XCTAssertGreaterThan(requirement.missing, 0)
        XCTAssertTrue(requirement.availableGatherRegions.contains(region.id))
        XCTAssertFalse(requirement.lockedGatherRegions.contains(region.id))
    }

    func testTrackedRecipeReadyUsesExistingCatalogCostsAndGate() throws {
        let catalog = try catalog()
        let recipe = try XCTUnwrap(catalog.recipes.first {
            $0.kind == "craft_new" && ($0.gateID == nil || $0.gateID == "G_START")
        })
        var state = GameSnapshot.newGame(catalog: catalog)
        state.trackedRecipeID = recipe.id
        state.materials = recipe.costs
        state.materials["refine_dust"] = max(state.materials["refine_dust", default: 0], recipe.dustCost)
        state.unlockedRegionIDs = Set(catalog.regions.map(\.id))
        if let gate = recipe.gateID, let boss = bossID(for: gate) { state.completedEncounterIDs.insert(boss) }

        let goal = try XCTUnwrap(PostClearGoalProjectionR122.project(catalog: catalog, state: state).trackedRecipe)
        XCTAssertTrue(goal.gateCleared)
        XCTAssertTrue(goal.ready)
        XCTAssertTrue(goal.requirements.allSatisfy { $0.missing == 0 })
    }

    func testUnknownAndUntrackedRecipeDoNotInventGoal() throws {
        let catalog = try catalog()
        var state = GameSnapshot.newGame(catalog: catalog)
        state.trackedRecipeID = "UNKNOWN_RECIPE"
        XCTAssertNil(PostClearGoalProjectionR122.project(catalog: catalog, state: state).trackedRecipe)
        state.trackedRecipeID = nil
        XCTAssertNil(PostClearGoalProjectionR122.project(catalog: catalog, state: state).trackedRecipe)
    }

    private func bossID(for gateID: String) -> String? {
        let pieces = gateID.split(separator: "_")
        guard pieces.count == 3, pieces[0] == "G" else { return nil }
        return "B_\(pieces[1])_\(pieces[2])"
    }
}
