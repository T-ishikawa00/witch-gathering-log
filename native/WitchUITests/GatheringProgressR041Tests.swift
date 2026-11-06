import XCTest

final class GatheringProgressR041Tests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGatheringProgressLarge() { verify("UICTContentSizeCategoryL") }
    func testGatheringProgressAXXXL() { verify("UICTContentSizeCategoryAccessibilityXXXL") }

    private func verify(_ size: String) {
        let key = "recipe-goal-r037-" + UUID().uuidString
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", size,
            "--qa-isolated", "--qa-save-key=" + key, "--qa-fixture=recipe-goal-r037",
            "--qa-recipe-goal=gather-shortage", "--qa-persist-fixture", "--qa-recipe-goal-baseline", "--screen=家"]
        app.launch()
        XCTAssertTrue(app.buttons["claim_offline"].waitForExistence(timeout: 25), "home fixture should load")
        checkProgress("home", key, size)

        openExploreWithoutGameAction()
        checkProgress("explore", key, size)
        let expand = app.buttons["explore_controls"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        scrollUntilFullyVisible(expand, in: app.scrollViews["explore_scroll"], stage: "explore_controls", maxDrags: 4)
        expand.tap()
        checkProgress("expanded", key, size)

        let identity = XCTAttachment(string: "saveKey=\(key)\nsize=\(size)\nclassification=SYNTHETIC_QA_FIXTURE_NOT_EARNED\noperations=read_only_navigation")
        identity.name = "gather_progress_identity_" + key
        identity.lifetime = .keepAlways
        add(identity)
    }

    private func openExploreWithoutGameAction() {
        let directTab = app.buttons["tab_探索"]
        if directTab.waitForExistence(timeout: 3) {
            directTab.tap()
        } else {
            let adaptiveMenu = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")
            ).firstMatch
            XCTAssertTrue(adaptiveMenu.waitForExistence(timeout: 10), "adaptive navigation menu must be available")
            adaptiveMenu.tap()
            let chooseExplore = app.buttons["choose_tab_探索"]
            XCTAssertTrue(chooseExplore.waitForExistence(timeout: 5), "Explore menu action must be available")
            chooseExplore.tap()
        }
        XCTAssertTrue(app.scrollViews["explore_scroll"].waitForExistence(timeout: 10), "Explore route must be active")
        XCTAssertTrue(app.buttons["region_R01"].waitForExistence(timeout: 10), "Explore controls must be visible")
    }

    private func scrollUntilFullyVisible(_ element: XCUIElement, in scroll: XCUIElement, stage: String, maxDrags: Int) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 12), "active \(stage) scroll must exist")
        var drags = 0
        for _ in 0..<maxDrags {
            let viewport = scroll.frame.intersection(app.frame)
            let frame = element.frame
            if element.isHittable && viewport.contains(frame) { break }
            XCTAssertGreaterThan(viewport.width, 0)
            XCTAssertGreaterThan(viewport.height, 0)
            let delta: CGFloat
            if frame.maxY > viewport.maxY {
                delta = -min(48, max(22, frame.maxY - viewport.maxY + 6))
            } else if frame.minY < viewport.minY {
                delta = min(48, max(22, viewport.minY - frame.minY + 6))
            } else {
                break
            }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
            drags += 1
        }
        let viewport = scroll.frame.intersection(app.frame)
        XCTAssertTrue(element.isHittable, "\(stage) must be hittable after bounded short scrolls; drags=\(drags), element=\(element.frame), viewport=\(viewport)")
        XCTAssertTrue(viewport.contains(element.frame), "\(stage) must fit fully inside the active scroll viewport")
        let geometry = XCTAttachment(string: "stage=\(stage)\ndrags=\(drags)\nelement=\(element.frame)\nscrollViewport=\(viewport)")
        geometry.name = "gather_progress_scroll_" + stage
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func seconds(_ text: String) -> Int {
        let pattern = "次の素材まで ([0-9]+)分([0-9]+)秒"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let minutes = Range(match.range(at: 1), in: text),
              let seconds = Range(match.range(at: 2), in: text),
              let m = Int(text[minutes]), let s = Int(text[seconds]), s < 60 else {
            XCTFail("R01 countdown not readable: " + text)
            return -1
        }
        return m * 60 + s
    }

    private func checkProgress(_ stage: String, _ key: String, _ size: String) {
        let scroll = app.scrollViews[stage == "home" ? "home_scroll" : "explore_scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 12))
        let progress = scroll.descendants(matching: .any).matching(identifier: "gathering_progress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 12))
        scrollUntilFullyVisible(progress, in: scroll, stage: stage, maxDrags: 5)
        XCTAssertTrue(progress.label.contains("次の素材まで"), progress.label)
        let before = progress.label
        let beforeSeconds = seconds(before)
        let started = Date()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in progress.label != before }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "real elapsed countdown must update")
        let afterSeconds = seconds(progress.label)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(beforeSeconds - afterSeconds, 1)
        XCTAssertLessThanOrEqual(beforeSeconds - afterSeconds, Int(ceil(elapsed)) + 2, "countdown must follow real elapsed seconds")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "gather_progress_\(stage)_\(size)_\(key)"
        shot.lifetime = .keepAlways
        add(shot)
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "gather_progress_AX_\(stage)_\(key)"
        snapshot.lifetime = .keepAlways
        add(snapshot)
    }
}
