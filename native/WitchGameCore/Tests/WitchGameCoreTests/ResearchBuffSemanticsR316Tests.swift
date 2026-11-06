import XCTest
@testable import WitchGameCore

/// Mechanic fixture only: deterministic candidate-Core arithmetic, not normal-play
/// balance, canonical approval, native rendering, or a full catalog challenge.
final class ResearchBuffSemanticsR316Tests: XCTestCase {
    private let partyIDs: Set<String> = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"]
    private let enemyID = "B_R04_BUFF_PROBE"
    private let duration = 16_000
    private let seed: UInt64 = 316_044

    private func run(challenged: Bool) throws -> CombatResult {
        let party = partyIDs.sorted().map {
            Combatant(id: $0, maxHP: 50_000, attack: 1_000, defense: 0)
        }
        let enemy = Combatant(id: enemyID, maxHP: 1_000_000_000, attack: 1_000, defense: 0,
                              actionPattern: "standard", firstTelegraphMs: 2_500)
        return try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: seed,
                                           maxDurationMs: duration,
                                           challengeID: challenged ? "CH_R04_02" : nil)
    }

    private func eventTime(_ event: CombatEvent, file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        try XCTUnwrap(event.timestampMs, "event must have a deterministic timestamp", file: file, line: line)
    }

    private func partyLoss(_ result: CombatResult) -> Int {
        partyIDs.reduce(0) { $0 + (result.initialPartyHP[$1] ?? 0) - (result.remainingPartyHP[$1] ?? 0) }
    }

    private func enemyHitDamage(_ result: CombatResult) -> [CombatEvent] {
        result.events.filter { $0.kind == "enemy_hit" && $0.sourceID == enemyID && partyIDs.contains($0.targetID) }
    }

    private func partyDamage(_ result: CombatResult) -> [CombatEvent] {
        result.events.filter { partyIDs.contains($0.sourceID) && $0.targetID == enemyID
            && ["direct", "smith_hammer", "counter", "chase", "reflect"].contains($0.kind) }
    }

    func testEnemyBuffScalesRealIncomingDamageAndPartyHPExactlyOnce() throws {
        let active = try run(challenged: true)
        let baseline = try run(challenged: false)
        let buffs = active.events.filter { $0.kind == "enemy_buff" && $0.sourceID == enemyID }
        XCTAssertFalse(buffs.isEmpty, "R04_02 mechanic must activate at its authored action interval")
        XCTAssertFalse(baseline.events.contains { $0.kind == "enemy_buff" })

        let activeHits = enemyHitDamage(active)
        let baselineHits = enemyHitDamage(baseline)
        XCTAssertFalse(activeHits.isEmpty)
        XCTAssertEqual(activeHits.count, baselineHits.count, "challenge modifier must not alter attack scheduling")
        let baseByRoot = Dictionary(grouping: baselineHits, by: { $0.rootActionID ?? "" })
        XCTAssertEqual(baseByRoot.count, baselineHits.count, "each control hit must have a unique attack root")
        var buffedHitCount = 0
        for hit in activeHits {
            let root = try XCTUnwrap(hit.rootActionID)
            let control = try XCTUnwrap(baseByRoot[root]?.first, "same-root control hit must exist")
            XCTAssertEqual(control.targetID, hit.targetID, "paired input must select the same party target")
            let time = try eventTime(hit)
            let withinBuff = try buffs.contains { buff in
                let start = try eventTime(buff)
                return time >= start && time < start + 5_000
            }
            if withinBuff {
                buffedHitCount += 1
                XCTAssertEqual(hit.amount, control.amount * 12_000 / 10_000,
                               "R04_02's active enemy buff must scale actual post-defense hit damage by 1.2")
            } else {
                XCTAssertEqual(hit.amount, control.amount, "outside the buff window, paired damage remains baseline")
            }
        }
        XCTAssertGreaterThan(buffedHitCount, 0, "fixture must observe at least one hit during the buff window")
        XCTAssertFalse(active.events.contains { ["heal", "lamp_support"].contains($0.kind) },
                       "the controlled fixture has no healing that could mask HP loss")
        XCTAssertEqual(partyLoss(active), activeHits.reduce(0) { $0 + $1.amount },
                       "party HP loss must equal one count of actual enemy_hit damage")
        XCTAssertEqual(partyLoss(baseline), baselineHits.reduce(0) { $0 + $1.amount })
        XCTAssertGreaterThan(partyLoss(active), partyLoss(baseline),
                             "the buff must produce a real aggregate party HP difference")
    }

    func testPartyWeakenScalesRealOutgoingDamageAndEnemyHPExactlyOnce() throws {
        let active = try run(challenged: true)
        let baseline = try run(challenged: false)
        let weakenings = active.events.filter { $0.kind == "party_weaken" && $0.sourceID == enemyID }
        XCTAssertFalse(weakenings.isEmpty, "R04_02 must apply its party debuff after a positive enemy hit")
        XCTAssertFalse(baseline.events.contains { $0.kind == "party_weaken" })

        let activeHits = enemyHitDamage(active)
        XCTAssertFalse(activeHits.isEmpty)
        let activePartyDamage = partyDamage(active)
        let baselinePartyDamage = partyDamage(baseline)
        let baseByRoot = Dictionary(grouping: baselinePartyDamage, by: { $0.rootActionID ?? "" })
        XCTAssertEqual(baseByRoot.count, baselinePartyDamage.count, "control output roots must be unique")

        let weakenWindows = try weakenings.map { event -> (actorID: String, start: Int, end: Int) in
            let start = try eventTime(event)
            return (event.targetID, start, start + event.amount)
        }
        var weakenedDamageCount = 0
        for hit in activePartyDamage {
            let root = try XCTUnwrap(hit.rootActionID)
            let time = try eventTime(hit)
            guard weakenWindows.contains(where: { $0.actorID == hit.sourceID && time >= $0.start && time < $0.end }) else { continue }
            let control = try XCTUnwrap(baseByRoot[root]?.first, "same-root party attack must exist in control")
            XCTAssertEqual(control.sourceID, hit.sourceID)
            XCTAssertEqual(control.targetID, hit.targetID)
            XCTAssertEqual(hit.amount, control.amount * 8_500 / 10_000,
                           "active party_weaken window must scale real outgoing damage by 0.85")
            weakenedDamageCount += 1
        }
        XCTAssertGreaterThan(weakenedDamageCount, 0, "fixture must observe a party attack within a debuff window")

        let enemyInitial = try XCTUnwrap(active.initialEnemyHP[enemyID])
        let enemyRemaining = try XCTUnwrap(active.remainingEnemyHP[enemyID])
        let baselineInitial = try XCTUnwrap(baseline.initialEnemyHP[enemyID])
        let baselineRemaining = try XCTUnwrap(baseline.remainingEnemyHP[enemyID])
        let activeLoss = enemyInitial - enemyRemaining
        let baselineLoss = baselineInitial - baselineRemaining
        XCTAssertEqual(activeLoss, activePartyDamage.reduce(0) { $0 + $1.amount },
                       "enemy HP delta must reconcile to counted party damage events only")
        XCTAssertEqual(baselineLoss, baselinePartyDamage.reduce(0) { $0 + $1.amount })
        XCTAssertLessThan(activeLoss, baselineLoss, "the debuff must lower actual damage and leave the enemy with more HP")
        XCTAssertEqual(partyLoss(active), enemyHitDamage(active).reduce(0) { $0 + $1.amount },
                       "this outgoing-damage comparison must not double-count presentation/absorb events")
    }
}
