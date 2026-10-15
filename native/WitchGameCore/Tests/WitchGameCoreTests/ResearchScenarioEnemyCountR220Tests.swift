import XCTest
@testable import WitchGameCore

/// Candidate-only consistency regression. The referenced Endgame catalog remains unapproved.
final class ResearchScenarioEnemyCountR220Tests: XCTestCase {
    func testR0102UsesAtMostThreeEnemiesAndOtherAddScenariosRemainUnchanged() throws {
        let profile = try GameRuntimeConfigurationR098.resolve()
        let r0102 = try profile.catalog.challengeCombatScenario("CH_R01_02")
        XCTAssertEqual(r0102.enemies.count, 3, "two catalog enemies plus one support add matches the 2–3 total-unit design")
        XCTAssertTrue(Set(r0102.enemies.map(\.id)).isSuperset(of: ["E_R01_02", "E_R01_03", "CH_R01_02_ADD_1"]))
        XCTAssertFalse(r0102.enemies.contains { $0.id == "CH_R01_02_ADD_2" })

        // The bounded fix must not change the two neighboring multi-enemy scenarios.
        XCTAssertEqual(try profile.catalog.challengeCombatScenario("CH_R02_03").enemies.count, 4)
        XCTAssertEqual(try profile.catalog.challengeCombatScenario("CH_R03_03").enemies.count, 4)
    }
}
