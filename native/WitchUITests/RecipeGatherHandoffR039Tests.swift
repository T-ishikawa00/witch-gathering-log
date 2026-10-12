import XCTest

/// One synthetic UI path through the existing gather command and save/reopen flow.
/// The five-minute wait is real elapsed time, not accelerated test time.
final class RecipeGatherHandoffR039Tests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }

    func testTrackedRecipeExplicitGatherClaimAndRelaunch() {
        let key = "recipe-goal-r037-" + UUID().uuidString
        launch(key: key, screen: "工房")
        let detail = app.buttons["recipe_detail_RC_EQ_BODY_01"]
        scrollUntilHittable(detail)
        detail.tap()

        let selected = app.staticTexts["recipe_goal_selected"]
        XCTAssertTrue(selected.waitForExistence(timeout: 12), "fixture starts with the tracked catalog recipe")
        let source = app.buttons["goal_gather_source_M_R01_G3_R01"]
        scrollUntilHittable(source)
        XCTAssertTrue(source.isEnabled)
        capture("goal_before_navigation", key)
        source.tap()

        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["recipe_gather_handoff_summary"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["recipe_gather_apply"].exists)
        capture("route_confirm_not_yet_applied", key)
        // Host consumer checks baseline == pre-navigation == route-confirm snapshots.
        // No command is issued until this explicit confirmation is tapped.
        app.buttons["recipe_gather_apply"].tap()
        XCTAssertTrue(waitForAbsence(app.staticTexts["recipe_gather_handoff_summary"], timeout: 12),
                      "the applied handoff is consumed; the temporary route summary should disappear")
        let selectedTarget = app.staticTexts["explore_gather_target"]
        XCTAssertTrue(selectedTarget.waitForExistence(timeout: 8))
        XCTAssertEqual(selectedTarget.label, "琥珀樹脂を採集中")
        capture("route_applied", key)

        // The R01 authored work interval is 300 seconds. Keep the app in the
        // foreground; no QA clock, Core timestamp injection, or direct resource write.
        let waitStart = Date()
        let interval: TimeInterval = 305
        while Date().timeIntervalSince(waitStart) < interval {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let home = app.buttons["tab_家"]
        XCTAssertTrue(home.waitForExistence(timeout: 8))
        XCTAssertTrue(home.isHittable, "home tab is outside the content scroll viewport and must be directly tappable")
        home.tap()
        let claim = app.buttons["claim_offline"]
        scrollUntilHittable(claim, in: app.scrollViews["home_scroll"])
        XCTAssertTrue(claim.isEnabled)
        capture("before_normal_claim", key)
        claim.tap()
        XCTAssertTrue(app.staticTexts["採集の成果をしまいました。"].waitForExistence(timeout: 15)
                      || app.staticTexts["採集の成果"].waitForExistence(timeout: 15))
        capture("after_normal_claim", key)

        app.terminate()
        launch(key: key, screen: "工房")
        let summary = app.buttons["tracked_recipe_summary"]
        scrollUntilHittable(summary)
        summary.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 12))
        let row = app.descendants(matching: .any).matching(identifier: "goal_material_M_R01_G3").firstMatch
        scrollUntilHittable(row)
        XCTAssertTrue(row.label.contains("所持 1 / 必要"), "normal gather settlement should lower the saved shortage")
        capture("reopened_shortage_reduced", key)
        identity(key)
    }

    private func launch(key: String, screen: String) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL", "--qa-isolated", "--qa-save-key=" + key,
            "--qa-fixture=recipe-goal-r037", "--qa-recipe-goal=gather-shortage",
            "--qa-persist-fixture", "--qa-recipe-goal-baseline", "--screen=" + screen]
        app.launch()
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 25))
    }

    private func scrollUntilHittable(_ element: XCUIElement, in scroll: XCUIElement? = nil,
                                    timeout: TimeInterval = 80) {
        let deadline = Date().addingTimeInterval(timeout)
        var steps = 0
        while Date() < deadline {
            let active = scroll ?? (app.scrollViews["sheet_scroll_制作目標"].exists
                                    ? app.scrollViews["sheet_scroll_制作目標"]
                                    : app.scrollViews["workshop_scroll"])
            let scroll = active
            guard scroll.waitForExistence(timeout: 2) else { break }
            let viewport = scroll.frame.insetBy(dx: 1, dy: 3)
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let button = exists && element.elementType == .button
            let visible = exists && !frame.isEmpty && (button ? viewport.contains(frame) : viewport.intersects(frame))
            if visible && (!button || element.isHittable) { return }
            let towardEnd = exists && !frame.isEmpty ? frame.midY >= viewport.midY : (steps / 12 == 0 || (steps / 12) % 3 == 2)
            let watchingGoal = app.scrollViews["sheet_scroll_制作目標"].exists
            let trackedBeforeDrag = watchingGoal ? app.buttons["clear_recipe_goal"].exists : false
            let untrackedBeforeDrag = watchingGoal ? app.buttons["track_recipe_goal"].exists : false
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardEnd ? 0.68 : 0.32))
            let finish = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardEnd ? 0.32 : 0.68))
            start.press(forDuration: 0.10, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.10)
            if watchingGoal {
                XCTAssertEqual(app.buttons["clear_recipe_goal"].exists, trackedBeforeDrag,
                               "scrolling must not clear or create a tracked goal")
                XCTAssertEqual(app.buttons["track_recipe_goal"].exists, untrackedBeforeDrag,
                               "scrolling must not change tracked-goal state")
            }
            steps += 1
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "recipe_gather_scroll_failure_\(UUID().uuidString)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("element did not become visible in its content scroll viewport")
    }

    private func capture(_ name: String, _ key: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "recipe_gather_\(name)_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func identity(_ key: String) {
        let attachment = XCTAttachment(string: "saveKey=\(key)\nscenario=gather-shortage\nclassification=SYNTHETIC_QA_FIXTURE_NOT_EARNED\nrecipeID=RC_EQ_BODY_01\nmaterialID=M_R01_G3\nsettlement=normal_claimOffline_after_305_real_seconds")
        attachment.name = "recipe_gather_identity_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
