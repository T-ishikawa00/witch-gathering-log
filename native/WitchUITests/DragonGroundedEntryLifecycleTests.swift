import XCTest

/// Drives the real battle-entry path through an app background/foreground
/// transition. A host-side validator must inspect the lifecycle trace before
/// treating the paused mesh as verified; XCTest completion alone is not proof.
final class DragonGroundedEntryLifecycleTests: XCTestCase {
    func testGroundedEntryMeshFreezesAndResumesDuringRealBattle() {
        let app = XCUIApplication()
        let saveKey = "dragon-entry-lifecycle-" + UUID().uuidString

        let identity = XCTAttachment(string: saveKey)
        identity.name = "dragon_grounded_entry_lifecycle_save_key"
        identity.lifetime = .keepAlways
        add(identity)

        app.launchArguments = [
            "--qa-isolated",
            "--qa-save-key=" + saveKey,
            "--qa-fixture=challenge",
            "--qa-persist-fixture",
            "--screen=探索",
            "--qa-entry-preparation-delay-ms=3000",
            "--qa-dragon-mesh-r004",
            "--qa-dragon-grounded-entry-r005",
            "--qa-battle-entry-trace",
            "--qa-entry-lifecycle-trace"
        ]
        app.launch()

        // Start the real encounter only after the app and accessibility tree
        // are ready. Launch-time --qa-encounter starts during async app setup,
        // so XCTest can return after the 0.6-second arrival has already ended.
        let region = app.buttons["region_R05"]
        XCTAssertTrue(region.waitForExistence(timeout: 30), "The persisted challenge fixture should expose its current expedition")
        region.tap()
        let chooseR04 = app.buttons["choose_region_R04"]
        XCTAssertTrue(chooseR04.waitForExistence(timeout: 5))
        XCTAssertTrue(chooseR04.isEnabled, "The challenge fixture should make R04 reachable")
        chooseR04.tap()
        let departed = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "へ出発。" )).firstMatch
        XCTAssertTrue(departed.waitForExistence(timeout: 10), "Wait for the actual region selection command")

        let controls = app.buttons["explore_controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        controls.tap()
        let boss = app.buttons["fight_B_R04_B"]
        for _ in 0..<3 where !boss.exists {
            let nextPage = app.buttons["enemies_next"]
            guard nextPage.waitForExistence(timeout: 5), nextPage.isEnabled else { break }
            nextPage.tap()
        }
        XCTAssertTrue(boss.waitForExistence(timeout: 10), "R04 boss should be selectable from the normal encounter list")
        XCTAssertTrue(boss.isHittable)
        let tapStartedAt = ProcessInfo.processInfo.systemUptime
        boss.tap()

        // The isolated QA hook stages battle preparation for 3 seconds before
        // starting the unchanged 0.6-second arrival. Anchor Home timing to the
        // UI tap start: no accessibility query or screenshot may delay it.
        // If XCTest itself returns late, the host must mark entry coverage
        // INCONCLUSIVE rather than stretching or speeding up the real action.
        let homeDeadline = tapStartedAt + 3.60
        let remaining = homeDeadline - ProcessInfo.processInfo.systemUptime
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        attachScreenshot(from: app, named: "grounded_entry_after_background_resume")

        // The encounter may finish while backgrounded. Wait for the normal
        // terminal UI, accepting either victory or defeat as a real outcome.
        let homeTab = app.buttons["tab_家"]
        let terminal = app.staticTexts["battle_resolution"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 180), "The app should show a normal victory or defeat result")
        let resolutionText = terminal.label
        XCTAssertFalse(resolutionText.isEmpty, "Victory and defeat are both valid terminal outcomes")
        let homeReady = NSPredicate(format: "exists == true AND enabled == true")
        expectation(for: homeReady, evaluatedWith: homeTab)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        attachScreenshot(from: app, named: "grounded_entry_after_resume_and_battle")

        let outcome = XCTAttachment(string: resolutionText)
        outcome.name = "dragon_grounded_entry_lifecycle_battle_outcome"
        outcome.lifetime = .keepAlways
        add(outcome)
    }

    private func attachScreenshot(from app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
