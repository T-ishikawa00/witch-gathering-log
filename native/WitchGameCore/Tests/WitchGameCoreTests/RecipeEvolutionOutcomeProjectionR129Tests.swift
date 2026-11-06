import XCTest
@testable import WitchGameCore

final class RecipeEvolutionOutcomeProjectionR129Tests: XCTestCase {
    func testPreviewMatchesActualSelectedInstanceEvolutionAndDoesNotMutateByItself() async throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let catalog = runtime.catalog
        let recipe = try XCTUnwrap(catalog.recipes.first { $0.id == "RC_EQ_W_G1" })
        XCTAssertEqual(recipe.kind, "evolve_in_place")
        XCTAssertEqual(recipe.parentTemplateID, "EQ_W_01")
        XCTAssertEqual(recipe.outputGearID, "EQ_W_G1")

        var initial = try runtime.makeNewSnapshot()
        let parentIndex = try XCTUnwrap(initial.gear.firstIndex { $0.definitionID == "EQ_W_01" })
        let parentBefore = initial.gear[parentIndex]
        let parentID = parentBefore.id
        for (material, amount) in recipe.costs { initial.materials[material] = amount }
        initial.materials["refine_dust"] = max(initial.materials["refine_dust", default: 0], recipe.dustCost)
        if let gate = recipe.gateID, gate != "G_START" {
            let p = gate.split(separator: "_")
            XCTAssertEqual(p.count, 3)
            initial.completedEncounterIDs.insert("B_\(p[1])_\(p[2])")
        }

        let beforeProjection = initial
        let outcome = try RecipeEvolutionOutcomeProjectionR129.project(
            catalog: catalog, state: initial, recipeID: recipe.id, selectedParentGearID: parentID)
        XCTAssertEqual(initial, beforeProjection, "A preview must not mutate the supplied save snapshot")
        XCTAssertEqual(outcome.retainedParent, parentBefore)
        XCTAssertEqual(outcome.retainedParent.id, parentID)
        XCTAssertEqual(outcome.parentDefinition.id, "EQ_W_01")
        XCTAssertEqual(outcome.outputDefinition.id, "EQ_W_G1")
        XCTAssertEqual(outcome.catalogAttackBonusBefore, catalog.gearAttackBonuses["EQ_W_01"] ?? 0)
        XCTAssertEqual(outcome.catalogAttackBonusAfter, catalog.gearAttackBonuses["EQ_W_G1"] ?? 0)
        XCTAssertEqual(outcome.addedInherentEffectIDs, ["BARRIER_WARD", "WARD_REPLACES_SEED"])
        XCTAssertTrue(outcome.removedInherentEffectIDs.isEmpty)
        XCTAssertFalse(outcome.latentOutcomeKnown)
        XCTAssertFalse(outcome.totalActorCombatStatsProjected)

        // This test intentionally leaves its save input/output in the caller-provided
        // unique evidence directory. It never deletes or overwrites prior QA artifacts.
        guard let outputPath = ProcessInfo.processInfo.environment["R129_TEST_OUTPUT_DIR"],
              outputPath.hasPrefix("/"), !outputPath.isEmpty else {
            throw XCTSkip("Set R129_TEST_OUTPUT_DIR to a new absolute evidence directory")
        }
        let saveDir = URL(fileURLWithPath: outputPath, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveDir.path), "Output path must be new and exclusive")
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(initial).write(to: saveDir.appendingPathComponent("initial_snapshot.json"), options: .atomic)
        let saveURL = saveDir.appendingPathComponent("save.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))
        let repository = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try runtime.makeEngine(saves: repository)
        _ = try await engine.dispatch(.evolveGear(gearID: parentID, recipeID: recipe.id),
                                      operationID: UUID(), expectedRevision: initial.revision)
        let evolved = await engine.snapshot()
        let actual = try XCTUnwrap(evolved.gear.first { $0.id == parentID })
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveURL.path), "Evolved save output must remain available for audit")
        var expectedRetainedInstance = parentBefore
        expectedRetainedInstance.definitionID = "EQ_W_G1"
        XCTAssertEqual(actual, expectedRetainedInstance, "Only the template ID should change; instance and investment remain")
        XCTAssertEqual(actual.definitionID, outcome.outputDefinition.id)
        XCTAssertEqual(actual.id, outcome.retainedParent.id)
        let reopened = try SaveRepository(initial: GameSnapshot(), fileURL: saveURL)
        let reopenedState = await reopened.snapshot()
        XCTAssertEqual(try XCTUnwrap(reopenedState.gear.first { $0.id == parentID }), expectedRetainedInstance,
                       "The isolated file-backed save must reopen with the evolved template and retained instance data")
    }

    func testRejectsWrongParentMissingRecipeMissingOutputAndNonEvolution() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let catalog = runtime.catalog
        let recipe = try XCTUnwrap(catalog.recipes.first { $0.id == "RC_EQ_W_G1" })
        var state = try runtime.makeNewSnapshot()
        let parent = try XCTUnwrap(state.gear.first { $0.definitionID == "EQ_W_01" })

        XCTAssertThrowsError(try RecipeEvolutionOutcomeProjectionR129.project(
            catalog: catalog, state: state, recipeID: "NO_SUCH_RECIPE", selectedParentGearID: parent.id)) {
            XCTAssertEqual($0 as? RecipeEvolutionOutcomeProjectionR129.ProjectionError, .recipeNotFound)
        }
        XCTAssertThrowsError(try RecipeEvolutionOutcomeProjectionR129.project(
            catalog: catalog, state: state, recipeID: "RC_EQ_W_01", selectedParentGearID: parent.id)) {
            XCTAssertEqual($0 as? RecipeEvolutionOutcomeProjectionR129.ProjectionError, .recipeIsNotEvolution)
        }
        state.gear[0].definitionID = "EQ_W_P1"
        XCTAssertThrowsError(try RecipeEvolutionOutcomeProjectionR129.project(
            catalog: catalog, state: state, recipeID: recipe.id, selectedParentGearID: parent.id)) {
            XCTAssertEqual($0 as? RecipeEvolutionOutcomeProjectionR129.ProjectionError, .selectedParentHasWrongTemplate)
        }
        state.gear[0] = parent
        let noOutput = RecipeDefinition(id: recipe.id, outputGearID: nil, costs: recipe.costs,
                                    status: recipe.status, kind: recipe.kind, dustCost: recipe.dustCost,
                                    parentTemplateID: recipe.parentTemplateID, gateID: recipe.gateID,
                                    qualityFrom: recipe.qualityFrom, qualityTo: recipe.qualityTo)
        let noOutputCatalog = replacing(recipe: noOutput, in: catalog)
        XCTAssertThrowsError(try RecipeEvolutionOutcomeProjectionR129.project(
            catalog: noOutputCatalog, state: state, recipeID: recipe.id, selectedParentGearID: parent.id)) {
            XCTAssertEqual($0 as? RecipeEvolutionOutcomeProjectionR129.ProjectionError, .outputTemplateMissing)
        }
        XCTAssertThrowsError(try RecipeEvolutionOutcomeProjectionR129.project(
            catalog: catalog, state: state, recipeID: recipe.id, selectedParentGearID: UUID())) {
            XCTAssertEqual($0 as? RecipeEvolutionOutcomeProjectionR129.ProjectionError, .selectedParentMissing)
        }
    }

    private func replacing(recipe: RecipeDefinition, in catalog: GameCatalog) -> GameCatalog {
        var recipes = catalog.recipes
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[index] = recipe }
        return GameCatalog(version: catalog.version, regions: catalog.regions, enemies: catalog.enemies,
                           gear: catalog.gear, research: catalog.research, materialIDs: catalog.materialIDs,
                           materialAvailabilityGates: catalog.materialAvailabilityGates, recipes: recipes,
                           actorIDs: catalog.actorIDs, challenges: catalog.challenges,
                           researchEffects: catalog.researchEffects, appearances: catalog.appearances,
                           furnitureIDs: catalog.furnitureIDs, dailyFreeTicketGrant: catalog.dailyFreeTicketGrant,
                           authority: catalog.authority, gearAttackBonuses: catalog.gearAttackBonuses,
                           gearHPBonuses: catalog.gearHPBonuses, gearDefenseBonuses: catalog.gearDefenseBonuses,
                           gachaOddsBasisPoints: catalog.gachaOddsBasisPoints)
    }
}
