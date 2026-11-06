import XCTest

/// Isolated synthetic fixture tests. They prove the renderer path under a saved QA scenario,
/// not earned acquisition, final art approval, or normal player progression.
final class LunaBookNativeContinuityTestsR010: XCTestCase {
    private func capture(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func runBookEncounter(failureAfterSuccess: Bool) {
        let app = XCUIApplication()
        app.terminate()
        let key = "r010-\(failureAfterSuccess ? "fault" : "control")-\(UUID().uuidString)"
        let identity = XCTAttachment(string:key)
        identity.name = "luna_book_r010_save_key"
        identity.lifetime = .keepAlways
        add(identity)
        app.launchArguments = [
            "--qa-isolated", "--qa-save-key="+key,
            "--qa-fixture=book-EQ_A_01", "--qa-persist-fixture",
            "--qa-encounter=B_R01_A",
            "--qa-luna-book-native-trace-r010",
            "--qa-luna-execute-recover-midpoint-r050"
        ] + (failureAfterSuccess ? ["--qa-luna-book-failure-after-success-r010"] : [])
        app.launch()
        XCTAssertTrue(app.staticTexts["battle_progress"].waitForExistence(timeout:20), "The isolated encounter should start")
        capture(failureAfterSuccess ? "luna_r010_fault_during_battle" : "luna_r010_control_during_battle", from: app)
        let home = app.buttons["tab_家"]
        let finished = NSPredicate(format:"enabled == true")
        expectation(for:finished,evaluatedWith:home)
        waitForExpectations(timeout:90)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        capture(failureAfterSuccess ? "luna_r010_fault_after_battle" : "luna_r010_control_after_battle", from: app)
        app.terminate()
        // Host validation reads last_battle_art.json from this unique save's container.
    }

    func testNormalBookPathAndR050MidpointControlR010() {
        runBookEncounter(failureAfterSuccess:false)
    }

    func testMissingWalkBodyAfterSuccessfulBookFallsBackAndCleansR010() {
        runBookEncounter(failureAfterSuccess:true)
    }
}
