import XCTest
@testable import WitchGameCore

final class ChallengeDotMechanicR256Tests: XCTestCase {
    func testR02ChallengeAppliesDotAndKeepsPeriodicHealWithCatalogScenario() throws {
        let catalog = try GameCatalog.bundledTestOverlay()
        let scenario = try catalog.challengeCombatScenario("CH_R02_01")

        XCTAssertEqual(scenario.enemies.map(\.id), ["E_R02_01", "E_R02_02"])
        XCTAssertEqual(scenario.enemies.first?.actionPattern, "dot")
        XCTAssertEqual(scenario.enemies.last?.actionPattern, "armor")

        let actorIDs = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]
        let party = actorIDs.map { catalog.projectCombatant(for: $0, with: []) }
        let result = try R6TimelineSimulator.run(
            party: party,
            enemies: scenario.enemies,
            seed: 51,
            maxDurationMs: 35_000,
            challengeID: "CH_R02_01",
            entityPresentation: scenario.entityPresentation
        )

        let applications = result.events.filter { $0.kind == "dot_applied" }
        XCTAssertFalse(applications.isEmpty, "catalog challenge should actually apply its DoT")
        XCTAssertTrue(applications.allSatisfy { $0.sourceID == "E_R02_01" })
        XCTAssertTrue(result.events.contains { $0.kind == "dot_tick" }, "DoT should tick after application")
        XCTAssertTrue(result.events.contains { $0.kind == "enemy_heal_cycle" }, "periodic healing remains part of the challenge")

        let initial = result.initialPartyHP.merging(result.initialEnemyHP, uniquingKeysWith: { first, _ in first })
        let actual = result.remainingPartyHP.merging(result.remainingEnemyHP, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(R6CombatPresentationSemantics.replay(events: result.events, initialHP: initial), actual)
    }
}
