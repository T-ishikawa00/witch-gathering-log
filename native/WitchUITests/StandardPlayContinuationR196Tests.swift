import CryptoKit
import Darwin
import XCTest

/// Off-live continuation journey for the existing R169 development save.
/// The host must bind and preserve that save before launch; this test never
/// resets state, injects a fixture, advances time, or passes QA arguments.
final class StandardPlayContinuationR196Tests: XCTestCase {
    private let app = XCUIApplication()
    private let wallBudget: TimeInterval = 900
    private var startedAt: TimeInterval = 0
    private var runToken = ""
    private var testStartUptime: TimeInterval = 0
    private var screenshotCount = 0
    private var setupReady = false

    private let actors: [(id: String, name: String)] = [
        ("C_WITCH", "エルナ"),
        ("C_APPRENTICE", "ルナ"),
        ("C_SMITH", "アイラ"),
        ("C_FAMILIAR", "ノワール")
    ]
    private let targetGearID = "EQ_W_P1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        startedAt = ProcessInfo.processInfo.systemUptime
        testStartUptime = startedAt
        guard let raw = ProcessInfo.processInfo.environment["WITCH_R196_RUN_TOKEN"],
              let uuid = UUID(uuidString: raw) else {
            XCTFail("Host runner must provide a unique UUID in WITCH_R196_RUN_TOKEN")
            return
        }
        runToken = uuid.uuidString.lowercased()
        setupReady = true
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground || app.state == .runningBackground { app.terminate() }
        try super.tearDownWithError()
    }

    func testContinueEarnedSaveThroughComparisonGachaAndAccessibleCompanions() throws {
        guard setupReady else { XCTFail("R196 setup preflight failed; refusing all app access"); return }
        guard ProcessInfo.processInfo.environment["WITCH_R196_R190_PREFLIGHT"] ==
                "89d533780ec1714ca5b783e45b9917cb2701d3e8bfaa05964a6879f5341ecb9b" else {
            XCTFail("Host must verify the pinned R190 development-save preflight before this non-destructive continuation")
            return
        }

        launchStandard()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 30), app.debugDescription)
        let homeScene = element("living_scene")
        XCTAssertTrue(homeScene.waitForExistence(timeout: 15), "The whole home scene must be present")
        capture("home_whole_scene")

        // Inspect all four party entries through the ordinary companion UI.
        // For each actor, verify the selected identity, rendered scene viewport,
        // and real summary fields; capture portrait and summary separately so
        // scrolling does not hide either part of the evidence.
        navigateToCompanions()
        for actor in actors {
            let scroll = app.scrollViews["companion_scroll"]
            let selector = app.buttons["companion_" + actor.id]
            XCTAssertTrue(reveal(selector, in: scroll, maxSwipes: 12), app.debugDescription)
            selector.tap()
            XCTAssertEqual(selector.value as? String, "選択中", "Wrong party selector for \(actor.id)")
            let title = app.staticTexts.matching(NSPredicate(format: "label == %@", actor.name)).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "Missing actor-specific summary title for \(actor.id)")
            let portrait = element("living_scene")
            let stats = app.staticTexts["companion_stats"]
            let level = app.staticTexts["companion_level"]
            let equipment = app.staticTexts["companion_equipped_weapon"]
            XCTAssertTrue(reveal(portrait, in: scroll, maxSwipes: 12), "Portrait not reachable for \(actor.id)")
            XCTAssertTrue(reveal(stats, in: scroll, maxSwipes: 12), "Summary not reachable for \(actor.id)")
            XCTAssertTrue(stats.exists && level.exists && equipment.exists, app.debugDescription)
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 1)
            XCTAssertTrue(viewport.contains(portrait.frame) && viewport.contains(stats.frame) && viewport.contains(title.frame),
                          "Portrait, identity, and summary must be visible together for the ordinary-size evidence frame: \(actor.id)")
            capture("standard_companion_\(actor.id)_portrait_and_summary")
        }

        // The pinned R190 save starts with the tutorial still locked despite
        // five earned free tickets. Inspect, but do not alter, that state.
        app.buttons["tab_家"].tap()
        openGacha()
        XCTAssertEqual(number(in: app.staticTexts["gacha_ticket_balance"].label), 5)
        XCTAssertFalse(app.buttons["gacha_target"].isEnabled)
        XCTAssertFalse(app.buttons["summon5"].isEnabled)
        XCTAssertFalse(app.buttons["daily_free_claim"].isEnabled)
        closeSheetIfPresent()

        // The ordinary paired preview runs two real same-slot owned gear UUIDs
        // against an already available campaign target. It is read-only; host
        // readback compares primary-save bytes and asserts zero rewards/deltas.
        navigateToCompanions()
        let familiarSelector = app.buttons["companion_C_FAMILIAR"]
        let companionScroll = app.scrollViews["companion_scroll"]
        XCTAssertTrue(reveal(familiarSelector, in: companionScroll, maxSwipes: 12), app.debugDescription)
        familiarSelector.tap()
        let inventory = app.buttons["inventory"]
        XCTAssertTrue(reveal(inventory, in: companionScroll, maxSwipes: 12), app.debugDescription)
        inventory.tap()
        let inventoryScroll = app.scrollViews["sheet_scroll_装備"]
        XCTAssertTrue(inventoryScroll.waitForExistence(timeout: 12), app.debugDescription)
        let countLabel = app.staticTexts["inventory_count"]
        XCTAssertTrue(reveal(countLabel, in: inventoryScroll, maxSwipes: 12))
        XCTAssertEqual(countLabel.label, "所持 5 / 表示 5")
        let compare = app.buttons["比較"].firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 12), "A same-slot comparison must be available from the earned Familiar inventory")
        XCTAssertTrue(reveal(compare, in: inventoryScroll, maxSwipes: 12), "Reveal Compare inside its own scroll viewport")
        XCTAssertTrue(compare.isEnabled && compare.isHittable)
        XCTAssertTrue(hostBarrier("trial_before", evidence: [
            "inventoryCount": 5, "gachaInitiallyLocked": true, "previewIsReadOnly": true,
            "saveMutationExpected": false, "rewardDeltaExpected": 0
        ]))
        compare.tap()
        let comparisonScroll = app.scrollViews["sheet_scroll_比較"]
        XCTAssertTrue(comparisonScroll.waitForExistence(timeout: 12), app.debugDescription)
        let intro = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "装備や進行、報酬は変わりません")).firstMatch
        if intro.exists { XCTAssertTrue(reveal(intro, in: comparisonScroll, maxSwipes: 12)) }
        let previewSections = app.staticTexts.matching(NSPredicate(format: "label == %@", "装着時の仲間の性能"))
        XCTAssertEqual(previewSections.count, 2, "Both actual owned gear items must have preview cards")
        let targetPicker = app.buttons["gear_trial_target_picker"]
        XCTAssertTrue(targetPicker.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(reveal(targetPicker, in: comparisonScroll, maxSwipes: 12), "Reveal campaign target picker")
        // SwiftUI includes the control title before its selected value in AX.
        XCTAssertTrue(targetPicker.isEnabled && targetPicker.label.contains("探索："), targetPicker.label)
        let trial = app.buttons["run_gear_trial"]
        XCTAssertTrue(trial.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(reveal(trial, in: comparisonScroll, maxSwipes: 12), "Reveal actual paired battle-preview action")
        XCTAssertTrue(trial.isEnabled)
        trial.tap()
        let outcomes = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "gear_trial_outcome_"))
        let bothOutcomes = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: outcomes)
        XCTAssertEqual(XCTWaiter.wait(for: [bothOutcomes], timeout: 90), .completed,
                       "The UI must render exactly two actual paired gear-trial outcomes")
        XCTAssertFalse(app.staticTexts["gear_trial_error"].exists, app.debugDescription)
        for index in 0..<2 {
            XCTAssertTrue(reveal(outcomes.element(boundBy: index), in: comparisonScroll, maxSwipes: 12),
                          "Both paired outcomes must be visible, not merely present in the tree")
        }
        let finish = app.buttons["finish_comparison"]
        XCTAssertTrue(finish.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(reveal(finish, in: comparisonScroll, maxSwipes: 12), "Reveal comparison finish control")
        XCTAssertTrue(hostBarrier("trial_after", evidence: [
            "comparisonPreviewCards": 2, "pairedOutcomes": 2, "targetKind": "ordinary_campaign",
            "rewardDeltaExpected": 0, "saveMutationExpected": false, "finishPending": true
        ]))
        capture("familiar_actual_two_loadout_trial")
        finish.tap()
        closeSheetIfPresent()

        // Select the exact target, inspect the rules, return through the normal
        // home/Gacha route, then spend exactly the five earned free tickets.
        openGacha()
        XCTAssertTrue(app.buttons["gacha_target"].isEnabled)
        app.buttons["gacha_target"].tap()
        let targetChoice = app.buttons["gacha_target_" + targetGearID]
        XCTAssertTrue(targetChoice.waitForExistence(timeout: 10), "Target option \(targetGearID) is unavailable")
        targetChoice.tap()
        let targetButton = app.buttons["gacha_target"]
        XCTAssertTrue(waitForLabel(targetButton, "霧花の毒杖", timeout: 10), targetButton.label)
        XCTAssertTrue(targetButton.label.contains("霧花の毒杖"), "The chosen target must identify EQ_W_P1 as 霧花の毒杖: \(targetButton.label)")
        capture("gacha_target_EQ_W_P1")
        app.buttons["確率と保証を見る"].tap()
        XCTAssertTrue(app.staticTexts["鑑定の仕組み"].waitForExistence(timeout: 10), app.debugDescription)
        capture("gacha_probability_and_guarantee")
        closeSheetIfPresent()

        openGacha()
        XCTAssertTrue(app.buttons["gacha_target"].label.contains("霧花の毒杖"))
        XCTAssertEqual(number(in: app.staticTexts["gacha_ticket_balance"].label), 5)
        let drawFive = app.buttons["summon5"]
        XCTAssertTrue(drawFive.isEnabled, app.debugDescription)
        drawFive.tap()
        XCTAssertTrue(app.staticTexts["届いた装備"].waitForExistence(timeout: 30), app.debugDescription)
        capture("five_free_appraisals_result")
        closeSheetIfPresent()
        openGacha()
        XCTAssertTrue(app.buttons["gacha_target"].label.contains("霧花の毒杖"))
        XCTAssertEqual(number(in: app.staticTexts["gacha_ticket_balance"].label), 0,
                       "Exactly five tickets must be spent; the five resulting gear instances are checked separately")
        closeSheetIfPresent()
        app.buttons["tab_仲間"].tap()
        app.buttons["companion_C_FAMILIAR"].tap()
        app.buttons["inventory"].tap()
        let inventoryAfterDraw = app.staticTexts["inventory_count"]
        XCTAssertTrue(inventoryAfterDraw.waitForExistence(timeout: 12))
        XCTAssertEqual(inventoryAfterDraw.label, "所持 10 / 表示 10", "Five real draws must add five actual owned inventory instances")
        closeSheetIfPresent()
        XCTAssertTrue(hostBarrier("gacha_after", evidence: [
            "targetGearID": targetGearID, "ticketBalance": 0, "gearCount": 10,
            "drawCount": 5, "drawWasOrdinaryUI": true
        ]))
        capture("gacha_after_five_draws")

        // One ordinary daily claim adds the existing catalog's five tickets.
        // Do not retry it; the displayed same-UTC-day disabled state is the UI
        // contract, while the host runner verifies the persisted timestamp.
        openGacha()
        let daily = app.buttons["daily_free_claim"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10) && daily.isEnabled, app.debugDescription)
        daily.tap()
        XCTAssertTrue(waitForLabel(daily, "本日の無料券は受け取り済み", timeout: 15), app.debugDescription)
        XCTAssertFalse(daily.isEnabled, "The daily claim must be disabled after one successful claim")
        XCTAssertEqual(number(in: app.staticTexts["gacha_ticket_balance"].label), 5)
        XCTAssertTrue(hostBarrier("after_daily", evidence: ["ticketBalance": 5, "dailyClaimEnabled": false]))
        capture("daily_claimed_once")

        // Cold reopen the same development namespace and prove the transaction
        // and pre-existing wardrobe/furniture choices remain visible.
        closeSheetIfPresent()
        app.terminate()
        launchStandard()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 30), app.debugDescription)
        openGacha()
        XCTAssertEqual(number(in: app.staticTexts["gacha_ticket_balance"].label), 5)
        XCTAssertFalse(app.buttons["daily_free_claim"].isEnabled)
        XCTAssertTrue(app.buttons["daily_free_claim"].label.contains("本日の無料券は受け取り済み"))
        XCTAssertTrue(app.buttons["gacha_target"].label.contains("霧花の毒杖"))
        closeSheetIfPresent()
        navigateToCompanions()
        let coldFamiliar = app.buttons["companion_C_FAMILIAR"]
        XCTAssertTrue(reveal(coldFamiliar, in: app.scrollViews["companion_scroll"], maxSwipes: 12)); coldFamiliar.tap()
        let coldInventory = app.buttons["inventory"]
        XCTAssertTrue(reveal(coldInventory, in: app.scrollViews["companion_scroll"], maxSwipes: 12)); coldInventory.tap()
        let coldInventoryCount = app.staticTexts["inventory_count"]
        XCTAssertTrue(reveal(coldInventoryCount, in: app.scrollViews["sheet_scroll_装備"], maxSwipes: 12))
        XCTAssertEqual(coldInventoryCount.label, "所持 10 / 表示 10")
        closeSheetIfPresent()
        app.buttons["tab_家"].tap()
        let makeover = app.buttons["模様替え"]
        XCTAssertTrue(makeover.waitForExistence(timeout: 10)); makeover.tap()
        XCTAssertTrue(waitForLabel(app.buttons["place_desk"], "しまう", timeout: 10), "Pre-existing desk placement must remain saved")
        closeSheetIfPresent()
        let tryOn = app.buttons["home_try_on"]
        XCTAssertTrue(tryOn.waitForExistence(timeout: 10)); tryOn.tap()
        let actorPicker = app.descendants(matching: .any)["wardrobe_actor_picker"]
        XCTAssertTrue(actorPicker.waitForExistence(timeout: 10)); actorPicker.tap()
        let ira = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "アイラ", "companion_")).firstMatch
        XCTAssertTrue(ira.waitForExistence(timeout: 8)); ira.tap()
        let apron = app.buttons.matching(identifier: "appearance_AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130")
            .matching(NSPredicate(format: "label == %@", "選択中")).firstMatch
        XCTAssertTrue(apron.waitForExistence(timeout: 12), "Pre-existing AIRA appearance must remain selected")
        capture("cold_reopen_saved_home_choices")
        XCTAssertTrue(hostBarrier("cold_reopen", evidence: [
            "gearCount": 10, "ticketBalance": 5, "targetGearID": targetGearID,
            "dailyClaimEnabled": false, "deskPlaced": true, "airaApronSelected": true
        ]))
        closeSheetIfPresent()

        // UIKit-only large-text override: no QA arguments, fixtures, or gameplay
        // mutation. Verify all four portrait and summary regions remain reachable.
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment = [:]
        XCTAssertEqual(app.launchArguments, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.launch()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 30), app.debugDescription)
        navigateToCompanions()
        for actor in actors {
            let scroll = app.scrollViews["companion_scroll"]
            let selector = app.buttons["companion_" + actor.id]
            XCTAssertTrue(reveal(selector, in: scroll, maxSwipes: 16), "Large-text selector not reachable for \(actor.id)")
            selector.tap()
            XCTAssertEqual(selector.value as? String, "選択中", "Wrong selected actor at large text: \(actor.id)")
            let portrait = element("living_scene")
            XCTAssertTrue(reveal(portrait, in: scroll, maxSwipes: 16), "Large-text portrait not reachable for \(actor.id)")
            XCTAssertTrue(portrait.isHittable)
            capture("large_text_\(actor.id)_portrait")
            let stats = app.staticTexts["companion_stats"]
            XCTAssertTrue(reveal(stats, in: scroll, maxSwipes: 16), "Large-text summary not reachable for \(actor.id)")
            XCTAssertTrue(stats.exists && app.staticTexts["companion_level"].exists && app.staticTexts["companion_equipped_weapon"].exists)
            let name = app.staticTexts.matching(NSPredicate(format: "label == %@", actor.name)).firstMatch
            XCTAssertTrue(name.exists, "Large-text actor identity missing for \(actor.id)")
            capture("large_text_\(actor.id)_summary")
        }
        XCTAssertLessThanOrEqual(screenshotCount, 20)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, wallBudget,
                          "R196 is bounded to 15 minutes; keep partial evidence on timeout")
        XCTAssertTrue(hostBarrier("large_text_complete", evidence: [
            "actorsChecked": actors.map(\.id), "dynamicType": "AccessibilityXXXL",
            "gameplayMutation": false, "screenshotCount": screenshotCount
        ]))
    }

    private func launchStandard() {
        app.launchArguments = []
        app.launchEnvironment = [:]
        XCTAssertTrue(app.launchArguments.isEmpty, "Standard continuation must launch without QA arguments")
        XCTAssertTrue(app.launchEnvironment.isEmpty, "Standard continuation must launch without injected app environment")
        app.launch()
    }

    private func navigateToCompanions() {
        let tab = app.buttons["tab_仲間"]
        if tab.waitForExistence(timeout: 2) {
            if !tab.isSelected { tab.tap() }
        } else {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "Adaptive footer menu is required when the four-tab footer is hidden")
            menu.tap()
            let choose = app.buttons["choose_tab_仲間"]
            XCTAssertTrue(choose.waitForExistence(timeout: 8), "Adaptive footer must expose the companion destination")
            choose.tap()
        }
        XCTAssertTrue(app.scrollViews["companion_scroll"].waitForExistence(timeout: 12), app.debugDescription)
    }

    private func openGacha() {
        if !app.buttons["tab_家"].isSelected { app.buttons["tab_家"].tap() }
        let button = app.buttons["魔導庫"]
        XCTAssertTrue(button.waitForExistence(timeout: 12), app.debugDescription)
        if !button.isHittable { _ = reveal(button, in: app.scrollViews["home_scroll"], maxSwipes: 12) }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
        XCTAssertTrue(app.buttons["gacha_ticket_balance"].exists || app.staticTexts["gacha_ticket_balance"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func closeSheetIfPresent() {
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "閉じる")).firstMatch
        if close.waitForExistence(timeout: 2), close.isHittable { close.tap() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, maxSwipes: Int) -> Bool {
        guard scroll.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<maxSwipes {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 1)
            if element.exists && viewport.contains(element.frame) && element.isHittable { return true }
            let moveUp = !element.exists || element.frame.maxY > viewport.maxY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: moveUp ? -100 : 100)))
        }
        return element.exists && scroll.frame.intersection(app.frame).contains(element.frame) && element.isHittable
    }

    private func waitForLabel(_ element: XCUIElement, _ fragment: String, timeout: TimeInterval) -> Bool {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: element)
        return XCTWaiter.wait(for: [expected], timeout: timeout) == .completed
    }

    private func number(in label: String) -> Int? {
        let pieces = label.split(whereSeparator: { !$0.isNumber })
        return pieces.last.flatMap { Int($0) }
    }

    private func capture(_ name: String) {
        guard screenshotCount < 20 else { XCTFail("R196 screenshot cap exceeded"); return }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "R196_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        screenshotCount += 1
    }

    /// Acknowledgement binds the host readback to an exclusive marker UUID and
    /// exact marker bytes. Only the six phases in the host runner's schema exist.
    private func hostBarrier(_ phase: String, evidence: [String: Any], timeout: TimeInterval = 60) -> Bool {
        let allowed = Set(["trial_before", "trial_after", "gacha_after", "after_daily", "cold_reopen", "large_text_complete"])
        guard allowed.contains(phase) else { XCTFail("Unexpected R196 phase: \(phase)"); return false }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stem = "r196_\(runToken)_\(phase)"
        let marker = documents.appendingPathComponent(stem + ".json")
        let ack = documents.appendingPathComponent(stem + ".verified")
        guard !FileManager.default.fileExists(atPath: marker.path), !FileManager.default.fileExists(atPath: ack.path) else {
            XCTFail("R196 marker or acknowledgement already exists; refusing overwrite for \(phase)")
            return false
        }
        let payload: [String: Any] = [
            "schema": "r196-phase-v1", "runToken": runToken, "phase": phase,
            "testName": name, "testPID": ProcessInfo.processInfo.processIdentifier,
            "testStartUptime": testStartUptime, "observedUptime": ProcessInfo.processInfo.systemUptime,
            "elapsedWallSeconds": ProcessInfo.processInfo.systemUptime - startedAt,
            "saveNamespace": "Witch03to05DevelopmentR169/save.json",
            "appLaunchArguments": app.launchArguments, "appLaunchEnvironmentEmpty": app.launchEnvironment.isEmpty,
            "fixture": NSNull(), "timeOverride": NSNull(), "grantOrItemInjection": false,
            "gameplayMutationByTestHarness": false, "evidence": evidence
        ]
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            XCTFail("Could not encode R196 marker"); return false
        }
        let fd = open(marker.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { XCTFail("Could not exclusively create R196 marker"); return false }
        let written = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Darwin.write(fd, base, raw.count)
        }
        _ = close(fd)
        guard written == bytes.count else { XCTFail("Incomplete R196 marker write"); return false }
        let markerSHA = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let ackBytes = try? Data(contentsOf: ack),
               let object = try? JSONSerialization.jsonObject(with: ackBytes) as? [String: Any],
               object["schema"] as? String == "r196-phase-ack-v1",
               object["runToken"] as? String == runToken,
               object["phase"] as? String == phase,
               object["markerSHA256"] as? String == markerSHA { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Root readback runner did not acknowledge R196 phase \(phase)")
        return false
    }
}
