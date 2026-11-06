import XCTest
@testable import WitchGameCore

/// Read-only projection cases against the bundled catalog; no engine commands or real saves.
final class ResearchMaterialGuidanceR280Tests: XCTestCase {
    private func catalog() throws -> GameCatalog { try GameCatalog.bundledTestOverlay() }
    private func research(_ catalog: GameCatalog, _ id: String) throws -> ResearchDefinition {
        try XCTUnwrap(catalog.research.first { $0.id == id })
    }
    private func rows(_ catalog: GameCatalog, _ state: GameSnapshot, _ research: ResearchDefinition) -> [ResearchMaterialGuidanceR280.Requirement] {
        ResearchMaterialGuidanceR280.project(catalog: catalog, state: state, research: research)
    }
    private enum LookupError: Error { case expectedRegionSources }
    private func source(_ requirement: ResearchMaterialGuidanceR280.Requirement, regionID: String) throws -> ResearchMaterialGuidanceR280.Source {
        guard case .regions(let sources) = requirement.availability else {
            XCTFail("expected known gather source")
            throw LookupError.expectedRegionSources
        }
        return try XCTUnwrap(sources.first { $0.regionID == regionID })
    }

    func testFreshR01DistinguishesAvailableG2FromR01AGatedG4() throws {
        let c = try catalog(), state = GameSnapshot.newGame(catalog: c)
        let rows = rows(c, state, try research(c, "RS_THEORY_2"))
        XCTAssertEqual(rows.map(\.materialID), ["M_R01_G2", "M_R01_G4"])
        XCTAssertEqual(rows.map(\.missing), [10, 10])
        if case .available = try source(rows[0], regionID: "R01").status {} else { XCTFail("G2 should be gatherable in fresh R01") }
        if case .sourceGateLocked = try source(rows[1], regionID: "R01").status {} else { XCTFail("G4 requires its catalog encounter gate") }
        XCTAssertEqual(state, GameSnapshot.newGame(catalog: c))
    }

    func testR02RegionLockAndEncounterGateAreReportedSeparately() throws {
        let c = try catalog(), r = try research(c, "RS_THEORY_3")
        var locked = GameSnapshot.newGame(catalog: c)
        let lockedRows = rows(c, locked, r)
        XCTAssertEqual(lockedRows.map(\.materialID), ["M_R02_G2", "M_R02_G3"])
        for row in lockedRows {
            if case .regionLocked = try source(row, regionID: "R02").status {} else { XCTFail("R02 is not unlocked") }
        }
        locked.unlockedRegionIDs.insert("R02")
        let regionOpenRows = rows(c, locked, r)
        for row in regionOpenRows {
            if case .sourceGateLocked = try source(row, regionID: "R02").status {} else { XCTFail("source gate must remain distinct from region unlock") }
        }
        locked.completedEncounterIDs.insert("B_R01_B")
        let gateOpenRows = rows(c, locked, r)
        if case .available = try source(try XCTUnwrap(gateOpenRows.first { $0.materialID == "M_R02_G2" }), regionID: "R02").status {} else { XCTFail("G2 source gate should open after B_R01_B") }
        if case .sourceGateLocked = try source(try XCTUnwrap(gateOpenRows.first { $0.materialID == "M_R02_G3" }), regionID: "R02").status {} else { XCTFail("G3 still requires B_R02_A") }
    }

    func testPartialAndSufficientInventoryChangesOnlyMissingRows() throws {
        let c = try catalog(), r = try research(c, "RS_THEORY_2")
        var state = GameSnapshot.newGame(catalog: c)
        state.materials["M_R01_G2"] = 7
        var projected = rows(c, state, r)
        XCTAssertEqual(projected.first { $0.materialID == "M_R01_G2" }?.missing, 3)
        XCTAssertEqual(projected.count, 2)
        state.materials["M_R01_G4"] = 10
        projected = rows(c, state, r)
        XCTAssertEqual(projected.map(\.materialID), ["M_R01_G2"])
        state.materials["M_R01_G2"] = 10
        XCTAssertTrue(rows(c, state, r).isEmpty)
    }

    func testCompletedResearchHasNoMaterialGuidance() throws {
        let c = try catalog(), r = try research(c, "RS_THEORY_2")
        var state = GameSnapshot.newGame(catalog: c)
        state.completedResearchIDs.insert(r.id)
        XCTAssertTrue(rows(c, state, r).isEmpty)
    }

    func testUnknownMaterialNeverGetsAnInferredRegion() throws {
        let c = try catalog(), state = GameSnapshot.newGame(catalog: c)
        let r = ResearchDefinition(id: "RS_TEST_UNKNOWN_R280", name: "test", cost: ["M_UNKNOWN_R280": 2], effectID: "unknown")
        let result = rows(c, state, r)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].missing, 2)
        if case .unknownMaterial = result[0].availability {} else { XCTFail("unknown ID must fail closed") }
    }

    func testKnownEnemyDropWithoutGatherRegionIsNotSuggestedAsGatherable() throws {
        let c = try catalog(), state = GameSnapshot.newGame(catalog: c)
        XCTAssertTrue(c.materialIDs.contains("M_R01_BA"))
        XCTAssertFalse(c.regions.contains { $0.gatherMaterialIDs.contains("M_R01_BA") })
        let r = ResearchDefinition(id: "RS_TEST_NO_SOURCE_R280", name: "test", cost: ["M_R01_BA": 1], effectID: "unknown")
        let result = rows(c, state, r)
        XCTAssertEqual(result.count, 1)
        if case .noGatherRegion = result[0].availability {} else { XCTFail("known non-gather material must not be assigned a region") }
    }

    func testProjectionLeavesSnapshotGatherTargetAndExistingReceiptUnchanged() async throws {
        let c = try catalog(), r = try research(c, "RS_THEORY_2")
        var initial = GameSnapshot.newGame(catalog: c)
        initial.gatherTargetMaterialID = "M_R01_G1"
        let repository = try SaveRepository(initial: initial)
        let operationID = UUID()
        let seededReceipt = try await repository.transact(expectedRevision: initial.revision, operationID: operationID) { _ in "seed receipt" }
        let before = await repository.snapshot()
        let receiptBefore = await repository.receipt(for: operationID)
        _ = rows(c, before, r)
        let after = await repository.snapshot()
        let receiptAfter = await repository.receipt(for: operationID)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.gatherTargetMaterialID, "M_R01_G1")
        XCTAssertEqual(receiptBefore, seededReceipt)
        XCTAssertEqual(receiptAfter, seededReceipt)
    }
}
