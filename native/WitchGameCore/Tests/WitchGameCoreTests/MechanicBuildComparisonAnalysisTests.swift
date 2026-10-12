import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Read-only candidate comparison. This is an analysis harness, not product
/// balance or an approved loadout recommendation.
final class MechanicBuildComparisonAnalysisTests: XCTestCase {
    private struct Row: Encodable {
        let build: String
        let seed: UInt64
        let enemyID: String
        let regionID: String
        let actionPattern: String
        let won: Bool
        let elapsedMs: Int
        let remainingPartyHP: [String: Int]
        let remainingEnemyHP: [String: Int]
        let eventCounts: [String: Int]
        let eventAmounts: [String: Int]
    }

    private struct Report: Encodable {
        let schema: String
        let status: String
        let catalogVersion: String
        let catalogSHA256: String
        let simulator: String
        let seeds: [UInt64]
        let rows: [Row]
        let notes: [String]
    }

    func testCandidateMechanicsAcrossPairedCampaignBuildsAndSeeds() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        XCTAssertEqual(catalog.enemies.count, 30)
        let catalogData = try JSONEncoder.sorted.encode(catalog)
        let catalogSHA = SHA256.hash(data: catalogData).map { String(format: "%02x", $0) }.joined()
        let actors = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        let loadouts: [(String, [String])] = [
            ("direct_control", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"]),
            ("poison_heal_chase", ["EQ_W_P2", "EQ_A_03", "EQ_S_02", "EQ_F_03"]),
            ("ward_heal_counter_chase", ["EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03"]),
            ("ward_guard_heal_chase", ["EQ_W_G1", "EQ_A_02", "EQ_S_03", "EQ_F_02"])
        ]
        let seeds: [UInt64] = [100_049, 100_069, 100_103]
        let starter = GameSnapshot.newGame(catalog: catalog)
        let engine = try GameEngine(catalog: catalog, saves: SaveRepository(initial: starter))
        var rows: [Row] = []

        for (buildName, templateIDs) in loadouts {
            var state = starter
            for (actorID, templateID) in zip(actors, templateIDs) {
                let definition = try XCTUnwrap(catalog.gear.first(where: { $0.id == templateID }), "missing (templateID)")
                XCTAssertTrue(definition.actorIDs.contains(actorID), "(templateID) is not valid for (actorID)")
                let item = GearInstance(definitionID: templateID, ownerID: actorID, protected: true,
                                        enhancement: 10, qualityID: "Q4")
                state.gear.append(item)
                state.equippedGearIDs[actorID + "|" + definition.slot] = item.id
            }
            for enemy in catalog.enemies {
                for seed in seeds {
                    let result = try await engine.previewCampaignEncounterR6QA(enemyID: enemy.id, seed: seed,
                                                                                snapshot: state)
                    let relevant = [
                        "poison_seed", "poison_stack", "poison_tick", "poison_burst",
                        "barrier", "barrier_ward", "barrier_absorb", "reflect", "heal", "heal_barrier", "heal_followup",
                        "smith_pressure", "smith_hammer", "smith_cover_barrier", "counter",
                        "mark", "chase", "dash"
                    ]
                    let counts = Dictionary(grouping: result.events.map(\.kind), by: { $0 })
                        .mapValues(\.count)
                        .filter { relevant.contains($0.key) }
                    let amounts = Dictionary(grouping: result.events.filter { relevant.contains($0.kind) }, by: \.kind)
                        .mapValues { $0.reduce(0) { $0 + $1.amount } }
                    rows.append(Row(build: buildName, seed: seed, enemyID: enemy.id, regionID: enemy.regionID,
                                    actionPattern: enemy.actionPattern ?? "standard", won: result.won,
                                    elapsedMs: result.events.compactMap(\.timestampMs).max() ?? 0,
                                    remainingPartyHP: result.remainingPartyHP,
                                    remainingEnemyHP: result.remainingEnemyHP,
                                    eventCounts: counts, eventAmounts: amounts))
                }
            }
        }
        XCTAssertEqual(rows.count, loadouts.count * catalog.enemies.count * seeds.count)
        let after = await engine.snapshot()
        XCTAssertEqual(after, starter, "preview matrix must not mutate save state")

        let report = Report(schema: "candidate_mechanics_build_matrix_r001",
                            status: "UNAPPROVED_TEST_OVERLAY",
                            catalogVersion: catalog.version,
                            catalogSHA256: catalogSHA,
                            simulator: R6CampaignQAAdapter.profileID,
                            seeds: seeds,
                            rows: rows,
                            notes: [
                                "4 candidate loadouts x 30 authored catalog enemies x 3 paired seeds = 360; actual read-only GameEngine R6 candidate preview.",
                                "All four gear pieces are Q4/+10 synthetic snapshots; this is not a progression-reachable economy comparison.",
                                "No values or products are approved by this report. R6 fixed-point candidate adapter and campaign enemy action translations remain provisional.",
                                "Event counts/amounts measure emitted events, not causal attribution where a generic event can be produced by multiple effects."
                            ])
        let outputPath = ProcessInfo.processInfo.environment["WITCH_MECHANIC_BUILD_ANALYSIS_OUTPUT"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("witch_candidate_mechanics_build_matrix_r001.json").path
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.sorted.encode(report).write(to: outputURL, options: .atomic)
        print("CANDIDATE_MECHANIC_MATRIX_FILE,\(outputURL.path),rows=\(rows.count),catalog=\(catalogSHA)")
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
