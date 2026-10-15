import XCTest
@testable import WitchGameCore

final class EnemyExecuteCoalescerR154Tests: XCTestCase {
    func testOnlyRepeatedSameActorRootGenerationAndFrameCoalesces() {
        var value = EnemyExecuteCoalescerR154()
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:2", sceneGeneration: 4, sceneFrame: 624))
        value.recordAccepted(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:2", sceneGeneration: 4, sceneFrame: 624)
        XCTAssertTrue(value.shouldCoalesce(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:2", sceneGeneration: 4, sceneFrame: 624))
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:3", sceneGeneration: 4, sceneFrame: 624))
        // An intervening different root clears the old accepted identity even
        // if its controller request later fails; it cannot merge across it.
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:2", sceneGeneration: 4, sceneFrame: 624))
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_B_R01_A", rootActionID: "enemy:B:2", sceneGeneration: 4, sceneFrame: 624))
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:2", sceneGeneration: 4, sceneFrame: 625))
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_B_R01_B", rootActionID: "enemy:B:2", sceneGeneration: 5, sceneFrame: 624))
    }

    func testMissingIdentityNeverCoalescesAndBreaksPriorRun() {
        var value = EnemyExecuteCoalescerR154()
        value.recordAccepted(actorID: "ACT_E_R01_01", rootActionID: "enemy:E:1", sceneGeneration: 0, sceneFrame: 7)
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_E_R01_01", rootActionID: nil, sceneGeneration: 0, sceneFrame: 7))
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_E_R01_01", rootActionID: "enemy:E:1", sceneGeneration: 0, sceneFrame: 7))
    }

    func testPriorityRequestClearsDeduplicationAndRejectedStartIsNotRemembered() {
        var value = EnemyExecuteCoalescerR154()
        value.recordAccepted(actorID: "ACT_E_R01_02", rootActionID: "enemy:E:2", sceneGeneration: 1, sceneFrame: 9)
        value.clear(actorID: "ACT_E_R01_02")
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_E_R01_02", rootActionID: "enemy:E:2", sceneGeneration: 1, sceneFrame: 9))
        // A failed controller play has no recordAccepted call, so the next request retries.
        XCTAssertFalse(value.shouldCoalesce(actorID: "ACT_E_R01_02", rootActionID: "enemy:E:2", sceneGeneration: 1, sceneFrame: 9))
    }

    func testGateDefaultsOffAndRequiresSimulatorIsolationAndCanonicalSaveKey() {
        let key = "15200000-0000-4000-8000-000000000001"
        let base = ["--qa-isolated", "--qa-save-key=" + key, EnemyExecuteCoalescingGateR154.flag]
        let environment = ["SIMULATOR_UDID": "device", "SIMULATOR_DEVICE_NAME": "iPhone"]
        XCTAssertFalse(EnemyExecuteCoalescingGateR154.isEnabled(arguments: [], environment: environment, isSimulator: true))
        XCTAssertFalse(EnemyExecuteCoalescingGateR154.isEnabled(arguments: base, environment: environment, isSimulator: false))
        XCTAssertTrue(EnemyExecuteCoalescingGateR154.isEnabled(arguments: base, environment: environment, isSimulator: true))
        XCTAssertFalse(EnemyExecuteCoalescingGateR154.isEnabled(arguments: base + [EnemyExecuteCoalescingGateR154.flag], environment: environment, isSimulator: true))
        XCTAssertFalse(EnemyExecuteCoalescingGateR154.isEnabled(arguments: ["--qa-isolated", "--qa-save-key=not-a-uuid", EnemyExecuteCoalescingGateR154.flag], environment: environment, isSimulator: true))
    }
}
