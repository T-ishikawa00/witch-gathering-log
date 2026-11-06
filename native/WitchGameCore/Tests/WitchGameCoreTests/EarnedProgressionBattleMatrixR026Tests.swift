import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// 6 preserved earned snapshots x 4 legal gear plans x 6 authored battles x 3 seeds.
/// Every battle runs through GameEngine.dispatch on a disposable in-memory repository.
final class EarnedProgressionBattleMatrixR026Tests: XCTestCase {
    private struct Battle: Encodable {
        let kind: String
        let id: String
        let regionID: String?
    }
    private struct Plan: Encodable {
        let id: String
        let templates: [String]?
    }
    private struct GearRecord: Encodable {
        let actorID: String
        let definitionID: String?
        let instanceID: String?
        let qualityID: String?
        let enhancement: Int?
        let refinement: Int?
        let affixIDs: [String]?
        let latentEffectID: String?
    }
    private struct Row: Encodable {
        let sourceKey: String
        let sourcePath: String
        let sourceFileSHA256: String
        let sourceSnapshotSHA256: String
        let sourceRevision: Int64
        let sourceDay: Int
        let strategy: String
        let battleKind: String
        let battleID: String
        let seed: UInt64
        let outcome: String
        let reason: String?
        let gear: [GearRecord]
        let commandReceipts: [String]
        let finalRevision: Int64?
        let ticks: Int?
        let elapsedMs: Int?
        let remainingPartyHP: [String: Int]?
        let survivors: Int?
        let eventCounts: [String: Int]?
        let currencyDelta: [String: Int]?
        let materialDelta: [String: Int]?
        let postBattleSnapshotSHA256: String?
    }
    private struct Source: Encodable {
        let key: String
        let path: String
        let fileSHA256: String
        let snapshotSHA256: String
        let revision: Int64
        let day: Int
        let strategy: String
        let gearCount: Int
        let equippedSlots: Int
    }
    private struct Report: Encodable {
        let schema: String
        let status: String
        let formalAdoption: Bool
        let runtimeChanged: Bool
        let candidateConfig: String
        let buildPlans: [Plan]
        let battles: [Battle]
        let seeds: [UInt64]
        let sources: [Source]
        let rows: [Row]
        let outcomeCounts: [String: Int]
        let limitations: [String]
    }
    private struct Input: Decodable { let snapshot: GameSnapshot? }

    func testSixEarnedSavesFourPlansSixBattlesThreeSeeds() async throws {
        guard let inputValue = ProcessInfo.processInfo.environment["WITCH_R026_INPUTS"],
              let outputPath = ProcessInfo.processInfo.environment["WITCH_R026_OUTPUT"] else {
            throw XCTSkip("Set WITCH_R026_INPUTS as six key|strategy|day|path records separated by semicolon and WITCH_R026_OUTPUT")
        }
        let inputs = inputValue.split(separator: ";").compactMap { record -> (String, String, Int, String)? in
            let fields = record.split(separator: "|", maxSplits: 3).map(String.init)
            guard fields.count == 4, let day = Int(fields[2]) else { return nil }
            return (fields[0], fields[1], day, fields[3])
        }
        XCTAssertEqual(inputs.count, 6, "Exactly six preserved snapshots are required")

        let catalog = try GameCatalog.bundledTestOverlay()
        let catalogSHA = sha256(try JSONEncoder.r026.encode(catalog))
        let actors = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        let plans: [Plan] = [
            Plan(id: "saved_equipment", templates: nil),
            Plan(id: "poison_heal_pressure_chase", templates: ["EQ_W_P2", "EQ_A_03", "EQ_S_02", "EQ_F_03"]),
            Plan(id: "ward_reflect_heal_cover_chase", templates: ["EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03"]),
            Plan(id: "ward_heal_cover_mark", templates: ["EQ_W_G1", "EQ_A_02", "EQ_S_03", "EQ_F_02"])
        ]
        let battles: [Battle] = [
            Battle(kind: "campaign_boss", id: "B_R01_B", regionID: "R01"),
            Battle(kind: "campaign_boss", id: "B_R03_B", regionID: "R03"),
            Battle(kind: "campaign_boss", id: "B_R05_B", regionID: "R05"),
            Battle(kind: "challenge", id: "CH_R02_03", regionID: nil),
            Battle(kind: "challenge", id: "CH_R03_03", regionID: nil),
            Battle(kind: "challenge", id: "CH_R05_02", regionID: nil)
        ]
        let seeds: [UInt64] = [100_049, 100_069, 100_097]
        var sources: [Source] = []
        var rows: [Row] = []

        for (sourceKey, strategy, day, path) in inputs {
            let url = URL(fileURLWithPath: path)
            let bytes = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(GameSnapshot.self, from: bytes)
            let snapshotHash = sha256(try JSONEncoder.r026.encode(decoded))
            XCTAssertTrue(decoded.unlockedRegionIDs.contains("R05"), "Required all-region gate missing: \(sourceKey)/day\(day)")
            XCTAssertTrue(decoded.completedEncounterIDs.contains("B_R05_B"), "R05 boss progression is not complete: \(sourceKey)/day\(day)")
            sources.append(Source(key: sourceKey, path: path, fileSHA256: sha256(bytes), snapshotSHA256: snapshotHash,
                                  revision: decoded.revision, day: day, strategy: strategy,
                                  gearCount: decoded.gear.count, equippedSlots: decoded.equippedGearIDs.count))

            for plan in plans {
                let picks = selectGear(plan: plan, snapshot: decoded, catalog: catalog, actors: actors)
                for battle in battles {
                    for seed in seeds {
                        let originalBytes = try Data(contentsOf: url)
                        let clone = try SaveRepository(initial: decoded)
                        let engine = try GameEngine(catalog: catalog, saves: clone,
                            candidateCombatOverlay: .r014LocalCandidate,
                            candidateCharacterGrowth: CandidateCharacterGrowth(strengthBP: 500))
                        var receipts: [String] = []
                        var reason: String? = picks.reason
                        var outcome = "UNAVAILABLE"
                        var result: CombatResult? = nil
                        var final: GameSnapshot? = nil

                        if reason == nil, picks.items.count == 4 {
                            do {
                                for (actorID, item) in picks.items {
                                    let before = await engine.snapshot()
                                    let receipt = try await engine.dispatch(.equip(gearID: item.id, actorID: actorID),
                                        operationID: UUID(), expectedRevision: before.revision)
                                    receipts.append(receipt.result)
                                }
                                var beforeBattle = await engine.snapshot()
                                if let regionID = battle.regionID {
                                    let regionReceipt = try await engine.dispatch(
                                        .startExpeditionAt(regionID: regionID, now: laterThan(beforeBattle.lastClaimAt)),
                                        operationID: UUID(), expectedRevision: beforeBattle.revision)
                                    receipts.append(regionReceipt.result)
                                    beforeBattle = await engine.snapshot()
                                }
                                let command: GameCommand = battle.kind == "challenge"
                                    ? .resolveChallenge(challengeID: battle.id, seed: seed)
                                    : .resolveEncounter(enemyID: battle.id, seed: seed)
                                let receipt = try await engine.dispatch(command, operationID: UUID(), expectedRevision: beforeBattle.revision)
                                receipts.append(receipt.result)
                                final = await engine.snapshot()
                                result = final?.lastCombatResult
                                guard let result, final?.lastEncounterID == battle.id else {
                                    throw CoreError.invalidCommand("combat command did not commit matching result")
                                }
                                outcome = result.won ? "WIN" : "LOSS"
                            } catch {
                                outcome = "COMMAND_ERROR"
                                reason = String(describing: error)
                            }
                        }

                        XCTAssertEqual(try Data(contentsOf: url), originalBytes, "Source save mutated: \(sourceKey)/day\(day)")
                        let afterGear = final ?? decoded
                        let gearRecords = actors.map { actor in
                            let id = afterGear.equippedGearIDs[actor + "|weapon"]
                            let item = afterGear.gear.first(where: { $0.id == id })
                            return GearRecord(actorID: actor, definitionID: item?.definitionID,
                                instanceID: item?.id.uuidString, qualityID: item?.qualityID,
                                enhancement: item?.enhancement, refinement: item?.refinement,
                                affixIDs: item?.affixIDs, latentEffectID: item?.latentEffectID)
                        }
                        let eventCounts = result.map { Dictionary(grouping: $0.events.map(\.kind), by: { $0 }).mapValues(\.count) }
                        rows.append(Row(sourceKey: sourceKey, sourcePath: path, sourceFileSHA256: sha256(bytes),
                            sourceSnapshotSHA256: snapshotHash, sourceRevision: decoded.revision, sourceDay: day,
                            strategy: plan.id, battleKind: battle.kind, battleID: battle.id, seed: seed,
                            outcome: outcome, reason: reason, gear: gearRecords, commandReceipts: receipts,
                            finalRevision: final?.revision, ticks: result?.ticks,
                            elapsedMs: result?.events.compactMap(\.timestampMs).max(),
                            remainingPartyHP: result?.remainingPartyHP,
                            survivors: result.map { $0.remainingPartyHP.values.filter { $0 > 0 }.count },
                            eventCounts: eventCounts,
                            currencyDelta: final.map { delta(before: decoded.currency, after: $0.currency) },
                            materialDelta: final.map { delta(before: decoded.materials, after: $0.materials) },
                            postBattleSnapshotSHA256: final.flatMap { try? sha256(JSONEncoder.r026.encode($0)) }))
                    }
                }
            }
        }
        XCTAssertEqual(rows.count, 432)
        var counts: [String: Int] = [:]
        for row in rows { counts[row.outcome, default: 0] += 1 }
        let report = Report(schema: "earned_progression_battle_matrix_r026", status: "UNAPPROVED_TEST_OVERLAY",
            formalAdoption: false, runtimeChanged: false,
            candidateConfig: "app_candidate_R014_MAGNET_MARK_STRIKE + R017 relative-growth strengthBP=500; current local candidate only",
            buildPlans: plans, battles: battles, seeds: seeds, sources: sources, rows: rows, outcomeCounts: counts,
            limitations: [
                "432 cells are 6 actual saved checkpoints x 4 plans x 6 battles x 3 seeds. Each available cell dispatches actual equip and resolveEncounter/resolveChallenge commands through GameEngine on an in-memory SaveRepository clone.",
                "No materials, tickets, gear, quality, or progression flags are granted. Candidate plan rows are UNAVAILABLE when required exact gear templates are absent; existing slot gear and its quality/enhancement/refinement/affixes are preserved.",
                "Campaign bosses require actual unlocked region and cleared prerequisite state. Expedition selection uses a clone and the saved claim clock; any resulting settlement remains clone-local and is included in deltas.",
                "Challenge simulations use their authored multi-enemy scenario IDs. Existing completed challenges may be replayed; first-clear reward is only awarded by the engine if the cloned source had not already completed it.",
                "This is a bounded candidate comparison, not a balance approval, Human playtest, R6 canonical parity assertion, or production-runtime change. Results apply only to these six earned save snapshots, candidate configuration, battles, and seeds."
            ])
        let output = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.r026.encode(report).write(to: output, options: .atomic)
        XCTAssertEqual(counts["COMMAND_ERROR", default: 0], 0, "All eligible actual commands must complete; see persisted report for outcomes")
        print("R026_EARNED_BATTLE_MATRIX,rows=\(rows.count),output=\(output.path),catalog=\(catalogSHA)")
    }

    private func selectGear(plan: Plan, snapshot: GameSnapshot, catalog: GameCatalog, actors: [String]) -> (items: [(String, GearInstance)], reason: String?) {
        var items: [(String, GearInstance)] = []
        for (index, actor) in actors.enumerated() {
            if let templates = plan.templates {
                let template = templates[index]
                guard let definition = catalog.gear.first(where: { $0.id == template }),
                      definition.actorIDs.isEmpty || definition.actorIDs.contains(actor) else {
                    return (items, "template missing or actor incompatible: \(actor)/\(template)")
                }
                guard let instance = snapshot.gear.first(where: { $0.definitionID == template }) else {
                    return (items, "not owned in saved inventory: \(template)")
                }
                items.append((actor, instance))
            } else {
                guard let id = snapshot.equippedGearIDs[actor + "|weapon"],
                      let instance = snapshot.gear.first(where: { $0.id == id }) else {
                    return (items, "saved weapon slot missing: \(actor)")
                }
                items.append((actor, instance))
            }
        }
        return (items, nil)
    }

    private func laterThan(_ date: Date?) -> Date {
        // Deterministic clone clock; never consult wall clock or move a checkpoint backward.
        (date ?? Date(timeIntervalSince1970: 0)).addingTimeInterval(1)
    }
    private func delta(before: [String: Int], after: [String: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Set(before.keys).union(after.keys).sorted().compactMap { key in
            let amount = after[key, default: 0] - before[key, default: 0]
            return amount == 0 ? nil : (key, amount)
        })
    }
    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

private extension JSONEncoder {
    static var r026: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
}
