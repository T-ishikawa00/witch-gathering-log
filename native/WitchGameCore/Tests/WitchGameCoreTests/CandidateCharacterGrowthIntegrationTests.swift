import Foundation
import XCTest
@testable import WitchGameCore

final class CandidateCharacterGrowthIntegrationTests: XCTestCase {
    func testR2ThresholdBoundariesCapSurplusAndIntMax() {
        var thresholds = [0]
        for level in 1..<CandidateCharacterGrowth.levelCap {
            let step = level - 1
            thresholds.append(thresholds.last! + 100 + 30 * step + 4 * step * step)
        }
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: -1).level, 1)
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: 99).level, 1)
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: 100), .init(level: 2, totalXP: 100, xpIntoLevel: 0, xpToNextLevel: 134, levelStartXP: 100))
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: 101).xpIntoLevel, 1)
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: thresholds[59] - 1).level, 59)
        let atCap = CandidateCharacterGrowth.progress(totalXP: thresholds[59])
        XCTAssertEqual(atCap.level, 60)
        XCTAssertNil(atCap.xpToNextLevel)
        XCTAssertEqual(atCap.xpIntoLevel, 0)
        let surplus = CandidateCharacterGrowth.progress(totalXP: thresholds[59] + 12_345)
        XCTAssertEqual(surplus.level, 60)
        XCTAssertEqual(surplus.xpIntoLevel, 12_345, "surplus XP stays recorded after the level cap")
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: Int.max).level, 60)
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: Int.max).totalXP, Int.max)
    }

    func testCandidateProfilesScaleAllActorsBeforeGearAndPreserveGuardChance() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let source: [String: (Int, Int, Int, Int, Int, Int)] = [
            "C_WITCH": (420, 38, 28, 32, 4, 4),
            "C_APPRENTICE": (360, 30, 26, 28, 3, 4),
            "C_SMITH": (620, 28, 52, 44, 3, 6),
            "C_FAMILIAR": (390, 32, 30, 30, 3, 4)
        ]
        let xp = 1_000_000
        let level = CandidateCharacterGrowth.progress(totalXP: xp).level
        for (actorID, values) in source {
            let gear: [GearInstance] = []
            let baseline = catalog.projectCombatant(for: actorID, with: gear)
            let control = catalog.projectCombatant(for: actorID, with: gear, totalXP: xp, candidateGrowth: .zeroStatControl)
            XCTAssertEqual(control, baseline, "0 BP must exactly preserve (actorID) control stats")
            let quarter = catalog.projectCombatant(for: actorID, with: gear, totalXP: xp, candidateGrowth: .quarterRelativeR2)
            let full = catalog.projectCombatant(for: actorID, with: gear, totalXP: xp, candidateGrowth: .fullRelativeR2)
            let steps = level - 1
            func expected(_ native: Int, _ sourceBase: Int, _ gain: Int, _ bp: Int) -> Int {
                native + (native * gain * steps * bp) / (sourceBase * 10_000)
            }
            XCTAssertEqual(full.maxHP, expected(baseline.maxHP, values.0, values.3, 10_000), "full R2 HP (actorID)")
            XCTAssertEqual(full.attack, expected(baseline.attack, values.1, values.4, 10_000), "full R2 attack (actorID)")
            XCTAssertEqual(full.defense, expected(baseline.defense, values.2, values.5, 10_000), "full R2 defense (actorID)")
            XCTAssertEqual(quarter.maxHP, expected(baseline.maxHP, values.0, values.3, 2_500), "quarter R2 HP (actorID)")
            XCTAssertEqual(quarter.attack, expected(baseline.attack, values.1, values.4, 2_500), "quarter R2 attack (actorID)")
            XCTAssertEqual(quarter.defense, expected(baseline.defense, values.2, values.5, 2_500), "quarter R2 defense (actorID)")
            XCTAssertEqual(full.guardChanceBP, baseline.guardChanceBP, "growth must not alter actor guard chance")
        }
        let witchWeapon = [GearInstance(definitionID: "EQ_W_01", ownerID: "C_WITCH")]
        let noGearFull = catalog.projectCombatant(for: "C_WITCH", with: [], totalXP: xp, candidateGrowth: .fullRelativeR2)
        let withGearFull = catalog.projectCombatant(for: "C_WITCH", with: witchWeapon, totalXP: xp, candidateGrowth: .fullRelativeR2)
        let noGearBase = catalog.projectCombatant(for: "C_WITCH", with: [])
        let withGearBase = catalog.projectCombatant(for: "C_WITCH", with: witchWeapon)
        XCTAssertEqual(withGearFull.attack - noGearFull.attack, withGearBase.attack - noGearBase.attack,
                       "candidate level base must be projected before additive gear bonuses")
        XCTAssertEqual(withGearFull.maxHP - noGearFull.maxHP, withGearBase.maxHP - noGearBase.maxHP)
    }

    func testGatherXPProjectsIntoActualBattleAndSurvivesSaveReopenWithoutDoubleGain() async throws {
        let base = try GameCatalog.bundledTestOverlay()
        let regions = base.regions.map { region in
            RegionDefinition(id: region.id, name: region.name, enemyIDs: region.enemyIDs, gatherMaterialIDs: region.gatherMaterialIDs,
                xpPerWork: region.id == "R01" ? 100 : region.xpPerWork, dustPerWork: 0,
                workSeconds: region.id == "R01" ? 1 : region.workSeconds)
        }
        let catalog = GameCatalog(version: base.version, regions: regions, enemies: base.enemies, gear: base.gear,
            research: base.research, materialIDs: base.materialIDs, recipes: base.recipes, actorIDs: base.actorIDs,
            challenges: base.challenges, researchEffects: base.researchEffects, appearances: base.appearances,
            furnitureIDs: base.furnitureIDs)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-growth-\(UUID().uuidString).json")
        defer {
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
            let lockURL = url.appendingPathExtension("lock")
            if FileManager.default.fileExists(atPath: lockURL.path) { try? FileManager.default.removeItem(at: lockURL) }
        }
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.lastClaimAt = epoch
        let store = try SaveRepository(initial: initial, fileURL: url)
        let growth = CandidateCharacterGrowth(strengthBP: 10_000)
        let engine = try GameEngine(catalog: catalog, saves: store, candidateCharacterGrowth: growth)
        _ = try await engine.claimOffline(now: epoch.addingTimeInterval(1), secondsPerUnit: 1, cap: 1,
            operationID: UUID(), expectedRevision: 0)
        let gained = await engine.snapshot()
        XCTAssertEqual(gained.characterXP["C_WITCH"], 100)
        XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: gained.characterXP["C_WITCH"] ?? 0).level, 2)

        _ = try await engine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 81), operationID: UUID(), expectedRevision: gained.revision)
        let afterBattle = await engine.snapshot()
        let firstResult = try XCTUnwrap(afterBattle.lastCombatResult)
        let expectedInitial = catalog.projectCombatant(for: "C_WITCH", with: initial.gear, totalXP: 100, candidateGrowth: growth)
        XCTAssertEqual(firstResult.initialPartyHP["C_WITCH"], expectedInitial.maxHP, "the committed battle must use XP-projected HP")
        let controlEngine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: gained))
        _ = try await controlEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 81), operationID: UUID(), expectedRevision: gained.revision)
        let controlSnapshot = await controlEngine.snapshot()
        let controlResult = try XCTUnwrap(controlSnapshot.lastCombatResult)
        XCTAssertGreaterThan(firstResult.initialPartyHP["C_WITCH"] ?? 0, controlResult.initialPartyHP["C_WITCH"] ?? 0)
        let projectedHit = try XCTUnwrap(firstResult.events.first(where: { $0.sourceID == "C_WITCH" && $0.kind == "direct" }))
        let controlHit = try XCTUnwrap(controlResult.events.first(where: { $0.sourceID == "C_WITCH" && $0.kind == "direct" }))
        XCTAssertGreaterThan(projectedHit.amount, controlHit.amount, "the committed battle must use XP-projected attack as well as HP")

        let xpBeforeReopen = afterBattle.characterXP
        let reopened = try SaveRepository(fileURL: url)
        let reopenedSnapshot = await reopened.snapshot()
        XCTAssertEqual(reopenedSnapshot, afterBattle)
        XCTAssertEqual(reopenedSnapshot.characterXP, xpBeforeReopen)
        let reopenedEngine = try GameEngine(catalog: catalog, saves: reopened, candidateCharacterGrowth: growth)
        _ = try await reopenedEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 81), operationID: UUID(), expectedRevision: reopenedSnapshot.revision)
        let afterSecondBattle = await reopenedEngine.snapshot()
        XCTAssertEqual(afterSecondBattle.characterXP, xpBeforeReopen, "battle replay must not grant gathering XP again")
        XCTAssertEqual(afterSecondBattle.lastCombatResult?.initialPartyHP["C_WITCH"], firstResult.initialPartyHP["C_WITCH"])
    }

    func testFiveHundredBPActualClaimProjectsAllFourThroughBattleAndReopenOnce() async throws {
        let base = try GameCatalog.bundledTestOverlay()
        let regions = base.regions.map { region in
            RegionDefinition(id: region.id, name: region.name, enemyIDs: region.enemyIDs, gatherMaterialIDs: region.gatherMaterialIDs,
                xpPerWork: region.id == "R01" ? 1_000 : region.xpPerWork, dustPerWork: 0,
                workSeconds: region.id == "R01" ? 1 : region.workSeconds)
        }
        let catalog = GameCatalog(version: base.version, regions: regions, enemies: base.enemies, gear: base.gear,
            research: base.research, materialIDs: base.materialIDs, recipes: base.recipes, actorIDs: base.actorIDs,
            challenges: base.challenges, researchEffects: base.researchEffects, appearances: base.appearances,
            furnitureIDs: base.furnitureIDs)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("witch-growth-500-\(UUID().uuidString).json")
        defer {
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
            let lockURL = url.appendingPathExtension("lock")
            if FileManager.default.fileExists(atPath: lockURL.path) { try? FileManager.default.removeItem(at: lockURL) }
        }

        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.lastClaimAt = epoch
        let store = try SaveRepository(initial: initial, fileURL: url)
        let profile = CandidateCharacterGrowth(strengthBP: 500)
        let engine = try GameEngine(catalog: catalog, saves: store, candidateCharacterGrowth: profile)
        let claimID = UUID()
        let firstClaim = try await engine.claimOffline(now: epoch.addingTimeInterval(20), secondsPerUnit: 1, cap: 20,
            operationID: claimID, expectedRevision: 0)
        let afterClaim = await engine.snapshot()
        XCTAssertEqual(afterClaim.revision, 1)
        XCTAssertEqual(Set(afterClaim.partyActorIDs), Set(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]))
        for actorID in afterClaim.partyActorIDs {
            XCTAssertEqual(afterClaim.characterXP[actorID], 20_000, "actual gathered work grants equal XP to each present actor")
            XCTAssertEqual(CandidateCharacterGrowth.progress(totalXP: afterClaim.characterXP[actorID] ?? 0).level,
                           CandidateCharacterGrowth.progress(totalXP: 20_000).level)
        }

        // A retry with the same operation identity must replay the receipt without a second XP award.
        let replay = try await engine.claimOffline(now: epoch.addingTimeInterval(20), secondsPerUnit: 1, cap: 20,
            operationID: claimID, expectedRevision: 0)
        let afterReplay = await engine.snapshot()
        XCTAssertEqual(replay, firstClaim)
        XCTAssertEqual(afterReplay, afterClaim)

        let reopened = try SaveRepository(fileURL: url)
        let reopenedSnapshot = await reopened.snapshot()
        XCTAssertEqual(reopenedSnapshot, afterClaim)
        let reopenedEngine = try GameEngine(catalog: catalog, saves: reopened, candidateCharacterGrowth: profile)
        let operation = UUID()
        _ = try await reopenedEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 581), operationID: operation,
            expectedRevision: reopenedSnapshot.revision)
        let afterBattle = await reopenedEngine.snapshot()
        let result = try XCTUnwrap(afterBattle.lastCombatResult)
        XCTAssertEqual(result.initialPartyHP.count, 4)
        for actorID in afterBattle.partyActorIDs {
            let equipped = afterBattle.equippedGearIDs
                .filter { $0.key.hasPrefix(actorID + "|") }
                .compactMap { _, instanceID in afterBattle.gear.first(where: { $0.id == instanceID }) }
            let projected = catalog.projectCombatant(for: actorID, with: equipped,
                completedResearchIDs: afterBattle.completedResearchIDs, totalXP: 20_000, candidateGrowth: profile)
            XCTAssertEqual(result.initialPartyHP[actorID], projected.maxHP, "actual committed battle must use the selected profile for every actor")
        }
        XCTAssertEqual(afterBattle.characterXP, afterClaim.characterXP, "battle resolution does not award gather XP")

        let controlStore = try SaveRepository(initial: afterClaim)
        let controlEngine = try GameEngine(catalog: catalog, saves: controlStore)
        _ = try await controlEngine.dispatch(.resolveEncounter(enemyID: "E_R01_01", seed: 581), operationID: UUID(),
            expectedRevision: afterClaim.revision)
        let controlSnapshot = await controlEngine.snapshot()
        let control = try XCTUnwrap(controlSnapshot.lastCombatResult)
        XCTAssertEqual(control.initialPartyHP.count, 4)
        XCTAssertNotEqual(result.initialPartyHP, control.initialPartyHP, "500 BP must affect the actual projected party at this attained level")
        XCTAssertNotEqual(result.events.filter { $0.sourceID == "C_WITCH" && $0.kind == "direct" }.map(\.amount),
                          control.events.filter { $0.sourceID == "C_WITCH" && $0.kind == "direct" }.map(\.amount),
                          "combat must use the profile's projected attack, not only display a level")

        let finalReopen = try SaveRepository(fileURL: url)
        let finalSnapshot = await finalReopen.snapshot()
        XCTAssertEqual(finalSnapshot, afterBattle)
        XCTAssertEqual(finalSnapshot.characterXP, afterClaim.characterXP)
        XCTAssertEqual(finalSnapshot.lastCombatResult?.initialPartyHP, result.initialPartyHP)
    }
}
