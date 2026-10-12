import XCTest
@testable import WitchGameCore

final class EquippedVisualCandidatesTests: XCTestCase {
    func testOnlyEquippedSnapshotOwnedItemsBecomeVisualCandidates() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let worn = GearInstance(definitionID: "EQ_BODY_01", ownerID: "C_WITCH")
        let spare = GearInstance(definitionID: "EQ_BODY_02", ownerID: "C_WITCH")
        var state = GameSnapshot.newGame(catalog: catalog)
        state.gear = [worn, spare]
        state.equippedGearIDs = ["C_WITCH|body": worn.id]
        let before = state
        let projections = catalog.equippedVisualCandidates(in: state)
        XCTAssertEqual(projections.map(\.gearID), ["EQ_BODY_01"])
        XCTAssertEqual(projections.first?.sceneKey, "DETAIL|C_WITCH|body")
        XCTAssertEqual(state, before, "render projection must be read-only")
        state.equippedGearIDs.removeAll()
        XCTAssertTrue(catalog.equippedVisualCandidates(in: state).isEmpty)
    }

    func testWrongOwnerAndMissingEquipmentPointerNeverProduceGhostAttachments() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        var state = GameSnapshot.newGame(catalog: catalog)
        let wrongOwner = GearInstance(definitionID: "EQ_A_01", ownerID: "C_WITCH")
        let unowned = GearInstance(definitionID: "EQ_BODY_01")
        state.gear = [wrongOwner, unowned]
        state.equippedGearIDs = ["C_APPRENTICE|weapon": wrongOwner.id, "C_WITCH|body": unowned.id]
        XCTAssertTrue(catalog.equippedVisualCandidates(in: state).isEmpty)
    }

    func testAllFifteenSmallDetailTypesProjectForEveryCompatibleActorOnly() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let prefixes = ["EQ_BODY_", "EQ_HAND_", "EQ_FEET_", "EQ_AMU_", "EQ_RING_"]
        let definitions = catalog.gear.filter { gear in prefixes.contains { gear.id.hasPrefix($0) } }
        XCTAssertEqual(definitions.count, 15)
        for definition in definitions {
            for actor in catalog.actorIDs {
                var state = GameSnapshot.newGame(catalog: catalog)
                let item = GearInstance(definitionID: definition.id, ownerID: actor)
                state.gear = [item]; state.equippedGearIDs = ["\(actor)|\(definition.slot)": item.id]
                let result = catalog.equippedVisualCandidates(in: state)
                XCTAssertEqual(result.count, definition.actorIDs.contains(actor) ? 1 : 0, "\(definition.id):\(actor)")
                if let candidate = result.first {
                    XCTAssertEqual(candidate.candidateAssetID, "DETAIL_\(definition.id)")
                }
            }
        }
    }

    func testBooksMetalHammerAndCatCatalystsRemainSeparateFromDeferredProposals() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let expected = Set(["EQ_A_01", "EQ_A_02", "EQ_A_03", "EQ_S_02", "EQ_S_03", "EQ_F_01", "EQ_F_02", "EQ_F_03"])
        let ids = expected.union(["EQ_S_01", "EQ_F_BODY_01", "EQ_F_HAND_01", "EQ_F_FEET_01", "EQ_F_RING_01"])
        for id in ids {
            let definition = try XCTUnwrap(catalog.gear.first { $0.id == id })
            let actor = try XCTUnwrap(definition.actorIDs.first)
            let item = GearInstance(definitionID: id, ownerID: actor)
            var state = GameSnapshot.newGame(catalog: catalog)
            state.gear = [item]; state.equippedGearIDs = ["\(actor)|\(definition.slot)": item.id]
            XCTAssertEqual(catalog.equippedVisualCandidates(in: state).map(\.gearID), expected.contains(id) ? [id] : [])
        }
    }
}
