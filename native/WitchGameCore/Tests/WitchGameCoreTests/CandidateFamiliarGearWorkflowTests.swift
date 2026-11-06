import XCTest
@testable import WitchGameCore

final class CandidateFamiliarGearWorkflowTests: XCTestCase {
    func testAll33GearTypesCraftEquipEnhanceAndPersist() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let gearIDs = Set(catalog.gear.map(\.id))
        XCTAssertEqual(catalog.gear.count, 33)
        XCTAssertEqual(Set(catalog.recipes.map(\.id)).count, catalog.recipes.count, "recipe IDs must be unique after candidate normalization")
        for id in gearIDs {
            XCTAssertEqual(catalog.recipes.filter { $0.outputGearID == id }.count, 1, "every gear type needs one unambiguous output recipe: \(id)")
        }

        var initial = GameSnapshot(unlockedRegionIDs: Set(catalog.regions.map(\.id)))
        for recipe in catalog.recipes {
            for (material, _) in recipe.costs { initial.materials[material] = 1_000_000 }
            if let gateID = recipe.gateID, gateID != "G_START" {
                let parts = gateID.split(separator: "_")
                if parts.count == 3 { initial.completedEncounterIDs.insert("B_\(parts[1])_\(parts[2])") }
            }
        }
        initial.materials["refine_dust"] = 1_000_000
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-all-gear-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("lock"))
        }
        let saves = try SaveRepository(initial: initial, fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: saves)
        var revision: Int64 = 0

        func send(_ command: GameCommand) async throws -> CommandReceipt {
            let receipt = try await engine.dispatch(command, operationID: UUID(), expectedRevision: revision)
            revision = receipt.revision
            return receipt
        }
        func makeInstance(_ id: String) async throws -> UUID {
            let recipe = try XCTUnwrap(catalog.recipes.first(where: { $0.outputGearID == id }))
            switch recipe.kind {
            case "craft_new":
                let oldIDs = Set((await engine.snapshot()).gear.map(\.id))
                _ = try await send(.craftRecipe(recipe.id))
                let afterCraft = await engine.snapshot()
                let created = try XCTUnwrap(afterCraft.gear.last(where: { $0.definitionID == id && !oldIDs.contains($0.id) }))
                return created.id
            case "evolve_in_place":
                let parentID = try XCTUnwrap(recipe.parentTemplateID)
                let inputID = try await makeInstance(parentID)
                _ = try await send(.evolveGear(gearID: inputID, recipeID: recipe.id))
                let afterEvolution = await engine.snapshot()
                let evolved = try XCTUnwrap(afterEvolution.gear.first(where: { $0.id == inputID && $0.definitionID == id }))
                return evolved.id
            default:
                XCTFail("unsupported output recipe kind \(recipe.kind) for \(id)")
                throw CoreError.invalidCatalog("unsupported output recipe")
            }
        }

        for id in catalog.gear.map(\.id).sorted() {
            let instanceID = try await makeInstance(id)
            let definition = try XCTUnwrap(catalog.gear.first(where: { $0.id == id }))
            let actorID = try XCTUnwrap(definition.actorIDs.first)
            _ = try await send(.equip(gearID: instanceID, actorID: actorID))
            _ = try await send(.enhance(gearID: instanceID))
            let snapshot = await engine.snapshot()
            let item = try XCTUnwrap(snapshot.gear.first(where: { $0.id == instanceID }))
            XCTAssertEqual(item.definitionID, id)
            XCTAssertEqual(item.ownerID, actorID)
            XCTAssertEqual(item.enhancement, 1)
            XCTAssertEqual(snapshot.equippedGearIDs["\(actorID)|\(definition.slot)"], instanceID)
        }

        let beforeRestart = await engine.snapshot()
        let reopened = try SaveRepository(fileURL: url)
        let afterRestart = await reopened.snapshot()
        XCTAssertEqual(afterRestart, beforeRestart, "all per-ID create/equip/enhance results must survive file-backed reopen")
        XCTAssertTrue(gearIDs.isSubset(of: Set(afterRestart.gear.map(\.definitionID))))
    }
}
