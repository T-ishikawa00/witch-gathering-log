import XCTest

/// Isolated AXXXL evidence for one informational paragraph. Only the post-relaunch
/// phase is read-only; setup actions are explicitly synthetic fixture preparation.
final class StaticCopyReadabilityR048Tests: XCTestCase {
    private let app = XCUIApplication()
    private let starterWeaponID = "10000000-0000-4000-8000-000000000001"
    private let recipeID = "RC_EQ_W_G1"
    private let expectedStatus = "目標の型の装備を所持しています。目標は保存したままなので、解除するか別の目標を選べます。"
    private var saveKey = ""
    private var attachmentIndex = 0

    override func setUpWithError() throws { continueAfterFailure = false }

    func testAXXXLParentStatusReadableAcrossScrollWithoutSaveChanges() {
        saveKey = "recipe-goal-r037-" + UUID().uuidString
        launch(category: "UICTContentSizeCategoryAccessibilityXXXL", screen: "工房")
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 25))

        // Synthetic precondition: seed/evolve, then relaunch the same isolated save.
        let mode = app.buttons["workshop_mode_evolve_in_place"]
        scrollUntilVisible(mode, in: app.scrollViews["workshop_scroll"], maxSteps: 18)
        XCTAssertTrue(mode.exists)
        mode.tap()
        let detail = app.buttons["recipe_detail_" + recipeID]
        scrollUntilVisible(detail, in: app.scrollViews["workshop_scroll"], maxSteps: 30)
        detail.tap()
        XCTAssertTrue(app.buttons["track_recipe_goal"].waitForExistence(timeout: 12))
        let parent = app.buttons["recipe_parent_" + starterWeaponID]
        scrollUntilVisible(parent, in: activeScroll, maxSteps: 30)
        XCTAssertTrue(parent.isHittable)
        parent.tap()
        XCTAssertTrue(app.staticTexts["recipe_selected_parent"].waitForExistence(timeout: 8))
        let track = app.buttons["track_recipe_goal"]
        scrollUntilVisible(track, in: activeScroll, maxSteps: 30)
        track.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        let evolve = app.buttons["goal_evolve"]
        scrollUntilVisible(evolve, in: activeScroll, maxSteps: 30)
        XCTAssertTrue(evolve.isEnabled)
        evolve.tap()
        let evolvedStatus = statusElement()
        XCTAssertTrue(evolvedStatus.waitForExistence(timeout: 12))
        XCTAssertEqual(evolvedStatus.label, expectedStatus)
        XCTAssertFalse(app.buttons["goal_evolve"].exists)
        attachIdentity(stage: "precondition_evolved", interactions: "parent=1,track=1,evolve=1", sampleCount: 0)

        // App startup readback after this relaunch brackets all navigation/scroll.
        app.terminate()
        launch(category: "UICTContentSizeCategoryAccessibilityXXXL", screen: "工房", readback: true)
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 25))
        let summary = app.buttons["tracked_recipe_summary"]
        scrollUntilVisible(summary, in: app.scrollViews["workshop_scroll"], maxSteps: 20)
        XCTAssertTrue(summary.isHittable)
        attachScreen(stage: "reopened_workshop_before_navigation")
        summary.tap() // Opens the tracked detail; it does not dispatch a game command.
        let status = statusElement()
        XCTAssertTrue(status.waitForExistence(timeout: 12))
        XCTAssertEqual(status.label, expectedStatus)
        let scroll = app.scrollViews["sheet_scroll_制作目標"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))

        let count = collectVisibleIntervals(status, in: scroll)
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(status.label, expectedStatus)
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].exists)
        XCTAssertFalse(app.buttons["goal_evolve"].exists)
        attachIdentity(stage: "read_only_complete", interactions: "summary_navigation=1,mutation=0", sampleCount: count)
    }

    private func launch(category: String, screen: String, readback: Bool = false) {
        var args: [String]
        if readback {
            // Existing-save readback deliberately omits the strict fixture request:
            // RecipeGoalQAFixture rejects additional --qa-* modes by design.
            args = ["-UIPreferredContentSizeCategoryName", category,
                    "--qa-isolated", "--qa-save-key=" + saveKey,
                    "--qa-readback-save", "--screen=" + screen]
        } else {
            args = ["-UIPreferredContentSizeCategoryName", category,
                    "--qa-isolated", "--qa-save-key=" + saveKey,
                    "--qa-fixture=recipe-goal-r037", "--qa-recipe-goal=evolve-ready",
                    "--qa-persist-fixture", "--qa-recipe-goal-baseline", "--screen=" + screen]
        }
        app.launchArguments = args
        app.launch()
    }

    private var activeScroll: XCUIElement {
        let sheet = app.scrollViews["sheet_scroll_制作目標"]
        return sheet.exists ? sheet : app.scrollViews["workshop_scroll"]
    }

    private func statusElement() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "recipe_goal_parent_status").firstMatch
    }

    private func scrollUntilVisible(_ element: XCUIElement, in scroll: XCUIElement, maxSteps: Int) {
        guard scroll.waitForExistence(timeout: 10) else { return }
        for _ in 0..<maxSteps {
            if element.exists && element.isHittable && scroll.frame.intersects(element.frame) { return }
            let frame = element.exists ? element.frame : .zero
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 2)
            let dy: CGFloat
            if element.exists && frame.maxY > viewport.maxY {
                dy = -min(105, max(26, frame.maxY - viewport.maxY + 12))
            } else if element.exists && frame.minY < viewport.minY {
                dy = min(105, max(26, viewport.minY - frame.minY + 12))
            } else { dy = -72 }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        }
    }

    @discardableResult
    private func collectVisibleIntervals(_ element: XCUIElement, in scroll: XCUIElement) -> Int {
        // Begin at the top so the accumulated local-Y intervals have a deterministic
        // first edge. This scroll-only positioning is inside the read-only phase.
        var stableTop = 0
        for _ in 0..<20 {
            let before = element.frame.minY
            scroll.swipeDown()
            let after = element.frame.minY
            if abs(after - before) < 0.5 { stableTop += 1 } else { stableTop = 0 }
            if stableTop >= 2 { break }
        }

        var count = 0
        var intervals: [(Double, Double)] = []
        var stalledScrolls = 0
        for index in 0..<30 {
            XCTAssertTrue(element.exists, "status paragraph must remain in accessibility tree")
            let textFrame = element.frame
            let viewport = scroll.frame.intersection(app.frame)
            let intersection = textFrame.intersection(viewport)
            let height = max(0, textFrame.height)
            let lower = intersection.isNull ? 0 : min(height, max(0, intersection.minY - textFrame.minY))
            let upper = intersection.isNull ? 0 : min(height, max(0, intersection.maxY - textFrame.minY))
            attachGeometry(geometry(index: index, textFrame: textFrame, viewport: viewport,
                                    interval: [lower, upper], textHeight: height, label: element.label))
            attachScreen(stage: String(format: "read_%02d", index))
            count += 1
            intervals.append((lower, upper))
            if coversCompleteParagraph(intervals, height: Double(height), tolerance: 1.0) { return count }

            let before = textFrame.minY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -min(150, max(36, viewport.height * 0.48)))))
            let after = element.frame.minY
            if abs(after - before) < 0.5 { stalledScrolls += 1 } else { stalledScrolls = 0 }
            if stalledScrolls >= 2 {
                XCTFail("scroll stopped before paragraph coverage was complete")
                return count
            }
        }
        XCTFail("visible intervals did not cover the complete paragraph after 30 bounded scroll positions")
        return count
    }

    private func coversCompleteParagraph(_ intervals: [(Double, Double)], height: Double, tolerance: Double) -> Bool {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        guard let first = sorted.first, first.0 <= tolerance else { return false }
        var end = first.1
        for interval in sorted.dropFirst() {
            if interval.0 > end + tolerance { return false }
            end = max(end, interval.1)
        }
        return end >= height - tolerance
    }

    private func rect(_ r: CGRect) -> [Double] { [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }

    private func geometry(index: Int, textFrame: CGRect, viewport: CGRect,
                          interval: [Double], textHeight: CGFloat, label: String) -> String {
        let obj: [String: Any] = [
            "schema": "static-copy-readability-r048-sample-r001",
            "saveKey": saveKey, "sampleIndex": index,
            "accessibilityIdentifier": "recipe_goal_parent_status",
            "accessibilityLabel": label, "expectedLabel": expectedStatus,
            "textFrame": rect(textFrame), "effectiveViewport": rect(viewport),
            "screenshotAttachmentName": String(format: "static_copy_r048_read_%02d_%@", index, saveKey),
            "textHeight": Double(textHeight), "visibleIntervalLocalY": interval,
            "coordinateSystem": "XCUITest app-window points; interval relative to paragraph frame",
            "classification": "SYNTHETIC_QA_FIXTURE_NOT_EARNED",
            "phase": "post_evolution_relaunch_read_only_scroll",
            "actions": "bounded_scroll_only; no claim/track/clear/evolve/craft action"
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            guard let value = String(data: data, encoding: .utf8) else {
                XCTFail("geometry attachment was not UTF-8")
                return "{}"
            }
            return value
        } catch {
            XCTFail("geometry attachment serialization failed: \(error)")
            return "{}"
        }
    }

    private func attachGeometry(_ json: String) {
        let item = XCTAttachment(string: json)
        item.name = "static_copy_r048_geometry_\(attachmentIndex)"
        item.lifetime = .keepAlways
        add(item)
        attachmentIndex += 1
    }

    private func attachScreen(stage: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "static_copy_r048_\(stage)_\(saveKey)"
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "static_copy_r048_AX_\(stage)_\(saveKey)"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func attachIdentity(stage: String, interactions: String, sampleCount: Int) {
        let text = "schema=static-copy-readability-r048-identity-r001\nsaveKey=\(saveKey)\nfixture=recipe-goal-r037\nscenario=evolve-ready\nrecipeID=\(recipeID)\nsize=AXXXL\nclassification=SYNTHETIC_QA_FIXTURE_NOT_EARNED\nstage=\(stage)\ninteractions=\(interactions)\nsampleCount=\(sampleCount)\nclaimTapCount=0\npreconditionMutationTapCount=3\nreadOnlyMutationTapCount=0"
        let attachment = XCTAttachment(string: text)
        attachment.name = "static_copy_r048_identity_\(stage)_\(saveKey)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
