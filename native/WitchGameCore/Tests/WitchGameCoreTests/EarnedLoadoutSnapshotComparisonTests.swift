import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Compares builds obtainable from preserved, completed actual-command saves.
/// It never writes to source saves; candidate swaps dispatch only in memory.
final class EarnedLoadoutSnapshotComparisonTests: XCTestCase {
    private struct SavedQAFile: Decodable { let snapshot: GameSnapshot }
    private struct GearPick: Encodable {
        let actorID: String
        let templateID: String
        let instanceID: String?
        let qualityID: String?
        let enhancement: Int?
        let eligibleAndOwned: Bool
    }
    private struct Row: Encodable {
        let sourceSave: String
        let sourceSaveSHA256: String
        let snapshotSHA256: String
        let sourceRevision: Int64
        let sourceRegion: String?
        let characterXP: [String: Int]
        let candidateGrowthBP: Int
        let candidateLevelsAtProfileBP: [String: Int]
        let build: String
        let buildAvailableFromOwnedInventory: Bool
        let gear: [GearPick]
        let blockingReason: String?
        let previewEnemyID: String
        let previewSeed: UInt64
        let won: Bool?
        let elapsedMs: Int?
        let survivors: Int?
        let remainingPartyHP: [String: Int]?
        let eventCounts: [String: Int]?
        let commandReceipt: String?
        let commandRevision: Int64?
        let engineProfile: String
    }
    private struct Report: Encodable {
        let schema: String
        let status: String
        let seedCohort: String
        let catalogSHA256: String
        let rows: [Row]
        let limitations: [String]
    }

    func testActualProgressionCheckpointsOnlyReequipExistingOwnedItems() async throws {
        guard let inputs = ProcessInfo.processInfo.environment["WITCH_EARNED_BUILD_SAVE_FILES"],
              let outputPath = ProcessInfo.processInfo.environment["WITCH_EARNED_BUILD_OUTPUT"] else {
            throw XCTSkip("Set WITCH_EARNED_BUILD_SAVE_FILES (semicolon-separated QA final-save files) and WITCH_EARNED_BUILD_OUTPUT")
        }
        let paths = inputs.split(separator: ";").map(String.init)
        XCTAssertFalse(paths.isEmpty)
        let catalog = try GameCatalog.bundledTestOverlay()
        let catalogData = try JSONEncoder.sorted.encode(catalog)
        let catalogSHA = digest(catalogData)
        let enemyID = "B_R05_B"
        let seed: UInt64 = 100_049
        let actors = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        let plans: [(String, [String]?)] = [
            ("saved_equipment", nil),
            ("poison_heal_pressure_chase", ["EQ_W_P2", "EQ_A_03", "EQ_S_02", "EQ_F_03"]),
            ("ward_reflect_heal_cover_chase", ["EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03"]),
            ("ward_heal_cover_mark", ["EQ_W_G1", "EQ_A_02", "EQ_S_03", "EQ_F_02"])
        ]
        var rows: [Row] = []

        for sourcePath in paths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let sourceData = try Data(contentsOf: sourceURL)
            let decoder = JSONDecoder()
            let original: GameSnapshot
            if let wrapper = try? decoder.decode(SavedQAFile.self, from: sourceData) { original = wrapper.snapshot }
            else { original = try decoder.decode(GameSnapshot.self, from: sourceData) }
            let snapshotData = try JSONEncoder.sorted.encode(original)
            let snapshotSHA = digest(snapshotData)
            XCTAssertTrue(original.unlockedRegionIDs.contains("R05"), "\(sourcePath) is not region-R05-unlocked")
            XCTAssertTrue(original.completedEncounterIDs.contains(enemyID), "\(sourcePath) did not clear \(enemyID)")

            for growthBP in [250, 500] {
            for (planName, templates) in plans {
                var picked: [GearPick] = []
                var selected: [(String, GearInstance)] = []
                var blocking: String? = nil
                if let templates {
                    for (actorID, templateID) in zip(actors, templates) {
                        guard let definition = catalog.gear.first(where: { $0.id == templateID }),
                              definition.actorIDs.isEmpty || definition.actorIDs.contains(actorID) else {
                            blocking = "template missing or actor incompatible: \(actorID)/\(templateID)"
                            picked.append(GearPick(actorID: actorID, templateID: templateID, instanceID: nil,
                                                   qualityID: nil, enhancement: nil, eligibleAndOwned: false))
                            continue
                        }
                        guard let item = original.gear.first(where: { $0.definitionID == templateID }) else {
                            blocking = "not available in saved inventory: \(templateID)"
                            picked.append(GearPick(actorID: actorID, templateID: templateID, instanceID: nil,
                                                   qualityID: nil, enhancement: nil, eligibleAndOwned: false))
                            continue
                        }
                        selected.append((actorID, item))
                        picked.append(GearPick(actorID: actorID, templateID: templateID, instanceID: item.id.uuidString,
                                               qualityID: item.qualityID, enhancement: item.enhancement,
                                               eligibleAndOwned: true))
                    }
                } else {
                    for actorID in actors {
                        guard let equippedID = original.equippedGearIDs[actorID + "|weapon"],
                              let item = original.gear.first(where: { $0.id == equippedID }) else { continue }
                        picked.append(GearPick(actorID: actorID, templateID: item.definitionID, instanceID: item.id.uuidString,
                                               qualityID: item.qualityID, enhancement: item.enhancement,
                                               eligibleAndOwned: true))
                    }
                }

                let available = templates == nil || (selected.count == actors.count && blocking == nil)
                if available {
                    let clone = try SaveRepository(initial: original)
                    let engine = try GameEngine(catalog: catalog, saves: clone,
                                                candidateCombatOverlay: .r014LocalCandidate,
                                                candidateCharacterGrowth: CandidateCharacterGrowth(strengthBP: growthBP))
                    if templates != nil {
                        for (actorID, item) in selected {
                            let current = await engine.snapshot()
                            _ = try await engine.dispatch(.equip(gearID: item.id, actorID: actorID),
                                operationID: UUID(), expectedRevision: current.revision)
                        }
                    }
                    let equippedSnapshot = await engine.snapshot()
                    for (actorID, templateID) in zip(actors, templates ?? picked.map(\.templateID)) {
                        guard let id = equippedSnapshot.equippedGearIDs[actorID + "|weapon"],
                              let item = equippedSnapshot.gear.first(where: { $0.id == id }) else {
                            blocking = "equipped slot missing for \(actorID)"
                            break
                        }
                        if templates != nil, item.definitionID != templateID {
                            blocking = "command did not equip expected template for \(actorID)"
                            break
                        }
                    }
                    if blocking == nil {
                        let commandReceipt = try await engine.dispatch(.resolveEncounter(enemyID: enemyID, seed: seed),
                            operationID: UUID(), expectedRevision: equippedSnapshot.revision)
                        let afterBattle = await engine.snapshot()
                        let result = try XCTUnwrap(afterBattle.lastCombatResult)
                        XCTAssertEqual(afterBattle.lastEncounterID, enemyID)
                        let observed = Dictionary(grouping: result.events.map(\.kind), by: { $0 }).mapValues(\.count)
                        rows.append(Row(sourceSave: sourceURL.lastPathComponent, sourceSaveSHA256: digest(sourceData),
                            snapshotSHA256: snapshotSHA, sourceRevision: original.revision, sourceRegion: original.activeRegionID, characterXP: original.characterXP,
                            candidateGrowthBP: growthBP,
                            candidateLevelsAtProfileBP: Dictionary(uniqueKeysWithValues: actors.map { ($0, CandidateCharacterGrowth.progress(totalXP: original.characterXP[$0, default: 0]).level) }),
                            build: planName, buildAvailableFromOwnedInventory: true, gear: picked, blockingReason: nil,
                            previewEnemyID: enemyID, previewSeed: seed, won: result.won,
                            elapsedMs: result.events.compactMap(\.timestampMs).max() ?? 0,
                            survivors: result.remainingPartyHP.values.filter { $0 > 0 }.count,
                            remainingPartyHP: result.remainingPartyHP, eventCounts: observed,
                            commandReceipt: commandReceipt.result, commandRevision: commandReceipt.revision, engineProfile: "app_candidate_R014_MAGNET_MARK_STRIKE_plus_R017_R2_RELATIVE_GROWTH_\(growthBP)BP_defaultCampaignScale"))
                    } else {
                        rows.append(Row(sourceSave: sourceURL.lastPathComponent, sourceSaveSHA256: digest(sourceData),
                            snapshotSHA256: snapshotSHA, sourceRevision: original.revision, sourceRegion: original.activeRegionID, characterXP: original.characterXP,
                            candidateGrowthBP: growthBP,
                            candidateLevelsAtProfileBP: Dictionary(uniqueKeysWithValues: actors.map { ($0, CandidateCharacterGrowth.progress(totalXP: original.characterXP[$0, default: 0]).level) }),
                            build: planName, buildAvailableFromOwnedInventory: false, gear: picked, blockingReason: blocking,
                            previewEnemyID: enemyID, previewSeed: seed, won: nil, elapsedMs: nil, survivors: nil,
                            remainingPartyHP: nil, eventCounts: nil, commandReceipt: nil, commandRevision: nil, engineProfile: "app_candidate_R014_MAGNET_MARK_STRIKE_plus_R017_R2_RELATIVE_GROWTH_\(growthBP)BP_defaultCampaignScale"))
                    }
                } else {
                    rows.append(Row(sourceSave: sourceURL.lastPathComponent, sourceSaveSHA256: digest(sourceData),
                        snapshotSHA256: snapshotSHA, sourceRevision: original.revision, sourceRegion: original.activeRegionID, characterXP: original.characterXP,
                        candidateGrowthBP: growthBP,
                        candidateLevelsAtProfileBP: Dictionary(uniqueKeysWithValues: actors.map { ($0, CandidateCharacterGrowth.progress(totalXP: original.characterXP[$0, default: 0]).level) }),
                        build: planName, buildAvailableFromOwnedInventory: false, gear: picked, blockingReason: blocking,
                        previewEnemyID: enemyID, previewSeed: seed, won: nil, elapsedMs: nil, survivors: nil,
                        remainingPartyHP: nil, eventCounts: nil, commandReceipt: nil, commandRevision: nil, engineProfile: "app_candidate_R014_MAGNET_MARK_STRIKE_plus_R017_R2_RELATIVE_GROWTH_\(growthBP)BP_defaultCampaignScale"))
                }
            }
            }
            XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData, "analysis must not alter preserved source saves")
        }

        let report = Report(schema: "earned_loadout_snapshot_comparison_r001",
                            status: "UNAPPROVED_TEST_OVERLAY",
                            seedCohort: "R025 actual-command free/no-ad strategy checkpoints at days 30 and 90; in-memory actual combat commands reuse owned gear instances",
                            catalogSHA256: catalogSHA, rows: rows,
                            limitations: [
                                "Only existing saved inventory is used. Alternate loadouts are equipped by real GameEngine commands in separate in-memory repositories; source files are read-only and re-hashed.",
                                "The three current inputs are passive_control, free_ward, and free_poison; passive_control intentionally skips targeted investment and daily free-summon policy, so it is a lower-activity control rather than a representative engaged player. The two active strategies share the same scripted virtual-day cadence.",
                                "Combat uses actual .resolveEncounter dispatch with the app candidate composition: R014_MAGNET_MARK_STRIKE overlay and R017 relative-growth 500BP. B_R05_B is not the overlay target, so this comparison measures actual campaign-scale stats and gear, not the R014 magnet mechanic.",
                                "This is not the fixed-point canonical R6 QA profile; that profile is a separate reference matrix. No claim of exact R6 parity is made.",
                                "Combat is dispatched through .resolveEncounter on an in-memory clone, so it exercises actual candidate campaign calculations and reward commit without touching the saved source checkpoint. Repeated-command reward semantics are test-clone only.",
                                "Each snapshot uses one paired enemy and seed 100049. This is a bounded sensitivity check, not balance acceptance or player experience evidence."
                            ])
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.sorted.encode(report).write(to: outputURL, options: .atomic)
        print("EARNED_LOADOUT_SNAPSHOT_MATRIX,\(outputURL.path),rows=\(rows.count),catalog=\(catalogSHA)")
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
