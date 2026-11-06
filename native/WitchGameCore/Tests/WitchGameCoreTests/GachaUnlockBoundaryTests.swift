import Foundation
import XCTest
@testable import WitchGameCore

final class GachaUnlockBoundaryTests: XCTestCase {
    func testLockedGachaTargetCannotMutateSnapshotOrSaveAndUnlockFlowPersistsSelection() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let targetID = "EQ_W_P2"

        let lockedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("witch-gacha-locked-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: lockedURL)
            try? FileManager.default.removeItem(at: lockedURL.appendingPathExtension("lock"))
        }
        let lockedStore = try SaveRepository(initial: GameSnapshot.newGame(catalog: catalog), fileURL: lockedURL)
        let lockedEngine = try GameEngine(catalog: catalog, saves: lockedStore)

        // Establish a real persisted baseline while keeping the onboarding state locked.
        _ = try await lockedEngine.dispatch(
            .startExpeditionAt(regionID: "R01", now: Date(timeIntervalSince1970: 1_800_000_000)),
            operationID: UUID(), expectedRevision: 0
        )
        let beforeRejectedChange = await lockedEngine.snapshot()
        let bytesBeforeRejectedChange = try Data(contentsOf: lockedURL)
        XCTAssertFalse(beforeRejectedChange.gachaUnlocked)
        XCTAssertEqual(beforeRejectedChange.currency["ticket_free"], 5, "the initial ticket grant is preserved while spending/configuration remains gated")

        do {
            _ = try await lockedEngine.dispatch(
                .setGachaTarget(templateID: targetID), operationID: UUID(), expectedRevision: beforeRejectedChange.revision
            )
            XCTFail("locked onboarding accepted a persisted gacha-target change")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }

        let afterRejectedChange = await lockedEngine.snapshot()
        XCTAssertEqual(afterRejectedChange, beforeRejectedChange)
        XCTAssertEqual(try Data(contentsOf: lockedURL), bytesBeforeRejectedChange, "rejected target changes must not rewrite the save")
        let lockedReload = try SaveRepository(fileURL: lockedURL)
        let lockedReloadSnapshot = await lockedReload.snapshot()
        XCTAssertEqual(lockedReloadSnapshot, beforeRejectedChange)

        let unlockedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("witch-gacha-unlocked-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: unlockedURL)
            try? FileManager.default.removeItem(at: unlockedURL.appendingPathExtension("lock"))
        }
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.materials["M_R01_G1"] = 6
        initial.materials["M_R01_G2"] = 6
        let unlockedStore = try SaveRepository(initial: initial, fileURL: unlockedURL)
        let unlockedEngine = try GameEngine(catalog: catalog, saves: unlockedStore)

        _ = try await unlockedEngine.dispatch(.craftRecipe("RC_EQ_W_01"), operationID: UUID(), expectedRevision: 0)
        var afterCraft = await unlockedEngine.snapshot()
        XCTAssertTrue(afterCraft.craftedGearOnce)
        let starterWeapon = try XCTUnwrap(afterCraft.gear.first(where: { $0.definitionID == "EQ_W_01" }))
        let craftedWeapon = try XCTUnwrap(afterCraft.gear.last(where: { $0.definitionID == "EQ_W_01" }))
        XCTAssertNotEqual(starterWeapon.id, craftedWeapon.id)

        _ = try await unlockedEngine.dispatch(
            .markGearComparisonSeen(firstGearID: starterWeapon.id, secondGearID: craftedWeapon.id),
            operationID: UUID(), expectedRevision: afterCraft.revision
        )
        afterCraft = await unlockedEngine.snapshot()
        XCTAssertTrue(afterCraft.gachaUnlocked)
        XCTAssertEqual(afterCraft.currency["ticket_free"], 5, "unlock must not alter the existing initial-ticket grant")

        _ = try await unlockedEngine.dispatch(
            .setGachaTarget(templateID: targetID), operationID: UUID(), expectedRevision: afterCraft.revision
        )
        let afterTargetSelection = await unlockedEngine.snapshot()
        XCTAssertEqual(afterTargetSelection.gachaPity.targetTemplateID, targetID)
        XCTAssertEqual(afterTargetSelection.revision, afterCraft.revision + 1)

        let unlockedReload = try SaveRepository(fileURL: unlockedURL)
        let persisted = await unlockedReload.snapshot()
        XCTAssertTrue(persisted.gachaUnlocked)
        XCTAssertEqual(persisted.gachaPity.targetTemplateID, targetID)
        XCTAssertEqual(persisted.revision, afterTargetSelection.revision)
    }
}
