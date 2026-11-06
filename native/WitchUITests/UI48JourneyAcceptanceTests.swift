import XCTest
import CryptoKit

/// Exercises progression gates through the ordinary UI using UUID-keyed isolated saves.
/// These are operation tests, not direct screen-route captures.
final class UI48JourneyAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var saveKey = UUID().uuidString.lowercased()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground { app.terminate() }
    }

    private func launch(fixture: String? = nil, screen: Int? = nil) {
        var args = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey,
                    "--qa-readback-save"]
        if let fixture { args.append("--ui48-fixture=" + fixture) }
        if let screen { args.append("--ui48-screen=\(screen)") }
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
    }

    @discardableResult
    private func screen(_ number: Int, timeout: TimeInterval = 30) -> XCUIElement {
        let id = String(format: "ui48_screen_%02d", number)
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "Expected UI48 screen S\(number)")
        XCTAssertFalse(app.staticTexts["この画面は準備中です"].exists)
        return result
    }

    private func tap(_ id: String, timeout: TimeInterval = 15) {
        let control = app.buttons[id]
        let rootControl = id.hasPrefix("tab_") || ["ui48_back", "ui48_close"].contains(id)
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
            } else if control.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(control.waitForExistence(timeout: timeout), "Missing action \(id)")
        XCTAssertTrue(control.isEnabled, "Disabled action \(id)")
        let center = CGPoint(x: control.frame.midX, y: control.frame.midY)
        let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
        XCTAssertTrue(viewport.contains(center), "Action center must be visible in its containing viewport: \(id)")
        XCTAssertTrue(control.isHittable, "Unreachable action \(id)")
        control.tap()
    }

    private func enclosingScrollView(for element: XCUIElement) -> XCUIElement? {
        guard element.exists else { return app.scrollViews.count == 1 ? app.scrollViews.firstMatch : nil }
        let matches = app.scrollViews.allElementsBoundByIndex.filter { scroll in
            let descendants = scroll.descendants(matching: element.elementType)
            if !element.identifier.isEmpty {
                return descendants.matching(identifier: element.identifier).firstMatch.exists
            }
            return descendants.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
        }
        return matches.min(by: { abs($0.frame.midY - element.frame.midY) < abs($1.frame.midY - element.frame.midY) })
    }

    private func waitForTerminalBattle(timeout: TimeInterval = 150) {
        let terminal = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ OR identifier == %@", "ui48_screen_09", "ui48_screen_10")).firstMatch
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: terminal)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: timeout), .completed,
                       "Actual automatic battle did not reach a result")
    }

    private func capture(_ name: String) throws {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let runner = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let hash = SHA256.hash(data: try Data(contentsOf: runner)).map { String(format: "%02x", $0) }.joined()
        let body: [String: String] = ["capture": name, "saveKey": saveKey,
            "testExecutableSHA256": hash, "launchArguments": app.launchArguments.joined(separator: " "),
            "evidenceClass": "isolated-ordinary-ui-operation"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = name + "_identity"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFrontierBossUnlocksNextRegionThroughS11AndS12AndPersists() throws {
        launch(fixture: "frontier", screen: 6)
        _ = screen(6)
        tap("魔物を探す")
        // In the frozen catalog B_R01_A is boss=false, so this fixture marks it
        // complete with the other regular encounters. The R02 unlock must still
        // be caused by defeating the remaining true boss, B_R01_B, through UI.
        func battleBoss(_ id: String, returnToExplore: Bool) {
            let row = app.buttons["ui48_enemy_\(id)"]
            XCTAssertTrue(row.waitForExistence(timeout: 12), "S06 must expose R01 boss \(id)")
            if id == "B_R01_A" {
                XCTAssertTrue(row.label.contains("討伐済み"), "The frontier fixture must reflect B_R01_A's catalog boss=false state")
            }
            if id == "B_R01_B" {
                XCTAssertTrue(row.label.contains("未討伐"), "The actual frontier boss must remain uncleared before its battle")
            }
            tap("ui48_enemy_\(id)")
            _ = screen(7)
            var fight = app.buttons["fight_\(id)"]
            if !fight.waitForExistence(timeout: 3) {
                let prerequisite = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "前の魔物を確認する")).firstMatch
                XCTAssertTrue(prerequisite.waitForExistence(timeout: 8), "Locked boss must expose its actual prerequisite")
                prerequisite.tap()
                _ = screen(7)
                fight = app.buttons["fight_B_R01_A"]
            }
            XCTAssertTrue(fight.waitForExistence(timeout: 10), "Boss prerequisite must be challengeable")
            XCTAssertTrue(fight.isEnabled)
            fight.tap()
            _ = screen(8, timeout: 20)
            waitForTerminalBattle()
            XCTAssertTrue(app.descendants(matching: .any)["ui48_screen_09"].exists,
                          "The frontier setup must win boss encounter \(id)")
            _ = screen(9)
            if returnToExplore {
                tap("探索へ戻る")
                _ = screen(4)
                tap("ui48_destinations")
                _ = screen(6)
                tap("魔物を探す")
            }
        }
        battleBoss("B_R01_A", returnToExplore: true)
        battleBoss("B_R01_B", returnToExplore: false)
        _ = screen(9)
        try capture("journey_frontier_R01_boss_victory_S09")

        let unlock = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "新しい地域が開きました")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "Real boss victory must expose its newly unlocked region")
        unlock.tap()
        _ = screen(11)
        XCTAssertTrue(app.buttons["新しい地域へ"].exists,
                      "S11 must offer the region actually unlocked by the battle")
        tap("新しい地域へ")
        _ = screen(12)
        XCTAssertTrue(app.buttons["ui48_switch_apply"].isEnabled, "S12 must allow the explicitly confirmed unlocked-region switch")
        try capture("journey_unlock_confirmation_S12")
        tap("ui48_switch_apply")
        _ = screen(4, timeout: 30)
        try capture("journey_region_switch_committed_S04")

        app.terminate()
        launch()
        _ = screen(1)
        tap("tab_探索")
        _ = screen(4)
        tap("ui48_map")
        _ = screen(5)
        tap("ui48_region_R02")
        _ = screen(12)
        XCTAssertTrue(app.buttons["ui48_switch_apply"].isEnabled,
                      "Cold reload must preserve the R02 unlock and allow its region handoff")
        try capture("journey_region_switch_cold_readback")
    }

    func testChallengeDetailStartsRealAutomaticBattleAndResultSurvivesReload() throws {
        launch(fixture: "full", screen: 34)
        _ = screen(34)
        XCTAssertTrue(app.staticTexts["15の研究課題"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "課題")).firstMatch.exists,
                      "S34 must show a live challenge detail")
        let challenge = app.buttons["完全自動戦闘で挑戦"]
        XCTAssertTrue(challenge.waitForExistence(timeout: 10), "Unlocked challenge must offer its actual battle action")
        XCTAssertTrue(challenge.isEnabled)
        challenge.tap()
        _ = screen(8, timeout: 20)
        waitForTerminalBattle()
        let won = app.descendants(matching: .any)["ui48_screen_09"].exists
        let terminalScreen = won ? 9 : 10
        _ = screen(terminalScreen)
        try capture(won ? "journey_challenge_victory_S09" : "journey_challenge_defeat_S10")

        app.terminate()
        launch()
        _ = screen(1)
        app.buttons["tab_採集帳"].tap()
        _ = screen(28)
        tap("ui48_journal_33")
        _ = screen(33)
        XCTAssertTrue(app.staticTexts["15の研究課題"].waitForExistence(timeout: 8))
        if won {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "達成済み")).firstMatch.waitForExistence(timeout: 8),
                          "A won challenge must be recorded as cleared after cold reload")
        }
        try capture("journey_challenge_cold_readback_S33")
    }

    func testActualDefeatInventoryBackAndRetryKeepSameEncounterWithoutStartingAgain() throws {
        // The validated S10 QA route prepares S07 and starts the real battle
        // against the catalog's last encounter; no result screen is fabricated.
        launch(fixture: "full", screen: 36)
        _ = screen(36)
        let initialTicketText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "無料鑑定券")).firstMatch
        XCTAssertTrue(initialTicketText.waitForExistence(timeout: 8))
        let initialTickets = initialTicketText.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first
        XCTAssertNotNil(initialTickets)
        app.terminate()
        launch(screen: 10)
        _ = screen(10, timeout: 150)
        XCTAssertTrue(app.staticTexts["装備や素材は失っていません。"].waitForExistence(timeout: 8),
                      "S10 must be an actual defeat result that confirms no items were lost")
        try capture("journey_actual_defeat_S10_before_inventory")

        tapLabelForJourney("持ちものを確認する")
        _ = screen(14)
        tap("ui48_back")
        _ = screen(10)
        tapLabelForJourney("再挑戦の準備")
        _ = screen(7)
        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fight_")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 8), "Retry preparation must return to the same actual encounter detail")
        XCTAssertTrue(retry.isEnabled, "Retry remains an explicit action; preparation alone must not start another battle")
        XCTAssertEqual(retry.identifier, "fight_B_R05_B", "Retry preparation must retain the catalog encounter used by the real S10 fixture battle")
        try capture("journey_actual_defeat_retry_prepared_same_target")
        tap("ui48_close")
        _ = screen(4)
        tap("tab_家")
        _ = screen(1)
        let homeTicketButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "無料鑑定券")).firstMatch
        XCTAssertTrue(homeTicketButton.waitForExistence(timeout: 8))
        let remainingTickets = homeTicketButton.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first
        XCTAssertEqual(remainingTickets, initialTickets, "Preparing a retry must not spend an appraisal ticket")
    }

    private func tapLabelForJourney(_ label: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing actual action: \(label)")
        XCTAssertTrue(button.isEnabled)
        button.tap()
    }
}
