import XCTest

/// Visible UI replay only. The runner stages the already-cleared earned save
/// before this test and supplies its fresh UUID key and challenge ID as env.
/// No challenge/fixture dispatch argument is accepted by this test.
final class R058VisibleChallengeTests: XCTestCase {
    private let app = XCUIApplication()

    func testVisibleReplayCH_R02_03() throws { try replay(challengeID: "CH_R02_03", observeMoth: true) }
    func testVisibleReplayCH_R04_02() throws { try replay(challengeID: "CH_R04_02", observeMoth: false) }
    func testVisibleReplayCH_R05_02() throws { try replay(challengeID: "CH_R05_02", observeMoth: false) }

    private func replay(challengeID expectedID: String, observeMoth: Bool) throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let challengeID = try XCTUnwrap(environment["R058_CHALLENGE_ID"], "Runner must set R058_CHALLENGE_ID")
        let saveKey = try XCTUnwrap(environment["R058_SAVE_KEY"], "Runner must set R058_SAVE_KEY")
        XCTAssertEqual(challengeID, expectedID)
        XCTAssertNotNil(UUID(uuidString: saveKey), "The same fresh UUID must name the staged save and app launch key")

        // The only R058 argument enables observation. It does not enable the
        // moth registration and cannot select/dispatch a challenge by itself.
        app.launchArguments = ["--qa-isolated", "--qa-save-key=\(saveKey)", "--screen=探索"]
        if observeMoth { app.launchArguments.append("--qa-effect-routes-r058=\(challengeID)") }
        XCTAssertFalse(app.launchArguments.contains(where: {
            $0.hasPrefix("--qa-challenge=") || $0.hasPrefix("--qa-fixture=") ||
            $0 == "--qa-moth-idle-registration-r050" || $0 == "--qa-moth-idle-baseline-r050" ||
            $0.hasPrefix("--art-audit=")
        }))
        app.launch()
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout: 25), "Ordinary Explore screen should be visible")
        let journalTab = app.buttons["tab_採集帳"]
        XCTAssertTrue(journalTab.waitForExistence(timeout: 10))
        journalTab.tap()

        let challenge = app.buttons["challenge_\(challengeID)"]
        var visibleAndHittable = false
        for _ in 0..<24 {
            if challenge.exists && challenge.isHittable { visibleAndHittable = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(visibleAndHittable, "The exact unlocked challenge must be reachable through the visible journal")
        XCTAssertTrue(challenge.isEnabled)
        capture("r058_\(challengeID)_before_tap")
        attachAXTree("r058_\(challengeID)_before_tap_ax")

        // Exactly one user-visible action starts the already-cleared replay.
        challenge.tap()
        attachJSON(["schema": "r058-visible-ui-action-v1", "mode": "visible_ui",
                    "challengeID": challengeID, "saveKey": saveKey,
                    "tappedAXIdentifier": "challenge_\(challengeID)", "tapCount": 1,
                    "launchArguments": app.launchArguments,
                    "restartReadbackRequested": true], name: "r058_\(challengeID)_visible_action_receipt")
        let completion = app.staticTexts["研究課題を達成しました。"]
        XCTAssertTrue(completion.waitForExistence(timeout: 240), "Challenge should resolve through normal UI flow")
        capture("r058_\(challengeID)_completed")
        attachAXTree("r058_\(challengeID)_completed_ax")
        app.terminate()

        // Restart the same save key without observer or challenge routing flags.
        app.launchArguments = ["--qa-isolated", "--qa-readback-save", "--qa-save-key=\(saveKey)", "--screen=採集帳"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout: 25), "Restarted model must reach the journal-ready screen")
        let restartedChallenge = app.buttons["challenge_\(challengeID)"]
        var restartReachable = false
        for _ in 0..<24 {
            if restartedChallenge.exists && restartedChallenge.isHittable { restartReachable = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(restartReachable, "The completed challenge remains reachable after same-key restart")
        capture("r058_\(challengeID)_same_key_restart")
        attachJSON(["schema": "r058-same-key-restart-observed-v1", "challengeID": challengeID,
                    "saveKey": saveKey, "launchArguments": app.launchArguments,
                    "qaSaveReadbackFlag": app.launchArguments.contains("--qa-readback-save"),
                    "journalReadyAXIdentifier": "tab_採集帳",
                    "completedChallengeReachable": restartReachable], name: "r058_\(challengeID)_restart_receipt")
        attachAXTree("r058_\(challengeID)_restart_ax")
        app.terminate()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachJSON(_ value: [String: Any], name: String) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not attach structured QA metadata: \(error)")
        }
    }

    private func attachAXTree(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
