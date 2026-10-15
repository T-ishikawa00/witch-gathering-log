import XCTest
@testable import WitchGameCore

/// Persistence check using the same resolved R098 runtime factory as the app.
/// The UUID directory is intentionally retained; this test never deletes saves.
final class WardrobeCandidatePersistenceR130SharedRuntimeTests: XCTestCase {
    func testAiraCandidatePersistsAndResetSurvivesReopen() async throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let r128 = try WardrobeCandidateCatalogR128.extending(runtime.catalog)
        let catalog = try WardrobeCandidateCatalogR130.extending(r128)
        let initial = try runtime.makeNewSnapshot()
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wardrobe-r130-shared-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        let saveURL = testDirectory.appendingPathComponent("isolated-save.json")

        let firstRepository = try SaveRepository(initial: initial, fileURL: saveURL)
        let firstEngine = try runtime.makeEngine(saves: firstRepository, appearanceCatalog: catalog)
        _ = try await firstEngine.dispatch(
            .setCosmetic(WardrobeCandidateCatalogR130.appearanceID, owned: true),
            operationID: UUID(), expectedRevision: 0)
        let afterOwnership = await firstEngine.snapshot()
        _ = try await firstEngine.dispatch(
            .selectCosmetic(actorID: "C_SMITH", cosmeticID: WardrobeCandidateCatalogR130.appearanceID),
            operationID: UUID(), expectedRevision: afterOwnership.revision)
        let applied = await firstEngine.snapshot()

        XCTAssertEqual(applied.selectedCosmeticIDs["C_SMITH"], WardrobeCandidateCatalogR130.appearanceID)
        XCTAssertTrue(applied.ownedCosmeticIDs.contains(WardrobeCandidateCatalogR130.appearanceID))
        XCTAssertEqual(applied.gear, initial.gear)
        XCTAssertEqual(applied.currency, initial.currency)
        XCTAssertEqual(applied.characterXP, initial.characterXP)

        let reopenedRepository = try SaveRepository(fileURL: saveURL)
        let reopenedEngine = try runtime.makeEngine(saves: reopenedRepository, appearanceCatalog: catalog)
        let reloaded = await reopenedEngine.snapshot()
        XCTAssertEqual(reloaded.selectedCosmeticIDs["C_SMITH"], WardrobeCandidateCatalogR130.appearanceID)
        XCTAssertTrue(reloaded.ownedCosmeticIDs.contains(WardrobeCandidateCatalogR130.appearanceID))
        XCTAssertEqual(reloaded.revision, applied.revision)
        XCTAssertEqual(reloaded.gear, applied.gear)

        _ = try await reopenedEngine.dispatch(
            .selectCosmetic(actorID: "C_SMITH", cosmeticID: nil),
            operationID: UUID(), expectedRevision: reloaded.revision)
        let reset = await reopenedEngine.snapshot()
        XCTAssertNil(reset.selectedCosmeticIDs["C_SMITH"])
        XCTAssertTrue(reset.ownedCosmeticIDs.contains(WardrobeCandidateCatalogR130.appearanceID))

        let resetColdRepository = try SaveRepository(fileURL: saveURL)
        let resetColdEngine = try runtime.makeEngine(saves: resetColdRepository, appearanceCatalog: catalog)
        let resetCold = await resetColdEngine.snapshot()
        XCTAssertNil(resetCold.selectedCosmeticIDs["C_SMITH"])
        XCTAssertTrue(resetCold.ownedCosmeticIDs.contains(WardrobeCandidateCatalogR130.appearanceID))
        XCTAssertEqual(resetCold.revision, reset.revision)
        XCTAssertEqual(resetCold.gear, initial.gear)
        XCTAssertEqual(resetCold.currency, initial.currency)
        XCTAssertEqual(resetCold.characterXP, initial.characterXP)
    }
}
