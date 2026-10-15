import XCTest
@testable import WitchGameCore

final class GearComparisonPartnerSelectionR210Tests: XCTestCase {
    private let familiar = "C_FAMILIAR"
    private let witch = "C_WITCH"
    private let selectedID = UUID(uuidString: "21000000-0000-4000-8000-000000000001")!
    private let duplicateLowID = UUID(uuidString: "21000000-0000-4000-8000-000000000002")!
    private let equippedID = UUID(uuidString: "21000000-0000-4000-8000-000000000003")!
    private let alternateID = UUID(uuidString: "21000000-0000-4000-8000-000000000004")!

    private func catalog() throws -> GameCatalog { try GameCatalog.bundledTestOverlay() }
    private func item(_ id: UUID, _ definitionID: String, owner: String? = nil,
                      quality: String = "Q0", enhancement: Int = 0, refinement: Int = 0) -> GearInstance {
        GearInstance(id: id, definitionID: definitionID, ownerID: owner,
                     enhancement: enhancement, refinement: refinement, qualityID: quality)
    }
    private func select(_ selected: UUID, actor: String, gear: [GearInstance],
                        equipped: [String: UUID], catalog: GameCatalog) -> UUID? {
        GearComparisonPartnerSelectionR210.selectCounterpart(
            itemID: selected, actorID: actor, gear: gear, definitions: catalog.gear,
            equippedGearIDs: equipped, usableGearIDs: Set(gear.map(\.id)))
    }

    func testPrefersExactEquippedInstanceOverEarlierDuplicateDefinition() throws {
        let c = try catalog()
        let gear = [item(selectedID, "EQ_F_02", quality: "Q2"),
                    item(duplicateLowID, "EQ_F_01", quality: "Q0"),
                    item(equippedID, "EQ_F_01", owner: familiar, quality: "Q2")]
        XCTAssertEqual(select(selectedID, actor: familiar, gear: gear,
                              equipped: ["C_FAMILIAR|weapon": equippedID], catalog: c), equippedID)
    }

    func testEquippedSelectionFallsBackToBestOtherCompatibleInstance() throws {
        let c = try catalog()
        let gear = [item(duplicateLowID, "EQ_F_01", quality: "Q0"),
                    item(equippedID, "EQ_F_01", owner: familiar, quality: "Q2"),
                    item(alternateID, "EQ_F_02", quality: "Q2", enhancement: 1)]
        XCTAssertEqual(select(equippedID, actor: familiar, gear: gear,
                              equipped: ["C_FAMILIAR|weapon": equippedID], catalog: c), alternateID)
    }

    func testMissingEquippedPointerUsesStableFallbackIndependentOfArrayOrder() throws {
        let c = try catalog()
        let gear = [item(selectedID, "EQ_F_02", quality: "Q2"),
                    item(alternateID, "EQ_F_01", quality: "Q2"),
                    item(equippedID, "EQ_F_01", quality: "Q2")]
        let first = select(selectedID, actor: familiar, gear: gear, equipped: [:], catalog: c)
        let reversed = select(selectedID, actor: familiar, gear: Array(gear.reversed()), equipped: [:], catalog: c)
        XCTAssertEqual(first, equippedID)
        XCTAssertEqual(reversed, equippedID)
    }

    func testRejectsActorIncompatibleAndForeignWornCounterparts() throws {
        let c = try catalog()
        let gear = [item(selectedID, "EQ_F_02", quality: "Q2"),
                    item(duplicateLowID, "EQ_W_G1", quality: "Q3"),
                    item(equippedID, "EQ_F_01", owner: witch, quality: "Q4"),
                    item(alternateID, "EQ_F_01", quality: "Q1")]
        XCTAssertEqual(select(selectedID, actor: familiar, gear: gear,
                              equipped: ["C_FAMILIAR|weapon": duplicateLowID], catalog: c), alternateID)
    }

    func testReturnsNilWithoutAnotherCompatibleOwnedInstance() throws {
        let c = try catalog()
        let gear = [item(selectedID, "EQ_F_02", quality: "Q2"),
                    item(duplicateLowID, "EQ_W_G1", quality: "Q3")]
        XCTAssertNil(select(selectedID, actor: familiar, gear: gear,
                            equipped: ["C_FAMILIAR|weapon": duplicateLowID], catalog: c))
    }

    func testRejectsUnknownOrIncompatibleSelectedInstance() throws {
        let c = try catalog()
        let gear = [item(selectedID, "EQ_W_G1", quality: "Q2"),
                    item(alternateID, "EQ_F_01", quality: "Q1")]
        XCTAssertNil(select(selectedID, actor: familiar, gear: gear,
                            equipped: ["C_FAMILIAR|weapon": alternateID], catalog: c))
        XCTAssertNil(select(UUID(uuidString: "21000000-0000-4000-8000-000000000099")!, actor: familiar,
                            gear: gear, equipped: [:], catalog: c))
    }
}
