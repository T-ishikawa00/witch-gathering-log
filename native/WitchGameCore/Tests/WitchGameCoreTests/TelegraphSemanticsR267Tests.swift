import XCTest
@testable import WitchGameCore

final class TelegraphSemanticsR267Tests: XCTestCase {
    private let party = ["C_WITCH", "C_APPRENTICE", "C_SMITH", "C_FAMILIAR"].map {
        Combatant(id: $0, maxHP: 100_000, attack: 1, defense: 0)
    }
    private let telegraphKinds: Set<String> = ["enemy_telegraph", "telegraph_heavy", "telegraph_aoe"]

    func testR01_03AlternatesSingleTargetMultiHitThenSingleTargetHeavyWithMatchingTells() throws {
        let result = try R6TimelineSimulator.run(
            party: party,
            enemies: [Combatant(id: "B_R01_B", maxHP: 100_000, attack: 100, defense: 0,
                               actionPattern: "rootBranchCycle", firstTelegraphMs: 0)],
            seed: 811, maxDurationMs: 9_000, challengeID: "CH_R01_03"
        )
        let events = result.events.filter { $0.sourceID == "B_R01_B" }
        let root1 = try XCTUnwrap(events.first { $0.rootActionID == "enemy:B_R01_B:1" && telegraphKinds.contains($0.kind) })
        XCTAssertEqual(root1.kind, "enemy_telegraph", "first root is the repeated single-target action")
        XCTAssertNotEqual(root1.targetID, "party")
        let root1Hits = events.filter { $0.rootActionID == root1.rootActionID && $0.kind == "enemy_hit" }
        XCTAssertEqual(root1Hits.count, 3, "first root is three hits against one target")
        XCTAssertEqual(Set(root1Hits.map(\.targetID)), Set([root1.targetID]))

        let root2 = try XCTUnwrap(events.first { $0.rootActionID == "enemy:B_R01_B:2" && telegraphKinds.contains($0.kind) })
        XCTAssertEqual(root2.kind, "telegraph_heavy", "second root is a single-target heavy, never an area tell")
        XCTAssertNotEqual(root2.targetID, "party")
        let root2Hits = events.filter { $0.rootActionID == root2.rootActionID && $0.kind == "enemy_hit" }
        XCTAssertEqual(root2Hits.count, 1)
        XCTAssertEqual(Set(root2Hits.map(\.targetID)), Set([root2.targetID]))
    }

    func testNormalRootBranchAreaCycleStillWarnsAndHitsTheWholeParty() throws {
        let result = try R6TimelineSimulator.run(
            party: party,
            enemies: [Combatant(id: "B_R01_B", maxHP: 100_000, attack: 100, defense: 0,
                               actionPattern: "rootBranchCycle", firstTelegraphMs: 0)],
            seed: 811, maxDurationMs: 8_000
        )
        let first = try XCTUnwrap(result.events.first {
            $0.sourceID == "B_R01_B" && $0.rootActionID == "enemy:B_R01_B:1" && telegraphKinds.contains($0.kind)
        })
        XCTAssertEqual(first.kind, "enemy_telegraph")
        let area = try XCTUnwrap(result.events.first {
            $0.sourceID == "B_R01_B" && $0.rootActionID == "enemy:B_R01_B:2" && telegraphKinds.contains($0.kind)
        })
        XCTAssertEqual(area.kind, "telegraph_aoe")
        XCTAssertEqual(area.targetID, "party")
        let partyHits = result.events.filter {
            $0.sourceID == "B_R01_B" && $0.rootActionID == area.rootActionID && $0.kind == "enemy_hit"
        }
        XCTAssertEqual(partyHits.count, party.count)
        XCTAssertEqual(Set(partyHits.map(\.targetID)), Set(party.map(\.id)))
    }
}
