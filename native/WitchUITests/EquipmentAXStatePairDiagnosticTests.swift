import XCTest

/// Diagnostic only: run the same frozen source once at Large and once at AXXX-large.
/// It records AX geometry and audit output without changing production UI or treating
/// an audit warning as an automatic test failure.
final class EquipmentAXStatePairDiagnosticTests: XCTestCase {
    func testAXXXLFirstGearTextAndActionsReachableAndProtectionPersists() throws {
        let app = XCUIApplication()
        let saveKey = "equipment-ax-r026-\(UUID().uuidString)"
        let saveKeyAttachment = XCTAttachment(string: "saveKey=\(saveKey)\nfixture=isolated persisted equipment fixture\n")
        saveKeyAttachment.name = "equipment_ax_unique_save_key"
        saveKeyAttachment.lifetime = .keepAlways
        add(saveKeyAttachment)
        let arguments = ["--qa-isolated", "--qa-persist-fixture", "--qa-save-key=\(saveKey)", "--screen=装備"]
        app.launchArguments = arguments
        app.launch()

        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 20))
        let itemName = app.staticTexts["灯爪の触媒"]
        XCTAssertTrue(itemName.waitForExistence(timeout: 15))
        attach("equipment_initial_viewport", app: app)

        let inventoryScroll = app.scrollViews.element(boundBy: app.scrollViews.count - 1)
        XCTAssertTrue(inventoryScroll.exists, "Inventory scroll view must be present")
        var steps: [String] = []
        func scrollSmallDistance() {
            let start = inventoryScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80))
            let end = inventoryScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        func scrollTowardTop() {
            let start = inventoryScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            let end = inventoryScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            start.press(forDuration: 0.1, thenDragTo: end)
        }

        // The complete card is intentionally taller than the viewport at AXXXL.
        // Verify its text and controls in separate settled scroll positions.
        var titleVisible = false
        for index in 0..<5 {
            let frame = itemName.frame
            let viewport = inventoryScroll.frame
            steps.append("titleStep=\(index) frame=\(frame) viewport=\(viewport) hittable=\(itemName.isHittable)")
            if frame.minY >= viewport.minY && frame.maxY <= viewport.maxY && itemName.isHittable {
                titleVisible = true
                break
            }
            scrollSmallDistance()
        }
        XCTAssertTrue(titleVisible, "First gear title should be fully scrollable into the viewport. \(steps.joined(separator: " | "))")

        let metadata = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "C  +0")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        var viewport = inventoryScroll.frame
        let titleFrame = itemName.frame
        let metadataFrame = metadata.frame
        let titleFullyVisible = titleFrame.minY >= viewport.minY && titleFrame.maxY <= viewport.maxY && itemName.isHittable
        XCTAssertTrue(titleFullyVisible)
        attach("equipment_title_visible", app: app)

        var metadataVisible = false
        for index in 0..<5 {
            let frame = metadata.frame
            viewport = inventoryScroll.frame
            steps.append("metadataStep=\(index) frame=\(frame) viewport=\(viewport) hittable=\(metadata.isHittable)")
            if frame.minY >= viewport.minY && frame.maxY <= viewport.maxY && metadata.isHittable {
                metadataVisible = true
                break
            }
            scrollSmallDistance()
        }
        XCTAssertTrue(metadataVisible, "First gear metadata should be fully scrollable into the viewport")

        let enabledCompare = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "比較", "gear_")).firstMatch
        let enabledGrow = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "育てる", "gear_")).firstMatch
        let disabledEquip = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "装備", "gear_")).firstMatch
        let disabledDismantle = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "分解", "gear_")).firstMatch
        XCTAssertTrue(enabledCompare.waitForExistence(timeout: 5))
        XCTAssertTrue(enabledGrow.waitForExistence(timeout: 5))
        XCTAssertTrue(disabledEquip.waitForExistence(timeout: 5))
        XCTAssertTrue(disabledDismantle.waitForExistence(timeout: 5))
        var actionsVisible = false
        for index in 0..<5 {
            let compareFrame = enabledCompare.frame
            let growFrame = enabledGrow.frame
            let equipFrame = disabledEquip.frame
            let dismantleFrame = disabledDismantle.frame
            viewport = inventoryScroll.frame
            steps.append("actionsStep=\(index) viewport=\(viewport) compare=\(compareFrame) grow=\(growFrame) equip=\(equipFrame) dismantle=\(dismantleFrame)")
            let visible: (CGRect) -> Bool = { $0.minY >= viewport.minY && $0.maxY <= viewport.maxY }
            if visible(compareFrame) && visible(growFrame) && visible(equipFrame) && visible(dismantleFrame) && enabledGrow.isHittable {
                actionsVisible = true
                break
            }
            scrollSmallDistance()
        }
        XCTAssertTrue(actionsVisible, "Each first-row action must be independently visible together at this settled position")
        XCTAssertTrue(enabledCompare.isEnabled && enabledCompare.isHittable)
        XCTAssertTrue(enabledGrow.isEnabled && enabledGrow.isHittable)
        XCTAssertFalse(disabledEquip.isEnabled)
        XCTAssertFalse(disabledDismantle.isEnabled)

        attachText("equipment_scrolled_geometry", [
            "viewport=\(viewport)",
            "title=\(itemName.label) frame=\(titleFrame)",
            "metadata=\(metadata.label) frame=\(metadataFrame)",
            "compare=\(enabledCompare.frame) enabled=\(enabledCompare.isEnabled) hittable=\(enabledCompare.isHittable)",
            "grow=\(enabledGrow.frame) enabled=\(enabledGrow.isEnabled) hittable=\(enabledGrow.isHittable)",
            "equip=\(disabledEquip.frame) enabled=\(disabledEquip.isEnabled)",
            "dismantle=\(disabledDismantle.frame) enabled=\(disabledDismantle.isEnabled)",
            steps.joined(separator: "\n")
        ].joined(separator: "\n"))
        attach("equipment_scrolled_viewport", app: app)

        // Toggle protection through the actual enabled control (no economy input
        // required), restart with the same isolated key, and verify the saved value.
        let gearID = "gear_10000000-0000-4000-8000-000000000004"
        // The fresh persisted fixture starts protected. Its AX label names the
        // available action, while its AX value reports the current state.
        let protection = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", gearID, "保護を解除")).firstMatch
        XCTAssertTrue(protection.waitForExistence(timeout: 5))
        XCTAssertEqual(protection.value as? String, "保護中")
        var protectionVisible = false
        for index in 0..<5 {
            let frame = protection.frame
            viewport = inventoryScroll.frame
            steps.append("protectionStep=\(index) frame=\(frame) viewport=\(viewport) hittable=\(protection.isHittable)")
            if frame.minY >= viewport.minY + 20 && frame.maxY <= viewport.maxY && protection.isHittable {
                protectionVisible = true
                break
            }
            scrollTowardTop()
        }
        XCTAssertTrue(protectionVisible, "Protection control must be fully visible before tapping")
        attachText("protection_control_geometry", "frame=\(protection.frame) viewport=\(inventoryScroll.frame) label=\(protection.label) value=\(String(describing: protection.value))")
        attach("equipment_protection_before_toggle", app: app)
        protection.tap()
        let unprotected = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", gearID, "を保護")).firstMatch
        XCTAssertTrue(unprotected.waitForExistence(timeout: 5))
        XCTAssertTrue(unprotected.label.contains("を保護"), unprotected.label)
        XCTAssertEqual(unprotected.value as? String, "保護なし")
        attach("equipment_protection_toggled", app: app)
        app.terminate()

        app.launchArguments = arguments.filter { $0 != "--qa-persist-fixture" }
        app.launch()
        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 20))
        let restoredProtection = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", gearID, "を保護")).firstMatch
        XCTAssertTrue(restoredProtection.waitForExistence(timeout: 10))
        var restoredControlVisible = false
        for _ in 0..<5 {
            let frame = restoredProtection.frame
            viewport = inventoryScroll.frame
            if frame.minY >= viewport.minY + 20 && frame.maxY <= viewport.maxY && restoredProtection.isHittable {
                restoredControlVisible = true
                break
            }
            scrollSmallDistance()
        }
        XCTAssertTrue(restoredControlVisible, "Restored protection state must be readable in the visible row")
        XCTAssertTrue(restoredProtection.label.contains("を保護"), restoredProtection.label)
        XCTAssertEqual(restoredProtection.value as? String, "保護なし")
        attach("equipment_protection_after_restart", app: app)

        // Also prove an enabled row action opens its native menu after scrolling.
        let restoredGrow = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "育てる", "gear_")).firstMatch
        for _ in 0..<5 where !restoredGrow.isHittable { scrollSmallDistance() }
        XCTAssertTrue(restoredGrow.isHittable)
        restoredGrow.tap()
        let enhance = app.buttons["強化"]
        XCTAssertTrue(enhance.waitForExistence(timeout: 5))
        XCTAssertTrue(enhance.isHittable)
        attach("equipment_growth_menu_after_restart", app: app)
        app.terminate()
    }

    func testEquipmentButtonsAndMetadataAtCurrentDynamicTypeSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--qa-isolated",
            "--qa-save-key=equipment-ax-r025-\(UUID().uuidString)",
            "--screen=装備"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["灯爪の触媒"].waitForExistence(timeout: 15))
        let itemName = app.staticTexts["灯爪の触媒"]
        let metadata = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "C  +0")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))

        var observations: [String] = []
        for label in ["比較", "装備", "育てる", "分解"] {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
            observations.append("LABEL \(label) count=\(matches.count)")
            for index in 0..<matches.count {
                let button = matches.element(boundBy: index)
                let frame = button.frame
                observations.append("BUTTON \(label) index=\(index) enabled=\(button.isEnabled) frame=\(frame)")
            }
        }
        observations.append("GEAR_NAME label=\(itemName.label) frame=\(itemName.frame)")
        observations.append("GEAR_METADATA label=\(metadata.label) frame=\(metadata.frame)")
        attach("equipment_before_audit", app: app)
        attachText("equipment_ax_geometry", observations.joined(separator: "\n"))

        var issues: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                issues.append("type=\(issue.auditType.rawValue) label=\(issue.element?.label ?? "") frame=\(String(describing: issue.element?.frame))\n\(issue.compactDescription)\n\(issue.detailedDescription)")
                return true
            }
        } catch {
            issues.append("AUDIT_THROW: \(String(reflecting: error))")
        }
        attachText("equipment_ax_all_issues", issues.isEmpty ? "No issues" : issues.joined(separator: "\n\n"))
        attach("equipment_after_audit", app: app)
        app.terminate()
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "_tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func attachText(_ name: String, _ value: String) {
        let attachment = XCTAttachment(string: value)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
