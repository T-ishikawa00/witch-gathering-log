import Foundation
import XCTest
@testable import WitchGameCore

final class R6CampaignQAIntegrationTests: XCTestCase {
    private struct Row: Encodable {
        let path: String
        let build: String
        let region: String
        let enemy: String
        let pattern: String
        let won: Bool
        let elapsedMs: Int
        let survivors: Int
        let partyHP: [Int]
        let events: Int
        let damageOut: Int
        let damageIn: Int
        enum CodingKeys: String, CodingKey {
            case path = "p", build = "b", region = "r", enemy = "e", pattern = "x", won = "w"
            case elapsedMs = "t", survivors = "s", partyHP = "h", events = "n", damageOut = "o", damageIn = "i"
        }
    }

    func testSmithCoverBarrierIsCandidateGearGatedAndF03ICDDoesNotChangeR6Reference() throws {
        let noSmithEffect = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"].map { id in
            Combatant(id: id, maxHP: id == "C_SMITH" ? 250 : 100, attack: id == "C_SMITH" ? 100 : 25,
                      defense: 0, effectIDs: id == "C_FAMILIAR" ? ["FAMILIAR_CHASE"] : [],
                      guardChanceBP: id == "C_SMITH" ? 1_000 : 0)
        }
        var withSmithEffect = noSmithEffect
        withSmithEffect[3].effectIDs.insert("SMITH_COVER_BARRIER")
        let enemy = Combatant(id: "QA_HEAVY", maxHP: 100_000, attack: 140, defense: 0,
                              actionPattern: "heavy", firstTelegraphMs: 500)
        let disabled = try R6TimelineSimulator.run(party: noSmithEffect, enemies: [enemy], seed: 77, maxDurationMs: 8_000)
        let enabled = try R6TimelineSimulator.run(party: withSmithEffect, enemies: [enemy], seed: 77, maxDurationMs: 8_000)
        XCTAssertFalse(disabled.events.contains { $0.kind == "smith_cover_barrier" })
        let candidateBarrier = try XCTUnwrap(enabled.events.first { $0.kind == "smith_cover_barrier" })
        XCTAssertEqual(candidateBarrier.sourceID, "C_SMITH")
        XCTAssertEqual(candidateBarrier.targetID, "C_SMITH")
        XCTAssertEqual(candidateBarrier.amount, 40, "candidate contract is 4,000 bp of Smith power")
        XCTAssertEqual(candidateBarrier.timestampMs, 2_100, "Smith selects Guard against the forecast threat")
        XCTAssertEqual(R6TimelineSimulator.familiarChaseCooldownMs(effectIDs: [], sourceProfile: false), 2_000)
        XCTAssertEqual(R6TimelineSimulator.familiarChaseCooldownMs(effectIDs: ["FAMILIAR_CHASE_ICD_1500MS"], sourceProfile: false), 1_500)
        XCTAssertEqual(R6TimelineSimulator.familiarChaseCooldownMs(effectIDs: ["FAMILIAR_CHASE_ICD_1500MS"], sourceProfile: true), 2_000,
                       "locked source fixture keeps its 2,000 ms rule")
    }

    func testReadOnlyR6CandidatePathAcrossAllCampaignEnemiesAndBuilds() async throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        XCTAssertEqual(catalog.enemies.count, 30)
        let starter = GameSnapshot.newGame(catalog: catalog)
        let game = try GameEngine(catalog: catalog, saves: SaveRepository(initial: starter))
        let loadouts: [(String, [String], String, Int)] = [
            ("starter", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"], "Q0", 0),
            ("direct_maxed_candidate", ["EQ_W_01", "EQ_A_01", "EQ_S_01", "EQ_F_01"], "Q4", 10),
            ("poison_chase_maxed_candidate", ["EQ_W_P2", "EQ_A_03", "EQ_S_02", "EQ_F_03"], "Q4", 10),
            ("ward_counter_maxed_candidate", ["EQ_W_G2", "EQ_A_03", "EQ_S_03", "EQ_F_03"], "Q4", 10)
        ]
        let actors = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
        var rows: [Row] = []
        for (build, templates, quality, enhancement) in loadouts {
            var state = starter
            for (actor, templateID) in zip(actors, templates) {
                let definition = try XCTUnwrap(catalog.gear.first(where: { $0.id == templateID }))
                XCTAssertTrue(definition.actorIDs.contains(actor))
                let key = actor + "|" + definition.slot
                let item = GearInstance(definitionID: templateID, ownerID: actor, protected: true,
                                        enhancement: enhancement, qualityID: quality)
                state.gear.append(item)
                state.equippedGearIDs[key] = item.id
            }
            for enemy in catalog.enemies {
                let pathResults: [(String, CombatResult)] = [
                    ("campaign_default", try await game.previewCampaignEncounterDefaultQA(enemyID: enemy.id, seed: 100_049, snapshot: state)),
                    (R6CampaignQAAdapter.profileID, try await game.previewCampaignEncounterR6QA(enemyID: enemy.id, seed: 100_049, snapshot: state))
                ]
                for (path, result) in pathResults {
                    let events = result.events
                    rows.append(Row(path: path, build: build, region: enemy.regionID, enemy: enemy.id,
                                    pattern: enemy.actionPattern ?? "standard", won: result.won,
                                    elapsedMs: events.compactMap(\.timestampMs).max() ?? 0,
                                    survivors: result.remainingPartyHP.values.filter { $0 > 0 }.count,
                                    partyHP: actors.map { result.remainingPartyHP[$0, default: 0] }, events: events.count,
                                    damageOut: events.filter { ["direct", "poison_seed", "smith_hammer", "chase", "counter", "poison_tick"].contains($0.kind) }.reduce(0) { $0 + $1.amount },
                                    damageIn: events.filter { $0.kind == "enemy_hit" || $0.kind == "dot_tick" }.reduce(0) { $0 + $1.amount }))
                }
            }
        }
        let after = await game.snapshot()
        XCTAssertEqual(after, starter, "QA preview must never mutate or persist to the normal save")
        XCTAssertEqual(rows.count, 240)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("witch_r6_campaign_matrix.json")
        try JSONEncoder().encode(rows).write(to: output, options: .atomic)
        print("R6_CAMPAIGN_QA_MATRIX_FILE,\(output.path),rows=\(rows.count)")
    }
}
