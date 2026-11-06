import XCTest

/// Off-live R061 scenario. This is a user-flow/renderability test, not a quality or approval test.
final class ERNABodyFitR061Tests: XCTestCase {
    private let body01 = "6A9220A2-77F0-4DB7-8DF3-01D4C7956101"
    private let body02 = "6A9220A2-77F0-4DB7-8DF3-01D4C7956102"

    func testActualEquipReplaceAndRenderedMotionForStandardAndTravel() throws {
        // Each costume starts from its own empty-body-slot fixture/save. The candidate gear is
        // actually equipped and replaced through InventoryView; nothing is pre-equipped.
        runCostumeSequence(name: "standard", selectTravelFirst: false)
        runCostumeSequence(name: "travel", selectTravelFirst: true)
    }

    private func runCostumeSequence(name: String, selectTravelFirst: Bool) {
        let key = "erna-body-fit-r061-\(name)-\(UUID().uuidString.lowercased())"
        let context = XCTAttachment(string: "R061_SAVE_CONTEXT|costume=\(name)|saveKey=\(key)")
        context.name = name + "_save_key_context"
        context.lifetime = .keepAlways
        add(context)
        let app = XCUIApplication()
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
                               "--qa-fixture=erna-body-fit-r061", "--qa-persist-fixture",
                               "--qa-readback-save", "--screen=仲間"]
        app.launch()
        XCTAssertTrue(app.buttons["inventory"].waitForExistence(timeout: 30))
        attach("\(name)_empty_slot_before", app)

        ensureERNASelected(in: app)
        if selectTravelFirst {
            let wardrobe = app.buttons["試着"]
            XCTAssertTrue(wardrobe.waitForExistence(timeout: 10))
            wardrobe.tap()
            // Costume rows share their identifier across sibling AX elements too.
            let appearance = app.descendants(matching: .any)
                .matching(identifier: "appearance_ERNA_TRAVEL")
            XCTAssertTrue(appearance.firstMatch.waitForExistence(timeout: 10))
            let select = appearance.matching(NSPredicate(format: "label == %@", "無料で試着する")).firstMatch
            XCTAssertTrue(select.waitForExistence(timeout: 5))
            select.tap()
            XCTAssertTrue(appearance.matching(NSPredicate(format: "label == %@", "選択中")).firstMatch.waitForExistence(timeout: 8))
            attach("travel_costume_selected", app)
            app.buttons["閉じる"].tap()
        }

        equip(body01, label: "body01_\(name)", in: app)
        app.buttons["閉じる"].tap()
        rebuildPortrait(app)
        attach("\(name)_body01_after_rebuild", app)
        app.terminate()
        runPartyMotion(saveKey: key, label: "body01_\(name)")

        // Reload the same isolated save and perform a real replacement. This verifies the old
        // body candidate loses ownership while the new one is selected, then scene binding is rebuilt.
        let replacement = XCUIApplication()
        replacement.launchArguments = ["--qa-isolated", "--qa-save-key=" + key,
                                       "--qa-readback-save", "--screen=仲間"]
        replacement.launch()
        XCTAssertTrue(replacement.buttons["inventory"].waitForExistence(timeout: 25))
        equip(body02, label: "body02_\(name)", in: replacement)
        XCTAssertFalse(gearElement(body01, label: "使用中", in: replacement).exists,
                       "Replacing body item must release the prior item")
        XCTAssertTrue(gearElement(body02, label: "使用中", in: replacement).exists)
        replacement.buttons["閉じる"].tap()
        rebuildPortrait(replacement)
        attach("\(name)_body02_after_rebuild", replacement)
        replacement.terminate()
        runPartyMotion(saveKey: key, label: "body02_\(name)")
    }

    private func equip(_ id: String, label: String, in app: XCUIApplication) {
        ensureERNASelected(in: app)
        app.buttons["inventory"].tap()
        let itemLabel = gearElement(id, label: nil, in: app)
        XCTAssertTrue(itemLabel.waitForExistence(timeout: 10), "Expected owned body item row \(id)")
        XCTAssertFalse(gearElement(id, label: "使用中", in: app).exists,
                       "Fixture must not pre-equip \(id)")
        // gear_<UUID> is assigned to sibling Image, StaticText, and Button nodes. A query from
        // the first matching row element therefore has no child buttons. Query the global tree
        // by the exact gear identifier and action label instead; `.any` also avoids XCTest's
        // legacy Button / modern PopUpButton coercion when a row contains the “育てる” Menu.
        let button = gearElement(id, label: "装備", in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
        button.tap()
        XCTAssertTrue(gearElement(id, label: "使用中", in: app).waitForExistence(timeout: 8))
        attach(label + "_equipped_in_inventory", app)
    }

    private func ensureERNASelected(in app: XCUIApplication) {
        let erna = app.buttons["companion_C_WITCH"]
        XCTAssertTrue(erna.waitForExistence(timeout: 8), "ERNA must be available for body gear")
        if (erna.value as? String) != "選択中" { erna.tap() }
        let selectedValue = NSPredicate(format: "value == %@", "選択中")
        expectation(for: selectedValue, evaluatedWith: erna)
        waitForExpectations(timeout: 5)
    }

    private func gearElement(_ id: String, label: String?, in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any).matching(identifier: "gear_" + id)
        guard let label else { return identified.firstMatch }
        return identified.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func rebuildPortrait(_ app: XCUIApplication) {
        // Re-enter the portrait scene after the inventory action to exercise normal sync/rebuild.
        let explore = app.buttons["tab_探索"]
        XCTAssertTrue(explore.waitForExistence(timeout: 8))
        explore.tap()
        let companions = app.buttons["tab_仲間"]
        XCTAssertTrue(companions.waitForExistence(timeout: 8))
        companions.tap()
        XCTAssertTrue(app.buttons["inventory"].waitForExistence(timeout: 8))
    }

    private func runPartyMotion(saveKey: String, label: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + saveKey,
                               "--qa-readback-save", "--qa-party-motion", "--qa-party-motion-step", "--screen=探索"]
        app.launch()
        for phase in ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"] {
            let state = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "味方動作検証: " + phase)).firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: phase == "idle" ? 25 : 30), "Missing QA motion phase \(phase)")
            let advance = app.buttons["qa_party_motion_advance"]
            XCTAssertTrue(advance.waitForExistence(timeout: 10), "QA step gate must be visible for \(phase)")
            let expectedPhase = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: advance)
            XCTAssertEqual(XCTWaiter.wait(for: [expectedPhase], timeout: 10), .completed,
                           "Advance control must be bound to the rendered phase")
            attach(label + "_" + phase + "_start", app)
            if phase == "walk" {
                // The pinned ERNA layered walk clip is 9 frames at 12 fps (0.75 s/loop).
                // These are visual samples, not frame-index/timing proof; the captured test video is reviewed separately.
                Thread.sleep(forTimeInterval: 0.75); attach(label + "_walk_nominal_loop1", app)
                Thread.sleep(forTimeInterval: 0.75); attach(label + "_walk_nominal_loop2", app)
            }
            // The isolated step flag freezes only the QA sequence at this state. Advancing
            // occurs after screenshot/AX evidence is attached, so slow XCTest work cannot skip phases.
            advance.tap()
        }
        Thread.sleep(forTimeInterval: 1.0)
        attach(label + "_motion_sequence_end", app)
        app.terminate()
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "_ax"; tree.lifetime = .keepAlways; add(tree)
    }
}
