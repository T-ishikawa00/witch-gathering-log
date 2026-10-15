import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import WitchGameCore

/// Mechanism-only deterministic probes. These fixtures do not represent ordinary progression,
/// victory balance, rewards, or formal design adoption. The only R02_02 row reuses R359's
/// already-passed exact evidence and is deliberately not simulated again.
final class ResearchMechanicClosureR371Tests: XCTestCase {
    private let challengeIDs = [
        "CH_R01_01", "CH_R01_02", "CH_R01_03", "CH_R02_01", "CH_R02_02",
        "CH_R02_03", "CH_R03_01", "CH_R03_02", "CH_R03_03", "CH_R04_01",
        "CH_R04_02", "CH_R04_03", "CH_R05_01", "CH_R05_02", "CH_R05_03"
    ]
    private let partyIDs: Set<String> = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
    private let seed: UInt64 = 371_001

    private struct TraceEnvelope: Encodable {
        let schema: String
        let challengeID: String
        let fixtureClass: String
        let fixtureDescription: String
        let seed: UInt64
        let assertions: [String: String]
        let result: CombatResult
    }

    private func statOnlyParty() -> [Combatant] {
        // Stat-only fixture keeps combatants alive for long enough to observe cycles while
        // retaining canonical actor IDs and the simulator's ordinary skill/action selection.
        ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"].map {
            Combatant(id: $0, maxHP: 100_000, attack: 10, defense: 0)
        }
    }

    private func run(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> CombatResult? {
        let catalog = try GameCatalog.bundledTestOverlay()
        let scenario = try catalog.challengeCombatScenario(id)
        XCTAssertEqual(scenario.challengeID, id, file: file, line: line)
        XCTAssertFalse(scenario.enemies.isEmpty, file: file, line: line)
        let result = try R6TimelineSimulator.run(
            party: statOnlyParty(), enemies: scenario.enemies, seed: seed,
            maxDurationMs: 180_000, challengeID: id,
            entityPresentation: scenario.entityPresentation)
        let replayed = replayedHP(result)
        let partyReconciled = replayed.party == result.remainingPartyHP
        let enemiesReconciled = replayed.enemies == result.remainingEnemyHP
        let timestampsPresent = result.events.allSatisfy { $0.timestampMs != nil }
        XCTAssertEqual(replayed.party, result.remainingPartyHP,
                       "independent event arithmetic must reconcile party HP", file: file, line: line)
        XCTAssertEqual(replayed.enemies, result.remainingEnemyHP,
                       "independent event arithmetic must reconcile enemy HP", file: file, line: line)
        XCTAssertTrue(timestampsPresent,
                      "event chronology must be available for HP/action joins", file: file, line: line)
        let ledgerVerdict = partyReconciled && enemiesReconciled && timestampsPresent ? "PASS" : "FAIL"
        try writeTrace(id, result: result, assertions: ["hpLedger": ledgerVerdict,
                                                        "partyLedger": partyReconciled ? "PASS" : "FAIL",
                                                        "enemyLedger": enemiesReconciled ? "PASS" : "FAIL",
                                                        "timestamps": timestampsPresent ? "PASS" : "FAIL",
                                                        "fixture": "MECHANISM_ONLY"])
        return result
    }

    private func writeTrace(_ id: String, result: CombatResult, assertions: [String: String]) throws {
        guard let rootString = ProcessInfo.processInfo.environment["WITCH_R371_EVIDENCE_ROOT"] else {
            XCTFail("WITCH_R371_EVIDENCE_ROOT is required; trace evidence must not be silently omitted")
            return
        }
        let root = URL(fileURLWithPath: rootString).standardizedFileURL
        guard root.isFileURL, FileManager.default.fileExists(atPath: root.path) else {
            XCTFail("evidence root must already exist")
            return
        }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true else {
            XCTFail("evidence root must be a directory")
            return
        }
        let env = TraceEnvelope(schema: "r371-mechanism-trace-v1", challengeID: id,
                                fixtureClass: "MECHANISM_ONLY",
                                fixtureDescription: "Canonical challenge scenario; fixed four actor IDs; controlled maxHP=100000, attack=10, defense=0; no save or rewards.",
                                seed: seed, assertions: assertions, result: result)
        let data = try JSONEncoder.sorted.encode(env)
        let url = root.appendingPathComponent("\(id)_seed_371001.json")
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = close(fd) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                offset += count
            }
        }
    }


    private func replayedHP(_ result: CombatResult) -> (party: [String: Int], enemies: [String: Int]) {
        var party = result.initialPartyHP
        var enemies = result.initialEnemyHP
        let playerDamage: Set<String> = ["direct", "smith_hammer", "poison_seed", "poison_tick", "counter", "chase", "reflect", "heal_followup"]
        let partyDamage: Set<String> = ["enemy_hit", "dot_tick", "enemy_reflect_projectile"]
        let enemyHealing: Set<String> = ["enemy_regen", "enemy_support", "lamp_support"]
        let partyHealing: Set<String> = ["heal", "enemy_heal_cycle"]
        for event in result.events {
            if playerDamage.contains(event.kind), let hp = enemies[event.targetID] {
                enemies[event.targetID] = max(0, hp - event.amount)
            } else if enemyHealing.contains(event.kind), let hp = enemies[event.targetID], let cap = result.initialEnemyHP[event.targetID] {
                enemies[event.targetID] = min(cap, hp + event.amount)
            } else if partyDamage.contains(event.kind), let hp = party[event.targetID] {
                party[event.targetID] = max(0, hp - event.amount)
            } else if partyHealing.contains(event.kind), let hp = party[event.targetID], let cap = result.initialPartyHP[event.targetID] {
                party[event.targetID] = min(cap, hp + event.amount)
            }
        }
        return (party, enemies)
    }

    private func linkedHits(_ result: CombatResult, from enemy: String, tell: String? = nil) -> [(CombatEvent, [CombatEvent])] {
        let tells = result.events.filter { $0.sourceID == enemy && (tell == nil || $0.kind == tell) && ($0.kind.hasPrefix("telegraph") || $0.kind == "enemy_telegraph") }
        return tells.compactMap { event in
            guard let root = event.rootActionID else { return nil }
            return (event, result.events.filter { $0.kind == "enemy_hit" && $0.sourceID == enemy && $0.rootActionID == root })
        }
    }

    private func assertLinkedTell(_ result: CombatResult, enemy: String, kind: String, aoe: Bool, minimumHits: Int = 1,
                                  afterMs: Int? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let linked = linkedHits(result, from: enemy, tell: kind).filter { pair in
            guard let afterMs else { return true }
            return (pair.0.timestampMs ?? -1) > afterMs
        }
        let valid = linked.filter { tell, hits in
            guard !hits.isEmpty, hits.count >= minimumHits,
                  let tellTime = tell.timestampMs,
                  hits.allSatisfy({ ($0.timestampMs ?? -1) >= tellTime }) else { return false }
            if aoe { return tell.targetID == "party" && Set(hits.map(\.targetID)).count >= 2 }
            return tell.targetID != "party" && Set(hits.map(\.targetID)) == Set([tell.targetID])
        }
        XCTAssertFalse(valid.isEmpty, "expected a tell linked by root/time to matching \(aoe ? "party" : "single-target") hits", file: file, line: line)
    }

    func testCH_R01_01HeavyTellHitLifecycleAndLedger() throws {
        let result = try XCTUnwrap(run("CH_R01_01")); assertLinkedTell(result, enemy: "B_R01_A", kind: "telegraph_heavy", aoe: false)
    }
    func testCH_R01_02ThreeEnemySupportAndSlow() throws {
        let result = try XCTUnwrap(run("CH_R01_02"))
        XCTAssertEqual(try GameCatalog.bundledTestOverlay().challengeCombatScenario("CH_R01_02").enemies.count, 3)
        let slow = try XCTUnwrap(result.events.first { $0.kind == "party_slow" })
        XCTAssertTrue(result.events.contains { $0.kind == "enemy_hit" && $0.sourceID == slow.sourceID && $0.targetID == slow.targetID && $0.rootActionID == slow.rootActionID })
    }
    func testCH_R01_03AlternatingSingleHeavyAndMultihitTargets() throws {
        let result = try XCTUnwrap(run("CH_R01_03")); let linked = linkedHits(result, from: "B_R01_B")
        XCTAssertTrue(linked.contains { $0.0.kind == "telegraph_heavy" && $0.1.count == 1 && $0.0.targetID != "party" })
        XCTAssertTrue(linked.contains { $0.0.kind == "enemy_telegraph" && $0.1.count == 3 && $0.0.targetID != "party" })
    }
    func testCH_R02_01DotAndHealCycleEventsAreRooted() throws {
        let result = try XCTUnwrap(run("CH_R02_01")); let dot = try XCTUnwrap(result.events.first { $0.kind == "dot_applied" })
        XCTAssertTrue(result.events.contains { $0.kind == "dot_tick" && $0.targetID == dot.targetID && ($0.timestampMs ?? -1) > (dot.timestampMs ?? Int.max) })
        XCTAssertTrue(result.events.contains { $0.kind == "enemy_heal_cycle" && $0.sourceID == "E_R02_01" })
    }
    func testCH_R02_02ReusesPinnedR359MembranePassWithoutReplaying() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["WITCH_R371_R359_RUN"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path).standardizedFileURL)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "3b25ecc1e2ec1b12a29ce6b05b75c14bd6eafb43d1468baf4a149c86610dd971")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(root["status"] as? String), "CORE_TESTS_PASSED_REVIEW_REQUIRED")
        let verdict = try XCTUnwrap(root["testVerdict"] as? [String: Any])
        let passed = try XCTUnwrap(verdict["passed"] as? [String])
        XCTAssertEqual(passed, ["ResearchMembraneR359Tests/testEarnedR02MembraneReducesOnlyMatchedActiveWindowHits"])
        XCTAssertTrue((verdict["failed"] as? [String])?.isEmpty == true)
    }
    func testCH_R02_03SupportWaveHasFourActorsAndSupportEvent() throws {
        let result = try XCTUnwrap(run("CH_R02_03")); let scenario = try GameCatalog.bundledTestOverlay().challengeCombatScenario("CH_R02_03")
        XCTAssertEqual(scenario.enemies.count, 4)
        XCTAssertTrue(result.events.contains { ["enemy_magic_support", "enemy_support"].contains($0.kind) })
    }
    func testCH_R03_01AlternatesSingleHeavyAndThreeLinkedHits() throws {
        let result = try XCTUnwrap(run("CH_R03_01")); let linked = linkedHits(result, from: "B_R03_A")
        XCTAssertTrue(linked.contains { $0.0.kind == "telegraph_heavy" && $0.1.count == 1 })
        XCTAssertTrue(linked.contains { $0.0.kind == "enemy_telegraph" && $0.1.count == 3 })
    }
    func testCH_R03_02HeatThresholdShiftAndPostShiftAOEAccounting() throws {
        let result = try XCTUnwrap(run("CH_R03_02")); let boss = "B_R03_B"
        let heat = try XCTUnwrap(result.events.first { $0.kind == "phase_heat" && $0.sourceID == boss })
        let shift = try XCTUnwrap(result.events.first { $0.kind == "enemy_phase_shift" && $0.sourceID == boss && $0.targetID == "phase_2" })
        let t = try XCTUnwrap(shift.timestampMs); let root = try XCTUnwrap(shift.rootActionID)
        let shiftIndex = try XCTUnwrap(result.events.firstIndex(of: shift))
        let hitPrefix = result.events[..<shiftIndex].filter { ["direct", "smith_hammer", "poison_seed", "poison_tick", "heal_followup", "counter", "chase", "reflect"].contains($0.kind) && $0.targetID == boss }
        XCTAssertTrue(hitPrefix.contains { $0.rootActionID == root }, "the threshold-crossing damage must precede and root-link to the shift")
        let initialBossHP = try XCTUnwrap(result.initialEnemyHP[boss])
        XCTAssertLessThanOrEqual(initialBossHP - hitPrefix.reduce(0) { $0 + $1.amount }, initialBossHP / 2)
        XCTAssertLessThan(try XCTUnwrap(heat.timestampMs), t)
        assertLinkedTell(result, enemy: boss, kind: "telegraph_aoe", aoe: true, afterMs: t)
    }
    func testCH_R03_03CastInterruptLinksToBossCast() throws {
        let result = try XCTUnwrap(run("CH_R03_03")); let starts = result.events.filter { $0.kind == "enemy_cast_start" }
        XCTAssertFalse(starts.isEmpty)
        let interrupts = result.events.filter { $0.kind == "cast_interrupt" && $0.targetID == "B_R03_B" }
        XCTAssertTrue(interrupts.contains { interrupt in starts.contains { $0.rootActionID == interrupt.rootActionID } },
                      "interrupted cast must join to a preceding cast-start root")
    }
    func testCH_R04_01HeavyAndOrdinarySingleTargetCycles() throws {
        let result = try XCTUnwrap(run("CH_R04_01")); let enemy = "B_R04_A"
        assertLinkedTell(result, enemy: enemy, kind: "telegraph_heavy", aoe: false)
        XCTAssertTrue(linkedHits(result, from: enemy, tell: "enemy_telegraph").contains { !$0.1.isEmpty })
    }
    func testCH_R04_02BuffWeakenAndDamageShareActionRoot() throws {
        let result = try XCTUnwrap(run("CH_R04_02")); let buff = try XCTUnwrap(result.events.first { $0.kind == "enemy_buff" })
        XCTAssertTrue(result.events.contains { $0.kind == "party_weaken" && $0.sourceID == buff.sourceID && $0.rootActionID == buff.rootActionID })
        XCTAssertTrue(result.events.contains { $0.kind == "enemy_hit" && $0.rootActionID == buff.rootActionID })
    }
    func testCH_R04_03AlternatingSingleTargetAndPartyAOE() throws {
        let result = try XCTUnwrap(run("CH_R04_03")); let enemy = "B_R04_B"
        assertLinkedTell(result, enemy: enemy, kind: "enemy_telegraph", aoe: false)
        assertLinkedTell(result, enemy: enemy, kind: "telegraph_aoe", aoe: true)
    }
    func testCH_R05_01HeavyExecutionHasAuthoredRecoveryGap() throws {
        let result = try XCTUnwrap(run("CH_R05_01")); let enemy = "B_R05_A"
        let heavy = linkedHits(result, from: enemy, tell: "telegraph_heavy").filter { !$0.1.isEmpty }
        XCTAssertGreaterThanOrEqual(heavy.count, 2)
        let firstTwo = Array(heavy.prefix(2))
        guard firstTwo.count == 2 else {
            XCTFail("expected two linked heavy executions before checking their recovery gap")
            return
        }
        guard let firstTime = firstTwo[0].0.timestampMs, let secondTime = firstTwo[1].0.timestampMs else {
            XCTFail("both heavy tells need timestamps before checking recovery gap")
            return
        }
        XCTAssertGreaterThanOrEqual(secondTime - firstTime, 4_300,
                                    "the authored 1.8s windup plus 2.5s recovery separates the next heavy tell")
        XCTAssertTrue(firstTwo[0].1.allSatisfy { $0.targetID == firstTwo[0].0.targetID })
        XCTAssertTrue(firstTwo[1].1.allSatisfy { $0.targetID == firstTwo[1].0.targetID })
    }
    func testCH_R05_02LampSupportLinkedToLivingGuardian() throws {
        let result = try XCTUnwrap(run("CH_R05_02")); let lamp = try XCTUnwrap(result.events.first { $0.kind == "lamp_support" })
        XCTAssertTrue(lamp.sourceID.hasPrefix("LAMP_VESSEL")); XCTAssertNotEqual(lamp.targetID, lamp.sourceID); XCTAssertGreaterThan(lamp.amount, 0)
        let guardian = lamp.targetID
        let lampTime = lamp.timestampMs ?? -1
        XCTAssertTrue(result.events.contains {
            $0.kind == "enemy_hit" && $0.sourceID == guardian &&
            $0.rootActionID == lamp.rootActionID && ($0.timestampMs ?? Int.max) <= lampTime
        }, "lamp support must share the guardian's prior attack root; enemy_hit.targetID is a party actor")
    }
    func testCH_R05_03ComboMultihitAndAOESequence() throws {
        let result = try XCTUnwrap(run("CH_R05_03")); let enemy = "B_R05_B"
        let combos = result.events.filter { $0.kind == "challenge_combo" && $0.sourceID == enemy }
        XCTAssertTrue(combos.contains { $0.targetID == "multi_hit" }); XCTAssertTrue(combos.contains { $0.targetID == "aoe" })
        assertLinkedTell(result, enemy: enemy, kind: "telegraph_aoe", aoe: true)
        XCTAssertTrue(linkedHits(result, from: enemy).contains { $0.1.count >= 3 })
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder }
}
