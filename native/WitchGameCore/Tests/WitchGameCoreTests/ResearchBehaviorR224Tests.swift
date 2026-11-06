import XCTest
@testable import WitchGameCore

/// Isolated mechanic-fixture checks only. These do not establish ordinary
/// progression, production balance, formal design approval, or native visuals.
final class ResearchBehaviorR224Tests: XCTestCase {
    private let partyIDs: Set<String> = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]

    private func party(hp: Int = 20_000, attack: Int = 100) -> [Combatant] {
        ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
            Combatant(id: $0, maxHP: hp, attack: attack, defense: 0)
        }
    }

    private let enemyDamageKinds: Set<String> = [
        "direct", "smith_hammer", "poison_seed", "heal_followup", "poison_tick", "counter", "chase", "reflect"
    ]

    private func allyDamage(_ result: CombatResult, targetID: String) -> [CombatEvent] {
        result.events.filter {
            partyIDs.contains($0.sourceID) && $0.targetID == targetID && enemyDamageKinds.contains($0.kind)
        }
    }

    private func timestamp(_ event: CombatEvent, file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        try XCTUnwrap(event.timestampMs, "event must carry its simulation timestamp", file: file, line: line)
    }

    func testR02MembraneChangesBossHPOnlyDuringItsActiveWindow() throws {
        let actors = party(attack: 100)
        let boss = Combatant(id: "B_R02_MEMBRANE_PROBE", maxHP: 1_000_000, attack: 1,
                             defense: 0, actionPattern: "standard", firstTelegraphMs: 30_000)
        let seed: UInt64 = 443
        let active = try R6TimelineSimulator.run(party: actors, enemies: [boss], seed: seed,
                                                  maxDurationMs: 9_999, challengeID: "CH_R02_02")
        let inactive = try R6TimelineSimulator.run(party: actors, enemies: [boss], seed: seed,
                                                    maxDurationMs: 9_999)

        let activeHits = allyDamage(active, targetID: boss.id)
        let inactiveHits = allyDamage(inactive, targetID: boss.id)
        XCTAssertFalse(activeHits.isEmpty, "fixture must produce real party-to-boss damage")
        XCTAssertEqual(activeHits.count, inactiveHits.count, "the membrane should change hit amount, not the scheduled attack set")

        let activeEarly = activeHits.filter { ($0.timestampMs ?? Int.max) < 6_000 }
        let activeLate = activeHits.filter { ($0.timestampMs ?? 0) >= 6_000 }
        XCTAssertFalse(activeEarly.isEmpty, "fixture must hit during the active membrane window")
        XCTAssertFalse(activeLate.isEmpty, "fixture must also hit in the closed 6–10s interval")

        func hitKey(_ event: CombatEvent) -> String {
            "\(event.tick)|\(event.timestampMs ?? -1)|\(event.sourceID)|\(event.targetID)|\(event.rootActionID ?? "")"
        }
        let inactiveGroups = Dictionary(grouping: inactiveHits, by: hitKey)
        XCTAssertTrue(inactiveGroups.values.allSatisfy { $0.count == 1 },
                      "attack identity must be unique before HP reconciliation")
        let inactiveByKey = inactiveGroups.compactMapValues(\.first)
        let armorPairs = active.events
            .filter { $0.kind == "enemy_armor" && $0.sourceID == boss.id }
            .compactMap { event -> (String, CombatEvent)? in
                guard let root = event.rootActionID,
                      let hit = activeHits.first(where: { $0.rootActionID == root && $0.sourceID == event.targetID }) else { return nil }
                return (hitKey(hit), event)
            }
        let armorGroups = Dictionary(grouping: armorPairs, by: { $0.0 })
        XCTAssertTrue(armorGroups.values.allSatisfy { $0.count == 1 },
                      "an attack root must not produce ambiguous armor accounting")
        let armorByKey = armorGroups.compactMapValues { $0.first?.1 }

        for hit in activeEarly {
            let key = hitKey(hit)
            let baseline = try XCTUnwrap(inactiveByKey[key], "matching unarmored hit must exist")
            let prevented = try XCTUnwrap(armorByKey[key], "active-window hit must have a joined armor amount")
            XCTAssertGreaterThan(prevented.amount, 0)
            XCTAssertEqual(baseline.amount - hit.amount, prevented.amount,
                           "the armor event must account for the observed damage reduction")
        }
        for hit in activeLate {
            let baseline = try XCTUnwrap(inactiveByKey[hitKey(hit)], "matching unarmored late hit must exist")
            XCTAssertEqual(hit.amount, baseline.amount, "outside the active window, the same attack deals baseline damage")
            XCTAssertFalse(armorByKey.keys.contains(hitKey(hit)), "no membrane reduction should be attached to late hits")
        }

        let activeInitial = try XCTUnwrap(active.initialEnemyHP[boss.id])
        let activeFinal = try XCTUnwrap(active.remainingEnemyHP[boss.id])
        let inactiveInitial = try XCTUnwrap(inactive.initialEnemyHP[boss.id])
        let inactiveFinal = try XCTUnwrap(inactive.remainingEnemyHP[boss.id])
        let activeLoss = activeInitial - activeFinal
        let baselineLoss = inactiveInitial - inactiveFinal
        XCTAssertEqual(activeLoss, activeHits.reduce(0) { $0 + $1.amount }, "boss HP delta must match actual party damage")
        XCTAssertEqual(baselineLoss, inactiveHits.reduce(0) { $0 + $1.amount })
        XCTAssertGreaterThan(baselineLoss, activeLoss, "the active membrane must leave the boss with more HP")
    }

    func testR03InterruptedRootsStayCancelledAndQueueContinuesWithHPControl() throws {
        let actors = party(hp: 10_000, attack: 10)
        let foe = Combatant(id: "B_R03_CAST_PROBE", maxHP: 100_000, attack: 100, defense: 0,
                            actionPattern: "dot", firstTelegraphMs: 1_500)
        let challenged = try R6TimelineSimulator.run(party: actors, enemies: [foe], seed: 912,
                                                      maxDurationMs: 12_000, challengeID: "CH_R03_03")
        let starts = challenged.events.filter { $0.kind == "enemy_cast_start" && $0.sourceID == foe.id }
        let interrupts = challenged.events.filter {
            $0.kind == "cast_interrupt" && partyIDs.contains($0.sourceID) && $0.targetID == foe.id
        }
        XCTAssertGreaterThanOrEqual(starts.count, 2, "the enemy must schedule a later cast after the first queue is interrupted")
        XCTAssertFalse(interrupts.isEmpty, "an ally hit must interrupt an outstanding cast")

        let startRoots = Set(starts.compactMap(\.rootActionID))
        let interruptedRoots = Set(interrupts.compactMap(\.rootActionID))
        XCTAssertEqual(startRoots.count, starts.count, "each cast start must identify its queued attack root")
        XCTAssertEqual(interruptedRoots.count, interrupts.count, "each interruption must identify one queued attack root")
        XCTAssertTrue(interruptedRoots.isSubset(of: startRoots))
        for root in interruptedRoots {
            let start = try XCTUnwrap(starts.first { $0.rootActionID == root }, "interrupted root must join to its cast-start event")
            XCTAssertEqual(start.targetID, root, "cast-start target identifies the exact queued root")
            XCTAssertFalse(challenged.events.contains {
                $0.kind == "enemy_hit" && $0.sourceID == foe.id && $0.rootActionID == root
            }, "an interrupted queued attack must not later damage its original target")
        }

        let firstInterruptAt = try XCTUnwrap(interrupts.compactMap(\.timestampMs).min())
        let laterStarts = starts.filter { ($0.timestampMs ?? -1) > firstInterruptAt }
        XCTAssertFalse(laterStarts.isEmpty, "after an interrupted root, the enemy must start another queued attack")
        let laterRoots = Set(laterStarts.compactMap(\.rootActionID))
        let laterTerminalRoots = interruptedRoots.union(Set(challenged.events
            .filter { $0.kind == "enemy_hit" && $0.sourceID == foe.id }
            .compactMap(\.rootActionID))).intersection(laterRoots)
        XCTAssertFalse(laterTerminalRoots.isEmpty, "the later queued attack must resolve or be explicitly interrupted before the horizon")

        // The four-actor fixture can interrupt every one-second cast window.
        // This same-input no-challenge control verifies that an un-interrupted
        // enemy attack in fact lands and changes party HP; it does not weaken
        // the challenge's cancellation assertion or claim later challenge hits.
        let control = try R6TimelineSimulator.run(party: actors, enemies: [foe], seed: 912,
                                                   maxDurationMs: 12_000)
        let controlHits = control.events.filter {
            $0.kind == "enemy_hit" && $0.sourceID == foe.id && partyIDs.contains($0.targetID)
        }
        XCTAssertFalse(controlHits.isEmpty, "same-seed un-interrupted control must contain a real enemy hit")
        XCTAssertFalse(control.events.contains { $0.kind == "enemy_cast_start" && $0.sourceID == foe.id })
        XCTAssertFalse(control.events.contains { $0.kind == "cast_interrupt" },
                       "the no-challenge control has no challenge-cancelled casts")
        let actualPartyLoss = partyIDs.reduce(0) { total, id in
            total + (control.initialPartyHP[id] ?? 0) - (control.remainingPartyHP[id] ?? 0)
        }
        let reportedDamage = control.events.filter {
            ($0.kind == "enemy_hit" || $0.kind == "dot_tick") && partyIDs.contains($0.targetID)
        }.reduce(0) { $0 + $1.amount }
        let reportedHealing = control.events.filter {
            $0.kind == "heal" && partyIDs.contains($0.targetID)
        }.reduce(0) { $0 + $1.amount }
        XCTAssertGreaterThan(actualPartyLoss, 0, "the un-interrupted control must reduce party HP")
        XCTAssertEqual(actualPartyLoss, reportedDamage - reportedHealing,
                       "control HP delta must reconcile to actual hit/dot damage less party healing")
    }

    func testR05LampSupportHealsOnlyWhileLampLivesAndStopsAfterItsDeath() throws {
        let actors = party(hp: 100_000, attack: 500)
        let guardianID = "E_R05_GUARDIAN_PROBE"
        let lampID = "LAMP_VESSEL_CH_R05_02"
        let duration = 6_000

        // Put the guardian first so the party can wound it while the lamp is
        // alive. This intentionally isolates the support branch; it does not
        // reproduce Domain.challengeCombatScenario's lamp-first target order.
        let aliveFixture = [
            Combatant(id: guardianID, maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "standard", firstTelegraphMs: 1_000),
            Combatant(id: lampID, maxHP: 100_000, attack: 0, defense: 0,
                      actionPattern: "stationary", firstTelegraphMs: 30_000)
        ]
        let supported = try R6TimelineSimulator.run(party: actors, enemies: aliveFixture, seed: 912,
                                                     maxDurationMs: duration, challengeID: "CH_R05_02")
        let heals = supported.events.filter { $0.kind == "lamp_support" }
        XCTAssertFalse(heals.isEmpty, "a living lamp must support a wounded living guardian on its impact")
        XCTAssertTrue(heals.allSatisfy { $0.sourceID == lampID && $0.targetID == guardianID && $0.amount > 0 },
                      "support must target the guardian and carry a positive HP amount")
        let guardianInitial = try XCTUnwrap(supported.initialEnemyHP[guardianID])
        let guardianFinal = try XCTUnwrap(supported.remainingEnemyHP[guardianID])
        let guardianDamage = allyDamage(supported, targetID: guardianID).reduce(0) { $0 + $1.amount }
        XCTAssertEqual(guardianFinal, guardianInitial - guardianDamage + heals.reduce(0) { $0 + $1.amount },
                       "guardian HP must reconcile to observed party damage and lamp healing")
        XCTAssertEqual(try XCTUnwrap(supported.remainingEnemyHP[lampID]),
                       try XCTUnwrap(supported.initialEnemyHP[lampID]),
                       "the support fixture must retain its lamp through the measured impact")

        // In the challenge's lamp-first order, one party hit destroys the
        // one-HP lamp before the guardian's scheduled impact.
        let deadFixture = [
            Combatant(id: lampID, maxHP: 1, attack: 0, defense: 0,
                      actionPattern: "stationary", firstTelegraphMs: 30_000),
            Combatant(id: guardianID, maxHP: 100_000, attack: 100, defense: 0,
                      actionPattern: "standard", firstTelegraphMs: 1_000)
        ]
        let unsupported = try R6TimelineSimulator.run(party: actors, enemies: deadFixture, seed: 912,
                                                      maxDurationMs: duration, challengeID: "CH_R05_02")
        XCTAssertEqual(unsupported.remainingEnemyHP[lampID], 0, "the one-HP lamp must actually be defeated")
        let lampKill = try XCTUnwrap(allyDamage(unsupported, targetID: lampID).first,
                                     "the lamp's defeat must come from a recorded party hit")
        let lampDeathAt = try timestamp(lampKill)
        let guardianHitsAfterDeath = unsupported.events.filter {
            $0.kind == "enemy_hit" && $0.sourceID == guardianID && partyIDs.contains($0.targetID)
                && ($0.timestampMs ?? -1) > lampDeathAt
        }
        XCTAssertFalse(guardianHitsAfterDeath.isEmpty, "a guardian impact must occur after the lamp is gone")
        XCTAssertTrue(unsupported.events.filter { $0.kind == "lamp_support" }.allSatisfy { ($0.timestampMs ?? Int.max) <= lampDeathAt },
                      "no support event may occur after the lamp death")
        XCTAssertLessThan(unsupported.remainingEnemyHP[guardianID] ?? Int.max,
                          unsupported.initialEnemyHP[guardianID] ?? 0,
                          "the guardian must still take party damage after the lamp dies")
        let partyHPWasHit = partyIDs.contains { (unsupported.remainingPartyHP[$0] ?? 0) < (unsupported.initialPartyHP[$0] ?? 0) }
        XCTAssertTrue(partyHPWasHit, "the post-death case must include a real enemy hit, not only a missing support event")
    }
}
