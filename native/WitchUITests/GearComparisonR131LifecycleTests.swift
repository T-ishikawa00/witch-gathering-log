import XCTest

/// UI coverage for the read-only R136 campaign/research comparison. The launch fixture is synthetic,
/// not earned progression; host barriers verify the keyed save remains unchanged.
final class GearComparisonR136LifecycleTests: XCTestCase {
    private let app = XCUIApplication()
    private let firstGearID = "13100000-0000-4000-8000-000000000001"
    private let secondGearID = "13100000-0000-4000-8000-000000000002"
    private let starterGearID = "10000000-0000-4000-8000-000000000001"
    private let actorID = "C_WITCH"
    private var saveKey = ""
    private var runToken = ""
    private var targetKind = ""
    private var targetID = ""

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if app.state != .notRunning { app.terminate() }
        try super.tearDownWithError()
    }

    func testLargeResearchComparisonAndColdReopen() {
        runComparison(contentSize: "UICTContentSizeCategoryL", research: true)
    }
    func testAXXXLResearchComparisonAndColdReopen() {
        runComparison(contentSize: "UICTContentSizeCategoryAccessibilityXXXL", research: true)
    }
    func testLargeCampaignBeforeResearchUnlockAndColdReopen() {
        runComparison(contentSize: "UICTContentSizeCategoryL", research: false)
    }
    func testAXXXLCampaignBeforeResearchUnlockAndColdReopen() {
        runComparison(contentSize: "UICTContentSizeCategoryAccessibilityXXXL", research: false)
    }

    private func runComparison(contentSize: String, research: Bool) {
        saveKey = newSaveKey()
        prepareRunToken()
        targetKind = research ? "challenge" : "campaign"
        targetID = research ? "CH_R01_01" : "E_R01_01"
        let fixture = research ? "gear-comparison-r131-unlocked" : "gear-comparison-r131-locked"
        launch(fixture: fixture, contentSize: contentSize)
        let scroll = comparisonScroll
        XCTAssertTrue(scroll.waitForExistence(timeout: 25))
        phaseBarrier("fixture_ready", fixture: fixture)

        XCTAssertTrue(app.staticTexts["霧花の毒杖"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["根守りの結界杖"].waitForExistence(timeout: 8))
        let intro = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "装備や進行、報酬は変わりません")).firstMatch
        reveal(intro, in: scroll, mustFitViewport: true)
        reveal(identified("gear_trial_actor"), in: scroll, mustFitViewport: true)
        let picker = app.buttons["gear_trial_target_picker"]
        reveal(picker, in: scroll, mustFitViewport: true)
        XCTAssertTrue(picker.isEnabled)
        if research {
            picker.tap()
            selectScrollableResearchChoice("研究：根道の再観測", pageLimit: 5, timeLimit: 15)
            XCTAssertTrue(picker.label.contains("根道の再観測"), picker.label)
        } else {
            XCTAssertTrue(picker.label.contains("苔角いのしし"), picker.label)
            let guidance = app.staticTexts["gear_trial_no_unlocked_challenge"]
            reveal(guidance, in: scroll, mustFitViewport: true)
            XCTAssertTrue(guidance.label.contains("研究課題が解放されます"), guidance.label)
            reveal(picker, in: scroll, mustFitViewport: true)
            picker.tap()
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "研究：")).firstMatch.exists)
            // The only initially reachable target is E_R01_01. Its own choice
            // closes the native menu; no hidden locked encounter is selected.
            let choice = app.buttons["探索：苔角いのしし"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
        }
        let run = app.buttons["run_gear_trial"]
        reveal(run, in: scroll, mustFitViewport: true)
        assertMinimumTapTarget(run)
        XCTAssertTrue(run.isEnabled)
        attach("before_preview", contentSize)
        run.tap()

        let firstTitle = resultCard(firstGearID)
        let secondTitle = resultCard(secondGearID)
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 60), "First selected UUID must receive its own result card")
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 60), "Second selected UUID must receive its own result card")
        XCTAssertFalse(app.staticTexts["gear_trial_error"].exists)
        for gearID in [firstGearID, secondGearID] {
            reveal(resultCard(gearID), in: scroll, mustFitViewport: true)
            assertOutcome(for: gearID, in: scroll)
            reveal(identified("gear_trial_party_hp_" + gearID), in: scroll, mustFitViewport: true)
            attach("preview_party_" + gearID, contentSize)
            let details = identified("gear_trial_details_" + gearID)
            reveal(details, in: scroll, mustFitViewport: true)
            XCTAssertTrue(details.isHittable)
            details.tap()
            let enemyHP = identified("gear_trial_enemy_hp_" + gearID)
            reveal(enemyHP, in: scroll, mustFitViewport: true)
            XCTAssertEqual(enemyHP.label, "敵の残り体力")
            attach("preview_enemy_" + gearID, contentSize)
        }
        phaseBarrier("preview_complete", fixture: fixture)

        closeComparison()
        phaseBarrier("comparison_closed", fixture: fixture)
        app.terminate()
        relaunch(fixture: fixture, contentSize: contentSize)
        XCTAssertTrue(comparisonScroll.waitForExistence(timeout: 25))
        XCTAssertFalse(resultCard(firstGearID).exists)
        XCTAssertFalse(resultCard(secondGearID).exists)
        phaseBarrier("cold_reopen", fixture: fixture)
        attach("cold_reopen_no_cached_result", contentSize)
        phaseBarrier("case_complete", fixture: fixture)
    }


    /// The native menu can virtualize offscreen entries, especially at AXXXL.
    /// Scroll only inside the visible popup bounds, then rebuild the choice query
    /// on every page. A missing item after five bounded attempts remains a hard failure.
    private func selectScrollableResearchChoice(_ label: String, pageLimit: Int, timeLimit: TimeInterval) {
        let menu = app.collectionViews.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Native Picker menu did not open")
        let deadline = Date().addingTimeInterval(timeLimit)

        for page in 0...pageLimit {
            let choice = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            if choice.exists && choice.isHittable {
                choice.tap()
                return
            }
            if page == pageLimit { break }
            guard Date() < deadline else {
                XCTFail("Research choice was not reachable within \(timeLimit)s")
                return
            }
            let visible = menu.frame.intersection(app.frame)
            guard !visible.isNull, visible.height >= 160, visible.width >= 100 else {
                XCTFail("Picker menu has no usable visible scroll region: \(menu.debugDescription)")
                return
            }
            let startPoint = CGPoint(x: visible.midX, y: visible.maxY - 44)
            let endPoint = CGPoint(x: visible.midX, y: max(visible.minY + 56, startPoint.y - min(260, visible.height * 0.55)))
            let start = app.coordinate(withNormalizedOffset: CGVector(
                dx: startPoint.x / app.frame.width, dy: startPoint.y / app.frame.height))
            let end = app.coordinate(withNormalizedOffset: CGVector(
                dx: endPoint.x / app.frame.width, dy: endPoint.y / app.frame.height))
            start.press(forDuration: 0.04, thenDragTo: end)
        }

        let finalChoice = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(finalChoice.exists && finalChoice.isHittable,
                      "Research choice remained unavailable after bounded menu scrolling.\n\(menu.debugDescription)")
        if finalChoice.exists && finalChoice.isHittable { finalChoice.tap() }
    }

    private var comparisonScroll: XCUIElement { app.scrollViews["sheet_scroll_比較"] }
    private func resultCard(_ id: String) -> XCUIElement { identified("gear_trial_result_" + id) }
    private func outcome(_ id: String) -> XCUIElement { identified("gear_trial_outcome_" + id) }
    private func identified(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func newSaveKey() -> String { "r131-gear-" + UUID().uuidString.lowercased() }

    private func prepareRunToken() {
        guard let token = ProcessInfo.processInfo.environment["WITCH_R136_RUN_TOKEN"], UUID(uuidString: token) != nil else {
            XCTFail("Host runner must provide a fresh UUID WITCH_R136_RUN_TOKEN")
            return
        }
        runToken = token.lowercased()
    }

    private func launch(fixture: String, contentSize: String) {
        app.launchArguments = [
            "--qa-isolated", "--qa-fixture=" + fixture,
            "--qa-r131-gear-comparison", "--qa-persist-fixture", "--qa-readback-save",
            "--qa-save-key=" + saveKey,
            "-UIPreferredContentSizeCategoryName", contentSize
        ]
        app.launch()
    }

    private func relaunch(fixture: String, contentSize: String) { launch(fixture: fixture, contentSize: contentSize) }

    private func closeComparison() {
        let close = app.navigationBars["比較"].buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Comparison sheet uses the NavigationStack close action")
        // UIKit reports its system toolbar accessibility frame as 36pt on this
        // runtime despite the 44pt SwiftUI label. That frame does not establish
        // the touch hit region. This lifecycle test proves the native close
        // action; it makes no unmeasured 44pt hit-region claim.
        XCTAssertTrue(app.frame.contains(close.frame))
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertFalse(comparisonScroll.waitForExistence(timeout: 2))
    }

    private func assertMinimumTapTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func assertOutcome(for gearID: String, in scroll: XCUIElement,
                               file: StaticString = #filePath, line: UInt = #line) {
        let value = outcome(gearID)
        reveal(value, in: scroll, mustFitViewport: true, file: file, line: line)
        XCTAssertTrue(value.exists, file: file, line: line)
        XCTAssertTrue(value.label == "試し戦闘の結果：勝利" || value.label == "試し戦闘の結果：勝利できず",
                      "Unexpected player-facing outcome: \(value.label)", file: file, line: line)
    }

    private func revealText(containing text: String, in scroll: XCUIElement,
                            file: StaticString = #filePath, line: UInt = #line) {
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        reveal(target, in: scroll, mustFitViewport: true, file: file, line: line)
        XCTAssertTrue(target.exists, "Missing result text: \(text)", file: file, line: line)
    }

    /// R129-style bounded scrolling: only drag within the sheet viewport, then
    /// require full visibility (and hittability for controls) before interaction.
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, mustFitViewport: Bool,
                        maxSteps: Int = 36, file: StaticString = #filePath, line: UInt = #line) {
        for step in 0..<maxSteps {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 3)
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let visible = exists && !frame.isEmpty && (mustFitViewport ? viewport.contains(frame) : viewport.intersects(frame))
            let interactive = exists && (element.elementType == .button || element.elementType == .other)
            if visible && (!interactive || element.isHittable) { return }
            let direction: CGFloat = exists && frame.maxY > viewport.maxY ? -1 : (exists && frame.minY < viewport.minY ? 1 : (step.isMultiple(of: 2) ? -1 : 1))
            let travel = min(CGFloat(76), max(CGFloat(28), exists && !frame.isEmpty
                ? abs(direction < 0 ? frame.maxY - viewport.maxY : viewport.minY - frame.minY) + 12 : 64))
            let y = min(max(viewport.midY, viewport.minY + travel / 2 + 8), viewport.maxY - travel / 2 - 8)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (viewport.midX - scroll.frame.minX) / scroll.frame.width,
                dy: (y - scroll.frame.minY) / scroll.frame.height))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * travel)))
        }
        let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 3)
        XCTAssertTrue(element.exists && viewport.contains(element.frame),
                      "Element must fully fit the visible comparison sheet before use", file: file, line: line)
        if element.elementType == .button || element.elementType == .other {
            XCTAssertTrue(element.isHittable, file: file, line: line)
        }
    }

    private func phaseBarrier(_ phase: String, fixture: String) {
        guard UUID(uuidString: runToken) != nil,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            XCTFail("R136 run token or XCTest Documents is unavailable")
            return
        }
        let directory = documents.appendingPathComponent("R136-" + runToken + "-" + saveKey, isDirectory: true)
        let marker = directory.appendingPathComponent("\(saveKey)_\(phase).json")
        let release = directory.appendingPathComponent("\(saveKey)_\(phase)_verified.json")
        do {
            if phase == "fixture_ready" {
                guard !FileManager.default.fileExists(atPath: directory.path) else {
                    XCTFail("R136 token directory already exists; refusing stale phase evidence")
                    return
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            guard FileManager.default.fileExists(atPath: directory.path),
                  !FileManager.default.fileExists(atPath: marker.path), !FileManager.default.fileExists(atPath: release.path) else {
                XCTFail("R136 phase marker is stale or duplicated: \(phase)")
                return
            }
            let payload: [String: String] = [
                "schema": "r136-ui-phase-v1", "saveKey": saveKey, "phase": phase,
                "fixture": fixture, "runToken": runToken,
                "targetKind": targetKind, "targetID": targetID,
                "testPID": String(ProcessInfo.processInfo.processIdentifier),
                "actorID": actorID, "baselineGearID": starterGearID,
                "comparisonGearIDs": firstGearID + "," + secondGearID
            ]
            try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: marker, options: [.atomic])
        } catch {
            XCTFail("Could not publish R136 phase marker \(phase): \(error)")
            return
        }
        print("R136_PHASE saveKey=\(saveKey) phase=\(phase) fixture=\(fixture)")
        let deadline = ProcessInfo.processInfo.systemUptime + 90
        let expectedStatus: String
        switch phase {
        case "fixture_ready": expectedStatus = "SYNTHETIC_BASELINE_CAPTURED"
        case "preview_complete": expectedStatus = "SAVE_BYTES_IDENTICAL_NO_REWARD"
        case "comparison_closed", "cold_reopen": expectedStatus = "SAVE_BYTES_IDENTICAL"
        case "case_complete": expectedStatus = "CASE_READBACK_COMPLETE"
        default: expectedStatus = "PHASE_OBSERVED"
        }
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let data = try? Data(contentsOf: release),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               object["schema"] == "r136-ui-phase-verified-v1", object["saveKey"] == saveKey,
               object["phase"] == phase, object["fixture"] == fixture, object["runToken"] == runToken,
               object["targetKind"] == targetKind, object["targetID"] == targetID,
               object["testPID"] == String(ProcessInfo.processInfo.processIdentifier), object["actorID"] == actorID,
               object["comparisonGearIDs"] == firstGearID + "," + secondGearID, object["status"] == expectedStatus { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Host did not validate R136 save/receipt state at \(phase)")
    }

    private func attach(_ name: String, _ contentSize: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name + "_" + saveKey
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let identity = XCTAttachment(string: "saveKey=\(saveKey)\nfixture=SYNTHETIC_NOT_EARNED\ncontentSize=\(contentSize)\nactorID=\(actorID)\ncomparisonGearIDs=\(firstGearID),\(secondGearID)\nbaselineGearID=\(starterGearID)")
        identity.name = name + "_identity_" + saveKey
        identity.lifetime = .keepAlways
        add(identity)
    }
}
