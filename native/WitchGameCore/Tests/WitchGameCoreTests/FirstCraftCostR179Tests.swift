import Foundation
import XCTest
@testable import WitchGameCore

/// Proposed focused contracts. Not compiled or executed in this candidate.
final class FirstCraftCostR179Tests: XCTestCase {
    func testOnlyExplicitFreshDevelopmentEligibilityGetsOneOneProjection() {
        let baseline = FirstCraftCostProjectionR179.declaredBaseline
        XCTAssertEqual(FirstCraftCostProjectionR179.resolve(
            recipeID: "RC_EQ_F_01", declaredCosts: baseline, firstCraftAidEligible: false,
            craftedGearOnce: false, capability: .enabled).costs, baseline)
        XCTAssertEqual(FirstCraftCostProjectionR179.resolve(
            recipeID: "RC_EQ_F_01", declaredCosts: baseline, firstCraftAidEligible: true,
            craftedGearOnce: false, capability: .disabled).costs, baseline)
        XCTAssertEqual(FirstCraftCostProjectionR179.resolve(
            recipeID: "RC_EQ_F_01", declaredCosts: baseline, firstCraftAidEligible: true,
            craftedGearOnce: false, capability: .enabled).costs,
            FirstCraftCostProjectionR179.eligibleFirstCraft)
        XCTAssertEqual(FirstCraftCostProjectionR179.resolve(
            recipeID: "RC_EQ_F_01", declaredCosts: baseline, firstCraftAidEligible: true,
            craftedGearOnce: true, capability: .enabled).costs, baseline)
    }

    func testOrdinaryRuntimeFactoryDefaultsCapabilityOff() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let engine = try runtime.makeEngine(saves: SaveRepository())
        XCTAssertEqual(engine.firstCraftAidCapabilityR179, .disabled)
    }

    func testLegacySnapshotWithoutMarkerDefaultsToNoEligibilityAndOmitsFalseMarker() throws {
        let legacy = try JSONDecoder().decode(GameSnapshot.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.firstCraftAidEligibleR179)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        XCTAssertNil(encoded["firstCraftAidEligibleR179"], "nil default must not perturb the R098 canonical fresh snapshot")
    }

    func testEnabledPolicyRejectsChangedCatalogBaselineEvenWhenSnapshotIsIneligible() throws {
        var altered = FirstCraftCostProjectionR179.declaredBaseline
        altered["M_R01_E2"] = 7
        XCTAssertThrowsError(try FirstCraftCostProjectionR179.validateCatalog(
            recipeID: "RC_EQ_F_01", declaredCosts: altered,
            snapshot: GameSnapshot(), capability: .enabled))
    }

    func testProjectionAndDispatchShareIncompatibleCatalogResult() throws {
        var altered = FirstCraftCostProjectionR179.declaredBaseline
        altered["M_R01_E2"] = 7
        let resolution = FirstCraftCostProjectionR179.resolve(
            recipeID: "RC_EQ_F_01", declaredCosts: altered, firstCraftAidEligible: true,
            craftedGearOnce: false, capability: .enabled)
        XCTAssertFalse(resolution.dispatchCompatible)
        XCTAssertFalse(resolution.aidApplied)
        XCTAssertEqual(resolution.costs, altered)
        XCTAssertThrowsError(try FirstCraftCostProjectionR179.validateCatalog(
            recipeID: "RC_EQ_F_01", declaredCosts: altered,
            snapshot: GameSnapshot(firstCraftAidEligibleR179: true), capability: .enabled))

        let catalog = GameCatalog(version: "test", regions: [], enemies: [], gear: [], research: [],
            materialIDs: ["M_R01_G1", "M_R01_E2"],
            recipes: [RecipeDefinition(id: "RC_EQ_F_01", outputGearID: "EQ_W_F_01",
                                       costs: altered, status: "test", gateID: "G_START")],
            actorIDs: [])
        let goal = try XCTUnwrap(RecipeGoalProjectionR035.goals(
            catalog: catalog, materialCounts: altered.mapValues { $0 + 10 },
            ownedGearTemplateIDs: [], unlockedRegionIDs: [], completedEncounterIDs: [],
            firstCraftAidEligibleR179: true, craftedGearOnce: false,
            firstCraftAidCapabilityR179: .enabled).first)
        XCTAssertFalse(goal.dispatchCompatible)
        XCTAssertFalse(goal.ready)
        XCTAssertFalse(goal.firstCraftAidApplied)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: goal.requirements.map { ($0.materialID, $0.required) }), altered)
    }

    func testCompatibleProjectionExposesExactlyTheCostsTransactionAccepts() throws {
        let catalog = GameCatalog(version: "test", regions: [], enemies: [], gear: [], research: [],
            materialIDs: ["M_R01_G1", "M_R01_E2"],
            recipes: [RecipeDefinition(id: "RC_EQ_F_01", outputGearID: "EQ_W_F_01",
                                       costs: FirstCraftCostProjectionR179.declaredBaseline,
                                       status: "test", gateID: "G_START")], actorIDs: [])
        let goal = try XCTUnwrap(RecipeGoalProjectionR035.goals(
            catalog: catalog, materialCounts: FirstCraftCostProjectionR179.eligibleFirstCraft,
            ownedGearTemplateIDs: [], unlockedRegionIDs: [], completedEncounterIDs: [],
            firstCraftAidEligibleR179: true, craftedGearOnce: false,
            firstCraftAidCapabilityR179: .enabled).first)
        XCTAssertTrue(goal.dispatchCompatible)
        XCTAssertTrue(goal.ready)
        XCTAssertTrue(goal.firstCraftAidApplied)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: goal.requirements.map { ($0.materialID, $0.required) }),
                       FirstCraftCostProjectionR179.eligibleFirstCraft)
        let transactionResolution = try FirstCraftCostProjectionR179.validateCatalog(
            recipeID: "RC_EQ_F_01", declaredCosts: FirstCraftCostProjectionR179.declaredBaseline,
            snapshot: GameSnapshot(firstCraftAidEligibleR179: true), capability: .enabled)
        XCTAssertEqual(transactionResolution.costs,
                       Dictionary(uniqueKeysWithValues: goal.requirements.map { ($0.materialID, $0.required) }))
        XCTAssertEqual(transactionResolution.aidApplied, goal.firstCraftAidApplied)
    }

}
