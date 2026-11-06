import Foundation
import XCTest
@testable import WitchGameCore

final class WardrobePresentationR094Tests: XCTestCase {
    private func saveURL() throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wardrobe-r094-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("save.json"))
    }

    func testTemporaryPreviewChangesOnlyLocalAppearanceProjection() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let initial = GameSnapshot.newGame(catalog: catalog)
        let (dir, url) = try saveURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SaveRepository(initial: initial, fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: repository)
        _ = try await engine.dispatch(.setTrackedRecipe("RC_EQ_W_P2"), operationID: UUID(), expectedRevision: 0)
        let before = await engine.snapshot()
        let bytesBefore = try Data(contentsOf: url)
        let appearance = try XCTUnwrap(catalog.appearances.first { $0.id == "ERNA_TRAVEL" && $0.kind == "costume" && $0.actorIDs.contains("C_WITCH") })

        var preview = WardrobePreviewSelectionR094()
        preview.show(appearanceID: appearance.id, kind: appearance.kind)
        let baseAppearance = ["C_WITCH": "standard", "WITCH_WEAPON": "STAFF_BRANCH"]
        let projected = preview.applying(to: baseAppearance)
        XCTAssertEqual(projected["C_WITCH"], appearance.id)
        XCTAssertEqual(projected["WITCH_WEAPON"], "STAFF_BRANCH")
        preview.clear()
        XCTAssertEqual(preview.applying(to: baseAppearance), baseAppearance)

        let after = await engine.snapshot()
        XCTAssertEqual(after, before, "preview must not dispatch or mutate GameSnapshot")
        XCTAssertEqual(try Data(contentsOf: url), bytesBefore, "preview must leave persisted bytes unchanged")
        XCTAssertFalse(after.ownedCosmeticIDs.contains(appearance.id))
        XCTAssertNil(after.selectedCosmeticIDs["C_WITCH"])
    }

    func testExplicitUseDispatchPersistsFreeOwnershipAndSelection() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let initial = GameSnapshot.newGame(catalog: catalog)
        let (dir, url) = try saveURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SaveRepository(initial: initial, fileURL: url)
        let engine = try GameEngine(catalog: catalog, saves: repository)
        let appearance = try XCTUnwrap(catalog.appearances.first { $0.id == "ERNA_TRAVEL" && $0.kind == "costume" && $0.actorIDs.contains("C_WITCH") })

        _ = try await engine.dispatch(.setCosmetic(appearance.id, owned: true), operationID: UUID(), expectedRevision: 0)
        let afterGrant = await engine.snapshot()
        _ = try await engine.dispatch(.selectCosmetic(actorID: "C_WITCH", cosmeticID: appearance.id), operationID: UUID(), expectedRevision: afterGrant.revision)
        let selected = await engine.snapshot()
        XCTAssertEqual(selected.revision, initial.revision + 2)
        XCTAssertTrue(selected.ownedCosmeticIDs.contains(appearance.id))
        XCTAssertEqual(selected.selectedCosmeticIDs["C_WITCH"], appearance.id)

        let reopened = try SaveRepository(fileURL: url)
        let reopenedState = await reopened.snapshot()
        XCTAssertEqual(reopenedState.ownedCosmeticIDs, selected.ownedCosmeticIDs)
        XCTAssertEqual(reopenedState.selectedCosmeticIDs, selected.selectedCosmeticIDs)
        XCTAssertEqual(reopenedState.revision, selected.revision)
    }

    func testWeaponPreviewUsesOnlyWeaponPresentationKey() {
        let preview = WardrobePreviewSelectionR094()
        var selected = preview
        selected.show(appearanceID: "STAFF_MOON", kind: "weapon")
        let base = ["C_WITCH": "ERNA_TRAVEL", "WITCH_WEAPON": "STAFF_BRANCH"]
        XCTAssertEqual(selected.applying(to: base), ["C_WITCH": "ERNA_TRAVEL", "WITCH_WEAPON": "STAFF_MOON"])
    }

    func testUnknownFurnitureDoesNotEnableDeskSpecificStaging() {
        let unknown: Set<String> = ["FURN_UNKNOWN", "FURN_CHAIR_TEST"]
        XCTAssertFalse(FurniturePresentationR094.hasBotanicalDesk(unknown))
        XCTAssertFalse(FurniturePresentationR094.hasBotanicalDesk([]))
        XCTAssertTrue(FurniturePresentationR094.hasBotanicalDesk(["FURN_DESK_BOTANICAL"]))
        XCTAssertTrue(FurniturePresentationR094.hasBotanicalDesk(unknown.union(["FURN_DESK_BOTANICAL"])))
        XCTAssertEqual(unknown, ["FURN_UNKNOWN", "FURN_CHAIR_TEST"], "mapping is read-only")
    }
}
