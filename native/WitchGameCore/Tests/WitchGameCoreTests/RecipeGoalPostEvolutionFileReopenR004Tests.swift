import Foundation
import XCTest
@testable import WitchGameCore

/// R004 follow-up: actual evolution, goal persistence, and file-backed reopen.
/// Uses an isolated temporary save and the unchanged R003 implementation sources.
final class RecipeGoalPostEvolutionFileReopenR004Tests: XCTestCase {
    func testEvolvedTrackedGoalAndLatentPayloadSurviveFileBackedReopen() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
        let recipe = try XCTUnwrap(catalog.recipes.first { $0.id == "RC_EQ_W_G1" })
        XCTAssertEqual(recipe.kind, "evolve_in_place")
        let parentTemplate = try XCTUnwrap(recipe.parentTemplateID)
        let outputTemplate = try XCTUnwrap(recipe.outputGearID)

        var initial = GameSnapshot.newGame(catalog: catalog)
        if let gateID = recipe.gateID, gateID != "G_START" {
            let components = gateID.split(separator: "_")
            if components.count == 3 {
                initial.completedEncounterIDs.insert("B_\(components[1])_\(components[2])")
            }
        }
        initial.materials = recipe.costs
        initial.materials["refine_dust"] = recipe.dustCost
        let parentIndex = try XCTUnwrap(initial.gear.firstIndex { $0.definitionID == parentTemplate })
        let stableGearID = initial.gear[parentIndex].id
        let slots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 321),
            CandidateLatentSlotR003(affixID: "AF_POWER", rawQ: 654),
            CandidateLatentSlotR003(affixID: "AF_WARD", rawQ: 987)
        ])
        try policy.validateEvolution(from: parentTemplate, to: outputTemplate,
            legacyEnvelope: CandidateLatentItemEnvelopeR003(
                latentEffectID: initial.gear[parentIndex].latentEffectID,
                candidateLatentSlots: slots))
        initial.gear[parentIndex].candidateLatentSlots = slots

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recipe-goal-r004-\(UUID().uuidString)", isDirectory: true)
        let saveURL = directory.appendingPathComponent("save.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SaveRepository(initial: initial, fileURL: saveURL)
        let engine = try GameEngine(catalog: catalog, saves: repository, candidateLatentPolicy: policy)

        let selectionID = UUID(uuidString: "74000000-0000-4000-8000-000000000001")!
        let selection = try await engine.dispatch(.setTrackedRecipe(recipe.id),
            operationID: selectionID, expectedRevision: initial.revision)
        let selected = await engine.snapshot()
        XCTAssertEqual(selection.revision, initial.revision + 1)
        XCTAssertEqual(selected.trackedRecipeID, recipe.id)
        XCTAssertEqual(selected.gear.first { $0.id == stableGearID }?.candidateLatentSlots, slots)

        let evolveID = UUID(uuidString: "74000000-0000-4000-8000-000000000002")!
        let evolution = try await engine.dispatch(.evolveGear(gearID: stableGearID, recipeID: recipe.id),
            operationID: evolveID, expectedRevision: selected.revision)
        let evolved = await engine.snapshot()
        XCTAssertEqual(evolution.revision, selected.revision + 1)
        XCTAssertEqual(evolved.trackedRecipeID, recipe.id, "tracking is user-owned and is not auto-cleared")
        let evolvedGear = try XCTUnwrap(evolved.gear.first { $0.id == stableGearID })
        XCTAssertEqual(evolvedGear.id, stableGearID, "in-place evolution preserves the instance UUID")
        XCTAssertEqual(evolvedGear.definitionID, outputTemplate)
        XCTAssertEqual(evolvedGear.candidateLatentSlots, slots, "all rawQ values survive the real evolution command")
        XCTAssertFalse(evolved.gear.contains { $0.definitionID == parentTemplate })

        let goal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: evolved))
        XCTAssertEqual(goal.recipeID, recipe.id)
        XCTAssertEqual(goal.parentOwned, false)
        XCTAssertEqual(goal.outputOwned, true)
        XCTAssertFalse(goal.ready, "the evolved-away parent must not be reported as craftable")
        for (materialID, cost) in recipe.costs {
            XCTAssertEqual(evolved.materials[materialID] ?? 0, 0, "actual recipe cost must be charged: \(materialID)")
            XCTAssertGreaterThanOrEqual(cost, 0)
        }
        XCTAssertEqual(evolved.materials["refine_dust"] ?? 0, 0)

        let economyAfterEvolution = (evolved.materials, evolved.currency, evolved.revision)
        let fileBytesBeforeReopen = try Data(contentsOf: saveURL)
        XCTAssertFalse(fileBytesBeforeReopen.isEmpty)
        let reopenedRepository = try SaveRepository(fileURL: saveURL)
        let reopened = await reopenedRepository.snapshot()
        XCTAssertEqual(reopened, evolved, "file-backed reopen must restore the complete snapshot")
        XCTAssertEqual(reopened.trackedRecipeID, recipe.id)
        let reopenedGear = try XCTUnwrap(reopened.gear.first { $0.id == stableGearID })
        XCTAssertEqual(reopenedGear.id, stableGearID)
        XCTAssertEqual(reopenedGear.candidateLatentSlots, slots)
        XCTAssertEqual(reopenedGear.candidateLatentSlots?.slots.map(\.rawQ), [321, 654, 987])
        XCTAssertEqual(reopened.materials, economyAfterEvolution.0)
        XCTAssertEqual(reopened.currency, economyAfterEvolution.1)
        XCTAssertEqual(reopened.revision, economyAfterEvolution.2)
        let reopenedGoal = try XCTUnwrap(RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: reopened))
        XCTAssertEqual(reopenedGoal.parentOwned, false)
        XCTAssertEqual(reopenedGoal.outputOwned, true)
        XCTAssertFalse(reopenedGoal.ready)
        XCTAssertEqual(try Data(contentsOf: saveURL), fileBytesBeforeReopen,
                       "read-only reopen must not rewrite save bytes")
    }
}
