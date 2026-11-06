import XCTest
@testable import WitchGameCore

final class UI48QALaunchGateTests: XCTestCase {
    private let required = ["--ui48-qa", "--qa-isolated", "--qa-save-key=11111111-1111-4111-8111-111111111111"]

    func testAcceptsRequiredAndDocumentedOptionalArguments() {
        XCTAssertTrue(UI48QALaunchGate.isValid(arguments: required))
        XCTAssertTrue(UI48QALaunchGate.isValid(arguments: ["WitchGathering"] + required + [
            "--ui48-screen=1", "--ui48-fixture=full", "--qa-readback-save",
            "-ApplePersistenceIgnoreState", "-XCTest"]
        ))
        XCTAssertTrue(UI48QALaunchGate.isValid(arguments: required + ["--ui48-screen=48", "--ui48-fixture=fresh"]))
        XCTAssertTrue(UI48QALaunchGate.isValid(arguments: required + ["--ui48-fixture=frontier"]))
        XCTAssertTrue(UI48QALaunchGate.isValid(arguments: required + ["--ui48-craft-observe"]))
    }

    func testRejectsMissingDuplicateUnknownAndOutOfRangeControls() {
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: ["--ui48-qa", "--qa-isolated"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-qa"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-screen=49"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-screen=01"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-screen=1", "--ui48-screen=2"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-fixture=unknown"]))
        for state in ["loading", "failed", "recovered", "future", "unrecoverable", "unknown"] {
            XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-state=\(state)"]), "accepted unsupported state: \(state)")
        }
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-state=loading", "--ui48-state=failed"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--qa-pose=idle"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-surprise"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: ["--ui48-craft-observe"]))
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--ui48-craft-observe", "--ui48-craft-observe"]))
    }

    func testSaveKeyMustBeOneCanonicalLowercaseUUIDNotAPathOrAmbiguousValue() {
        for key in ["", "not-a-uuid", "../11111111-1111-4111-8111-111111111111",
                    "11111111-1111-4111-8111-111111111111/../../save.json",
                    "11111111-1111-4111-8111-11111111111A", "11111111111141118111111111111111"] {
            let args = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + key]
            XCTAssertFalse(UI48QALaunchGate.isValid(arguments: args), "accepted unsafe key: \(key)")
        }
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: required + ["--qa-save-key=11111111-1111-4111-8111-111111111111"]))
    }

    func testOrdinaryAndPriorIsolatedRoutesRemainSeparate() throws {
        XCTAssertFalse(UI48QALaunchGate.isValid(arguments: []))
        XCTAssertEqual(try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: false, isolatedR146GateEnabled: false, arguments: []), .ordinaryR098)
        XCTAssertEqual(try StandardPlayStartupSelectionR169.resolve(
            developmentBuildEnabled: false, isolatedR146GateEnabled: true,
            arguments: ["--qa-isolated", "--qa-shared-party-work-r146", "--qa-save-key=11111111-1111-4111-8111-111111111111"]), .isolatedQAR146)
    }
}
