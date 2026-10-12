import XCTest

final class ScrollIndicatorCandidateTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLargeHomeAndExploreScrollSnapshots() {
        let saveKey = launchForContentSize("UICTContentSizeCategoryL")
        capture("large_home_top", saveKey: saveKey)

        let homeClaim = app.buttons["claim_offline"]
        XCTAssertTrue(homeClaim.waitForExistence(timeout: 10))
        scrollUntilFullyVisible(homeClaim, footerID: "tab_家", maximumSwipes: 8)
        capture("large_home_after_scroll", saveKey: saveKey)

        openExploreWithoutGameAction()
        capture("large_explore_top", saveKey: saveKey)
        let controls = app.buttons["explore_controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        scrollUntilFullyVisible(controls, footerID: "tab_探索", maximumSwipes: 8)
        capture("large_explore_after_scroll", saveKey: saveKey)
    }

    func testAccessibilityXXXLHomeAndExploreRemainScrollable() {
        let saveKey = launchForContentSize("UICTContentSizeCategoryAccessibilityXXXL")
        capture("axxxl_home_top", saveKey: saveKey)

        let homeClaim = app.buttons["claim_offline"]
        XCTAssertTrue(homeClaim.waitForExistence(timeout: 10))
        scrollUntilFullyVisible(homeClaim, footerID: "tab_家", maximumSwipes: 12)
        capture("axxxl_home_after_scroll", saveKey: saveKey)

        openExploreWithoutGameAction()
        capture("axxxl_explore_top", saveKey: saveKey)
        let controls = app.buttons["explore_controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        scrollUntilFullyVisible(controls, footerID: "tab_探索", maximumSwipes: 12)
        capture("axxxl_explore_after_scroll", saveKey: saveKey)
    }

    @discardableResult
    private func launchForContentSize(_ category: String) -> String {
        if app.state != .notRunning { app.terminate() }
        let saveKey = "scroll-indicator-\(UUID().uuidString)"
        app.launchArguments = [
            "--qa-isolated",
            "--qa-save-key=\(saveKey)",
            "-UIPreferredContentSizeCategoryName",
            category
        ]
        app.launch()
        XCTAssertTrue(app.buttons["claim_offline"].waitForExistence(timeout: 20), "Home should be ready for requested content category \(category)")
        let categoryAttachment = XCTAttachment(string: "requestedContentSizeCategory=\(category)\nsaveKey=\(saveKey)")
        categoryAttachment.name = "scroll_indicator_launch_\(category)"
        categoryAttachment.lifetime = .keepAlways
        add(categoryAttachment)
        return saveKey
    }

    private func openExploreWithoutGameAction() {
        let exploreTab = app.buttons["tab_探索"]
        if exploreTab.waitForExistence(timeout: 5) {
            exploreTab.tap()
        } else {
            let adaptiveMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")).firstMatch
            XCTAssertTrue(adaptiveMenu.waitForExistence(timeout: 10), "Adaptive navigation menu should be present")
            adaptiveMenu.tap()
            let chooseExplore = app.buttons["choose_tab_探索"]
            XCTAssertTrue(chooseExplore.waitForExistence(timeout: 5))
            chooseExplore.tap()
        }
        XCTAssertTrue(app.buttons["region_R01"].waitForExistence(timeout: 10), "Explore view should be visible")
    }

    private func scrollUntilFullyVisible(_ element: XCUIElement, footerID: String, maximumSwipes: Int) {
        let footer = app.buttons[footerID]
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "Fixed tab bar should remain available")
        // Home/explore each expose one root ScrollView and no sheet in these tests.
        // Its viewport excludes the opaque header. app.frame alone does not.
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Root scroll viewport should be available")
        var swipeCount = 0
        for _ in 0..<maximumSwipes {
            let frame = element.frame
            let viewport = scroll.frame.intersection(app.frame)
            let top = viewport.minY + 2
            let bottom = min(viewport.maxY, footer.frame.minY) - 2
            XCTAssertLessThanOrEqual(frame.height, bottom - top, "Target must fit inside the unobscured viewport")
            if element.isHittable && frame.minY >= top && frame.maxY <= bottom {
                break
            }
            // A full upward swipe can overshoot and hide the target behind the
            // fixed header. Correct in either direction with a bounded drag.
            let delta = frame.minY < top ? min(viewport.height * 0.35, top - frame.minY + 8)
                : -min(viewport.height * 0.35, frame.maxY - bottom + 8)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
            swipeCount += 1
        }
        let frame = element.frame
        let viewport = scroll.frame.intersection(app.frame)
        let visible = CGRect(x: viewport.minX, y: viewport.minY + 2, width: viewport.width,
                             height: min(viewport.maxY, footer.frame.minY) - viewport.minY - 4)
        XCTAssertTrue(element.isHittable, "Target should be reachable after scrolling; swipes=\(swipeCount), frame=\(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY, "Target top must clear the opaque fixed header")
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY, "Target bottom must clear the fixed tab bar")
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        let geometry = XCTAttachment(string: "target=\(element.identifier)\nframe=\(frame)\nscrollViewport=\(viewport)\nunobscuredBounds=\(visible)\nfooter=\(footer.frame)\nswipes=\(swipeCount)")
        geometry.name = "scroll_indicator_reachability_\(element.identifier)"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func capture(_ name: String, saveKey: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)_\(saveKey)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
