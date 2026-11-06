import XCTest
import CryptoKit

/// A normal first-session path. This test intentionally uses no scenario fixture,
/// time override, reward grant, or accelerated-battle flag.
final class FreshSaveFirstSessionR140Tests: XCTestCase {
    private let app = XCUIApplication()
    private var saveKey = UUID().uuidString.lowercased()
    private let hardBudgetSeconds: TimeInterval = 45 * 60
    private let gatheringBudgetSeconds: TimeInterval = 40 * 60
    private var startedAt = Date()
    private var startedUptime: TimeInterval = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
        saveKey = UUID().uuidString.lowercased()
        startedAt = Date()
        startedUptime = ProcessInfo.processInfo.systemUptime
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + saveKey, "--qa-gear-trial-readback-r140"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        super.tearDown()
    }

    private func elapsed() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime - startedUptime
    }

    /// Host runner must inspect the bound save/receipt and create the ack before
    /// this test advances. The canonical save key is also the per-run token.
    private func hostBarrier(_ phase: String, timeout: TimeInterval = 60) {
        let allowed = ["fresh_launch", "trial_before", "trial_after", "cold_reopen", "case_complete"]
        XCTAssertTrue(allowed.contains(phase))
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stem = "r140_\(saveKey)_\(phase)"
        let marker = docs.appendingPathComponent(stem + ".json")
        let ack = docs.appendingPathComponent(stem + ".verified")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ack.path))
        let payload: [String: Any] = ["schema": "r140-phase-v1", "runToken": saveKey,
            "saveKey": saveKey, "phase": phase, "testPID": ProcessInfo.processInfo.processIdentifier,
            "testName": name, "observedUptime": ProcessInfo.processInfo.systemUptime]
        let bytes: Data
        do { bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) }
        catch { XCTFail("Could not encode R140 phase marker: \(error)"); return }
        do { try bytes.write(to: marker, options: [.atomic]) }
        catch { XCTFail("Could not publish exclusive R140 phase marker: \(error)"); return }
        let markerSHA = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let ackBytes = try? Data(contentsOf: ack),
               let ackObject = try? JSONSerialization.jsonObject(with: ackBytes) as? [String: Any],
               ackObject["schema"] as? String == "r140-phase-ack-v1",
               ackObject["runToken"] as? String == saveKey,
               ackObject["phase"] as? String == phase,
               ackObject["markerSHA256"] as? String == markerSHA { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Root readback runner did not acknowledge \(phase) before the bounded timeout")
    }

    private func record(_ phase: String, values: [String: Any] = [:]) {
        var payload: [String: Any] = [
            "test": name,
            "phase": phase,
            "saveKey": saveKey,
            "observedAt": ISO8601DateFormatter().string(from: Date()),
            "elapsedWallSeconds": elapsed(),
            "launchArguments": app.launchArguments,
            "fixture": NSNull(),
            "timeOverride": NSNull(),
            "grantOrItemInjection": false,
            "acceleratedBattle": false
        ]
        values.forEach { payload[$0.key] = $0.value }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "R127_phase_\(phase)_\(Int(elapsed()))s"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "R127_screen_\(phase)_\(Int(elapsed()))s"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func goToExplore() {
        let explore = app.buttons["tab_探索"]
        if explore.waitForExistence(timeout: 5) {
            explore.tap()
        } else {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 15), "Adaptive navigation must expose the normal Explore route")
            menu.tap()
            let choose = app.buttons["choose_tab_探索"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            choose.tap()
        }
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout: 10))
        let controls = app.buttons["explore_controls"]
        if !app.buttons["fight_E_R01_02"].exists {
            XCTAssertTrue(controls.waitForExistence(timeout: 10))
            controls.tap()
        }
        XCTAssertTrue(app.buttons["fight_E_R01_02"].waitForExistence(timeout: 10))
    }

    private func fightR01E2() {
        let fight = app.buttons["fight_E_R01_02"]
        XCTAssertTrue(fight.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["explore_scroll"]
        for _ in 0..<12 {
            if fight.isHittable { break }
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(fight.isHittable, "The ordinary E_R01_02 encounter must be reachable through Explore")
        XCTAssertTrue(fight.isEnabled, "The ordinary E_R01_02 encounter must remain replayable through its normal control")
        fight.tap()
        let active = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "4人で自動戦闘中")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10), "Wait for a real dispatched battle, not just a tap")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: active)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 180), .completed, "Normal battle did not reach its presentation end")
        let reward = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "灯糸 +1")).firstMatch
        XCTAssertTrue(reward.waitForExistence(timeout: 10), "Victory must display the actual E_R01_02 drop")
        XCTAssertFalse(app.alerts["確認が必要です"].exists, "A failed dispatch cannot count as an earned drop")
        record("ordinary_battle_E_R01_02", values: ["observedReward": reward.label])
    }

    private func scrollExploreToTop() {
        let scroll = app.scrollViews["explore_scroll"]
        for _ in 0..<12 {
            if app.buttons["explore_controls"].isHittable || app.buttons["explore_controls_close"].isHittable { break }
            if scroll.exists { scroll.swipeDown() } else { app.swipeDown() }
        }
    }

    private func ensureGatherControls() {
        let row = app.buttons["gather_M_R01_G1"]
        if !row.exists {
            scrollExploreToTop()
            let expand = app.buttons["explore_controls"]
            XCTAssertTrue(expand.waitForExistence(timeout: 10)); XCTAssertTrue(expand.isHittable)
            expand.tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
    }

    private func tapClaimAndClose() {
        scrollExploreToTop()
        let collapse = app.buttons["explore_controls_close"]
        if collapse.exists && collapse.isHittable { collapse.tap() }
        let claim = app.buttons["claim_offline"]
        XCTAssertTrue(claim.waitForExistence(timeout: 10))
        if !claim.isHittable {
            let scroll = app.scrollViews["explore_scroll"]
            for _ in 0..<12 { if claim.isHittable { break }; if scroll.exists { scroll.swipeDown() } else { app.swipeDown() } }
        }
        XCTAssertTrue(claim.isHittable)
        claim.tap()
        let close = app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "Normal collection result should present after claim")
        close.tap()
        XCTAssertTrue(claim.waitForExistence(timeout: 10))
        ensureGatherControls()
    }

    private func ownedMaterialCount(_ id: String) -> Int {
        let button = app.buttons["gather_" + id]
        let label = button.label
        guard let range = label.range(of: "所持") else { return -1 }
        let digits = label[range.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits) ?? -1
    }

    private func claimG1UnitWithinBudget(previous: Int, deadline: TimeInterval) -> Int {
        let remainingBudget = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let until = ProcessInfo.processInfo.systemUptime + min(305, remainingBudget)
        while ProcessInfo.processInfo.systemUptime < until {
            let remain = until - ProcessInfo.processInfo.systemUptime
            if remain > 0 { Thread.sleep(forTimeInterval: min(10, remain)) }
            XCTAssertLessThan(elapsed(), hardBudgetSeconds, "First-session journey exceeded its 45-minute hard budget")
        }
        tapClaimAndClose()
        let current = ownedMaterialCount("M_R01_G1")
        record("real_300s_claim", values: ["previousG1": previous, "currentG1": current, "deltaG1": current - previous])
        return current
    }

    private func scrollTo(_ button: XCUIElement, scrollID: String, attempts: Int = 20) -> Bool {
        revealFully(button, scrollID: scrollID, attempts: attempts)
    }

    /// Reveal within the named sheet and require a complete on-screen frame before tapping.
    /// This preserves the full-hit-area oracle that R127's first run failed to satisfy.
    private func revealFully(_ element: XCUIElement, scrollID: String, attempts: Int = 24) -> Bool {
        let scroll = app.scrollViews[scrollID]
        guard scroll.waitForExistence(timeout: 5) else { return false }
        for step in 0..<attempts {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 2)
            if element.exists && viewport.contains(element.frame) && element.isHittable { return true }
            let direction: CGFloat = element.exists && element.frame.maxY < viewport.minY ? 1 : -1
            let y = viewport.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (viewport.midX - scroll.frame.minX) / scroll.frame.width,
                dy: (y - scroll.frame.minY) / scroll.frame.height))
            let travel = step.isMultiple(of: 2) ? 62.0 : 42.0
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * travel)))
        }
        let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 2)
        return element.exists && viewport.contains(element.frame) && element.isHittable
    }

    func testOrdinaryFirstSessionCraftCampaignTrialEquipSummonAndReopen() {
        XCTAssertEqual(app.launchArguments, ["--qa-isolated", "--qa-save-key=" + saveKey, "--qa-gear-trial-readback-r140"],
                       "Only isolated persistence, a unique save key, and the R140 receipt-only observer are allowed for this earned-path run")
        XCTAssertTrue(UUID(uuidString: saveKey) != nil)
        XCTAssertFalse(app.launchArguments.contains(where: { $0.hasPrefix("--qa-fixture=") || $0.contains("time") || $0.contains("grant") || $0.contains("fast") }))
        XCTAssertFalse(app.launchArguments.contains("--qa-r131-gear-comparison"), "R131 is synthetic-fixture gated and must never be enabled in an earned journey")
        record("fresh_launch")
        hostBarrier("fresh_launch")

        // Battle drops E2, while the game's normal selected G1 gathering clock continues.
        for battleNumber in 1...6 {
            // A normal dispatch collapses Explore's expanded controls. Reopen
            // the ordinary Explore section before each subsequent battle.
            goToExplore()
            fightR01E2()
            record("battle_batch_\(battleNumber)", values: ["earnedMaterial": "M_R01_E2", "earnedUnits": battleNumber])
        }
        let expandedClose = app.buttons["explore_controls_close"]
        if expandedClose.exists { expandedClose.tap() }
        let initialTarget = app.staticTexts["explore_gather_target"]
        XCTAssertTrue(initialTarget.waitForExistence(timeout: 10))
        XCTAssertTrue(initialTarget.label.contains("しなり霊枝を採集中"), initialTarget.label)
        tapClaimAndClose()
        var g1 = ownedMaterialCount("M_R01_G1")
        XCTAssertGreaterThanOrEqual(g1, 0, "The normal gather button must expose its actual owned count")
        record("after_six_ordinary_battles", values: ["earnedE2Units": 6, "ownedG1": g1])

        // RC_EQ_W_01 is the initially targeted craft. It requires 6 G1 + 6 G2;
        // ordinary enemy drops are E2 and cannot substitute for G2. The bounded
        // real-time experiment also checks the eligible RC_EQ_F_01 route, whose
        // authored cost uses the six E2 earned above and six G1.
        let recipeDeadline = startedUptime + gatheringBudgetSeconds
        while g1 < 6 && ProcessInfo.processInfo.systemUptime < recipeDeadline {
            let previous = g1
            g1 = claimG1UnitWithinBudget(previous: previous, deadline: recipeDeadline)
            if g1 <= previous {
                // A whole 300-second interval elapsed without a unit. Retain an
                // explicit milestone then continue only within the same hard cap.
                record("no_g1_unit_after_interval", values: ["ownedG1": g1, "secondsPerAuthoredWorkUnit": 300])
            }
        }
        XCTAssertGreaterThanOrEqual(elapsed(), 0)
        XCTAssertLessThan(elapsed(), hardBudgetSeconds, "Time budget exhausted before recipe decision")

        // Capture the actual G2 gather-row value before leaving Explore; the
        // button is not part of the Workshop accessibility hierarchy.
        ensureGatherControls()
        let g2BeforeWorkshop = ownedMaterialCount("M_R01_G2")
        record("materials_before_workshop", values: ["ownedG1": g1, "ownedG2": g2BeforeWorkshop])
        app.buttons["tab_工房"].tap()
        XCTAssertTrue(app.scrollViews["workshop_scroll"].waitForExistence(timeout: 10))
        let staffRecipe = app.buttons["craft_RC_EQ_W_01"]
        XCTAssertTrue(scrollTo(staffRecipe, scrollID: "workshop_scroll"), "The normal workshop must expose RC_EQ_W_01")
        let staffEnabled = staffRecipe.isEnabled
        XCTAssertFalse(staffEnabled, "Normal R01 fights award M_R01_E2, not the six M_R01_G2 needed by RC_EQ_W_01")
        let familiarRecipe = app.buttons["craft_RC_EQ_F_01"]
        XCTAssertTrue(scrollTo(familiarRecipe, scrollID: "workshop_scroll"), "The normal workshop must expose the E2-backed familiar recipe")
        let g2 = g2BeforeWorkshop
        record("recipe_availability", values: ["RC_EQ_W_01_enabled": staffEnabled, "RC_EQ_F_01_enabled": familiarRecipe.isEnabled, "ownedG1": g1, "ownedG2": g2, "earnedE2Units": 6, "expectedCraftedDefinitionID": "EQ_F_01", "expectedCraftedGearCountDelta": 1])
        XCTAssertTrue(familiarRecipe.isEnabled, "Six normal E_R01_02 victories and six actually gathered G1 should unlock the catalog's RC_EQ_F_01 recipe")
        familiarRecipe.tap()
        let craftDeadline = ProcessInfo.processInfo.systemUptime + 15
        while familiarRecipe.isEnabled && ProcessInfo.processInfo.systemUptime < craftDeadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(familiarRecipe.isEnabled, "Successful normal craft consumes the six earned E2 and six gathered G1")
        record("crafted_RC_EQ_F_01", values: ["recipeID": "RC_EQ_F_01", "consumedG1": 6, "consumedE2": 6])

        // The generated gear shares a display name with its starter item, so
        // the name comparison alone is not instance proof. Record the expected
        // definition/count delta; Root's post-run read-only save observer must
        // bind the newly created UUID to owner C_FAMILIAR.
        app.buttons["tab_仲間"].tap()
        let familiar = app.buttons["companion_C_FAMILIAR"]
        XCTAssertTrue(familiar.waitForExistence(timeout: 10)); familiar.tap()
        app.buttons["inventory"].tap()
        XCTAssertTrue(app.staticTexts["inventory_count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["inventory_count"].label, "所持 5 / 表示 5", "Four untouched starters plus the real craft must create exactly one additional owned gear instance")
        record("inventory_after_craft", values: ["expectedDefinitionID": "EQ_F_01", "expectedOwnedGearCount": 5, "instanceUUIDRequiresReadOnlySaveJoin": true])
        let comparisonScroll = app.scrollViews["sheet_scroll_比較"]
        let compare = app.buttons["比較"].firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(scrollTo(compare, scrollID: "sheet_scroll_装備"),
                      "Reveal the actual inventory Compare control inside its scroll viewport; do not weaken hittability.")
        XCTAssertTrue(compare.isHittable)
        compare.tap()
        XCTAssertTrue(comparisonScroll.waitForExistence(timeout: 10), app.debugDescription)
        let craftedNameCards = app.staticTexts.matching(NSPredicate(format: "label == %@", "灯爪の触媒"))
        XCTAssertGreaterThanOrEqual(craftedNameCards.count, 2, "The comparison screen must show both crafted and starter same-slot items")
        record("actual_gear_comparison", values: ["sameSlotCards": craftedNameCards.count,
               "fixture": NSNull(), "readbackOnlyFlag": "--qa-gear-trial-readback-r140"])

        // Use the ordinary campaign target offered by the current save. This is
        // a read-only paired calculation over the real crafted and owned gear.
        // The flag only writes an external QA receipt; it does not create a fixture,
        // alter selection, seed, battle state, or save progression.
        let targetPicker = app.buttons["gear_trial_target_picker"]
        XCTAssertTrue(targetPicker.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(revealFully(targetPicker, scrollID: "sheet_scroll_比較"),
                      "The ordinary campaign target picker must be fully visible before interaction.")
        XCTAssertTrue(targetPicker.label.hasPrefix("探索："),
                      "Post-campaign gear comparison must offer an available campaign opponent, not a synthetic research unlock: \(targetPicker.label)")
        let trialButton = app.buttons["run_gear_trial"]
        XCTAssertTrue(trialButton.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(revealFully(trialButton, scrollID: "sheet_scroll_比較"),
                      "The read-only trial action must be fully visible before interaction.")
        XCTAssertTrue(trialButton.isEnabled)
        hostBarrier("trial_before", timeout: 60)
        trialButton.tap()
        let outcomes = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "gear_trial_outcome_"))
        let bothOutcomes = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: outcomes)
        XCTAssertEqual(XCTWaiter.wait(for: [bothOutcomes], timeout: 90), .completed,
                       "Both earned same-slot UUIDs must produce a campaign trial result")
        XCTAssertFalse(app.staticTexts["gear_trial_error"].exists, app.debugDescription)
        for index in 0..<2 {
            let outcome = outcomes.element(boundBy: index)
            XCTAssertTrue(revealFully(outcome, scrollID: "sheet_scroll_比較"),
                          "Each paired outcome must be actually rendered and readable.")
        }
        record("earned_campaign_gear_trial", values: ["targetKind": "campaign", "outcomeCount": outcomes.count,
               "syntheticFixture": false, "rewardsCommitted": false])
        hostBarrier("trial_after", timeout: 60)
        let finishComparison = app.buttons["finish_comparison"]
        XCTAssertTrue(finishComparison.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(revealFully(finishComparison, scrollID: "sheet_scroll_比較"),
                      "Finish must be fully visible after the real trial results.")
        finishComparison.tap()

        // The inventory list is newest-first, so its first Equip control belongs
        // to the newly crafted gear. The live companion label confirms owner/UI state.
        if !app.staticTexts["inventory_count"].exists {
            let close = app.buttons["閉じる"]
            if close.waitForExistence(timeout: 5) { close.tap() }
            app.buttons["tab_仲間"].tap(); familiar.tap(); app.buttons["inventory"].tap()
        }
        let equip = app.buttons["装備"].firstMatch
        XCTAssertTrue(equip.waitForExistence(timeout: 10))
        XCTAssertTrue(revealFully(equip, scrollID: "sheet_scroll_装備"), "Reveal the newest crafted inventory row before equipping it")
        XCTAssertTrue(equip.isHittable); equip.tap()
        let closeInventory = app.buttons["閉じる"]
        if closeInventory.waitForExistence(timeout: 5) { closeInventory.tap() }
        app.buttons["tab_仲間"].tap(); familiar.tap()
        let equipped = app.staticTexts["companion_equipped_weapon"]
        XCTAssertTrue(equipped.waitForExistence(timeout: 10))
        XCTAssertEqual(equipped.label, "装備：灯爪の触媒")
        record("crafted_weapon_equipped_to_familiar", values: ["expectedOwnerID": "C_FAMILIAR", "expectedDefinitionID": "EQ_F_01", "instanceUUIDRequiresReadOnlySaveJoin": true])

        app.buttons["tab_家"].tap()
        let gacha = app.buttons["魔導庫"]
        XCTAssertTrue(gacha.waitForExistence(timeout: 10)); gacha.tap()
        let target = app.buttons["gacha_target"]
        let pull = app.buttons["summon5"]
        XCTAssertTrue(target.waitForExistence(timeout: 10)); XCTAssertTrue(target.isEnabled)
        XCTAssertTrue(pull.exists); XCTAssertTrue(pull.isEnabled, "The ordinary initial five free tickets must remain usable")
        pull.tap()
        XCTAssertTrue(app.staticTexts["届いた装備"].waitForExistence(timeout: 15))
        record("normal_five_free_pull")
        let closeResult = app.buttons["閉じる"]
        XCTAssertTrue(closeResult.waitForExistence(timeout: 5)); closeResult.tap()

        // Cold relaunch the same isolated, fixture-free save and check durable state.
        app.terminate()
        app.launchArguments = ["--qa-isolated", "--qa-save-key=" + saveKey, "--qa-gear-trial-readback-r140"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout: 20))
        app.buttons["魔導庫"].tap()
        XCTAssertTrue(app.buttons["gacha_target"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["gacha_target"].isEnabled)
        XCTAssertTrue(app.buttons["summon5"].exists)
        record("cold_reopen_gacha_unlocked")
        let closeGacha = app.buttons["閉じる"]
        XCTAssertTrue(closeGacha.waitForExistence(timeout: 5)); closeGacha.tap()
        app.buttons["tab_仲間"].tap(); familiar.tap()
        XCTAssertEqual(equipped.label, "装備：灯爪の触媒")
        app.buttons["inventory"].tap()
        XCTAssertTrue(app.staticTexts["inventory_count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["inventory_count"].label, "所持 10 / 表示 10", "Four starters + one crafted Familiar item + five normal pull results must persist")
        record("cold_reopen_gear_and_inventory")
        hostBarrier("cold_reopen", timeout: 60)
        XCTAssertLessThan(elapsed(), hardBudgetSeconds, "The complete first-session route exceeded its 45-minute bound")
        hostBarrier("case_complete", timeout: 60)
    }
}
