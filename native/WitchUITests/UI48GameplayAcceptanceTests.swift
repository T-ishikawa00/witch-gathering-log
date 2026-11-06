import XCTest
import CryptoKit

/// Save-backed gameplay paths exercised through the ordinary UI in isolated QA saves.
/// The gathering fixture changes only the age of the initial work clock to avoid a wall-clock wait.
final class UI48GameplayAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var saveKey = UUID().uuidString.lowercased()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground { app.terminate() }
    }

    private func launch(fixture: String, screen: Int? = nil, observeCraft: Bool = false) {
        var arguments = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey,
                         "--qa-readback-save", "--ui48-fixture=" + fixture]
        if let screen { arguments.append("--ui48-screen=\(screen)") }
        if observeCraft { arguments.append("--ui48-craft-observe") }
        app.launchArguments = arguments
        app.launch()
    }

    private func relaunchSavedState(screen: Int? = nil) {
        var arguments = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey, "--qa-readback-save"]
        if let screen { arguments.append("--ui48-screen=\(screen)") }
        app.launchArguments = arguments
        app.launch()
    }

    @discardableResult
    private func screen(_ number: Int, timeout: TimeInterval = 25) -> XCUIElement {
        let identifier = String(format: "ui48_screen_%02d", number)
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "Expected gameplay screen S\(number)")
        XCTAssertFalse(app.staticTexts["この画面は準備中です"].exists, "Gameplay route rendered the fallback placeholder")
        return result
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let control = app.buttons[identifier]
        let rootControl = identifier.hasPrefix("tab_") || ["ui48_back", "ui48_close"].contains(identifier)
        let scroll = enclosingScrollView(for: control)
        for _ in 0..<8 {
            if control.exists {
                let frame = control.frame
                let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
                if control.isHittable && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) { break }
                if rootControl && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) { break }
            }
            guard control.exists else { scroll?.swipeUp(); continue }
            let target = control.frame
            if let scroll {
                if target.midY < scroll.frame.minY { scroll.swipeDown() }
                else if target.midY > scroll.frame.maxY { scroll.swipeUp() }
                else if target.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            } else if target.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(control.waitForExistence(timeout: timeout), "Missing action \(identifier)", file: file, line: line)
        XCTAssertTrue(control.isEnabled, "Action is disabled: \(identifier)", file: file, line: line)
        let center = CGPoint(x: control.frame.midX, y: control.frame.midY)
        let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
        XCTAssertTrue(viewport.contains(center), "Action center must be visible in its containing viewport: \(identifier)", file: file, line: line)
        XCTAssertTrue(control.isHittable, "Action is not reachable by scrolling: \(identifier)", file: file, line: line)
        control.tap()
    }

    private func tapElement(_ control: XCUIElement, description: String) {
        let scroll = enclosingScrollView(for: control)
        for _ in 0..<8 {
            if control.exists {
                let frame = control.frame
                let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
                if control.isHittable && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) { break }
            }
            guard control.exists else { scroll?.swipeUp(); continue }
            let target = control.frame
            if let scroll {
                if target.midY < scroll.frame.minY { scroll.swipeDown() }
                else if target.midY > scroll.frame.maxY { scroll.swipeUp() }
                else if target.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            } else if target.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(control.waitForExistence(timeout: 10), "Missing action: \(description)")
        XCTAssertTrue(control.isEnabled, "Action is disabled: \(description)")
        let center = CGPoint(x: control.frame.midX, y: control.frame.midY)
        let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
        XCTAssertTrue(viewport.contains(center), "Action center must be visible in its containing viewport: \(description)")
        XCTAssertTrue(control.isHittable, "Action is not reachable by scrolling: \(description)")
        control.tap()
    }

    private func enclosingScrollView(for element: XCUIElement) -> XCUIElement? {
        guard element.exists else { return app.scrollViews.count == 1 ? app.scrollViews.firstMatch : nil }
        let scrolls = app.scrollViews.allElementsBoundByIndex
        let matches = scrolls.filter { scroll in
            let descendants = scroll.descendants(matching: element.elementType)
            if !element.identifier.isEmpty {
                return descendants.matching(identifier: element.identifier).firstMatch.exists
            }
            return descendants.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
        }
        return matches.min(by: { abs($0.frame.midY - element.frame.midY) < abs($1.frame.midY - element.frame.midY) })
    }

    private func waitForSaveAction() {
        let busy = app.descendants(matching: .any)["ui48_busy"]
        if busy.waitForExistence(timeout: 1) {
            let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 30), .completed, "Save-backed gameplay action did not finish")
        }
    }

    private func visibleOwnedGearCount() -> Int? {
        let pattern = try! NSRegularExpression(pattern: "所持\\s*([0-9]+)\\s*点")
        for element in app.staticTexts.allElementsBoundByIndex {
            let label = element.label
            let range = NSRange(label.startIndex..<label.endIndex, in: label)
            if let match = pattern.firstMatch(in: label, range: range),
               let digits = Range(match.range(at: 1), in: label) {
                return Int(label[digits])
            }
        }
        return nil
    }

    private func visibleFreeTicketCount() -> Int? {
        let pattern = try! NSRegularExpression(pattern: "無料鑑定券\\s*([0-9]+)枚")
        let balance = app.staticTexts["ui48_vault_free_balance"]
        // Claiming the daily grant scrolls to the bottom action. SwiftUI may
        // omit the off-screen balance from its accessibility snapshot entirely.
        let scroll = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }
        for _ in 0..<10 where !balance.exists { scroll?.swipeDown() }
        guard balance.waitForExistence(timeout: 5) else { return nil }
        // The actual S36 accessibility label uses U+3000 between the label
        // and count. Normalize it before applying the numeric parser.
        let label = balance.label
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        guard let match = pattern.firstMatch(in: label, range: range),
              let digits = Range(match.range(at: 1), in: label) else { return nil }
        return Int(label[digits])
    }

    private func capture(_ name: String, classification: String) throws {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let runner = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let runnerSHA = SHA256.hash(data: try Data(contentsOf: runner)).map { String(format: "%02x", $0) }.joined()
        let payload: [String: String] = ["capture": name, "classification": classification,
            "testCase": name, "saveKey": saveKey, "testExecutableSHA256": runnerSHA,
            "launchArguments": app.launchArguments.joined(separator: " ")]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = name + "_identity"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    func testOnboardingGoalSourceBattleCraftCompareAndFreeAppraisal() throws {
        launch(fixture: "gathering")
        _ = screen(2)
        let claim = app.buttons["claim_offline"]
        XCTAssertTrue(claim.waitForExistence(timeout: 10), "Elapsed isolated gathering should offer a real collect action")
        XCTAssertTrue(claim.isEnabled)
        claim.tap()
        _ = screen(3)
        XCTAssertTrue(app.staticTexts["採集した素材"].waitForExistence(timeout: 8), "Claim result should show the saved gathering output")
        try capture("onboarding_01_gathering_claim", classification: "isolated-save-real-collect")
        app.terminate()
        relaunchSavedState(screen: 2)
        _ = screen(2)
        XCTAssertFalse(app.buttons["claim_offline"].exists,
                       "A cold reload after collection must not expose the same completed reward for a second claim")
        try capture("onboarding_01b_claim_cold_no_duplicate", classification: "persistence-verified-no-duplicate-claim")
        tap("tab_家")
        _ = screen(1)

        let homeGoal = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "集める", "つくろう")).firstMatch
        XCTAssertTrue(homeGoal.waitForExistence(timeout: 10), "The fresh-player home must expose its current recipe goal")
        XCTAssertTrue(homeGoal.label.contains("灯爪の触媒"),
                      "The fresh first-craft goal must target RC_EQ_F_01, 灯爪の触媒")
        tapElement(homeGoal, description: "home next-goal card")
        _ = screen(20)
        XCTAssertTrue(app.staticTexts["灯爪の触媒"].waitForExistence(timeout: 8),
                      "Opening the home goal must preserve the same recipe output")
        XCTAssertTrue(app.buttons["ui48_recipe_track"].waitForExistence(timeout: 8), "Recipe goal can be tracked without committing a craft")
        let materialReadoutsBefore = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持")).allElementsBoundByIndex.map(\.label).sorted()
        tap("ui48_recipe_track")
        waitForSaveAction()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持")).allElementsBoundByIndex.map(\.label).sorted(),
                       materialReadoutsBefore, "Tracking the goal must not consume materials")
        tap("ui48_recipe_cancel")
        _ = screen(19)
        XCTAssertTrue(app.staticTexts["制作の目標"].waitForExistence(timeout: 8), "Tracked recipe should appear in the workshop")
        XCTAssertTrue(app.staticTexts["灯爪の触媒"].exists,
                      "The tracked workshop goal must remain the same output selected from home")
        try capture("onboarding_02_goal_tracked", classification: "real-save-no-material-consumption")

        // The recipe may offer a gather handoff or an investigation route. Verify
        // its route result, then use the ordinary Explore entrance to continue.
        tap("ui48_workshop_goal_materials")
        _ = screen(20)
        let source = app.buttons["ui48_recipe_gather"]
        XCTAssertTrue(source.waitForExistence(timeout: 8), "S20 must offer the actual source for the missing recipe material")
        tap("ui48_recipe_gather")
        // S20 may hand off to a gather/investigation confirmation. Do not assume
        // the root close control is tappable during a pending handoff; the next
        // explicit Explore entrance is the ordinary recovery/navigation path.
        let handoff = app.descendants(matching: .any)["ui48_screen_12"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 8),
                      "Choosing the missing material's source must open the live gathering/investigation handoff")
        let switchApply = app.buttons["ui48_switch_apply"]
        XCTAssertTrue(switchApply.waitForExistence(timeout: 8), "S12 must show the explicit destination switch control")
        XCTAssertFalse(switchApply.isEnabled,
                       "An unbeaten source enemy must not be selectable as a work target")
        let requiredEnemy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "確認する")).firstMatch
        XCTAssertTrue(requiredEnemy.waitForExistence(timeout: 8),
                      "The blocked handoff must expose its actual required encounter")
        tapElement(requiredEnemy, description: "required source encounter")
        _ = screen(7)
        let sourceFight = app.buttons["fight_E_R01_02"]
        XCTAssertTrue(sourceFight.waitForExistence(timeout: 8),
                      "The current R01 material source is E2; its catalog currently has no E1 prerequisite")
        XCTAssertTrue(sourceFight.isEnabled,
                      "The live source encounter action must be available without inventing an unconfigured prerequisite")
        tap("ui48_close")
        _ = screen(1)

        func startEncounter(_ enemyID: String) {
            tap("tab_探索")
            _ = screen(4)
            tap("ui48_destinations")
            _ = screen(6)
            let encounterTab = app.buttons["魔物を探す"]
            XCTAssertTrue(encounterTab.waitForExistence(timeout: 8), "S06 must expose the native encounter-selection tab")
            XCTAssertTrue(encounterTab.isEnabled)
            encounterTab.tap()
            let target = app.buttons["ui48_enemy_\(enemyID)"]
            XCTAssertTrue(target.waitForExistence(timeout: 10), "R01 encounter \(enemyID) must be selectable through Explore")
            tapElement(target, description: "select \(enemyID)")
            _ = screen(7)
            var hops = 0
            var fight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fight_")).firstMatch
            while !fight.waitForExistence(timeout: 2), hops < 3 {
                let prerequisite = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "前の魔物を確認する")).firstMatch
                XCTAssertTrue(prerequisite.waitForExistence(timeout: 5), "Encounter must expose a battle or its prerequisite")
                tapElement(prerequisite, description: "encounter prerequisite")
                _ = screen(7)
                hops += 1
                fight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fight_")).firstMatch
            }
            XCTAssertTrue(fight.waitForExistence(timeout: 5), "Encounter prerequisite chain did not reach a battle action")
            XCTAssertTrue(fight.isEnabled)
            fight.tap()
            _ = screen(8, timeout: 20)
            let win = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "ui48_screen_09")).firstMatch
            let loss = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "ui48_screen_10")).firstMatch
            // Wait for either terminal screen, then require victory for this path.
            let result = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR identifier == %@", "ui48_screen_09", "ui48_screen_10")).firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 150), .completed, "Automatic battle did not produce a saved result")
            XCTAssertTrue(win.exists, "The onboarding encounter \(enemyID) must be winnable with the existing party")
            _ = screen(9)
            XCTAssertTrue(app.staticTexts["採集した素材"].waitForExistence(timeout: 8), "Victory must show the saved encounter material result")
        }

        startEncounter("E_R01_01")
        XCTAssertTrue(app.staticTexts["採集した素材"].waitForExistence(timeout: 8), "Victory must show the saved encounter material result")
        try capture("onboarding_03_battle_E1", classification: "isolated-save-real-automatic-battle")
        tap("探索へ戻る")
        _ = screen(4)
        startEncounter("E_R01_02")
        try capture("onboarding_03b_battle_E2", classification: "isolated-save-real-automatic-battle")
        tap("工房で確認する")
        _ = screen(19)
        let starterRecipe = app.buttons["ui48_recipe_RC_EQ_F_01"]
        XCTAssertTrue(starterRecipe.waitForExistence(timeout: 10), "The initial FirstCraft aid recipe must be present in the live workshop")
        starterRecipe.tap()
        if app.descendants(matching: .any)["ui48_screen_20"].waitForExistence(timeout: 5) {
            _ = screen(20)
            let confirm = app.buttons["ui48_recipe_confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 8), "The real S20 material and unlock conditions must permit the first craft")
            XCTAssertTrue(confirm.isEnabled, "First-craft aid did not make its promised starter recipe ready after the source battle")
            confirm.tap()
        }
        _ = screen(21)
        let craft = app.buttons["ui48_craft_commit"]
        XCTAssertTrue(craft.waitForExistence(timeout: 8))
        XCTAssertTrue(craft.isEnabled, "Craft action should reflect sufficient real materials")
        craft.tap()
        waitForSaveAction()
        _ = screen(26, timeout: 30)
        XCTAssertTrue(app.staticTexts["次の冒険の、相棒に。"].waitForExistence(timeout: 8))
        let compare = app.buttons["ui48_result_compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 8), "Crafted gear should route to actual companion comparison")
        compare.tap()
        _ = screen(16)
        XCTAssertTrue(app.staticTexts["仲間の性能"].waitForExistence(timeout: 8), "Comparison must calculate current and changed party performance")
        tap("ui48_compare_close")
        waitForSaveAction()
        _ = screen(36, timeout: 30)
        XCTAssertTrue(app.staticTexts["星灯りの魔導庫"].exists, "Completing comparison should unlock the appraisal vault")

        // Record owned inventory count before the appraisal, then read the same
        // isolated save back after relaunch to prove the result became owned gear.
        tap("ui48_close")
        _ = screen(19) // Comparison was entered from the workshop, which remains the active root.
        tap("tab_仲間")
        _ = screen(13)
        tap("ui48_companion_inventory")
        _ = screen(14)
        let gearCountBeforeDraw = try XCTUnwrap(visibleOwnedGearCount(), "Inventory must expose its real owned gear count before appraisal")
        try capture("onboarding_03c_owned_gear_before_appraisal", classification: "live-owned-gear-baseline")
        tap("ui48_close")
        _ = screen(13)
        tap("tab_採集帳")
        _ = screen(28)
        tapElement(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "星灯りの魔導庫")).firstMatch,
                   description: "journal route to unlocked appraisal vault")
        _ = screen(36)
        let daily = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "今日の無料券を受け取る")).firstMatch
        if daily.exists && daily.isEnabled {
            let scroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height })
            let top = scroll.frame.minY
            let bottom = app.buttons["ui48_vault_draw_1"].frame.minY - 12
            let viewport = CGRect(x: scroll.frame.minX, y: top, width: scroll.frame.width, height: bottom - top)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            for _ in 0..<10 {
                if viewport.contains(daily.frame) { break }
                origin.withOffset(CGVector(dx: viewport.midX, dy: bottom - 16))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: top + 16)))
            }
            XCTAssertTrue(viewport.contains(daily.frame), "Daily claim must be fully visible above the draw dock")
            XCTAssertTrue(daily.isHittable)
            daily.tap()
            waitForSaveAction()
            _ = screen(36)
        }
        let ticketsBeforeDraw = try XCTUnwrap(visibleFreeTicketCount(), "Vault must show its real free-ticket balance before appraisal")
        XCTAssertGreaterThan(ticketsBeforeDraw, 0, "The local free appraisal requires an owned free ticket")
        try capture("onboarding_03d_free_tickets_before_appraisal", classification: "live-ticket-balance-before-command")
        let draw = app.buttons["ui48_vault_draw_1"]
        XCTAssertTrue(draw.waitForExistence(timeout: 8), "Unlocked vault should expose the local free draw")
        XCTAssertTrue(draw.isEnabled, "Free ticket should be based on actual first-craft progression")
        draw.tap()
        waitForSaveAction()
        _ = screen(39, timeout: 30)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "今回届いた装備　1点")).firstMatch.waitForExistence(timeout: 10),
                      "The local appraisal result must be backed by one saved owned gear instance")
        try capture("onboarding_04_free_appraisal_result", classification: "isolated-save-real-craft-comparison-and-draw")
        tapElement(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "魔導庫へ戻る")).firstMatch,
                   description: "return from saved appraisal result")
        _ = screen(36)
        let ticketsAfterDraw = try XCTUnwrap(visibleFreeTicketCount(), "Vault must show the remaining free tickets after appraisal")
        XCTAssertEqual(ticketsAfterDraw, ticketsBeforeDraw - 1, "One real free draw must spend exactly one displayed ticket")
        try capture("onboarding_04b_free_ticket_after_draw", classification: "live-ticket-balance-after-command")

        app.terminate()
        relaunchSavedState(screen: 36)
        _ = screen(36)
        XCTAssertEqual(try XCTUnwrap(visibleFreeTicketCount()), ticketsAfterDraw,
                       "The free-ticket spend must survive cold relaunch")
        tap("ui48_close")
        _ = screen(28)
        tap("tab_仲間")
        _ = screen(13)
        tap("ui48_companion_inventory")
        _ = screen(14)
        XCTAssertEqual(try XCTUnwrap(visibleOwnedGearCount()), gearCountBeforeDraw + 1,
                       "The single appraisal result must remain present as owned gear after cold relaunch")
        try capture("onboarding_04c_free_appraisal_cold_readback", classification: "persistence-verified-ticket-and-owned-gear")
    }

    func testCraftCancelRapidConfirmationProcessingAndColdResult() throws {
        launch(fixture:"full",screen:21,observeCraft:true)
        _ = screen(21)
        XCTAssertTrue(app.staticTexts["ui48_craft_status"].label.contains("内容を確認"))
        tap("ui48_craft_back")
        _ = screen(19)
        XCTAssertFalse(app.staticTexts["制作中の目標"].exists)
        tap("tab_仲間");tap("ui48_companion_inventory")
        _ = screen(14)
        let before=try XCTUnwrap(visibleOwnedGearCount())
        app.terminate()
        launch(fixture:"full",screen:21,observeCraft:true)
        _ = screen(21)
        // The same save key loads existing bytes; the fixture is not reapplied.
        let materials=app.staticTexts.allElementsBoundByIndex.map(\.label).filter{$0.hasPrefix("所持 ") && $0.contains(" / 必要 ")}
        XCTAssertFalse(materials.isEmpty)
        let craft=app.buttons["ui48_craft_commit"]
        XCTAssertTrue(craft.waitForExistence(timeout:10))
        craft.tap(withNumberOfTaps:2,numberOfTouches:1)
        let status=app.staticTexts["ui48_craft_status"]
        let saving=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","制作結果を保存しています"),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[saving],timeout:5),.completed)
        XCTAssertFalse(app.buttons["ui48_craft_commit"].isEnabled)
        XCTAssertFalse(app.buttons["ui48_craft_back"].isEnabled)
        let accepted=app.staticTexts.allElementsBoundByIndex.map(\.label).filter{$0.hasPrefix("制作前の所持 ")}
            .map{$0.replacingOccurrences(of:"制作前の所持 ",with:"所持 ")}
        XCTAssertEqual(accepted.sorted(),materials.sorted(),"The pending craft must show its accepted costs even after the saved inventory refresh")
        try capture("product_craft_processing",classification:"synthetic-inventory-real-craft-post-save-observation")
        // Interrupt the presentation while the saved operation is still being observed.
        // Cold startup must retain exactly that one item and must not dispatch a retry.
        app.terminate();relaunchSavedState(screen:14);_ = screen(14)
        XCTAssertEqual(try XCTUnwrap(visibleOwnedGearCount()),before+1,"Rapid confirmation and restart must produce exactly one item")
        try capture("product_craft_cold_result",classification:"real-durable-result-after-presentation-interruption")
    }

    func testRegionSwitchFromMapAppliesAndSurvivesColdRelaunch() throws {
        launch(fixture: "full", screen: 1)
        _ = screen(1)
        tap("tab_探索")
        _ = screen(4)
        tap("ui48_map")
        _ = screen(5)
        let destination = app.buttons["ui48_region_R02"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8), "Regional map must expose the catalogued second region")
        destination.tap()
        _ = screen(12)
        XCTAssertTrue(app.staticTexts["眠り霧の湿原"].waitForExistence(timeout: 8),
                      "Region confirmation must identify the selected live destination")
        let apply = app.buttons["ui48_switch_apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 8))
        XCTAssertTrue(apply.isEnabled, "The isolated full fixture has unlocked the second region")
        apply.tap()
        waitForSaveAction()
        _ = screen(4)
        XCTAssertTrue(app.buttons["ui48_map"].label.contains("眠り霧の湿原"),
                      "Applying the region switch must update the live exploration destination")
        try capture("region_switch_R02_applied", classification: "isolated-real-region-switch")

        app.terminate()
        relaunchSavedState()
        _ = screen(1)
        tap("tab_探索")
        _ = screen(4)
        XCTAssertTrue(app.buttons["ui48_map"].label.contains("眠り霧の湿原"),
                      "The selected exploration region must survive a cold relaunch")
        try capture("region_switch_R02_cold_readback", classification: "persistence-verified-region-state")
    }

    func testSavedLoadoutApplyAndDismantleProtectionSurviveRelaunch() throws {
        launch(fixture: "full", screen: 17)
        _ = screen(17)
        tap("ui48_loadout_primary_1")
        waitForSaveAction()
        XCTAssertTrue(app.staticTexts["現在使用中"].waitForExistence(timeout: 8), "Saving the current gear set should persist its actual references")
        try capture("loadout_01_saved_first", classification: "isolated-synthetic-gear-real-loadout-save")

        tap("ui48_close")
        _ = screen(13)
        tap("ui48_companion_inventory")
        _ = screen(14)
        let allGearButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_gear_"))
        XCTAssertTrue(allGearButtons.firstMatch.waitForExistence(timeout: 10))
        // Pin identifiers before selecting any card. Selecting a lazy-grid cell
        // changes the accessibility tree, so index-based queries can resolve to
        // a different cell after each update.
        let gearIDs = allGearButtons.allElementsBoundByIndex.map(\.identifier)
            .filter { $0.hasPrefix("ui48_gear_") }
        XCTAssertFalse(gearIDs.isEmpty, "Inventory must expose stable gear instance identifiers")
        var changedEquipment = false
        var alternateGearUUID: String?
        for gearID in gearIDs.prefix(120) {
            let item = app.buttons[gearID]
            guard item.waitForExistence(timeout: 4) else { continue }
            for _ in 0..<5 where !item.isHittable { app.scrollViews.firstMatch.swipeUp() }
            guard item.isHittable else { continue }
            item.tap()
            let detail = app.buttons["ui48_inventory_detail"]
            XCTAssertTrue(detail.waitForExistence(timeout: 5), "Selecting a gear card must expose its detail action")
            detail.tap()
            _ = screen(15)
            let unownedItem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未装備")).firstMatch
            let equip = app.buttons["ui48_detail_equip"]
            if unownedItem.exists && equip.exists && equip.isEnabled {
                equip.tap()
                waitForSaveAction()
                changedEquipment = true
                alternateGearUUID = gearID.replacingOccurrences(of: "ui48_gear_", with: "")
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "が装備中")).firstMatch.waitForExistence(timeout: 8),
                              "Equipping a compatible alternative must update the live gear owner")
                tap("ui48_back")
                _ = screen(14)
                break
            }
            tap("ui48_back")
            _ = screen(14)
        }
        XCTAssertTrue(changedEquipment, "Synthetic duplicate gear should allow an actual alternative equipment configuration")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "が装備中")).firstMatch.waitForExistence(timeout: 8),
                      "The selected gear should be equipped before saving the alternate set")
        tap("ui48_close")
        _ = screen(13)
        tap("ui48_companion_loadouts")
        _ = screen(17)
        tap("ui48_loadout_primary_2")
        waitForSaveAction()
        XCTAssertTrue(app.staticTexts["現在使用中"].waitForExistence(timeout: 8), "The alternate configuration should be saved into the second set")
        let applyFirst = app.buttons["ui48_loadout_primary_1"]
        XCTAssertTrue(applyFirst.waitForExistence(timeout: 8))
        XCTAssertTrue(applyFirst.isEnabled, "Saved first set should be applicable after changing equipment")
        applyFirst.tap()
        waitForSaveAction()
        XCTAssertTrue(app.staticTexts["現在使用中"].waitForExistence(timeout: 8), "Applying the first set should restore its saved gear references")
        try capture("loadout_01b_alternate_saved_then_first_applied", classification: "real-save-loadout-switch")

        tap("ui48_close")
        _ = screen(13)
        tap("ui48_companion_inventory")
        _ = screen(14)
        let savedID = try XCTUnwrap(alternateGearUUID,
            "The test must retain the exact alternate gear instance saved in set 2")
        let savedSetGear = app.buttons["ui48_gear_\(savedID)"]
        XCTAssertTrue(savedSetGear.waitForExistence(timeout: 10), "The set-2 gear must remain in owned inventory after applying set 1")
        let inventoryScroll = app.scrollViews.firstMatch
        for _ in 0..<10 where !savedSetGear.isHittable {
            if savedSetGear.frame.midY < inventoryScroll.frame.minY { inventoryScroll.swipeDown() }
            else { inventoryScroll.swipeUp() }
        }
        XCTAssertTrue(savedSetGear.isHittable, "The retained set-2 gear card must be reachable")
        savedSetGear.tap()
        let protectionStatus = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "保存セット登録・分解保護")
        ).firstMatch
        XCTAssertTrue(protectionStatus.waitForExistence(timeout: 8),
                      "An unequipped item still referenced by loadout set 2 must be protected")
        XCTAssertFalse(protectionStatus.label.contains("が装備中"),
                       "The protected item must be unequipped after applying loadout set 1")
        tap("ui48_inventory_dismantle")
        _ = screen(18)
        XCTAssertFalse(app.buttons["ui48_dismantle_select_\(savedID)"].exists,
                       "Core-backed dismantle candidate list must exclude saved loadout references")
        let selectAll = app.buttons["すべて選ぶ"]
        if selectAll.exists { selectAll.tap() }
        XCTAssertFalse(app.buttons["ui48_dismantle_select_\(savedID)"].exists,
                       "Batch selection must never add saved loadout references")
        try capture("loadout_02_dismantle_candidates_exclude_saved", classification: "real-core-protection-in-isolated-save")

        let candidateIDs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_dismantle_select_"))
        let candidateCountBefore = candidateIDs.count
        XCTAssertGreaterThan(candidateCountBefore, 0, "Full isolated inventory must provide eligible bulk dismantle candidates")
        let clearSelection = app.buttons["選択解除"]
        XCTAssertTrue(clearSelection.waitForExistence(timeout: 8), "Inventory handoff should select its eligible dismantle set")
        clearSelection.tap()
        let singleCandidateID = candidateIDs.firstMatch.identifier.replacingOccurrences(of: "ui48_dismantle_select_", with: "")
        XCTAssertFalse(singleCandidateID.isEmpty)
        let singleCandidate = app.buttons["ui48_dismantle_select_\(singleCandidateID)"]
        XCTAssertTrue(singleCandidate.waitForExistence(timeout: 8))
        singleCandidate.tap()
        let dismantle = app.buttons["ui48_dismantle_confirm"]
        XCTAssertTrue(dismantle.waitForExistence(timeout: 8))
        XCTAssertTrue(dismantle.isEnabled, "A selected eligible item may be submitted for explicit single-item confirmation")
        XCTAssertTrue(dismantle.label.contains("1 点"), "Single-item mode must identify exactly one selected item")
        dismantle.tap()
        let destructiveConfirm = app.buttons["確認した装備を分解する"]
        XCTAssertTrue(destructiveConfirm.waitForExistence(timeout: 8), "Single-item dismantle requires a separate explicit confirmation")
        destructiveConfirm.tap()
        waitForSaveAction()
        XCTAssertFalse(app.buttons["ui48_dismantle_select_\(singleCandidateID)"].exists,
                       "Confirmed single-item dismantle must remove only its selected eligible instance")
        XCTAssertLessThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_dismantle_select_")).count,
                          candidateCountBefore,
                          "Single-item dismantle must update the real isolated inventory")
        tap("ui48_dismantle_cancel")
        _ = screen(14)
        tap("ui48_inventory_dismantle")
        _ = screen(18)

        let bulkCandidateCount = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_dismantle_select_")).count
        XCTAssertGreaterThan(bulkCandidateCount, 0, "Saved-set protection must leave eligible items for the bulk path")
        let bulkDismantle = app.buttons["ui48_dismantle_confirm"]
        XCTAssertTrue(bulkDismantle.waitForExistence(timeout: 8))
        XCTAssertTrue(bulkDismantle.isEnabled, "Only the live Core-filtered candidate set may be submitted")
        bulkDismantle.tap()
        let bulkConfirmation = app.buttons["確認した装備を分解する"]
        XCTAssertTrue(bulkConfirmation.waitForExistence(timeout: 8), "Bulk dismantle requires a separate explicit confirmation")
        bulkConfirmation.tap()
        waitForSaveAction()
        XCTAssertFalse(app.buttons["ui48_dismantle_select_\(savedID)"].exists,
                       "Saved loadout gear must remain excluded after a real bulk dismantle operation")
        XCTAssertLessThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_dismantle_select_")).count,
                          bulkCandidateCount,
                          "Confirmed bulk dismantle must remove eligible gear from the isolated save")
        try capture("loadout_02b_bulk_dismantle_saved_items_preserved", classification: "isolated-real-bulk-dismantle-core-protection")

        app.terminate()
        launch(fixture: "full", screen: 17)
        _ = screen(17)
        XCTAssertTrue(app.staticTexts["現在使用中"].waitForExistence(timeout: 10), "Saved loadout must persist after cold relaunch")
        try capture("loadout_03_cold_readback", classification: "persistence-verified-isolated-save")
    }
}
