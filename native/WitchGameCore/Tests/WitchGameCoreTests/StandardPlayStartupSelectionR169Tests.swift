import XCTest
@testable import WitchGameCore

final class StandardPlayStartupSelectionR169Tests: XCTestCase {
    func testBuildModesKeepOrdinaryAndExistingQARoutesDistinct() throws {
        XCTAssertEqual(try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: false, isolatedR146GateEnabled: false, arguments: []), .ordinaryR098)
        XCTAssertEqual(try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: false, isolatedR146GateEnabled: true,
            arguments: ["--qa-isolated", "--qa-shared-party-work-r146", "--qa-save-key=11111111-1111-4111-8111-111111111111"]), .isolatedQAR146)
    }

    func testExplicitDevelopmentBuildUsesDedicatedNamespaceWithoutArguments() throws {
        let mode = try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: true, isolatedR146GateEnabled: false, arguments: [])
        XCTAssertEqual(mode, .standardPlayR169)
        XCTAssertTrue(mode.usesSharedPartyWork)
        XCTAssertEqual(mode.saveNamespace, "Witch03to05DevelopmentR169")
        XCTAssertEqual(StandardPlayStartupSelectionR169.Mode.ordinaryR098.saveNamespace, "Witch03to05R1")
    }

    func testAnyQAArgumentFailsClosedInDevelopmentMode() {
        for argument in ["--qa-isolated", "--qa-save-key=11111111-1111-4111-8111-111111111111", "--qa-pose=idle", "--ui48-screen=4"] {
            XCTAssertThrowsError(try StandardPlayStartupSelectionR169.resolve(
                developmentBuildEnabled: true, isolatedR146GateEnabled: false, arguments: [argument]))
        }
        XCTAssertThrowsError(try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: true, isolatedR146GateEnabled: true, arguments: []))
    }

    func testCompleteUI48GateUsesStandardGameplayNamespace() throws {
        let args = ["WitchGathering", "--ui48-qa", "--qa-isolated",
                    "--qa-save-key=11111111-1111-4111-8111-111111111111", "--ui48-screen=48",
                    "--ui48-fixture=fresh", "--qa-readback-save", "-ApplePersistenceIgnoreState"]
        XCTAssertTrue(UI48QALaunchGate.isValid(arguments: args))
        let mode = try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: true, isolatedR146GateEnabled: false, arguments: args)
        XCTAssertEqual(mode, .standardPlayR169)
        XCTAssertEqual(mode.saveNamespace, "Witch03to05DevelopmentR169")
    }
}
