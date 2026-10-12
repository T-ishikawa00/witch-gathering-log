import Foundation
import XCTest
@testable import WitchGameCore

/// Isolated save/command contract for a player-selected goal. No production save is used.
final class RecipeGoalTrackingR002Tests: XCTestCase {
    private func saveURL(_ label: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recipe-goal-r002-\(label)", isDirectory: true)
            .appendingPathComponent("save.json")
    }

    func testLegacySnapshotWithoutTrackedRecipeDecodesAsNoGoal() throws {
        let encoded = try JSONEncoder().encode(GameSnapshot.newGame(catalog: GameCatalog.bundledTestOverlay()))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "trackedRecipeID")
        let legacy = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(GameSnapshot.self, from: legacy)
        XCTAssertNil(decoded.trackedRecipeID, "legacy absence must not invent a default goal")
    }

    func testSetLockedRecipeGoalPersistsWithoutChangingProgressAndClearIsExplicit() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let url = saveURL("set-clear")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = GameSnapshot.newGame(catalog: catalog)
        let repo = try SaveRepository(initial: initial, fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: repo)
        let before = await engine.snapshot()
        let selection = GameCommand.setTrackedRecipe("RC_EQ_W_P2")
        let setReceipt = try await engine.dispatch(selection,
            operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000001")!, expectedRevision: before.revision)
        let selected = await engine.snapshot()
        XCTAssertEqual(selected.revision, before.revision + 1)
        XCTAssertEqual(selected.trackedRecipeID, "RC_EQ_W_P2")
        XCTAssertEqual(selected.materials, before.materials)
        XCTAssertEqual(selected.currency, before.currency)
        XCTAssertEqual(selected.gear, before.gear)

        let tracked = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: selected))
        XCTAssertFalse(tracked.gateCleared, "locked goals remain trackable and report the lock")
        XCTAssertEqual(tracked.parentOwned, false, "tracking is independent of parent ownership")
        XCTAssertFalse(tracked.ready)

        let reopened = try SaveRepository(fileURL: url)
        let reopenedBeforeClear = await reopened.snapshot()
        XCTAssertEqual(reopenedBeforeClear.trackedRecipeID, "RC_EQ_W_P2")
        let clearReceipt = try await GameEngine(catalog: catalog, saves: reopened).dispatch(
            .setTrackedRecipe(nil), operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000002")!,
            expectedRevision: setReceipt.revision)
        XCTAssertEqual(clearReceipt.revision, setReceipt.revision + 1)
        let cleared = await reopened.snapshot()
        XCTAssertNil(cleared.trackedRecipeID)
        XCTAssertEqual(cleared.materials, before.materials)
        XCTAssertEqual(cleared.currency, before.currency)
        XCTAssertEqual(cleared.gear, before.gear)
        let reopenedAfterClear = try SaveRepository(fileURL: url)
        let reopenedCleared = await reopenedAfterClear.snapshot()
        XCTAssertNil(reopenedCleared.trackedRecipeID)
    }

    func testUnknownAndUnsupportedRecipeRejectWithoutSaveOrRevisionChange() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let url = saveURL("reject")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = try SaveRepository(initial: GameSnapshot.newGame(catalog: catalog), fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: repo)
        let first = try await engine.dispatch(.setTrackedRecipe("RC_EQ_W_P2"),
            operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000011")!, expectedRevision: 0)
        let stableState = await engine.snapshot()
        let stableBytes = try Data(contentsOf: url)
        let unsupported = try XCTUnwrap(catalog.recipes.first { $0.kind != "craft_new" && $0.kind != "evolve_in_place" }?.id)
        for invalidID in ["NO_SUCH_RECIPE", unsupported] {
            do {
                _ = try await engine.dispatch(.setTrackedRecipe(invalidID), operationID: UUID(), expectedRevision: first.revision)
                XCTFail("unsupported tracked recipe accepted: \(invalidID)")
            } catch let error as CoreError {
                guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
            }
            let afterReject = await engine.snapshot()
            XCTAssertEqual(afterReject, stableState)
            XCTAssertEqual(try Data(contentsOf: url), stableBytes)
        }
    }

    func testDuplicateOperationAndStaleRevisionKeepNormalDispatchSemantics() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let url = saveURL("revision")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = try SaveRepository(initial: GameSnapshot.newGame(catalog: catalog), fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: repo)
        let op = UUID(uuidString: "35000000-0000-4000-8000-000000000021")!
        let command = GameCommand.setTrackedRecipe("RC_EQ_W_P2")
        let receipt = try await engine.dispatch(command, operationID: op, expectedRevision: 0)
        let bytes = try Data(contentsOf: url)
        let duplicate = try await engine.dispatch(command, operationID: op, expectedRevision: 0)
        XCTAssertEqual(duplicate, receipt)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        do {
            _ = try await engine.dispatch(.setTrackedRecipe(nil), operationID: UUID(), expectedRevision: 0)
            XCTFail("stale revision accepted")
        } catch let error as CoreError {
            guard case .revisionConflict(expected: 0, actual: 1) = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterConflict = await engine.snapshot()
        XCTAssertEqual(afterConflict.trackedRecipeID, "RC_EQ_W_P2")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testTrackedGoalRemainsResolvableAfterParentIsGoneAndReportsLockedSources() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let parentGone = GameSnapshot(gear: [GearInstance(definitionID: "EQ_W_G1")],
                                      unlockedRegionIDs: ["R01"], trackedRecipeID: "RC_EQ_W_G1")
        let status = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: parentGone))
        XCTAssertEqual(status.parentOwned, false)
        XCTAssertEqual(status.outputOwned, true)
        XCTAssertEqual(parentGone.trackedRecipeID, "RC_EQ_W_G1", "projection must not auto-clear")

        var regional = parentGone
        regional.gear = [GearInstance(definitionID: "EQ_FEET_02")]
        regional.trackedRecipeID = "RC_EQ_FEET_03"
        let feet = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: regional))
        XCTAssertEqual(feet.parentOwned, true)
        XCTAssertFalse(feet.gateCleared)
        XCTAssertTrue(feet.requirements.contains { $0.materialID == "M_R04_G3" && $0.missing > 0 && $0.lockedGatherRegions.contains("R04") })
    }

    func testGoalDoesNotAutoClearWhenActualEvolutionChangesParentInstance() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.completedEncounterIDs.insert("B_R01_B")
        initial.materials = ["M_R01_BA": 1, "M_R01_BB": 1, "M_R01_G3": 16]
        let gearID = try XCTUnwrap(initial.gear.first { $0.definitionID == "EQ_W_01" }?.id)
        let repo = try SaveRepository(initial: initial)
        let engine = try GameEngine(catalog: catalog, saves: repo)
        _ = try await engine.dispatch(.setTrackedRecipe("RC_EQ_W_G1"),
            operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000031")!, expectedRevision: initial.revision)
        let selected = await engine.snapshot()
        _ = try await engine.dispatch(.evolveGear(gearID: gearID, recipeID: "RC_EQ_W_G1"),
            operationID: UUID(uuidString: "35000000-0000-4000-8000-000000000032")!, expectedRevision: selected.revision)
        let evolved = await engine.snapshot()
        XCTAssertEqual(evolved.trackedRecipeID, "RC_EQ_W_G1")
        XCTAssertEqual(evolved.materials["M_R01_G3"], 0)
        let status = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: evolved))
        XCTAssertEqual(status.parentOwned, false)
        XCTAssertEqual(status.outputOwned, true)
        XCTAssertFalse(status.ready, "an evolved-away parent cannot be reported as ready")
    }

    func testTrackedEvolutionRequiresRealParentEvenWithClearGateAndAllCosts() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let recipe = try XCTUnwrap(catalog.recipes.first { $0.id == "RC_EQ_W_G1" })
        XCTAssertEqual(recipe.kind, "evolve_in_place")
        let requiredEncounter: String? = recipe.gateID.map { gateID in
            let parts = gateID.split(separator: "_")
            return parts.count == 3 ? "B_\(parts[1])_\(parts[2])" : nil
        } ?? nil
        let completed = Set(requiredEncounter.map { [$0] } ?? [])
        var materials = recipe.costs
        materials["refine_dust"] = recipe.dustCost
        let withoutParent = GameSnapshot(materials: materials,
                                         unlockedRegionIDs: Set(catalog.regions.map(\.id)),
                                         completedEncounterIDs: completed,
                                         trackedRecipeID: recipe.id)
        let missingParentGoal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: withoutParent))
        XCTAssertTrue(missingParentGoal.gateCleared)
        XCTAssertTrue(missingParentGoal.requirements.allSatisfy { $0.missing == 0 })
        XCTAssertEqual(missingParentGoal.dustMissing, 0)
        XCTAssertEqual(missingParentGoal.parentOwned, false)
        XCTAssertFalse(missingParentGoal.ready, "synthetic projection parent must not imply real ownership")

        var withParent = withoutParent
        withParent.gear = [GearInstance(definitionID: try XCTUnwrap(recipe.parentTemplateID))]
        let readyGoal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: withParent))
        XCTAssertEqual(readyGoal.parentOwned, true)
        XCTAssertTrue(readyGoal.ready, "same gate and costs are ready when the actual parent exists")
    }
}
