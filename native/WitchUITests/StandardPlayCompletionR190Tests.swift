import XCTest

/// Candidate UI route for a fresh R169 standard-development save with the
/// R179 one-time first-craft aid. It deliberately launches without QA args.
/// A host preflight must confirm that the dedicated R169 primary and
/// .previous save are absent before this test is started.
final class StandardPlayCompletionR190Tests: XCTestCase {
    private let app = XCUIApplication()
    private let wallBudget: TimeInterval = 1_500
    private var startedAt: TimeInterval = 0
    private var testRunID = ""
    private var testProcessID = 0
    private let apronID = "AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130"

    override func setUpWithError() throws {
        continueAfterFailure = false
        startedAt = ProcessInfo.processInfo.systemUptime
        testRunID = UUID().uuidString.lowercased()
        testProcessID = Int(ProcessInfo.processInfo.processIdentifier)
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        try super.tearDownWithError()
    }

    func testFreshStandardDevelopmentGatherCraftEquipWardrobeFurnitureColdReopen() throws {
        guard ProcessInfo.processInfo.environment["WITCH_R190_R169_NAMESPACE_PREFLIGHT"] == "ABSENT_PRIMARY_AND_PREVIOUS" else {
            XCTFail("Host must verify the dedicated R169 save.json and save.json.previous are absent; no reset or overwrite is allowed")
            return
        }
        app.launchArguments = []
        app.launchEnvironment = [:]
        XCTAssertTrue(app.launchArguments.isEmpty, "R169 rejects all --qa* arguments; this is a normal UI journey")
        app.launch()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 30), app.debugDescription)
        // Fresh R144 development state starts on ordinary G1 gathering. Confirm
        // this default before fighting; do not change or reseed the work target.
        app.buttons["tab_探索"].tap()
        openExploreControlsIfNeeded()
        let initialTarget = app.staticTexts["r146_shared_work_target"]
        XCTAssertTrue(initialTarget.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(initialTarget.label.contains("採集"), "Fresh standard mode should retain the real default G1 target")
        let gather = app.buttons["r146_work_gather_M_R01_G1"]
        XCTAssertTrue(reveal(gather, in: "explore_scroll", maxSwipes: 14), app.debugDescription)
        XCTAssertEqual(gather.value as? String, "選択中", "Do not dispatch a redundant target switch before accrual")
        record("fresh_default_gather_G1", details: ["targetLabel": initialTarget.label])

        // Earn E2 from the ordinary, visible first-clear encounter.
        let fight = app.buttons["fight_E_R01_02"]
        XCTAssertTrue(reveal(fight, in: "explore_scroll", maxSwipes: 12), app.debugDescription)
        XCTAssertTrue(fight.isEnabled)
        fight.tap()
        waitForBattleToFinish(timeout: 180)
        XCTAssertFalse(app.alerts["確認が必要です"].exists, "A rejected battle cannot count as the first clear")
        record("ordinary_first_clear_E_R01_02")

        // Gather the single authored G1 needed by the R179 aid through ordinary
        // shared-work UI and elapsed wall time. Existing progress is accepted;
        // no clock, grant, fixture, or direct engine command is used.
        openExploreControlsIfNeeded()
        XCTAssertTrue(gather.isEnabled)
        XCTAssertEqual(gather.value as? String, "選択中")
        let clock = app.staticTexts["r146_shared_work_clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 15), app.debugDescription)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*完了 [1-9][0-9]*単位.*"),
            object: clock)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 330), .completed,
                       "Wait for actual authored work accrual; do not speed up the clock")
        record("ordinary_G1_ready", details: ["clockLabel": clock.label])
        let collect = app.buttons["r146_shared_work_collect"]
        XCTAssertTrue(reveal(collect, in: "explore_scroll", maxSwipes: 14))
        XCTAssertTrue(collect.isEnabled)
        collect.tap()
        let summary = app.descendants(matching: .any)["r146_shared_work_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "しなり霊枝")).firstMatch.waitForExistence(timeout: 10),
                      "G1 collection must show the correct material, not E2 灯糸")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\+[1-9][0-9]*")).firstMatch.waitForExistence(timeout: 10),
                      "The actual G1 collection summary must include a positive collected amount")
        record("ordinary_G1_claimed")
        closeSheetIfPresent()

        // R179's shared projection must present and dispatch the same one-time
        // 1/1 costs; after the successful transaction, the ordinary repeat cost
        // returns to baseline. No cost or reward is injected by this test.
        app.buttons["tab_工房"].tap()
        XCTAssertTrue(app.scrollViews["workshop_scroll"].waitForExistence(timeout: 15), app.debugDescription)
        let recipeDetail = app.buttons["recipe_detail_RC_EQ_F_01"]
        XCTAssertTrue(reveal(recipeDetail, in: "workshop_scroll", maxSwipes: 16))
        recipeDetail.tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_制作目標"].waitForExistence(timeout: 12), app.debugDescription)
        let g1 = app.descendants(matching: .any)["goal_material_summary_M_R01_G1"]
        let e2 = app.descendants(matching: .any)["goal_material_summary_M_R01_E2"]
        XCTAssertTrue(g1.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(e2.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(g1.label.contains("必要 1"), "G1 must independently show the R179 one-unit requirement: \(g1.label)")
        XCTAssertTrue(e2.label.contains("必要 1"), "E2 must independently show the R179 one-unit requirement: \(e2.label)")
        let craft = app.buttons["goal_craft"]
        XCTAssertTrue(craft.waitForExistence(timeout: 10)); XCTAssertTrue(craft.isEnabled)
        record("first_craft_ready", details: ["g1Summary": g1.label, "e2Summary": e2.label])
        craft.tap()
        let spentCraft = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: craft)
        XCTAssertEqual(XCTWaiter.wait(for: [spentCraft], timeout: 15), .completed,
                       "Successful aid use must consume the one-time readiness through the shared projection")
        record("first_craft_committed")
        closeSheetIfPresent()

        // Equip only the newly created actual inventory row. Do not assume a
        // generated UUID; the row order and read-only save join identify it.
        app.buttons["tab_仲間"].tap()
        let familiar = app.buttons["companion_C_FAMILIAR"]
        XCTAssertTrue(familiar.waitForExistence(timeout: 12)); familiar.tap()
        app.buttons["inventory"].tap()
        XCTAssertTrue(app.staticTexts["inventory_count"].waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertEqual(app.staticTexts["inventory_count"].label, "所持 5 / 表示 5",
                       "A fresh four-item inventory should contain exactly one real crafted item")
        // InventoryView sorts newest first, matching the existing R140 route.
        let equip = app.buttons["装備"].firstMatch
        XCTAssertTrue(equip.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(equip.isHittable && equip.isEnabled)
        equip.tap()
        XCTAssertTrue(app.staticTexts["companion_equipped_weapon"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["companion_equipped_weapon"].label.contains("灯爪の触媒"), app.debugDescription)
        record("crafted_gear_equipped")
        closeSheetIfPresent()

        // Use one existing development wardrobe candidate through the ordinary
        // picker, then verify persistence after cold reopen. This is a functional
        // candidate-path check, not visual or Human adoption.
        app.buttons["tab_家"].tap()
        let tryOn = app.buttons["home_try_on"]
        XCTAssertTrue(tryOn.waitForExistence(timeout: 12)); tryOn.tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_試着"].waitForExistence(timeout: 12), app.debugDescription)
        let actorPicker = app.descendants(matching: .any)["wardrobe_actor_picker"]
        XCTAssertTrue(actorPicker.waitForExistence(timeout: 10)); actorPicker.tap()
        let actorChoice = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "アイラ", "companion_")).firstMatch
        XCTAssertTrue(actorChoice.waitForExistence(timeout: 8)); actorChoice.tap()
        let apronUse = appearanceButton(apronID, label: "この見た目を使う")
        XCTAssertTrue(reveal(apronUse, in: "sheet_scroll_試着", maxSwipes: 16))
        XCTAssertTrue(apronUse.isEnabled)
        record("wardrobe_candidate_before_apply")
        apronUse.tap()
        XCTAssertTrue(waitForLabel(appearanceButton(apronID, label: "選択中"), "選択中", timeout: 12))
        record("wardrobe_candidate_applied")
        closeSheetIfPresent()

        // Place the existing free starter desk from the normal furniture UI.
        // This is the shipped starter furniture route, not a new SKU.
        app.buttons["tab_家"].tap()
        let makeover = app.buttons["模様替え"]
        XCTAssertTrue(makeover.waitForExistence(timeout: 12)); makeover.tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_模様替え"].waitForExistence(timeout: 10), app.debugDescription)
        let place = app.buttons["place_desk"]
        XCTAssertTrue(place.waitForExistence(timeout: 10), app.debugDescription)
        if place.label.contains("置く") {
            if app.buttons["無料の研究机を受け取る"].exists {
                app.buttons["無料の研究机を受け取る"].tap()
                let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: place)
                XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
            }
            XCTAssertTrue(place.isEnabled)
            place.tap()
        }
        XCTAssertTrue(waitForLabel(place, "しまう", timeout: 10), app.debugDescription)
        record("starter_desk_placed")
        closeSheetIfPresent()

        // Same bundle, no QA arguments, same R169 namespace. Verify durable gear,
        // outfit, and furniture state. Keep the resulting dev save; never reset it.
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.buttons["模様替え"].waitForExistence(timeout: 10)); app.buttons["模様替え"].tap()
        XCTAssertTrue(waitForLabel(app.buttons["place_desk"], "しまう", timeout: 10))
        closeSheetIfPresent()
        app.buttons["home_try_on"].tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_試着"].waitForExistence(timeout: 10))
        let reopenedPicker = app.descendants(matching: .any)["wardrobe_actor_picker"]
        XCTAssertTrue(reopenedPicker.waitForExistence(timeout: 10)); reopenedPicker.tap()
        let reopenedActor = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "アイラ", "companion_")).firstMatch
        XCTAssertTrue(reopenedActor.waitForExistence(timeout: 8))
        reopenedActor.tap()
        XCTAssertEqual(appearanceButton(apronID, label: "選択中").waitForExistence(timeout: 10), true)
        record("cold_reopen_wardrobe_and_furniture")
        closeSheetIfPresent()
        app.buttons["tab_仲間"].tap(); familiar.tap()
        XCTAssertTrue(app.staticTexts["companion_equipped_weapon"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["companion_equipped_weapon"].label.contains("灯爪の触媒"))
        record("cold_reopen_equipped_gear")
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, wallBudget,
                          "R190 is bounded to 25 minutes; preserve the partial evidence on timeout")
    }

    private func appearanceButton(_ id: String, label: String) -> XCUIElement {
        app.buttons.matching(identifier: "appearance_" + id)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func openExploreControlsIfNeeded() {
        if !app.buttons["explore_controls_close"].exists {
            let open = app.buttons["explore_controls"]
            XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
            if !open.isHittable { app.swipeUp() }
            XCTAssertTrue(open.isHittable); open.tap()
        }
        XCTAssertTrue(app.buttons["explore_controls_close"].waitForExistence(timeout: 10))
    }

    private func waitForBattleToFinish(timeout: TimeInterval) {
        let active = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "4人で自動戦闘中")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 20), "Must dispatch the ordinary encounter")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: active)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: timeout), .completed)
    }

    private func reveal(_ element: XCUIElement, in scrollID: String, maxSwipes: Int) -> Bool {
        let scroll = app.scrollViews[scrollID]
        guard scroll.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<maxSwipes {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 2)
            if element.exists && viewport.contains(element.frame) && element.isHittable { return true }
            let up = !element.exists || element.frame.maxY > viewport.maxY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -90 : 90)))
        }
        return element.exists && scroll.frame.intersection(app.frame).contains(element.frame) && element.isHittable
    }

    private func waitForLabel(_ element: XCUIElement, _ fragment: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func closeSheetIfPresent() {
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "閉じる")).firstMatch
        if close.waitForExistence(timeout: 2), close.isHittable { close.tap() }
    }

    private func record(_ phase: String, details: [String: Any] = [:]) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let payload: [String: Any] = [
            "schema": "r190-standard-play-phase-v1",
            "testRunUUID": testRunID,
            "phase": phase,
            "testPID": testProcessID,
            "testStartUptime": startedAt,
            "observedUptime": ProcessInfo.processInfo.systemUptime,
            "elapsedWallSeconds": elapsed,
            "saveNamespace": "Witch03to05DevelopmentR169/save.json",
            "launchArguments": app.launchArguments,
            "details": details
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            XCTFail("Could not serialize the phase attachment")
            return
        }
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let markers = documents.appendingPathComponent("R190").appendingPathComponent(testRunID)
            try FileManager.default.createDirectory(at: markers, withIntermediateDirectories: true)
            try data.write(to: markers.appendingPathComponent(phase + ".json"), options: .withoutOverwriting)
        } catch {
            XCTFail("Could not preserve the test-owned phase marker: \(error)")
        }
        let attachment = XCTAttachment(string: text)
        attachment.name = "R190 Documents/\(testRunID)/phase_\(phase)_\(Int(elapsed))s.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "R190_screen_\(phase)_\(Int(elapsed))s"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
