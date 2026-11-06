import Foundation
import XCTest
@testable import WitchGameCore

/// Proves that choosing a different available craft first consumes the R179 aid
/// opportunity but does not strand the ordinary comparison -> appraisal route.
/// Catalog materials are fixture inputs here; this is a command-path test, not
/// natural-progression or economy evidence.
final class FirstCraftAidAlternateCraftReachabilityR1Tests: XCTestCase {
    @MainActor
    func testAlternateFirstCraftCanStillCompareAndUseInitialFreeAppraisalTicket() async throws {
        let base = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let profile = try StandardPlayRuntimeProfileR1(base: base, options: .r020CurrentAppCandidate)
        var initial = try profile.makeNewSnapshot()
        let alternative = try XCTUnwrap(base.catalog.recipes.first { $0.id == "RC_EQ_W_01" })
        initial.materials = alternative.costs
        XCTAssertEqual(initial.currency["ticket_free"], 5)
        XCTAssertTrue(initial.firstCraftAidEligibleR179 == true)

        let saves = try SaveRepository(initial: initial)
        let engine = try profile.makeEngine(saves: saves)
        let craft = try await engine.dispatchConfirmingSavedReceipt(.craftRecipe(alternative.id),
            operationID: UUID(), expectedRevision: initial.revision)
        XCTAssertTrue(craft.result.contains("crafted:"))
        var state = await saves.snapshot()
        XCTAssertTrue(state.craftedGearOnce)
        XCTAssertFalse(FirstCraftCostProjectionR179.resolve(recipeID: FirstCraftCostProjectionR179.recipeID,
            declaredCosts: FirstCraftCostProjectionR179.declaredBaseline,
            firstCraftAidEligible: state.firstCraftAidEligibleR179 == true,
            craftedGearOnce: state.craftedGearOnce, capability: profile.firstCraftAid).aidApplied,
            "The R179 first-craft opportunity is consumed by any successful craft under current rules")

        let crafted = try XCTUnwrap(state.gear.last { $0.definitionID == alternative.outputGearID })
        let craftedSlot = try XCTUnwrap(base.catalog.gear.first { $0.id == crafted.definitionID }?.slot)
        let comparisonPartner = try XCTUnwrap(state.gear.first { item in
            guard item.id != crafted.id,
                  let definition = base.catalog.gear.first(where: { $0.id == item.definitionID }) else { return false }
            return definition.slot == craftedSlot
        })
        let compare = try await engine.dispatchConfirmingSavedReceipt(.markGearComparisonSeen(
            firstGearID: comparisonPartner.id, secondGearID: crafted.id), operationID: UUID(),
            expectedRevision: state.revision)
        XCTAssertTrue(compare.result.contains("comparison tutorial complete"))
        state = await saves.snapshot()
        XCTAssertTrue(state.gearComparisonSeen)
        XCTAssertTrue(state.gachaUnlocked)
        XCTAssertEqual(state.currency["ticket_free"], 5, "Comparison does not fabricate or consume tickets")

        _ = try await engine.dispatchConfirmingSavedReceipt(.mockSummon(
            poolDefinitionIDs: base.catalog.gear.map(\.id), count: 1,
            costCurrencyID: "ticket_free", seed: 91_001), operationID: UUID(),
            expectedRevision: state.revision)
        state = await saves.snapshot()
        XCTAssertEqual(state.currency["ticket_free"], 4)
        XCTAssertEqual(state.gear.count, initial.gear.count + 2,
            "The first real craft and one ticket-funded appraisal result are both persisted")
    }
}
