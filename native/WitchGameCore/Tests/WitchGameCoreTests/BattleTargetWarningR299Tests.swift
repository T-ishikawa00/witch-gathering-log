import XCTest
@testable import WitchGameCore

final class BattleTargetWarningR299Tests: XCTestCase {
    private let enemyID = "B_R04_B"
    private let party: Set<String> = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]

    private func makeReducer(hp: Int = 1_140) -> BattleTargetWarningR299 {
        BattleTargetWarningR299(initialEnemyHP: [enemyID: hp], partyIDs: party)
    }

    private func event(_ kind: String, source: String = "B_R04_B", target: String,
                       root: String? = "enemy:B_R04_B:3", amount: Int = 1) -> CombatEvent {
        CombatEvent(tick: 1, kind: kind, sourceID: source, targetID: target,
                    amount: amount, rootActionID: root)
    }

    func testR297ObservedEventSequenceKeepsAuthoredAimSeparateFromCoverRedirect() {
        var reducer = makeReducer()
        // R297 persisted trace: the heavy telegraph points at the Witch.
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        XCTAssertEqual(reducer.current?.targetID, "C_WITCH")
        XCTAssertEqual(reducer.current?.isPartyWide, false)

        // The Smith redirects the hit, but that does not rewrite the telegraph.
        reducer.consume(event("cover_redirect", source: "C_SMITH", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        XCTAssertEqual(reducer.current?.targetID, "C_WITCH")
        reducer.consume(event("enemy_hit", target: "C_SMITH", root: "enemy:B_R04_B:3", amount: 35))
        XCTAssertNil(reducer.current)

        // The saved party-wide heavy uses the same heavy event kind, distinguished
        // by its explicit party sentinel rather than by inferring future recipients.
        reducer.consume(event("telegraph_heavy", target: "party", root: "enemy:B_R04_B:6"))
        XCTAssertEqual(reducer.current?.targetID, "party")
        XCTAssertEqual(reducer.current?.isPartyWide, true)
        reducer.consume(event("enemy_hit", target: "C_WITCH", root: "enemy:B_R04_B:6", amount: 35))
        XCTAssertNil(reducer.current)
    }

    func testAoeKindAndExplicitPartyMemberTargetAreRepresentedWithoutGuessing() {
        var reducer = makeReducer()
        reducer.consume(event("telegraph_aoe", target: "party", root: "enemy:B_R04_B:9"))
        XCTAssertEqual(reducer.current?.isPartyWide, true)
        reducer.consume(event("telegraph_aoe", target: "C_SMITH", root: "enemy:B_R04_B:10"))
        XCTAssertEqual(reducer.current?.targetID, "C_SMITH")
        XCTAssertEqual(reducer.current?.isPartyWide, false)
    }

    func testIgnoresPlaceholderPartyCasterUnknownTargetAndMissingRoot() {
        var reducer = makeReducer()
        reducer.consume(event("telegraph_heavy", source: "C_SMITH", target: "C_WITCH"))
        reducer.consume(event("enemy_cast_start", target: "enemy:B_R04_B:placeholder"))
        reducer.consume(event("enemy_telegraph", target: "future_actor"))
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: nil))
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: "  \n"))
        XCTAssertNil(reducer.current)
    }

    func testUnrelatedEnemyHitDoesNotClearAndExactFirstHitDoes() {
        var reducer = makeReducer()
        reducer.consume(event("enemy_telegraph", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        reducer.consume(event("enemy_hit", source: "B_OTHER", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        XCTAssertNotNil(reducer.current)
        reducer.consume(event("enemy_hit", target: "C_WITCH", root: "enemy:B_R04_B:other"))
        XCTAssertNotNil(reducer.current)
        reducer.consume(event("enemy_hit", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        XCTAssertNil(reducer.current)
        reducer.consume(event("enemy_hit", target: "C_FAMILIAR", root: "enemy:B_R04_B:3"))
        XCTAssertNil(reducer.current)
    }

    func testInterruptClearsOnlyMatchingEnemyRootAndTarget() {
        var reducer = makeReducer()
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        reducer.consume(event("cast_interrupt", source: "C_APPRENTICE", target: "B_R04_B", root: "enemy:B_R04_B:other"))
        XCTAssertNotNil(reducer.current)
        reducer.consume(event("cast_interrupt", source: "C_APPRENTICE", target: "B_OTHER", root: "enemy:B_R04_B:3"))
        XCTAssertNotNil(reducer.current)
        reducer.consume(event("cast_interrupt", source: "C_APPRENTICE", target: "B_R04_B", root: "enemy:B_R04_B:3"))
        XCTAssertNil(reducer.current)
    }

    func testKnownEnemyDeathAndExplicitResetClearWarning() {
        var reducer = makeReducer(hp: 20)
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        reducer.consume(event("direct", source: "C_WITCH", target: "B_R04_B", root: "C_WITCH:basic:1", amount: 19))
        XCTAssertNotNil(reducer.current)
        reducer.consume(event("direct", source: "C_WITCH", target: "B_R04_B", root: "C_WITCH:basic:2", amount: 1))
        XCTAssertNil(reducer.current)

        var active = makeReducer()
        active.consume(event("telegraph_heavy", target: "party", root: "enemy:B_R04_B:4"))
        active.reset()
        XCTAssertNil(active.current)
    }

    func testUnknownEnemyDamageDoesNotClearAllowedSourceWarning() {
        var reducer = makeReducer()
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        reducer.consume(event("direct", source: "C_WITCH", target: "B_OTHER", root: "C_WITCH:basic:1", amount: 10_000))
        XCTAssertEqual(reducer.current?.sourceID, enemyID)
        var invalid = BattleTargetWarningR299(initialEnemyHP: ["B_R04_B": 0], partyIDs: party)
        invalid.consume(event("telegraph_heavy", target: "C_WITCH"))
        XCTAssertNil(invalid.current)
    }

    func testNextRootFromSameEnemySupersedesTheOlderWarning() {
        var reducer = makeReducer()
        reducer.consume(event("telegraph_heavy", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        reducer.consume(event("telegraph_aoe", target: "party", root: "enemy:B_R04_B:6"))
        XCTAssertEqual(reducer.current?.rootActionID, "enemy:B_R04_B:6")
        XCTAssertEqual(reducer.current?.targetID, "party")
        reducer.consume(event("enemy_hit", target: "C_WITCH", root: "enemy:B_R04_B:3"))
        XCTAssertEqual(reducer.current?.rootActionID, "enemy:B_R04_B:6")
    }
}
