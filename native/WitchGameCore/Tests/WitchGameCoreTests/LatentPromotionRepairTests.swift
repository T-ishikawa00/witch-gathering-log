import Foundation
import XCTest
@testable import WitchGameCore

final class LatentPromotionRepairTests: XCTestCase {
    func testQ3ToQ4PromotionAppliesRegisteredLatentAndPersistsIdempotently() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let gearID = "EQ_W_01"
        let instanceID = UUID()
        let recipe = try XCTUnwrap(catalog.recipes.first(where: { $0.id == "QUALITY_Q3_Q4" }))
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.revision = 0
        initial.unlockedRegionIDs.formUnion(catalog.regions.map(\.id))
        initial.completedEncounterIDs.formUnion(catalog.enemies.map(\.id))
        initial.activeRegionID = "R01"
        initial.gatherTargetMaterialID = catalog.regions.first(where: { $0.id == "R01" })?.gatherMaterialIDs.first
        initial.materials["refine_dust"] = max(100_000, recipe.dustCost)
        initial.gear.append(GearInstance(id: instanceID, definitionID: gearID, ownerID: "C_WITCH", qualityID: "Q3"))
        initial.equippedGearIDs["C_WITCH|WITCH_WEAPON"] = instanceID

        let promotedURL = FileManager.default.temporaryDirectory.appendingPathComponent("witch-latent-promoted-\(UUID().uuidString).json")
        let baselineURL = FileManager.default.temporaryDirectory.appendingPathComponent("witch-latent-baseline-\(UUID().uuidString).json")
        defer {
            for url in [promotedURL, baselineURL] {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.appendingPathExtension("lock"))
            }
        }

        let promotedStore = try SaveRepository(initial: initial, fileURL: promotedURL)
        let promotedEngine = try GameEngine(catalog: catalog, saves: promotedStore)
        let baselineStore = try SaveRepository(initial: initial, fileURL: baselineURL)
        let baselineEngine = try GameEngine(catalog: catalog, saves: baselineStore)

        let baselineGear = try XCTUnwrap(initial.gear.first)
        let beforeStats = catalog.projectCombatant(for: "C_WITCH", with: [baselineGear])

        let promoteCommand = GameCommand.promoteQuality(gearID: instanceID)
        let operationID = UUID()
        let promotion = try await promotedEngine.dispatch(promoteCommand, operationID: operationID, expectedRevision: 0)
        XCTAssertEqual(promotion.revision, 1)
        let promoted = await promotedEngine.snapshot()
        let promotedGear = try XCTUnwrap(promoted.gear.first(where: { $0.id == instanceID }))
        XCTAssertEqual(promotedGear.qualityID, "Q4")
        XCTAssertEqual(promotedGear.latentEffectID, "LATENT_POWER_TEST")
        XCTAssertTrue(promotedGear.protected)
        XCTAssertEqual(promotedGear.investmentDust, recipe.dustCost)
        XCTAssertEqual(promoted.equippedGearIDs["C_WITCH|WITCH_WEAPON"], instanceID)

        let afterStats = catalog.projectCombatant(for: "C_WITCH", with: [promotedGear])
        let q4WithoutLatent = GearInstance(id: instanceID, definitionID: gearID, ownerID: "C_WITCH", qualityID: "Q4")
        let q4BaseStats = catalog.projectCombatant(for: "C_WITCH", with: [q4WithoutLatent])
        let q4QualityMultiplier = 100 + 15
        let q4WeaponBaseBonus = catalog.gearAttackBonuses[gearID, default: 0]
        let expectedLatentDelta = (q4WeaponBaseBonus + 5) * q4QualityMultiplier / 100 - q4WeaponBaseBonus * q4QualityMultiplier / 100
        XCTAssertEqual(afterStats.attack, q4BaseStats.attack + expectedLatentDelta,
            "the registered power latent contributes the existing candidate +5 before the current Q4 quality multiplier")
        XCTAssertGreaterThan(afterStats.attack, beforeStats.attack)
        XCTAssertTrue(afterStats.effectIDs.contains("LATENT_POWER_TEST"))

        // The old identifier existed in saves already; it remains a combat and UI alias without rewriting stored data.
        let legacyGear = GearInstance(id: instanceID, definitionID: gearID, ownerID: "C_WITCH", latentEffectID: "LATENT_TEST_01", qualityID: "Q4")
        let legacyStats = catalog.projectCombatant(for: "C_WITCH", with: [legacyGear])
        XCTAssertEqual(legacyStats.attack, afterStats.attack)
        XCTAssertTrue(legacyStats.effectIDs.contains("LATENT_TEST_01"))

        let replay = try await promotedEngine.dispatch(promoteCommand, operationID: operationID, expectedRevision: 0)
        XCTAssertEqual(replay, promotion, "same operation ID must replay the original promotion receipt")
        let afterReplay = await promotedEngine.snapshot()
        XCTAssertEqual(afterReplay, promoted, "replay must not add a second latent, cost, or revision")

        do {
            _ = try await promotedEngine.dispatch(promoteCommand, operationID: UUID(), expectedRevision: promoted.revision)
            XCTFail("a second Q4 promotion should be rejected at the quality cap")
        } catch let error as CoreError {
            guard case .invalidCommand = error else { return XCTFail("unexpected error: \(error)") }
        }
        let afterRejectedRepromotion = await promotedEngine.snapshot()
        XCTAssertEqual(afterRejectedRepromotion, promoted)

        let reopened = try SaveRepository(fileURL: promotedURL)
        let restored = await reopened.snapshot()
        XCTAssertEqual(restored, promoted, "quality and latent identifier must survive file-backed reopen")
        let restoredGear = try XCTUnwrap(restored.gear.first(where: { $0.id == instanceID }))
        XCTAssertEqual(catalog.projectCombatant(for: "C_WITCH", with: [restoredGear]).attack, afterStats.attack)
        let restoredEngine = try GameEngine(catalog: catalog, saves: reopened)

        // Exercise the real committed encounter command path using the same seed and loadout.
        _ = try await baselineEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 91), operationID: UUID(), expectedRevision: 0)
        _ = try await restoredEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 91), operationID: UUID(), expectedRevision: promoted.revision)
        let baselineBattleSnapshot = await baselineEngine.snapshot()
        let promotedBattleSnapshot = await restoredEngine.snapshot()
        let baselineBattle = try XCTUnwrap(baselineBattleSnapshot.lastCombatResult)
        let promotedBattle = try XCTUnwrap(promotedBattleSnapshot.lastCombatResult)
        let baselineFirstStrike = try XCTUnwrap(baselineBattle.events.first(where: { $0.kind == "direct" && $0.sourceID == "C_WITCH" && $0.targetID == "E_R01_01" }))
        let promotedFirstStrike = try XCTUnwrap(promotedBattle.events.first(where: { $0.kind == "direct" && $0.sourceID == "C_WITCH" && $0.targetID == "E_R01_01" }))
        XCTAssertGreaterThan(promotedFirstStrike.amount, baselineFirstStrike.amount, "committed battle must use the promoted item's projected latent stats")
        XCTAssertEqual(promotedBattle.initialPartyHP["C_WITCH"], afterStats.maxHP)
    }
}
