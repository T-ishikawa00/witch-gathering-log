import XCTest

/// Lifecycle driver. The host independently validates the actual SpriteKit
/// geometry readbacks from the isolated app's retained JSON receipt.
final class DragonWalkMeshDiagnosticTests: XCTestCase {
    func testMeshWalkSurvivesBackgroundAndRestoresIdle() {
        let app = XCUIApplication()
        let key = "dragon-mesh-pause-" + UUID().uuidString
        let identity = XCTAttachment(string: key)
        identity.name = "dragon_mesh_pause_save_key"
        identity.lifetime = .keepAlways
        add(identity)
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
            "--art-audit=ACT_B_R04_B", "--qa-dragon-mesh-r004", "--qa-dragon-mesh-pause-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["四脚歩行の停止検証"].waitForExistence(timeout: 30))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "dragon_mesh_before_background"; before.lifetime = .keepAlways; add(before)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertTrue(app.staticTexts["四脚歩行の停止検証"].waitForExistence(timeout: 10))
        let resumed = XCTAttachment(screenshot: app.screenshot())
        resumed.name = "dragon_mesh_after_background"; resumed.lifetime = .keepAlways; add(resumed)
        XCTAssertTrue(app.staticTexts["四脚歩行の停止検証を完了"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "dragon_mesh_restored_idle"; restored.lifetime = .keepAlways; add(restored)
    }
}
