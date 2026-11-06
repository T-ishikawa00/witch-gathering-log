import XCTest

/// Six synthetic UI cases. These exercise normal dispatch/persistence, but their
/// fixture-seeded resources are not earned progression evidence.
final class RecipeGoalCandidateTests: XCTestCase {
    private let app = XCUIApplication()
    private let starterWeaponID = "10000000-0000-4000-8000-000000000001"
    private var scrollDiagnostics: [String] = []

    override func tearDown() {
        if !scrollDiagnostics.isEmpty {
            let attachment = XCTAttachment(string: scrollDiagnostics.joined(separator: "\n"))
            attachment.name = "recipe_goal_scroll_diagnostics_" + UUID().uuidString
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.tearDown()
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testLockedGoalLarge() { runLocked(category: "UICTContentSizeCategoryL") }
    func testLockedGoalAXXXL() { runLocked(category: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testCraftGoalLarge() { runCraft(category: "UICTContentSizeCategoryL") }
    func testCraftGoalAXXXL() { runCraft(category: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testEvolutionGoalLarge() { runEvolution(category: "UICTContentSizeCategoryL") }
    func testEvolutionGoalAXXXL() { runEvolution(category: "UICTContentSizeCategoryAccessibilityXXXL") }

    private func runLocked(category: String) {
        let key = launch(scenario: "locked-track-clear", recipeID: "RC_EQ_W_P1", category: category)
        openRecipe("RC_EQ_W_P1", key: key, category: category)
        let requirement = app.descendants(matching: .any).matching(identifier: "goal_material_M_R02_E1").firstMatch
        scrollUntilHittable(requirement)
        XCTAssertTrue(requirement.label.contains("眠り胞子"))
        XCTAssertTrue(requirement.label.contains("討伐の解放待ち"))
        let parent = app.buttons["recipe_parent_" + starterWeaponID]
        scrollUntilHittable(parent)
        assertMinimumHitTarget(parent)
        capture("locked_parent_choice", key, category)
        parent.tap()
        XCTAssertTrue(app.staticTexts["recipe_selected_parent"].waitForExistence(timeout: 6))
        let evolve = app.buttons["goal_evolve"]
        scrollUntilHittable(evolve)
        assertMinimumHitTarget(evolve)
        XCTAssertFalse(evolve.isEnabled, "locked gate/materials must not dispatch")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "討伐で解放されます。"))
            .firstMatch.exists)
        capture("locked_detail", key, category)

        let track = app.buttons["track_recipe_goal"]
        scrollUntilHittable(track)
        assertMinimumHitTarget(track)
        track.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        capture("locked_goal_selected", key, category)

        app.terminate()
        relaunchExisting(key: key, scenario: "locked-track-clear", category: category)
        let summary = app.buttons["tracked_recipe_summary"]
        scrollUntilHittable(summary)
        summary.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        let clear = app.buttons["clear_recipe_goal"]
        scrollUntilHittable(clear)
        assertMinimumHitTarget(clear)
        capture("locked_reopened_before_clear", key, category)
        clear.tap()
        XCTAssertTrue(app.buttons["track_recipe_goal"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["clear_recipe_goal"].exists)
        capture("locked_cleared", key, category)
        attachIdentity(key, scenario: "locked-track-clear", category: category,
                       recipeID: "RC_EQ_W_P1", action: "track_relaunch_clear")
    }

    private func runCraft(category: String) {
        let key = launch(scenario: "craft-ready", recipeID: "RC_EQ_BODY_01", category: category)
        openRecipe("RC_EQ_BODY_01", key: key, category: category)
        for material in ["M_R01_E2", "M_R01_G3", "M_R01_G4"] {
            let row = app.descendants(matching: .any).matching(identifier: "goal_material_" + material).firstMatch
            scrollUntilHittable(row)
            XCTAssertTrue(row.exists, "catalog requirement row should be present: \(material)")
        }
        let track = app.buttons["track_recipe_goal"]
        scrollUntilHittable(track)
        assertMinimumHitTarget(track)
        track.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        let craft = app.buttons["goal_craft"]
        scrollUntilHittable(craft)
        assertMinimumHitTarget(craft)
        XCTAssertTrue(craft.isEnabled, "fixture seeds only this recipe's exact catalog costs and gate")
        capture("craft_before", key, category)
        craft.tap()
        XCTAssertTrue(app.staticTexts["この型の装備を所持しています"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].exists,
                      "successful craft must not clear the selected goal")
        capture("craft_after", key, category)

        app.terminate()
        relaunchExisting(key: key, scenario: "craft-ready", category: category)
        let summary = app.buttons["tracked_recipe_summary"]
        scrollUntilHittable(summary)
        XCTAssertTrue(summary.exists)
        summary.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["この型の装備を所持しています"].exists)
        capture("craft_reopened", key, category)
        attachIdentity(key, scenario: "craft-ready", category: category,
                       recipeID: "RC_EQ_BODY_01", action: "craft_and_relaunch")
    }

    private func runEvolution(category: String) {
        let key = launch(scenario: "evolve-ready", recipeID: "RC_EQ_W_G1", category: category)
        openRecipe("RC_EQ_W_G1", key: key, category: category)
        for material in ["M_R01_BA", "M_R01_BB", "M_R01_G3"] {
            let row = app.descendants(matching: .any).matching(identifier: "goal_material_" + material).firstMatch
            scrollUntilHittable(row)
            XCTAssertTrue(row.exists, "catalog requirement row should be present: \(material)")
        }
        let parent = app.buttons["recipe_parent_" + starterWeaponID]
        scrollUntilHittable(parent)
        assertMinimumHitTarget(parent)
        capture("evolve_parent_choice", key, category)
        parent.tap()
        XCTAssertTrue(app.staticTexts["recipe_selected_parent"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["recipe_selected_parent"].exists,
                      "parent selection should be visible before dispatch")
        let track = app.buttons["track_recipe_goal"]
        scrollUntilHittable(track)
        track.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        let evolve = app.buttons["goal_evolve"]
        scrollUntilHittable(evolve)
        assertMinimumHitTarget(evolve)
        XCTAssertTrue(evolve.isEnabled, "only the explicitly selected parent and exact recipe costs are eligible")
        capture("evolve_before", key, category)
        evolve.tap()
        let ownedGoal = app.descendants(matching: .any).matching(identifier: "recipe_goal_parent_status").firstMatch
        scrollUntilHittable(ownedGoal)
        XCTAssertTrue(ownedGoal.exists, "owned output with missing parent uses informational wording")
        XCTAssertTrue(ownedGoal.label.contains("目標の型の装備を所持しています"))
        XCTAssertTrue(app.staticTexts["この型の装備を所持しています"].exists)
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].exists, "goal remains tracked after evolution")
        XCTAssertFalse(app.buttons["goal_evolve"].exists, "missing parent cannot be evolved again")
        XCTAssertFalse(app.buttons["goal_open_inventory"].exists,
                       "owned output with missing parent is informational, not an inventory CTA")
        XCTAssertTrue(app.buttons["clear_recipe_goal"].exists)
        capture("evolve_parent_missing", key, category)

        app.terminate()
        relaunchExisting(key: key, scenario: "evolve-ready", category: category)
        let summary = app.buttons["tracked_recipe_summary"]
        scrollUntilHittable(summary)
        summary.tap()
        let reopenedOwnedGoal = app.descendants(matching: .any).matching(identifier: "recipe_goal_parent_status").firstMatch
        scrollUntilHittable(reopenedOwnedGoal)
        XCTAssertTrue(reopenedOwnedGoal.exists)
        XCTAssertTrue(reopenedOwnedGoal.label.contains("目標の型の装備を所持しています"))
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].exists)
        XCTAssertFalse(app.buttons["goal_evolve"].exists)
        XCTAssertTrue(app.buttons["clear_recipe_goal"].exists)
        capture("evolve_reopened", key, category)
        attachIdentity(key, scenario: "evolve-ready", category: category,
                       recipeID: "RC_EQ_W_G1", action: "evolve_selected_uuid_and_relaunch")
    }

    private func launch(scenario: String, recipeID: String, category: String) -> String {
        if app.state != .notRunning { app.terminate() }
        let key = "recipe-goal-r037-" + UUID().uuidString
        setArguments(key: key, scenario: scenario, screen: "工房", category: category)
        app.launch()
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 25))
        let kind = recipeID == "RC_EQ_BODY_01" ? "craft_new" : "evolve_in_place"
        let mode = app.buttons["workshop_mode_" + kind]
        scrollUntilHittable(mode)
        assertMinimumHitTarget(mode)
        mode.tap()
        let detail = app.buttons["recipe_detail_" + recipeID]
        scrollUntilHittable(detail, timeout: 70)
        XCTAssertTrue(detail.exists, "workshop must show catalog recipe detail entry")
        return key
    }

    private func relaunchExisting(key: String, scenario: String, category: String) {
        setArguments(key: key, scenario: scenario, screen: "工房", category: category)
        app.launch()
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 24),
                      "goal summary is hosted in the workshop tab, not the home tab")
    }

    private func setArguments(key: String, scenario: String, screen: String, category: String) {
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
            "--qa-fixture=recipe-goal-r037", "--qa-recipe-goal=" + scenario,
            "--qa-persist-fixture", "--qa-recipe-goal-baseline", "--screen=" + screen,
            "-UIPreferredContentSizeCategoryName", category]
    }

    private func openRecipe(_ recipeID: String, key: String, category: String) {
        let detail = app.buttons["recipe_detail_" + recipeID]
        scrollUntilHittable(detail)
        capture("workshop_recipe_" + recipeID, key, category)
        detail.tap()
        XCTAssertTrue(app.buttons["track_recipe_goal"].waitForExistence(timeout: 12)
                      || app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 12))
    }

    private var activeScroll: XCUIElement {
        let sheet = app.scrollViews["sheet_scroll_制作目標"]
        if sheet.exists { return sheet }
        return app.scrollViews["workshop_scroll"]
    }

    private func scrollUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 80) {
        let deadline = Date().addingTimeInterval(timeout)
        var steps = 0
        var diagnostics: [String] = []
        while Date() < deadline {
            let scroll = activeScroll
            guard scroll.waitForExistence(timeout: 2) else { break }
            let viewport = scroll.frame.insetBy(dx: 1, dy: 3)
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let button = exists && element.elementType == .button
            let visible = exists && !frame.isEmpty && (button ? viewport.contains(frame) : viewport.intersects(frame))
            // Static text need not accept touch; visible informational rows are
            // readable even when XCTest reports them as not hittable.
            if visible && (!button || element.isHittable) { return }
            var towardEnd: Bool
            if exists && !frame.isEmpty {
                towardEnd = frame.midY >= viewport.midY
            } else {
                // Search both directions when off-screen AX elements disappear.
                // Short drags avoid skipping an entire interactive target.
                let sweep = steps / 12
                towardEnd = sweep == 0 || sweep % 3 == 2
            }
            let safeIdentifier = exists ? element.identifier : "not_exposed"
            let goalSheetBefore = app.scrollViews["sheet_scroll_制作目標"].exists
            let clearBefore = app.buttons["clear_recipe_goal"].exists
            let trackBefore = app.buttons["track_recipe_goal"].exists
            let selectedBefore = app.staticTexts["recipe_goal_selected"].exists
            let direction = towardEnd ? "toward_end" : "toward_start"
            var entry = "STEP \(steps) BEFORE target=\(safeIdentifier) exists=\(exists) frame=\(frame) viewport=\(viewport) elementType=\(exists ? String(element.elementType.rawValue) : "not_exposed") direction=\(direction) goalSheet=\(goalSheetBefore) clear=\(clearBefore) track=\(trackBefore) selected=\(selectedBefore)"
            entry += "\nAX_BEFORE\n\(app.debugDescription)"
            // Use a short, bounded pan in the ScrollView's interior. A full
            // XCTest swipe moved this 77pt target between y~734 and y~69,
            // skipping the 512pt viewport entirely. The delta is derived from
            // the target's current gap and capped so AX can converge without
            // tapping or changing the goal. Goal flags are checked after every
            // pan below; edge-origin gestures are deliberately avoided.
            let pan = boundedScrollPan(scroll: scroll, viewport: viewport, elementFrame: frame, targetExists: exists, towardEnd: towardEnd)
            entry += "\nPAN \(pan.description)"
            pan.start.press(forDuration: 0.01, thenDragTo: pan.end)
            let goalSheetAfter = app.scrollViews["sheet_scroll_制作目標"].exists
            let clearAfter = app.buttons["clear_recipe_goal"].exists
            let trackAfter = app.buttons["track_recipe_goal"].exists
            let selectedAfter = app.staticTexts["recipe_goal_selected"].exists
            let afterFrame = element.exists ? element.frame : .zero
            entry += "\nSTEP \(steps) AFTER targetExists=\(element.exists) frame=\(afterFrame) goalSheet=\(goalSheetAfter) clear=\(clearAfter) track=\(trackAfter) selected=\(selectedAfter)"
            entry += "\nAX_AFTER\n\(app.debugDescription)"
            diagnostics.append(entry)
            scrollDiagnostics.append(entry)
            if (goalSheetAfter != goalSheetBefore || clearAfter != clearBefore || trackAfter != trackBefore || selectedAfter != selectedBefore) {
                let evidence = XCTAttachment(string: entry)
                evidence.name = "recipe_goal_scroll_mutation_step_\(steps)_" + UUID().uuidString
                evidence.lifetime = .keepAlways
                add(evidence)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "recipe_goal_scroll_mutation_screen_\(steps)_" + UUID().uuidString
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTAssertEqual(goalSheetAfter, goalSheetBefore, "Scrolling must not open or dismiss the recipe goal sheet")
                XCTAssertEqual(clearAfter, clearBefore, "Scrolling must not change the tracked goal")
                XCTAssertEqual(trackAfter, trackBefore, "Scrolling must not dispatch goal selection or clearing")
                XCTAssertEqual(selectedAfter, selectedBefore, "Scrolling must not change goal selection state")
            }
            steps += 1
        }
        let debug = XCTAttachment(string: diagnostics.joined(separator: "\n") + "\n\n" + app.debugDescription)
        debug.name = "recipe_goal_scroll_failure_" + UUID().uuidString
        debug.lifetime = .keepAlways
        add(debug)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "recipe_goal_scroll_failure_screen_" + UUID().uuidString
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("element did not become visible in the explicit scroll viewport: requested recipe UI element")
    }


    private func boundedScrollPan(scroll: XCUIElement, viewport: CGRect, elementFrame: CGRect, targetExists: Bool, towardEnd: Bool) -> (start: XCUICoordinate, end: XCUICoordinate, description: String) {
        if !targetExists {
            let travel = min(CGFloat(96), viewport.height * 0.18)
            let sign: CGFloat = towardEnd ? -1 : 1
            let startY = viewport.midY
            let endY = startY + sign * travel
            let x = viewport.midX
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: (x - scroll.frame.minX) / scroll.frame.width, dy: (startY - scroll.frame.minY) / scroll.frame.height))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: (x - scroll.frame.minX) / scroll.frame.width, dy: (endY - scroll.frame.minY) / scroll.frame.height))
            return (start, end, "target=not_exposed fallback=\(towardEnd ? "toward_end" : "toward_start") start=(\(x),\(startY)) end=(\(x),\(endY)) travel=\(travel)")
        }
        let isBelow = elementFrame.maxY > viewport.maxY
        let isAbove = elementFrame.minY < viewport.minY
        let needed: CGFloat
        let sign: CGFloat
        if isBelow {
            needed = elementFrame.maxY - viewport.maxY + 12
            sign = -1 // finger moves up; content moves toward the end
        } else if isAbove {
            needed = viewport.minY - elementFrame.minY + 12
            sign = 1 // finger moves down; content moves toward the start
        } else {
            // Partial intersection: align the nearer clipped edge, retaining
            // the full-frame containment requirement for interactive controls.
            let topGap = max(0, viewport.minY - elementFrame.minY)
            let bottomGap = max(0, elementFrame.maxY - viewport.maxY)
            if topGap >= bottomGap {
                needed = topGap + 12
                sign = 1
            } else {
                needed = bottomGap + 12
                sign = -1
            }
        }
        let cap = min(CGFloat(96), viewport.height * 0.18)
        let travel = min(max(CGFloat(18), needed), cap)
        let margin = travel * 0.5 + 12
        let startY = min(max(viewport.midY, viewport.minY + margin), viewport.maxY - margin)
        let endY = startY + sign * travel
        let x = viewport.midX
        let start = scroll.coordinate(withNormalizedOffset: CGVector(
            dx: (x - scroll.frame.minX) / scroll.frame.width,
            dy: (startY - scroll.frame.minY) / scroll.frame.height))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(
            dx: (x - scroll.frame.minX) / scroll.frame.width,
            dy: (endY - scroll.frame.minY) / scroll.frame.height))
        let desc = "start=(\(x),\(startY)) end=(\(x),\(endY)) travel=\(travel) needed=\(needed) viewport=\(viewport)"
        return (start, end, desc)
    }

    private func assertMinimumHitTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "interactive target is narrower than 44pt", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 44, "interactive target is shorter than 44pt", file: file, line: line)
    }

    private func capture(_ name: String, _ key: String, _ category: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "recipe_goal_\(category)_\(name)_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachIdentity(_ key: String, scenario: String, category: String,
                                recipeID: String, action: String) {
        let attachment = XCTAttachment(string: "saveKey=\(key)\nscenario=\(scenario)\nclassification=SYNTHETIC_QA_FIXTURE_NOT_EARNED\ncategory=\(category)\nrecipeID=\(recipeID)\nexpectedAction=\(action)")
        attachment.name = "recipe_goal_identity_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
