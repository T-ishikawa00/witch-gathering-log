import XCTest

/// Large / AXXXL UI proof for the selected-parent evolution preview.
/// All state starts from the explicitly synthetic R037 evolve-ready fixture.
final class RecipeEvolutionPreviewLifecycleR129Tests: XCTestCase {
    private let app = XCUIApplication()
    private let recipeID = "RC_EQ_W_G1"
    private let parentUUID = "10000000-0000-4000-8000-000000000001"
    private let attackText = "装備固有の攻撃補正 +3→+3（変化なし）"
    private let wardText = "毒の種スキルを使わず、脅威があるときに仲間へ結界を張る"
    private let retainedText = "品質・強化・研成・潜在効果を引き継ぎます。"
    private var saveKey = ""
    private var runToken = ""

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if app.state != .notRunning { app.terminate() }
        try super.tearDownWithError()
    }

    func testEvolutionPreviewLargeAndSelectedParentLifecycle() {
        runLifecycle(contentSize: "UICTContentSizeCategoryL")
    }

    func testEvolutionPreviewAXXXLAndSelectedParentLifecycle() {
        runLifecycle(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func runLifecycle(contentSize: String) {
        saveKey = "recipe-goal-r037-" + UUID().uuidString
        guard let token = ProcessInfo.processInfo.environment["WITCH_R129_RUN_TOKEN"],
              UUID(uuidString: token) != nil else {
            XCTFail("WITCH_R129_RUN_TOKEN must be the UUID assigned by the host runner")
            return
        }
        runToken = token.lowercased()
        launch(contentSize: contentSize)
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 25))
        phaseBarrier("fixture_ready")
        openEvolutionRecipe()

        let outcome = identified("recipe_evolution_outcome")
        XCTAssertFalse(outcome.exists, "The projection must not appear before selecting an exact parent item")
        XCTAssertFalse(app.buttons["goal_evolve"].exists)
        let parentChoice = app.buttons["recipe_parent_" + parentUUID]
        reveal(parentChoice, mustFitViewport: true)
        XCTAssertTrue(parentChoice.isHittable)
        XCTAssertFalse(parentChoice.label.contains(parentUUID), "The visible selector label must not expose the raw UUID")
        capture("parent_choice", contentSize)
        parentChoice.tap()

        let selected = identified("recipe_selected_parent")
        XCTAssertTrue(selected.waitForExistence(timeout: 8))
        XCTAssertFalse(selected.label.contains(parentUUID), "The visible parent label must not expose a UUID")
        XCTAssertTrue(outcome.waitForExistence(timeout: 8))
        assertPreviewCopy(outcome: outcome)
        capture("preview_attack", contentSize, afterRevealing: attackText)
        capture("preview_effect", contentSize, afterRevealing: wardText)
        capture("preview_retention", contentSize, afterRevealing: retainedText)

        // Tracking is the only command before close/reopen. A preview or sheet
        // transition must never dispatch evolution implicitly.
        let track = app.buttons["track_recipe_goal"]
        reveal(track, mustFitViewport: true)
        XCTAssertTrue(track.isHittable)
        track.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        phaseBarrier("goal_tracked")
        let close = app.navigationBars["制作目標"].buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertFalse(app.scrollViews["sheet_scroll_制作目標"].waitForExistence(timeout: 3))

        let summary = app.buttons["tracked_recipe_summary"]
        reveal(summary, mustFitViewport: true)
        summary.tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_制作目標"].waitForExistence(timeout: 8))
        XCTAssertFalse(outcome.exists, "Reopening the tracked goal must not retain an implicit parent preview")
        XCTAssertFalse(app.buttons["goal_evolve"].exists, "Reopening must not dispatch or stage evolution")
        let parentAgain = app.buttons["recipe_parent_" + parentUUID]
        reveal(parentAgain, mustFitViewport: true)
        XCTAssertTrue(parentAgain.isHittable)
        capture("reopened_parent_choice_no_evolution", contentSize)
        parentAgain.tap()
        XCTAssertTrue(outcome.waitForExistence(timeout: 8))
        assertPreviewCopy(outcome: outcome)
        phaseBarrier("before_evolve")
        XCTAssertTrue(app.buttons["goal_evolve"].isEnabled)

        let evolve = app.buttons["goal_evolve"]
        reveal(evolve, mustFitViewport: true)
        XCTAssertTrue(evolve.isEnabled)
        evolve.tap()
        let parentStatus = identified("recipe_goal_parent_status")
        XCTAssertTrue(parentStatus.waitForExistence(timeout: 15))
        XCTAssertTrue(parentStatus.label.contains("目標の型の装備を所持しています"))
        XCTAssertFalse(app.buttons["goal_evolve"].exists, "The evolved item is no longer the recipe's parent")
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].exists, "Evolution must retain the tracked target")
        phaseBarrier("after_evolve")
        capture("after_evolution", contentSize)

        app.terminate()
        launch(contentSize: contentSize)
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout: 25))
        let reopenedSummary = app.buttons["tracked_recipe_summary"]
        reveal(reopenedSummary, mustFitViewport: true)
        XCTAssertTrue(reopenedSummary.isHittable)
        reopenedSummary.tap()
        XCTAssertTrue(parentStatus.waitForExistence(timeout: 12))
        XCTAssertTrue(parentStatus.label.contains("目標の型の装備を所持しています"))
        XCTAssertFalse(outcome.exists, "Cold reopen must not show an outcome for a parent that has already evolved")
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].exists)
        XCTAssertFalse(app.buttons["goal_evolve"].exists)
        phaseBarrier("cold_reopen")
        capture("cold_reopen_after_evolution", contentSize)
        attachIdentity(contentSize: contentSize, stage: "complete",
                       parentSelectionIdentifier: "recipe_parent_" + parentUUID,
                       setup: "SYNTHETIC_NOT_EARNED; R037 evolve-ready fixture; one track, one explicit evolve")
        phaseBarrier("case_complete")
    }

    /// Read-only host coordination for the exact save generations used by this
    /// UI case. The host owns the fresh barrier directory and releases a phase
    /// only after it has archived and validated the matching save bytes.
    private func phaseBarrier(_ phase: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              UUID(uuidString: runToken) != nil else {
            XCTFail("R129 run token or XCTest Documents directory is unavailable")
            return
        }
        let directory = documents.appendingPathComponent("R129-" + runToken, isDirectory: true)
        let marker = directory.appendingPathComponent("\(saveKey)_\(phase).json")
        let release = directory.appendingPathComponent("\(saveKey)_\(phase)_verified.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: marker.path),
                  !FileManager.default.fileExists(atPath: release.path) else {
                XCTFail("R129 phase marker already exists: \(phase)")
                return
            }
            let payload = try JSONSerialization.data(withJSONObject: [
                "saveKey": saveKey, "phase": phase, "runToken": runToken,
                "testPID": String(ProcessInfo.processInfo.processIdentifier),
                "recipeID": recipeID, "parentUUID": parentUUID
            ],
                                                      options: [.sortedKeys])
            try payload.write(to: marker, options: [.atomic])
        } catch {
            XCTFail("Could not publish R129 phase marker \(phase): \(error)")
            return
        }
        print("R129_PHASE_BARRIER saveKey=\(saveKey) phase=\(phase)")
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        let expectedStatus: String
        switch phase {
        case "fixture_ready": expectedStatus = "BASELINE_CAPTURED"
        case "before_evolve", "cold_reopen": expectedStatus = "BYTE_IDENTICAL"
        case "case_complete": expectedStatus = "CASE_READBACK_COMPLETE"
        default: expectedStatus = "STATE_VERIFIED"
        }
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let data = try? Data(contentsOf: release),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               object["saveKey"] == saveKey, object["phase"] == phase,
               object["runToken"] == runToken,
               object["testPID"] == String(ProcessInfo.processInfo.processIdentifier),
               object["recipeID"] == recipeID,
               object["parentUUID"] == parentUUID,
               object["status"] == expectedStatus {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Host did not complete R129 readback at \(phase)")
    }

    private func launch(contentSize: String) {
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName", contentSize,
            "--qa-isolated",
            "--qa-save-key=" + saveKey,
            "--qa-fixture=recipe-goal-r037",
            "--qa-recipe-goal=evolve-ready",
            "--qa-persist-fixture",
            "--qa-recipe-goal-baseline",
            "--screen=工房"
        ]
        app.launch()
    }

    private func openEvolutionRecipe() {
        let mode = app.buttons["workshop_mode_evolve_in_place"]
        reveal(mode, mustFitViewport: true)
        XCTAssertTrue(mode.isHittable)
        mode.tap()
        let detail = app.buttons["recipe_detail_" + recipeID]
        reveal(detail, mustFitViewport: true, maxSteps: 40)
        XCTAssertTrue(detail.isHittable)
        detail.tap()
        XCTAssertTrue(app.buttons["track_recipe_goal"].waitForExistence(timeout: 12))
    }

    private func assertPreviewCopy(outcome: XCUIElement) {
        XCTAssertTrue(outcome.exists)
        assertStaticTextVisible(attackText)
        assertStaticTextVisible(wardText)
        assertStaticTextVisible(retainedText)
        let allText = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
        XCTAssertFalse(allText.contains("BARRIER_WARD"), "Internal effect IDs must not be shown to players")
        XCTAssertFalse(allText.contains("WARD_REPLACES_SEED"), "Internal effect IDs must not be shown to players")
        XCTAssertFalse(allText.contains(parentUUID), "Raw UUID must not appear in visible accessibility labels")
    }

    private func assertStaticTextVisible(_ exactText: String, file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", exactText)).firstMatch
        reveal(text, mustFitViewport: true, file: file, line: line)
        XCTAssertTrue(text.exists, "Missing player-facing preview copy: \(exactText)", file: file, line: line)
        let viewport = activeScroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 3)
        XCTAssertTrue(viewport.contains(text.frame), "Preview copy must be fully within the scroll viewport", file: file, line: line)
    }

    private var activeScroll: XCUIElement {
        let sheet = app.scrollViews["sheet_scroll_制作目標"]
        return sheet.exists ? sheet : app.scrollViews["workshop_scroll"]
    }

    private func identified(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, mustFitViewport: Bool, maxSteps: Int = 36,
                        file: StaticString = #filePath, line: UInt = #line) {
        for step in 0..<maxSteps {
            let scroll = activeScroll
            guard scroll.waitForExistence(timeout: 4) else { break }
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 3)
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let visible = exists && !frame.isEmpty && (mustFitViewport ? viewport.contains(frame) : viewport.intersects(frame))
            let interactive = exists && element.elementType == .button
            if visible && (!interactive || element.isHittable) { return }

            let scrollBefore = app.scrollViews["sheet_scroll_制作目標"].exists
            let trackedBefore = app.staticTexts["recipe_goal_selected"].exists
            let clearBefore = app.buttons["clear_recipe_goal"].exists
            let trackBefore = app.buttons["track_recipe_goal"].exists
            let direction: CGFloat
            if exists && frame.maxY > viewport.maxY { direction = -1 }
            else if exists && frame.minY < viewport.minY { direction = 1 }
            else { direction = step.isMultiple(of: 3) ? -1 : 1 }
            let travel = min(CGFloat(84), max(CGFloat(26), exists && !frame.isEmpty
                ? (direction < 0 ? frame.maxY - viewport.maxY : viewport.minY - frame.minY) + 14
                : 70))
            let x = viewport.midX
            let y = min(max(viewport.midY, viewport.minY + travel / 2 + 8), viewport.maxY - travel / 2 - 8)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (x - scroll.frame.minX) / scroll.frame.width,
                dy: (y - scroll.frame.minY) / scroll.frame.height))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * travel)))

            XCTAssertEqual(app.scrollViews["sheet_scroll_制作目標"].exists, scrollBefore,
                           "Scrolling must not open or dismiss the goal sheet", file: file, line: line)
            XCTAssertEqual(app.staticTexts["recipe_goal_selected"].exists, trackedBefore,
                           "Scrolling must not change tracked-goal state", file: file, line: line)
            XCTAssertEqual(app.buttons["clear_recipe_goal"].exists, clearBefore,
                           "Scrolling must not clear the tracked goal", file: file, line: line)
            XCTAssertEqual(app.buttons["track_recipe_goal"].exists, trackBefore,
                           "Scrolling must not dispatch goal selection", file: file, line: line)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "r129_scroll_failure_ax_\(UUID().uuidString)"
        tree.lifetime = .keepAlways
        add(tree)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "r129_scroll_failure_screen_\(UUID().uuidString)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("UI element did not reach the bounded viewport: \(element.identifier)", file: file, line: line)
    }

    private func capture(_ stage: String, _ contentSize: String, afterRevealing text: String? = nil) {
        if let text { assertStaticTextVisible(text) }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "r129_\(contentSize)_\(stage)_\(saveKey)"
        image.lifetime = .keepAlways
        add(image)
    }

    private func attachIdentity(contentSize: String, stage: String,
                                parentSelectionIdentifier: String, setup: String) {
        let details = """
        schema=recipe-evolution-preview-r129-ui-r001
        saveKey=\(saveKey)
        classification=SYNTHETIC_NOT_EARNED
        contentSize=\(contentSize)
        recipeID=\(recipeID)
        parentUUID=\(parentUUID)
        fixtureReceipt=recipe_goal_fixture_\(saveKey).json
        parentBinding=exact button identifier \(parentSelectionIdentifier)
        setup=\(setup)
        stage=\(stage)
        rawUUIDVisible=false
        implicitEvolutionOnCloseReopen=false
        explicitEvolutionTapCount=1
        """
        let attachment = XCTAttachment(string: details)
        attachment.name = "r129_identity_\(contentSize)_\(saveKey)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
