import XCTest

final class EquipmentAuditDiagnosticTests: XCTestCase {
    func testInventorySearchKeyboardAndFilterReachability() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--qa-isolated", "--qa-save-key=equipment-search-axxxl-r001", "--screen=装備"]
        app.launch()
        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 20))
        let count = app.staticTexts["inventory_count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(count.label.contains("表示 4"), count.label)
        let field = app.textFields["inventory_search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(field.isHittable, "Search field must be visible and tappable at the selected Dynamic Type size")
        attach("search_before_focus", app: app)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard did not appear")
        attach("search_keyboard", app: app)
        field.typeText("灯爪")
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.contains("表示 1"), count.label)
        XCTAssertTrue(app.staticTexts["灯爪の触媒"].waitForExistence(timeout: 5))
        attach("search_filtered_one", app: app)

        let quality = app.buttons["inventory_quality_picker"]
        // The focused field can leave the quality menu below the keyboard.
        // AXXX uses a menu; standard sizes expose the individual segments.
        if quality.exists {
            quality.tap()
        }
        let ur = app.buttons["UR"]
        XCTAssertTrue(ur.waitForExistence(timeout: 5))
        ur.tap()
        XCTAssertTrue(count.label.contains("表示 0"), count.label)
        attach("search_quality_intersection", app: app)

        field.tap()
        for _ in 0..<2 { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        XCTAssertTrue(count.label.contains("表示 0"), count.label)
        if quality.exists { quality.tap() }
        let all = app.buttons["すべて"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        XCTAssertTrue(count.label.contains("表示 4"), count.label)
        attach("search_cleared_and_all_quality", app: app)

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.swipeUp()
        attach("search_keyboard_scroll", app: app)
        XCTAssertTrue(count.exists)
        XCTAssertTrue(app.buttons["閉じる"].exists)
    }

    func testEquipmentContrastAndAllAtSettledPositions() throws {
        for (scrolled, kind) in [(false, "contrast"), (false, "all"), (true, "contrast"), (true, "all")] {
            let app = XCUIApplication()
            app.launchArguments = ["--qa-isolated", "--qa-save-key=equipment-ax-r033-\(UUID().uuidString)", "--screen=装備"]
            app.launch()
            XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 20))
            Thread.sleep(forTimeInterval: 1)
            if scrolled {
                app.scrollViews.firstMatch.swipeUp()
                Thread.sleep(forTimeInterval: 1)
            }
            let prefix = "equipment_\(scrolled ? "settled_scrolled" : "initial")_\(kind)"
            attach("\(prefix)_before", app: app)
            var findings: [String] = []
            do {
                try app.performAccessibilityAudit(for: kind == "contrast" ? .contrast : .all) { issue in
                    findings.append("type=\(issue.auditType.rawValue) elementType=\(String(describing: issue.element?.elementType)) identifier=\(issue.element?.identifier ?? "") label=\(issue.element?.label ?? "") frame=\(String(describing: issue.element?.frame))\n\(issue.compactDescription)\n\(issue.detailedDescription)")
                    return true
                }
            } catch { findings.append("AUDIT_THROW: \(String(reflecting: error))") }
            let report = XCTAttachment(string: findings.isEmpty ? "No issues" : findings.joined(separator: "\n\n"))
            report.name = "\(prefix)_issues"
            report.lifetime = .keepAlways
            add(report)
            attach("\(prefix)_after", app: app)
            print("EQUIPMENT_AUDIT=\(prefix) issueCount=\(findings.count)")
            app.terminate()
        }
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)_tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
