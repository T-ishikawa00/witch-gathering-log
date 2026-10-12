import XCTest

final class LatentGearCandidateTests: XCTestCase {
    private let app = XCUIApplication()
    private let low = "073D865A-047C-47D0-90C0-24C46F367C00"
    private let high = "073D865A-047C-47D0-90C0-24C46F367C04"

    override func setUpWithError() throws { continueAfterFailure = false }
    func testLargeLatentSlotsComparisonAndEquip() { exercise(category: "UICTContentSizeCategoryL") }
    func testAccessibilityXXXLComparisonAndEquip() { exercise(category: "UICTContentSizeCategoryAccessibilityXXXL") }

    private func exercise(category: String) {
        if app.state != .notRunning { app.terminate() }
        let key = "latent-ui-" + UUID().uuidString
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
            "--qa-fixture=latent-slots-r031", "--qa-persist-fixture", "--qa-latent-compare",
            "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        let scroll = app.scrollViews["sheet_scroll_比較"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 25))
        capture("top", key)
        for (item, prefix) in [(low, "C"), (high, "LR")] {
            for index in 0..<3 {
                let row = app.descendants(matching: .any).matching(identifier: "gear_" + item + "_latent_\(index)").firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 8))
                reveal(row, in: scroll)
                let label = row.label
                if index == 1 {
                    XCTAssertTrue(label.contains("他の仲間向け"), label)
                } else if item == low {
                    XCTAssertTrue(label.contains(["Rで解放", "SRで解放", "URで解放"][index]), label)
                } else {
                    XCTAssertTrue(label.contains("有効"), label)
                    XCTAssertTrue(label.contains("LRの最低値を適用"), label)
                }
                XCTAssertFalse(label.contains("rawQ"))
                XCTAssertFalse(label.contains("AF_"))
                capture(prefix + "_slot_\(index)", key)
            }
        }
        let equip = app.buttons["compare_equip_" + high]
        reveal(equip, in: scroll)
        XCTAssertTrue(equip.isEnabled)
        XCTAssertGreaterThanOrEqual(equip.frame.height, 44)
        XCTAssertGreaterThanOrEqual(equip.frame.width, 44)
        equip.tap()
        capture("equipped", key)
        let finish = app.buttons["finish_comparison"]
        reveal(finish, in: scroll)
        XCTAssertTrue(finish.isEnabled)
        XCTAssertGreaterThanOrEqual(finish.frame.height, 44)
        finish.tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_装備"].waitForExistence(timeout: 10))
        capture("inventory_after_comparison", key)
        let info = XCTAttachment(string: "saveKey=\(key)\ncategory=\(category)\nhighItemID=\(high)\nfixture=latent-slots-r031\nexpectedOwner=C_WITCH\nexpectedComparisonSeen=true")
        info.name = "latent_interaction_identity_" + key; info.lifetime = .keepAlways; add(info)
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        var count = 0
        for _ in 0..<24 {
            let f = element.frame, v = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 3)
            XCTAssertLessThanOrEqual(f.height, v.height, "Target must fit viewport")
            if element.isHittable && f.minY >= v.minY && f.maxY <= v.maxY { break }
            let dy = f.minY < v.minY ? min(v.height * 0.4, v.minY - f.minY + 10)
                : -min(v.height * 0.4, f.maxY - v.maxY + 10)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
            count += 1
        }
        let f = element.frame, v = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 3)
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(f.minY, v.minY)
        XCTAssertLessThanOrEqual(f.maxY, v.maxY)
        XCTAssertGreaterThanOrEqual(f.minX, v.minX)
        XCTAssertLessThanOrEqual(f.maxX, v.maxX)
        let geometry = XCTAttachment(string: "id=\(element.identifier)\nlabel=\(element.label)\nframe=\(f)\nviewport=\(v)\nswipes=\(count)")
        geometry.name = "latent_geometry_" + element.identifier; geometry.lifetime = .keepAlways; add(geometry)
    }
    private func capture(_ name: String, _ key: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name + "_" + key; a.lifetime = .keepAlways; add(a)
    }
}
