import XCTest
@testable import WitchGameCore

final class RecipeGatherHandoffTargetR157Tests: XCTestCase {
    func testR144InvestigationOverridesMatchingLegacyGatherID() {
        XCTAssertTrue(RecipeGatherHandoffTargetR157.needsDispatch(
            sharedWorkEnabled: true,
            typedTarget: .investigate("E_R01_01"),
            legacyGatherTargetID: "G1",
            requestedMaterialID: "G1"))
        XCTAssertFalse(RecipeGatherHandoffTargetR157.isCommitted(
            sharedWorkEnabled: true,
            typedTarget: .investigate("E_R01_01"),
            legacyGatherTargetID: "G1",
            requestedMaterialID: "G1"))
    }

    func testR144RequiresExactTypedGatherTarget() {
        XCTAssertFalse(RecipeGatherHandoffTargetR157.needsDispatch(
            sharedWorkEnabled: true,
            typedTarget: .gather("G1"),
            legacyGatherTargetID: "G1",
            requestedMaterialID: "G1"))
        XCTAssertTrue(RecipeGatherHandoffTargetR157.needsDispatch(
            sharedWorkEnabled: true,
            typedTarget: .gather("G2"),
            legacyGatherTargetID: "G1",
            requestedMaterialID: "G1"))
    }

    func testR144LegacyFallbackIsNotMistakenForPersistedTypedSelection() {
        XCTAssertTrue(RecipeGatherHandoffTargetR157.needsDispatch(
            sharedWorkEnabled: true,
            typedTarget: nil,
            legacyGatherTargetID: "G1",
            requestedMaterialID: "G1"))
    }

    func testDefaultPolicyPreservesLegacyComparison() {
        XCTAssertFalse(RecipeGatherHandoffTargetR157.needsDispatch(
            sharedWorkEnabled: false,
            typedTarget: .investigate("E_R01_01"),
            legacyGatherTargetID: "G1",
            requestedMaterialID: "G1"))
        XCTAssertTrue(RecipeGatherHandoffTargetR157.needsDispatch(
            sharedWorkEnabled: false,
            typedTarget: .gather("G1"),
            legacyGatherTargetID: "G2",
            requestedMaterialID: "G1"))
    }

    func testPartialFailureContextDistinguishesCommittedRegion() {
        XCTAssertEqual(RecipeGatherHandoffTargetR157.failureContext(
            regionDispatchCommitted: true,
            activeRegionID: "R01",
            requestedRegionID: "R01",
            targetCommitted: false), .regionChangedTargetPending)
        XCTAssertEqual(RecipeGatherHandoffTargetR157.failureContext(
            regionDispatchCommitted: false,
            activeRegionID: "R01",
            requestedRegionID: "R01",
            targetCommitted: false), .targetUnchangedInSelectedRegion)
        XCTAssertEqual(RecipeGatherHandoffTargetR157.failureContext(
            regionDispatchCommitted: true,
            activeRegionID: "R02",
            requestedRegionID: "R01",
            targetCommitted: false), .noPartialRegionChange)
        XCTAssertEqual(RecipeGatherHandoffTargetR157.failureContext(
            regionDispatchCommitted: true,
            activeRegionID: "R01",
            requestedRegionID: "R01",
            targetCommitted: true), .noPartialRegionChange)
    }
}
