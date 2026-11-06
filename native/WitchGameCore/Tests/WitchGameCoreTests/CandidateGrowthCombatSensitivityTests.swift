import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Read-only paired previews using real, command-earned E2E snapshots. No
/// command is dispatched and no reward/save state is changed by this comparison.
final class CandidateGrowthCombatSensitivityTests: XCTestCase {
    private struct ActorStats: Encodable {
        let id: String, hp: Int, attack: Int, defense: Int, xp: Int, level: Int
        let growthDeltaHP: Int, growthDeltaAttack: Int, growthDeltaDefense: Int
        let gearDeltaHP: Int, gearDeltaAttack: Int, gearDeltaDefense: Int
    }
    private struct ResultRow: Encodable {
        let checkpointDay: Int, regionID: String, loadout: String, encounterKind: String, encounterID: String
        let profileID: String, strengthBP: Int, actors: [ActorStats]
        let won: Bool, ticks: Int, initialPartyHP: [String: Int], remainingPartyHP: [String: Int]
        let initialEnemyHP: [String: Int], remainingEnemyHP: [String: Int]
        let fixtureSHA256: String, previewSeed: UInt64
    }
    private struct ProfileAssessment: Encodable {
        let loadout: String, strengthBP: Int, encounterCount: Int, ttkComparableCount: Int
        let medianTTShorteningPercent: Double, everyPreviewWon: Bool
        let positiveGrowthStatComponents: Int, partyGearAttackDeltaMin: Int, partyGearAttackDeltaMax: Int
    }
    private struct Report: Encodable {
        let schema: String, approval: String, mode: String, evaluatedStrengthBP: [Int]
        let ttShorteningCriterionPercent: Double, rows: [ResultRow], assessment: [ProfileAssessment]
        let sourceFilesSHA256: [String: String]
        let constraints: [String]
    }

    func testPairedCampaignBossAndChallengeAtSavedProgressionCheckpoints() async throws {
        guard let snapshotDirectory = ProcessInfo.processInfo.environment["WITCH_GROWTH_SENSITIVITY_SNAPSHOT_DIR"] else {
            throw XCTSkip("set WITCH_GROWTH_SENSITIVITY_SNAPSHOT_DIR to a completed actual-command E2E combat_checkpoints folder")
        }
        guard let outputPath = ProcessInfo.processInfo.environment["WITCH_GROWTH_SENSITIVITY_OUTPUT"] else {
            throw XCTSkip("set WITCH_GROWTH_SENSITIVITY_OUTPUT to save the paired preview report")
        }
        let catalog = try GameCatalog.bundledTestOverlay()
        let snapshotRoot = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let strengths = try requestedStrengths()
        let profiles = strengths.map(CandidateCharacterGrowth.init(strengthBP:))
        var rows: [ResultRow] = []

        for day in [1, 7, 14, 21] {
            let fixtureURL = snapshotRoot.appendingPathComponent(String(format: "snapshot_day_%02d.json", day))
            let fixtureData = try Data(contentsOf: fixtureURL)
            let fixtureSHA = SHA256.hash(data: fixtureData).map { String(format: "%02x", $0) }.joined()
            let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: fixtureData)
            guard let regionID = snapshot.activeRegionID,
                  let region = catalog.regions.first(where: { $0.id == regionID }) else {
                XCTFail("checkpoint day \(day) has no active catalog region")
                continue
            }
            let bossID = region.enemyIDs.first(where: { $0.hasSuffix("_A") && $0.hasPrefix("B_") })
                ?? region.enemyIDs.last!
            let challengeID = catalog.challenges.first(where: { $0.region == regionID })?.id
            var starterStressSnapshot = snapshot
            let freshStarter = GameSnapshot.newGame(catalog: catalog)
            starterStressSnapshot.gear = freshStarter.gear
            starterStressSnapshot.equippedGearIDs = freshStarter.equippedGearIDs
            XCTAssertEqual(starterStressSnapshot.characterXP, snapshot.characterXP)
            XCTAssertEqual(starterStressSnapshot.completedResearchIDs, snapshot.completedResearchIDs)
            XCTAssertEqual(starterStressSnapshot.gear.count, 4, "stress profile uses only the four canonical starter pieces")
            let starterEncoder = JSONEncoder(); starterEncoder.outputFormatting = [.sortedKeys]
            let starterData = try starterEncoder.encode(starterStressSnapshot)
            let starterSHA = SHA256.hash(data: starterData).map { String(format: "%02x", $0) }.joined()

            for profile in profiles {
                // Keep the simulation seed paired across profiles; only the
                // projected party statistics may vary.
                let seed = UInt64(0x47524F5700000000) &+ UInt64(day * 10_000)
                for (loadout, combatSnapshot, inputSHA) in [("saved_loadout", snapshot, fixtureSHA),
                                                              ("starter_equipment_stress", starterStressSnapshot, starterSHA)] {
                    let memoryStore = try SaveRepository(initial: combatSnapshot)
                    let engine = try GameEngine(catalog: catalog, saves: memoryStore, candidateCharacterGrowth: profile)
                    let party = projectedParty(snapshot: combatSnapshot, catalog: catalog, profile: profile)
                    let actorStats = party.map { combatant in
                        let xp = combatSnapshot.characterXP[combatant.id, default: 0]
                        let equipped = combatSnapshot.equippedGearIDs.filter { $0.key.hasPrefix(combatant.id + "|") }
                            .compactMap { _, id in combatSnapshot.gear.first(where: { $0.id == id }) }
                        let withNoGear = catalog.projectCombatant(for: combatant.id, with: [],
                            completedResearchIDs: combatSnapshot.completedResearchIDs,
                            totalXP: xp, candidateGrowth: profile)
                        let withBaselineGrowth = catalog.projectCombatant(for: combatant.id, with: equipped,
                            completedResearchIDs: combatSnapshot.completedResearchIDs, totalXP: xp,
                            candidateGrowth: CandidateCharacterGrowth(strengthBP: 0))
                        return ActorStats(id: combatant.id, hp: combatant.maxHP, attack: combatant.attack,
                            defense: combatant.defense, xp: xp, level: CandidateCharacterGrowth.progress(totalXP: xp).level,
                            growthDeltaHP: combatant.maxHP - withBaselineGrowth.maxHP,
                            growthDeltaAttack: combatant.attack - withBaselineGrowth.attack,
                            growthDeltaDefense: combatant.defense - withBaselineGrowth.defense,
                            gearDeltaHP: combatant.maxHP - withNoGear.maxHP,
                            gearDeltaAttack: combatant.attack - withNoGear.attack,
                            gearDeltaDefense: combatant.defense - withNoGear.defense)
                    }
                    let campaign = try await engine.previewCampaignEncounterDefaultQA(enemyID: bossID, seed: seed,
                        snapshot: combatSnapshot, maxDurationMs: 120_000)
                    rows.append(ResultRow(checkpointDay: day, regionID: regionID, loadout: loadout,
                        encounterKind: "campaign_boss", encounterID: bossID, profileID: profile.id,
                        strengthBP: profile.strengthBP, actors: actorStats, won: campaign.won, ticks: campaign.ticks,
                        initialPartyHP: campaign.initialPartyHP, remainingPartyHP: campaign.remainingPartyHP,
                        initialEnemyHP: campaign.initialEnemyHP, remainingEnemyHP: campaign.remainingEnemyHP,
                        fixtureSHA256: inputSHA, previewSeed: seed))

                    if let challengeID {
                        let scenario = try catalog.challengeCombatScenario(challengeID)
                        let challenge = try R6TimelineSimulator.run(party: party, enemies: scenario.enemies,
                            seed: seed &+ 1, maxDurationMs: 120_000, challengeID: challengeID,
                            entityPresentation: scenario.entityPresentation)
                        rows.append(ResultRow(checkpointDay: day, regionID: regionID, loadout: loadout,
                            encounterKind: "challenge_candidate_preview", encounterID: challengeID,
                            profileID: profile.id, strengthBP: profile.strengthBP, actors: actorStats,
                            won: challenge.won, ticks: challenge.ticks,
                            initialPartyHP: challenge.initialPartyHP, remainingPartyHP: challenge.remainingPartyHP,
                            initialEnemyHP: challenge.initialEnemyHP, remainingEnemyHP: challenge.remainingEnemyHP,
                            fixtureSHA256: inputSHA, previewSeed: seed &+ 1))
                    }
                    let afterPreview = await memoryStore.snapshot()
                    XCTAssertEqual(afterPreview, combatSnapshot, "read-only preview mutated day-\(day)/\(loadout) snapshot for \(profile.id)")
                }
            }
        }
        XCTAssertEqual(rows.count, 4 * profiles.count * 2 * 2, "expected boss/challenge for each checkpoint, loadout, and profile")
        let assessments = makeAssessments(rows: rows, strengths: strengths)
        let sourceRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WITCH_SOURCE_ROOT"] ?? FileManager.default.currentDirectoryPath)
        let sourcePaths = ["Sources/WitchGameCore/Domain.swift", "Sources/WitchGameCore/GameEngine.swift",
            "Sources/WitchGameCore/R6TimelineSimulator.swift", "Sources/WitchGameCore/CandidateCharacterGrowth.swift",
            "Tests/WitchGameCoreTests/CandidateGrowthCombatSensitivityTests.swift"]
        var sourceHashes: [String: String] = [:]
        for path in sourcePaths {
            let url = sourceRoot.appendingPathComponent(path)
            sourceHashes[path] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        let report = Report(schema: "candidate_growth_paired_combat_sensitivity_r002",
            approval: "UNAPPROVED_TEST_OVERLAY",
            mode: "Paired saved progression snapshot across injected derived-stat profiles; second synthetic stress snapshot keeps XP/research/progression and substitutes four canonical starter gear instances.",
            evaluatedStrengthBP: strengths, ttShorteningCriterionPercent: 25,
            rows: rows, assessment: assessments, sourceFilesSHA256: sourceHashes,
            constraints: [
                "Snapshots were persisted and reopened by the 90-day GameEngine E2E runner; no combat outcome or inventory was seeded.",
                "starter_equipment_stress is an intentionally synthetic diagnostic snapshot, not a claim about a valid user-earnable save path.",
                "These are read-only R6Timeline previews, not committed battles, rewards, progression, or human playtests.",
                "Challenge previews call catalog.challengeCombatScenario directly and do not bypass or claim the actual challenge unlock gate.",
                "The 25 percent median time-to-win shortening threshold is a parent-selected experiment criterion, not approved game design.",
                "All requested basis-point profiles are comparison candidates only; none is formally adopted.",
                "The test asserts save snapshot immutability, but does not decide which growth ratio is balanced or fun."
            ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputURL, options: .atomic)
        print("GROWTH_COMBAT_SENSITIVITY_REPORT,\(outputURL.path),rows=\(rows.count)")
    }

    private func projectedParty(snapshot: GameSnapshot, catalog: GameCatalog,
                                profile: CandidateCharacterGrowth) -> [Combatant] {
        snapshot.partyActorIDs.map { actorID in
            let instances = snapshot.equippedGearIDs.filter { $0.key.hasPrefix(actorID + "|") }
                .compactMap { _, instanceID in snapshot.gear.first(where: { $0.id == instanceID }) }
            return catalog.projectCombatant(for: actorID, with: instances,
                completedResearchIDs: snapshot.completedResearchIDs,
                totalXP: snapshot.characterXP[actorID, default: 0], candidateGrowth: profile)
        }
    }

    private func requestedStrengths() throws -> [Int] {
        let raw = ProcessInfo.processInfo.environment["WITCH_GROWTH_SENSITIVITY_BPS"]
        let values: [Int]
        if let raw {
            let pieces = raw.split(separator: ",")
            let parsed = pieces.compactMap { Int(String($0).trimmingCharacters(in: .whitespaces)) }
            guard parsed.count == pieces.count, parsed.count <= 21,
                  parsed.allSatisfy({ (0...10_000).contains($0) }), Set(parsed).count == parsed.count else {
                throw NSError(domain: "GrowthSensitivity", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "WITCH_GROWTH_SENSITIVITY_BPS must be unique comma-separated integers from 0 through 10000 (max 21 values)"])
            }
            values = parsed
        } else {
            values = [0, 250, 500, 750, 1_000, 2_500, 10_000]
        }
        return Array(Set(values + [0])).sorted()
    }

    private func makeAssessments(rows: [ResultRow], strengths: [Int]) -> [ProfileAssessment] {
        let loadouts = Array(Set(rows.map(\.loadout))).sorted()
        var output: [ProfileAssessment] = []
        for loadout in loadouts {
            let baselineRows = rows.filter { $0.loadout == loadout && $0.strengthBP == 0 }
            let baselineByEncounter = Dictionary(uniqueKeysWithValues: baselineRows.map {
                ("\($0.checkpointDay)|\($0.encounterKind)|\($0.encounterID)", $0)
            })
            for strength in strengths {
                let candidateRows = rows.filter { $0.loadout == loadout && $0.strengthBP == strength }
                let deltas: [Double] = candidateRows.compactMap { row in
                    let key = "\(row.checkpointDay)|\(row.encounterKind)|\(row.encounterID)"
                    guard let baseline = baselineByEncounter[key], baseline.won, row.won, baseline.ticks > 0 else { return nil }
                    return Double(baseline.ticks - row.ticks) / Double(baseline.ticks) * 100
                }
                let sorted = deltas.sorted()
                let median: Double
                if sorted.isEmpty { median = 0 }
                else if sorted.count.isMultiple(of: 2) { median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 }
                else { median = sorted[sorted.count / 2] }
                let statRows = candidateRows.filter { $0.encounterKind == "campaign_boss" }
                let positiveComponents = statRows.flatMap(\.actors).reduce(into: 0) { total, actor in
                    total += [actor.growthDeltaHP, actor.growthDeltaAttack, actor.growthDeltaDefense].filter { $0 > 0 }.count
                }
                let gearAttack = candidateRows.map { $0.actors.reduce(0) { $0 + $1.gearDeltaAttack } }
                output.append(ProfileAssessment(loadout: loadout, strengthBP: strength,
                    encounterCount: candidateRows.count, ttkComparableCount: deltas.count, medianTTShorteningPercent: median,
                    everyPreviewWon: candidateRows.count == 8 && candidateRows.allSatisfy(\.won),
                    positiveGrowthStatComponents: positiveComponents,
                    partyGearAttackDeltaMin: gearAttack.min() ?? 0, partyGearAttackDeltaMax: gearAttack.max() ?? 0))
            }
        }
        return output
    }
}
