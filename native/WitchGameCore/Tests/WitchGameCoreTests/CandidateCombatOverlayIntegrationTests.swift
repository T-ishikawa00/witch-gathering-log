import XCTest
@testable import WitchGameCore

final class CandidateCombatOverlayIntegrationTests: XCTestCase {
    func testOverlayIsOptInAndOnlyChangesSelectedDefaultEncounter() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let enemy = try XCTUnwrap(catalog.enemies.first { $0.id == "E_R03_04" })
        let starter = GameSnapshot.newGame(catalog: catalog)
        let baseline = try GameEngine(catalog: catalog, saves: SaveRepository(initial: starter))
        let candidate = try GameEngine(catalog: catalog, saves: SaveRepository(initial: starter),
            candidateCombatOverlay: .r014LocalCandidate)

        let baselineResult = try await baseline.previewCampaignEncounterDefaultQA(enemyID: enemy.id, seed: 1304,
            snapshot: starter, maxDurationMs: 12_000)
        let candidateResult = try await candidate.previewCampaignEncounterDefaultQA(enemyID: enemy.id, seed: 1304,
            snapshot: starter, maxDurationMs: 12_000)
        XCTAssertFalse(baselineResult.events.contains { $0.kind == "enemy_magnet_mark" })
        XCTAssertTrue(candidateResult.events.contains { $0.kind == "enemy_magnet_mark" && $0.sourceID == enemy.id })
        XCTAssertTrue(candidateResult.events.contains {
            $0.kind == "enemy_hit" && $0.sourceID == enemy.id
                && $0.diagnostics?["candidateMagnetCoefficientBP"] == 12_500
        })

        let otherEnemy = try XCTUnwrap(catalog.enemies.first { $0.regionID == enemy.regionID && $0.id != enemy.id })
        let otherResult = try await candidate.previewCampaignEncounterDefaultQA(enemyID: otherEnemy.id, seed: 1304,
            snapshot: starter, maxDurationMs: 12_000)
        XCTAssertFalse(otherResult.events.contains { $0.kind == "enemy_magnet_mark" },
                       "candidate injection is scoped to E_R03_04")

        let sourceProfile = try await candidate.previewCampaignEncounterR6QA(enemyID: enemy.id, seed: 1304,
            snapshot: starter, maxDurationMs: 12_000)
        XCTAssertFalse(sourceProfile.events.contains { $0.kind == "enemy_magnet_mark" },
                       "canonical fixed-point source profile remains isolated")
        let previewSnapshot = await candidate.snapshot()
        XCTAssertNil(previewSnapshot.lastCombatResult, "read-only preview must not persist battle state")
    }

    func testOverlayFlowsThroughAtomicEncounterReceiptWithoutCatalogMutation() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let enemy = try XCTUnwrap(catalog.enemies.first { $0.id == "E_R03_04" })
        let initialPattern = enemy.actionPattern
        var starter = GameSnapshot.newGame(catalog: catalog)
        starter.activeRegionID = enemy.regionID
        starter.unlockedRegionIDs.insert(enemy.regionID)
        if let prerequisite = enemy.prerequisiteEncounterID { starter.completedEncounterIDs.insert(prerequisite) }
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: starter),
            candidateCombatOverlay: .r014LocalCandidate)
        let receipt = try await engine.dispatch(.resolveEncounter(enemyID: enemy.id, seed: 1304),
            operationID: UUID(), expectedRevision: starter.revision)
        let saved = await engine.snapshot()
        XCTAssertEqual(saved.revision, receipt.revision)
        XCTAssertEqual(saved.lastEncounterID, enemy.id)
        XCTAssertTrue(saved.lastCombatResult?.events.contains { $0.kind == "enemy_magnet_mark" } == true)
        XCTAssertEqual(catalog.enemies.first(where: { $0.id == enemy.id })?.actionPattern, initialPattern,
                       "overlay must not rewrite or persist catalog definitions")
    }
}
