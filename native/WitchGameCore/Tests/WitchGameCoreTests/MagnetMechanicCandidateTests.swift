import Foundation
import XCTest
@testable import WitchGameCore

final class MagnetMechanicCandidateTests: XCTestCase {
    private let baseParams = MagnetMechanicParameters(markWindowMs: 800, strikeWindupMs: 1_200,
                                                      strikeCoefficientBP: 15_000)

    private func party(attack: Int = 20, hp: Int = 100_000) -> [Combatant] {
        ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: hp, attack: attack, defense: 0)
        }
    }

    private func run(pattern: String = "magnetMarkStrike", seed: UInt64 = 91,
                     params: MagnetMechanicParameters? = nil,
                     challengeID: String? = nil,
                     barriers: [String: (amount: Int, expiryMs: Int)] = [:],
                     party: [Combatant]? = nil, enemyHP: Int = 100_000) throws -> CombatResult {
        let enemy = Combatant(id: "E_R03_04", maxHP: enemyHP, attack: 400, defense: 0,
                              actionPattern: pattern, firstTelegraphMs: 0)
        let presentation = ["E_R03_04": CombatEntityPresentation(entityID: "E_R03_04", kind: "enemy",
            catalogID: "E_R03_04", label: "磁紋とかげ", assetKey: "ACT_E_R03_04")]
        return try R6TimelineSimulator.run(party: party ?? self.party(), enemies: [enemy], seed: seed,
                                           maxDurationMs: 10_000, challengeID: challengeID,
                                           entityPresentation: presentation, initialBarriers: barriers,
                                           candidateMagnetParameters: params)
    }

    func testMarkLocksSameTargetRootAndAmplifiesRealHitExactlyOnce() throws {
        let candidate = try run(seed: 91, params: baseParams)
        let baseline = try run(pattern: "heavy", seed: 91)
        let markEvents = candidate.events.filter { $0.kind == "enemy_magnet_mark" }
        XCTAssertGreaterThanOrEqual(markEvents.count, 2)
        for mark in markEvents {
            let root = try XCTUnwrap(mark.rootActionID)
            let tell = try XCTUnwrap(candidate.events.first {
                $0.kind == "telegraph_heavy" && $0.rootActionID == root
            })
            let hits = candidate.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == root }
            XCTAssertEqual(tell.targetID, mark.targetID, "mark and strike tell stay on the locked target")
            XCTAssertEqual(hits.count, 1, "one empowered strike per marked root")
            XCTAssertEqual(hits.first?.targetID, mark.targetID)
            XCTAssertEqual(hits.first?.diagnostics?["candidateMagnetCoefficientBP"], 15_000)
            XCTAssertFalse(candidate.events.contains(where: {
                $0.rootActionID == root && ($0.kind == "party_move" || $0.kind == "enemy_move" || $0.kind == "target_pull")
            }), "R4 specifies a mark, not forced movement")
        }
        let firstCandidate = try XCTUnwrap(candidate.events.first { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" })
        let firstBaseline = try XCTUnwrap(baseline.events.first { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" })
        XCTAssertGreaterThan(firstCandidate.amount, firstBaseline.amount)
        XCTAssertGreaterThan(firstCandidate.amount, 0, "the result reflects mitigation/status after applying the configured coefficient")
        XCTAssertEqual(firstCandidate.diagnostics?["candidateMagnetCoefficientBP"], 15_000)
    }

    func testExistingTypedChallengeInterruptCancelsMarkRootAndDamage() throws {
        let interrupted = try run(seed: 91, params: baseParams, challengeID: "CH_R03_03")
        let interrupts = interrupted.events.filter { $0.kind == "cast_interrupt" && $0.targetID == "E_R03_04" }
        XCTAssertFalse(interrupts.isEmpty, "uses only the already-typed R03 challenge interrupt path")
        for event in interrupts {
            XCTAssertTrue(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].contains(event.sourceID))
            XCTAssertFalse(interrupted.events.contains {
                $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == event.rootActionID
            }, "an interrupted mark root must not later land its boosted hit")
        }
        let ordinary = try run(seed: 91, params: baseParams)
        XCTAssertFalse(ordinary.events.contains { $0.kind == "cast_interrupt" && $0.targetID == "E_R03_04" },
                       "do not invent an interrupt-capable action in ordinary auto combat")
        XCTAssertTrue(ordinary.events.contains { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" })
    }

    func testExistingBarrierAbsorbsAmplifiedHitBeforeHPAndExpiryIsRespected() throws {
        let baseline = try run(seed: 1, params: baseParams)
        let firstMark = try XCTUnwrap(baseline.events.first { $0.kind == "enemy_magnet_mark" })
        let targetID = firstMark.targetID
        let fullyShielded = try run(seed: 1, params: baseParams,
                                    barriers: [targetID: (amount: 10_000, expiryMs: 9_000)])
        let familiarRoot = try XCTUnwrap(fullyShielded.events.first {
            $0.kind == "enemy_magnet_mark" && $0.targetID == targetID
        }?.rootActionID)
        let absorbed = try XCTUnwrap(fullyShielded.events.first {
            $0.kind == "barrier_absorb" && $0.rootActionID == familiarRoot
        })
        let noHP = try XCTUnwrap(fullyShielded.events.first {
            $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == familiarRoot
        })
        XCTAssertGreaterThan(absorbed.amount, 0)
        XCTAssertEqual(noHP.amount, 0)

        let partial = try run(seed: 1, params: baseParams,
                              barriers: [targetID: (amount: 100, expiryMs: 9_000)])
        let partialAbsorb = try XCTUnwrap(partial.events.first {
            $0.kind == "barrier_absorb" && $0.rootActionID == familiarRoot
        })
        let partialHit = try XCTUnwrap(partial.events.first {
            $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == familiarRoot
        })
        XCTAssertEqual(partialAbsorb.amount, 100)
        XCTAssertGreaterThan(partialHit.amount, 0)

        let expired = try run(seed: 1, params: baseParams,
                              barriers: [targetID: (amount: 10_000, expiryMs: 1_000)])
        XCTAssertFalse(expired.events.contains {
            $0.kind == "barrier_absorb" && $0.rootActionID == familiarRoot
        })
        XCTAssertEqual(expired.events.first {
            $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == familiarRoot
        }?.amount, 528)
    }

    func testDefeatedEnemyCannotLandPendingMagnetRootAndSourceProfileRejectsCandidateParams() throws {
        let killedBeforeImpact = try run(seed: 91, params: MagnetMechanicParameters(markWindowMs: 800,
            strikeWindupMs: 800, strikeCoefficientBP: 15_000),
            party: party(attack: 10_000), enemyHP: 1)
        XCTAssertTrue(killedBeforeImpact.won)
        XCTAssertTrue(killedBeforeImpact.events.contains { $0.kind == "enemy_magnet_mark" })
        XCTAssertFalse(killedBeforeImpact.events.contains { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" })

        XCTAssertThrowsError(try R6TimelineSimulator.run(party: party(),
            enemies: [Combatant(id: "E_R03_04", maxHP: 100_000, attack: 400, defense: 0, actionPattern: "heavy")],
            seed: 91, sourceProfileSeed: "fixture-seed", candidateMagnetParameters: baseParams),
            "candidate data must not enter canonical source-profile runs")
    }

    func testTimeParametersRejectUnboundedAndOverflowingInputs() throws {
        for invalid in [
            MagnetMechanicParameters(markWindowMs: 0, strikeWindupMs: 1, strikeCoefficientBP: 12_500),
            MagnetMechanicParameters(markWindowMs: 30_001, strikeWindupMs: 1, strikeCoefficientBP: 12_500),
            MagnetMechanicParameters(markWindowMs: Int.max, strikeWindupMs: Int.max, strikeCoefficientBP: 12_500),
            MagnetMechanicParameters(markWindowMs: 800, strikeWindupMs: 1_200, strikeCoefficientBP: 30_001)
        ] {
            XCTAssertThrowsError(try run(seed: 2, params: invalid))
        }
        XCTAssertThrowsError(try R6TimelineSimulator.run(party: party(),
            enemies: [Combatant(id: "E_R03_04", maxHP: 100_000, attack: 400, defense: 0, actionPattern: "magnetMarkStrike")],
            seed: 2, maxDurationMs: Int.max, candidateMagnetParameters: baseParams),
            "candidate experiments must reject unbounded timeline horizons before scheduling")
        XCTAssertThrowsError(try R6TimelineSimulator.run(party: party(),
            enemies: [Combatant(id: "E_R03_04", maxHP: 100_000, attack: Int.max, defense: 0, actionPattern: "magnetMarkStrike")],
            seed: 2, maxDurationMs: 4_000, candidateMagnetParameters: baseParams),
            "candidate damage scaling must reject an unrepresentable result without trapping")
    }

    func testTargetKilledByAnotherEnemyCancelsLockedMagnetRootWithoutRetargetOrInterrupt() throws {
        let fragileParty = party(attack: 1, hp: 100)
        let presentation = ["E_R03_04": CombatEntityPresentation(entityID: "E_R03_04", kind: "enemy",
            catalogID: "E_R03_04", label: "磁紋とかげ", assetKey: "ACT_E_R03_04")]
        let other = Combatant(id: "E_OTHER", maxHP: 1_000_000, attack: 10_000, defense: 0,
                              actionPattern: "interrupt", firstTelegraphMs: 0)
        let result = try R6TimelineSimulator.run(party: fragileParty,
            enemies: [Combatant(id: "E_R03_04", maxHP: 1_000_000, attack: 400, defense: 0,
                                actionPattern: "magnetMarkStrike", firstTelegraphMs: 0), other],
            seed: 1, maxDurationMs: 4_000, entityPresentation: presentation,
            candidateMagnetParameters: baseParams)
        let mark = try XCTUnwrap(result.events.first { $0.kind == "enemy_magnet_mark" })
        let root = try XCTUnwrap(mark.rootActionID)
        XCTAssertTrue(result.events.contains { $0.kind == "enemy_hit" && $0.sourceID == "E_OTHER" && $0.targetID == mark.targetID })
        XCTAssertTrue(result.events.contains { $0.kind == "enemy_magnet_target_lost" && $0.rootActionID == root && $0.targetID == mark.targetID })
        XCTAssertFalse(result.events.contains { $0.kind == "cast_interrupt" && $0.rootActionID == root }, "target loss is not an interrupt")
        XCTAssertFalse(result.events.contains { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == root })
    }

    func testLivingMarkedTargetCanStillBeCoveredByExistingSmithMechanic() throws {
        let params = MagnetMechanicParameters(markWindowMs: 650, strikeWindupMs: 850, strikeCoefficientBP: 12_500)
        var chosenSeed: UInt64?
        for seed in 1...100 {
            let probe = try run(seed: UInt64(seed), params: params, party: party(attack: 1, hp: 1_000))
            if let mark = probe.events.first(where: { $0.kind == "enemy_magnet_mark" }), mark.targetID != "C_SMITH" {
                chosenSeed = UInt64(seed); break
            }
        }
        let seed = try XCTUnwrap(chosenSeed)
        let presentation = ["E_R03_04": CombatEntityPresentation(entityID: "E_R03_04", kind: "enemy",
            catalogID: "E_R03_04", label: "磁紋とかげ", assetKey: "ACT_E_R03_04")]
        let result = try R6TimelineSimulator.run(party: party(attack: 1, hp: 1_000),
            enemies: [Combatant(id: "E_R03_04", maxHP: 1_000_000, attack: 400, defense: 0,
                                actionPattern: "magnetMarkStrike", firstTelegraphMs: 0)],
            seed: seed, maxDurationMs: 3_000, entityPresentation: presentation,
            candidateMagnetParameters: params)
        let mark = try XCTUnwrap(result.events.first { $0.kind == "enemy_magnet_mark" })
        let root = try XCTUnwrap(mark.rootActionID)
        let redirect = try XCTUnwrap(result.events.first { $0.kind == "cover_redirect" && $0.rootActionID == root })
        XCTAssertEqual(redirect.targetID, mark.targetID, "the cover event names the original marked target")
        let hit = try XCTUnwrap(result.events.first { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == root })
        XCTAssertEqual(hit.targetID, "C_SMITH", "existing Smith cover may change the actual defender")
        XCTAssertNotEqual(hit.targetID, mark.targetID)
    }

    func testPublicMagnetPreviewFixturesExposeRealRootsAndTypedInterruptVariant() throws {
        let preview = try EnemyActionPreviewFixture.magnetMarkStrike(seed: 1_304, maxDurationMs: 12_000)
        let mark = try XCTUnwrap(preview.events.first { $0.kind == "enemy_magnet_mark" })
        let root = try XCTUnwrap(mark.rootActionID)
        XCTAssertEqual(mark.sourceID, "E_R03_04")
        XCTAssertTrue(["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].contains(mark.targetID))
        XCTAssertTrue(preview.entityPresentation["E_R03_04"]?.label == "磁紋とかげ")
        XCTAssertTrue(preview.events.contains { $0.kind == "telegraph_heavy" && $0.rootActionID == root })
        XCTAssertTrue(preview.events.contains { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == root })

        let interrupted = try EnemyActionPreviewFixture.magnetMarkStrikeInterrupted(seed: 1_304, maxDurationMs: 12_000)
        let interruptedRoot = try XCTUnwrap(interrupted.events.first { $0.kind == "enemy_magnet_mark" }?.rootActionID)
        XCTAssertTrue(interrupted.events.contains { $0.kind == "cast_interrupt" && $0.rootActionID == interruptedRoot && $0.targetID == "E_R03_04" })
        XCTAssertFalse(interrupted.events.contains { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" && $0.rootActionID == interruptedRoot })
    }

    func testSeededParameterSweepAgainstGenericHeavyBaseline() throws {
        struct Row: Codable {
            let markWindowMs: Int
            let strikeWindupMs: Int
            let strikeCoefficientBP: Int
            let seeds: Int
            let meanFirstHitMs: Double
            let meanIncomingHPDamage: Double
            let meanPartyHPRemaining: Double
            let meanBarrierAbsorbed: Double
            let meanHitCount: Double
            let heavyBaselineMeanFirstHitMs: Double
            let heavyBaselineMeanIncomingHPDamage: Double
            let heavyBaselineMeanHitCount: Double
            let meanDamageDeltaVsHeavy: Double
        }
        let windows = [(650, 850), (800, 1_200), (1_000, 1_500)]
        let coefficients = [12_500, 15_000, 17_500]
        let seeds = Array(UInt64(1)...UInt64(24))
        var rows: [Row] = []
        for (mark, windup) in windows {
            for coefficient in coefficients {
                var firstHit = 0, damage = 0, hpLeft = 0, absorbed = 0, hitCount = 0
                var baseFirstHit = 0, baseDamage = 0, baseHits = 0
                for seed in seeds {
                    let result = try run(seed: seed, params: MagnetMechanicParameters(markWindowMs: mark,
                        strikeWindupMs: windup, strikeCoefficientBP: coefficient),
                        party: party(attack: 25, hp: 50_000), enemyHP: 1_000_000)
                    let enemyHits = result.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" }
                    firstHit += enemyHits.first?.timestampMs ?? 0
                    damage += enemyHits.reduce(0) { $0 + $1.amount }
                    hitCount += enemyHits.count
                    absorbed += result.events.filter { $0.kind == "barrier_absorb" && $0.sourceID == "E_R03_04" }.reduce(0) { $0 + $1.amount }
                    hpLeft += result.remainingPartyHP.values.reduce(0, +)
                    let baseline = try run(pattern: "heavy", seed: seed,
                        party: party(attack: 25, hp: 50_000), enemyHP: 1_000_000)
                    let baselineHits = baseline.events.filter { $0.kind == "enemy_hit" && $0.sourceID == "E_R03_04" }
                    baseFirstHit += baselineHits.first?.timestampMs ?? 0
                    baseDamage += baselineHits.reduce(0) { $0 + $1.amount }
                    baseHits += baselineHits.count
                }
                rows.append(Row(markWindowMs: mark, strikeWindupMs: windup,
                    strikeCoefficientBP: coefficient, seeds: seeds.count,
                    meanFirstHitMs: Double(firstHit) / Double(seeds.count),
                    meanIncomingHPDamage: Double(damage) / Double(seeds.count),
                    meanPartyHPRemaining: Double(hpLeft) / Double(seeds.count),
                    meanBarrierAbsorbed: Double(absorbed) / Double(seeds.count),
                    meanHitCount: Double(hitCount) / Double(seeds.count),
                    heavyBaselineMeanFirstHitMs: Double(baseFirstHit) / Double(seeds.count),
                    heavyBaselineMeanIncomingHPDamage: Double(baseDamage) / Double(seeds.count),
                    heavyBaselineMeanHitCount: Double(baseHits) / Double(seeds.count),
                    meanDamageDeltaVsHeavy: Double(damage - baseDamage) / Double(seeds.count)))
            }
        }
        let data = try JSONEncoder.sortedCandidate.encode(rows)
        try data.write(to: URL(fileURLWithPath: "magnet_parameter_sweep.json"))
        XCTAssertEqual(rows.count, 9)
        XCTAssertTrue(rows.allSatisfy { $0.seeds == 24 && $0.meanHitCount > 0 })
    }
}

private extension JSONEncoder {
    static var sortedCandidate: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
