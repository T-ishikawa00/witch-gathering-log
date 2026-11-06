import XCTest
import CryptoKit

/// Additional real-navigation checks for journal, challenge, disclosure and
/// cancellation paths. Runs only with UUID-keyed isolated UI48 saves.
final class UI48CoverageAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var saveKey = UUID().uuidString.lowercased()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground { app.terminate() }
    }

    private func launch(_ screen: Int, fixture: String = "full") {
        app = XCUIApplication()
        app.launchArguments = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey,
                              "--qa-readback-save", "--ui48-fixture=" + fixture,
                              "--ui48-screen=\(screen)"]
        app.launch()
    }

    private func relaunch(_ screen: Int) {
        app = XCUIApplication()
        app.launchArguments = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey,
                              "--qa-readback-save", "--ui48-screen=\(screen)"]
        app.launch()
    }

    @discardableResult
    private func screen(_ number: Int, timeout: TimeInterval = 25) -> XCUIElement {
        let identifier = String(format: "ui48_screen_%02d", number)
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "Expected UI48 S\(number)")
        XCTAssertFalse(app.staticTexts["この画面は準備中です"].exists, "S\(number) must not be a placeholder")
        return result
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10) {
        tapElement(app.buttons[identifier], description: identifier, timeout: timeout)
    }

    private func tapLabel(_ label: String, timeout: TimeInterval = 10) {
        let element = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        tapElement(element, description: "button label containing \(label)", timeout: timeout)
    }

    private func tapElement(_ element: XCUIElement, description: String, timeout: TimeInterval = 10) {
        // LazyVGrid does not materialize offscreen records. Reveal the actual
        // vertical content before resolving the action, then retain hit checks.
        if !element.waitForExistence(timeout: min(timeout, 2)) {
            let vertical = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }
            for _ in 0..<12 {
                if element.exists { break }
                if let vertical { vertical.swipeUp() } else { app.swipeUp() }
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(description)")
        XCTAssertTrue(element.isEnabled, "Disabled \(description)")
        let scroll = enclosingScrollView(for: element)
        for _ in 0..<8 {
            let currentFrame = element.frame
            let currentViewport = scroll?.frame.intersection(app.frame) ?? app.frame
            if element.isHittable && currentViewport.contains(CGPoint(x: currentFrame.midX, y: currentFrame.midY)) { break }
            let target = element.frame
            if let scroll {
                if target.midY < scroll.frame.minY { scroll.swipeDown() }
                else if target.midY > scroll.frame.maxY { scroll.swipeUp() }
                else if target.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            } else if target.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
        XCTAssertTrue(viewport.contains(center), "Action center must be visible in its containing viewport: \(description)")
        XCTAssertTrue(element.isHittable, "Unreachable \(description)")
        element.tap()
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

    private func capture(_ name: String, phase: String) throws {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let runner = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let hash = SHA256.hash(data: try Data(contentsOf: runner)).map { String(format: "%02x", $0) }.joined()
        let payload: [String: String] = [
            "capture": name, "phase": phase, "testCase": name,
            "saveKey": saveKey, "testExecutableSHA256": hash,
            "launchArguments": app.launchArguments.joined(separator: " "),
            "evidenceClass": phase.contains("cold") ? "persistence-readback" : "real-ui-operation"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = name + "_phase_receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    private func resourceReadouts() -> [String] {
        app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { $0.contains("/") || $0.contains("所持") }
            .sorted()
    }

    func testJournalMaterialAndEnemyRecordsSelectAndReturn() throws {
        launch(28)
        _ = screen(28)
        tap("ui48_journal_29")
        _ = screen(29)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持数")).firstMatch.waitForExistence(timeout: 8),
                      "S29 must show the live inventory count for its selected material")
        XCTAssertTrue(app.staticTexts["採集できる場所"].exists)
        try capture("coverage_journal_material_default", phase: "S29_read_only_live_record")

        let material = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "露灯草")).firstMatch
        tapElement(material, description: "material-record selector for 露灯草")
        XCTAssertTrue(app.staticTexts["露灯草"].waitForExistence(timeout: 8),
                      "Selecting a material must update the live record hero")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持数")).firstMatch.exists)
        try capture("coverage_journal_material_selected", phase: "S29_material_selection")
        tap("ui48_back")
        _ = screen(28)

        tap("ui48_journal_30")
        _ = screen(30)
        XCTAssertTrue(app.staticTexts["苔角いのしし"].waitForExistence(timeout: 8),
                      "Full isolated record fixture must display its selected enemy")
        XCTAssertTrue(app.staticTexts["記録"].exists)
        try capture("coverage_journal_enemy_default", phase: "S30_read_only_live_record")
        tap("ui48_enemy_record_B_R01_B")
        XCTAssertTrue(app.staticTexts["苔冠の古樹"].waitForExistence(timeout: 8),
                      "Selecting an enemy record must update the live detail")
        XCTAssertTrue(app.staticTexts["苔冠の生木核"].exists,
                      "Selected enemy record must show its actual catalog drop material")
        try capture("coverage_journal_enemy_selected", phase: "S30_enemy_selection")
        tap("ui48_back")
        _ = screen(28)
        try capture("coverage_journal_records_return", phase: "S29_S30_back_to_index")
    }

    func testMaterialUsesOpenRecipeAndCancelWithoutSpending() throws {
        launch(29)
        _ = screen(29)
        let before = resourceReadouts()
        let recipes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_material_recipe_"))
        XCTAssertTrue(recipes.firstMatch.waitForExistence(timeout: 10), "The selected material must show its actual catalog uses")
        tapElement(recipes.firstMatch, description: "material use recipe")
        let detail = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["ui48_screen_20", "ui48_screen_21"])).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 15), "A material use must open its live recipe requirements")
        let isReady = app.descendants(matching: .any).matching(identifier: "ui48_screen_21").firstMatch.exists
        let action = app.buttons[isReady ? "ui48_craft_commit" : "ui48_recipe_track"]
        XCTAssertTrue(action.waitForExistence(timeout: 10),
                      "Ready recipes must expose craft confirmation; missing-material recipes must expose tracking")
        // Inspect the state-specific action without executing either command.
        try capture("coverage_material_use_recipe_preview", phase: "S29_S20_S21_recipe_preview_no_commit")
        tap("ui48_back")
        _ = screen(29)
        XCTAssertEqual(resourceReadouts(), before, "Opening a recipe must not spend material or craft")
        app.terminate()
        relaunch(29)
        _ = screen(29)
        XCTAssertEqual(resourceReadouts(), before, "Read-only recipe preview must remain unchanged after reload")
        try capture("coverage_material_use_cold_readback", phase: "S29_recipe_preview_cold_no_commit")
    }

    func testEnemyRecordInvestigationPreviewCancelApplyAndColdReload() throws {
        launch(30)
        _ = screen(30)
        tap("ui48_enemy_investigate")
        _ = screen(12)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "苔角いのしし")).firstMatch.exists)
        try capture("coverage_enemy_investigation_preview", phase: "S30_S12_investigate_preview_no_commit")
        tap("いまの採集を続ける")
        _ = screen(30)
        app.terminate()
        relaunch(4)
        _ = screen(4)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "再調査 · 苔角いのしし")).firstMatch.exists,
                       "Cancelling the route must retain the prior gathering task")
        try capture("coverage_enemy_investigation_cancel_cold", phase: "S12_investigate_cancel_cold_no_commit")
        app.terminate()
        relaunch(30)
        _ = screen(30)
        tap("ui48_enemy_investigate")
        _ = screen(12)
        tap("ui48_switch_apply")
        _ = screen(4)
        let work = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "再調査 · 苔角いのしし")).firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 15), "Explicit apply must start the selected enemy's real investigation")
        try capture("coverage_enemy_investigation_applied", phase: "S30_S12_investigate_explicit_apply")
        app.terminate()
        relaunch(4)
        _ = screen(4)
        XCTAssertTrue(work.waitForExistence(timeout: 15), "Investigation destination must survive reload")
        try capture("coverage_enemy_investigation_applied_cold", phase: "S04_investigate_cold_readback")
    }

    func testLRCollectionOwnedCardOpensGearDetailReturnsAndVaultWithoutSpending() throws {
        launch(36, fixture: "full")
        _ = screen(36)
        let initialTicket = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "無料鑑定券")).firstMatch
        XCTAssertTrue(initialTicket.waitForExistence(timeout: 8))
        let before = initialTicket.label
        app.terminate()
        launch(35, fixture: "full")
        _ = screen(35)
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "×"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "The full isolated fixture must expose an owned LR collection card")
        tapElement(cards.firstMatch, description: "owned LR collection card")
        _ = screen(15)
        XCTAssertTrue(app.staticTexts["装備の詳細"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "品質")).firstMatch.exists,
                      "Selecting a collection entry must open its actual owned gear detail")
        tap("ui48_back")
        _ = screen(35)
        tapLabel("魔導庫を開く")
        _ = screen(36)
        let ticketAfter = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "無料鑑定券")).firstMatch
        XCTAssertTrue(ticketAfter.waitForExistence(timeout: 8))
        XCTAssertEqual(ticketAfter.label, before, "Opening the vault from collection must not spend free tickets")
        XCTAssertTrue(app.buttons["ui48_vault_draw_1"].isEnabled, "The isolated full fixture should retain its actual free-draw availability")
    }

    func testAllFifteenChallengesOpenAndCancelWithoutStartingCombat() throws {
        launch(33)
        _ = screen(33)
        var opened = 0
        for region in ["R01", "R02", "R03", "R04", "R05"] {
            tap("ui48_challenge_region_\(region)")
            _ = screen(33)
            let rows = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
                "ui48_challenge_", "ui48_challenge_region_"))
            let rowIDs = rows.allElementsBoundByIndex.map(\.identifier)
                .filter { !$0.isEmpty && !$0.hasPrefix("ui48_challenge_region_") }
            XCTAssertEqual(rowIDs.count, 3,
                           "Region \(region) must expose its three catalog-backed challenge tasks")
            try capture("coverage_challenges_\(region)_list", phase: "S33_\(region)_challenge_list")
            for rowID in rowIDs {
                let row = app.buttons[rowID]
                let rowParts = row.label.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                XCTAssertGreaterThanOrEqual(rowParts.count, 2,
                                            "Challenge row must expose its ordinal and live catalog title")
                XCTAssertTrue(rowParts[0].range(of: #"^\d{2}$"#, options: .regularExpression) != nil,
                              "Challenge row must expose its two-digit ordinal")
                let title = rowParts[1]
                XCTAssertFalse(title.isEmpty, "Challenge row title must come from the live catalog")
                tapElement(row, description: "challenge \(rowID)")
                _ = screen(34)
                XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8),
                              "S34 must show the selected challenge's live catalog title")
                XCTAssertTrue(app.staticTexts["課題の記録"].exists)
                XCTAssertTrue(app.staticTexts["参加する魔物"].exists)
                XCTAssertTrue(app.staticTexts["初回達成報酬"].exists)
                let actionExists = app.buttons["完全自動戦闘で挑戦"].exists
                    || app.buttons["もう一度挑戦する"].exists
                    || app.buttons["解放に必要な魔物を確認"].exists
                XCTAssertTrue(actionExists,
                              "Every task must expose its actual available action or locked-state next step")
                XCTAssertFalse(app.descendants(matching: .any)["ui48_screen_08"].exists,
                               "Opening task details must not start an automatic battle")
                try capture("coverage_challenge_detail_\(region)_\(opened + 1)",
                            phase: "S34_\(region)_detail_before_cancel")
                tap("ui48_back")
                _ = screen(33)
                XCTAssertFalse(app.descendants(matching: .any)["ui48_screen_08"].exists,
                               "Cancelling task \(rowID) must leave combat unstarted")
                opened += 1
            }
        }
        XCTAssertEqual(opened, 15, "All 15 catalog tasks must be opened and cancelled through the UI")
        try capture("coverage_challenges_all_15_cancelled", phase: "S33_all_15_details_cancelled_no_combat")
    }

    func testOddsDisclosureMatchesCurrentLocalCatalogAndPityState() throws {
        launch(36)
        _ = screen(36)
        tapLabel("提供割合と保証を確認")
        _ = screen(38)
        XCTAssertTrue(app.staticTexts["提供割合と保証"].exists)
        // These basis-point values are read verbatim from this frozen build's
        // catalog_overlay.json and validated by GameRuntimeConfigurationR098;
        // they are local development candidates, not approved product odds.
        let catalogOdds: [(String, Int)] = [("C", 3_500), ("R", 4_000), ("SR", 2_000), ("UR", 400), ("LR", 100)]
        XCTAssertEqual(catalogOdds.reduce(0) { $0 + $1.1 }, 10_000,
                       "The current catalog's displayed quality rows must total its basis-point denominator")
        for (quality, basisPoints) in catalogOdds {
            XCTAssertTrue(app.staticTexts[quality].waitForExistence(timeout: 8), "Missing catalog quality row \(quality)")
            let expected = String(format: "%.2f%%", Double(basisPoints) / 100.0)
            XCTAssertTrue(app.staticTexts[expected].exists,
                          "S38 must show \(quality)'s current catalog value \(expected), without substituting design-sample values")
        }
        XCTAssertTrue(app.staticTexts["上位品質までの記録　0"].exists,
                      "The disclosure must reflect the isolated save's actual upper-tier pity count")
        XCTAssertTrue(app.staticTexts["中位品質までの記録　0"].exists,
                      "The disclosure must reflect the isolated save's actual mid-tier pity count")
        XCTAssertTrue(app.staticTexts["目標保証は次回上位品質まで未成立"].exists,
                      "The initial isolated save must disclose its real untriggered target guarantee")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式な商品仕様・確率としては未承認")).firstMatch.exists,
                      "Local candidate odds must remain clearly distinguished from approved product rules")
        try capture("coverage_vault_odds_catalog_and_initial_pity", phase: "S38_live_catalog_and_save_disclosure")
        tap("ui48_back")
        _ = screen(36)
        try capture("coverage_vault_odds_return", phase: "S38_back_to_vault")
    }

    func testFiveWorkshopActionPreviewsCancelWithoutChangingSavedRequirements() throws {
        let cases: [(Int, String, Bool)] = [
            (21, "ui48_craft_back", false),
            (22, "ui48_evolution_back", true),
            (23, "ui48_upgrade_cancel", false),
            (24, "ui48_refinement_cancel", false),
            (25, "ui48_upgrade_cancel", false)
        ]
        for (screenNumber, cancelID, selectEvolution) in cases {
            saveKey = UUID().uuidString.lowercased()
            launch(screenNumber)
            _ = screen(screenNumber)
            if selectEvolution {
                let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_evolution_branch_"))
                XCTAssertGreaterThan(options.count, 0, "S22 must expose a real evolution preview option")
                tapElement(options.firstMatch, description: "first catalog evolution preview")
            }
            let before = resourceReadouts()
            XCTAssertFalse(before.isEmpty, "S\(screenNumber) must expose actual requirements before cancellation")
            try capture("coverage_workshop_S\(screenNumber)_before_cancel", phase: "S\(screenNumber)_preview_before_cancel")
            tap(cancelID)
            XCTAssertFalse(app.descendants(matching: .any)["ui48_screen_26"].exists,
                           "Canceling S\(screenNumber) must not create a result screen")
            try capture("coverage_workshop_S\(screenNumber)_after_cancel", phase: "S\(screenNumber)_cancelled_no_commit")

            app.terminate()
            relaunch(screenNumber)
            _ = screen(screenNumber)
            if selectEvolution {
                let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_evolution_branch_"))
                XCTAssertGreaterThan(options.count, 0, "S22 must still expose the same catalog evolution preview after reload")
                tapElement(options.firstMatch, description: "same evolution preview after reload")
            }
            let after = resourceReadouts()
            XCTAssertEqual(after, before,
                           "Canceling S\(screenNumber) and cold-reloading must preserve the displayed material requirements")
            try capture("coverage_workshop_S\(screenNumber)_cold_readback", phase: "S\(screenNumber)_cancel_cold_readback")
            app.terminate()
        }
    }

    func testRegionSwitchCancelLeavesCurrentRegionAfterColdReload() throws {
        saveKey = UUID().uuidString.lowercased()
        launch(1)
        _ = screen(1)
        tap("tab_探索")
        _ = screen(4)
        tap("ui48_map")
        _ = screen(5)
        tap("ui48_region_R02")
        _ = screen(12)
        XCTAssertTrue(app.buttons["ui48_switch_apply"].isEnabled,
                      "Full isolated fixture must make the preview destination eligible")
        XCTAssertTrue(app.staticTexts["眠り霧の湿原"].exists,
                      "The destination preview must identify R02 before cancellation")
        try capture("coverage_region_R02_before_cancel", phase: "S12_region_switch_preview")
        tapLabel("いまの採集を続ける")
        _ = screen(5)
        tap("ui48_back")
        _ = screen(4)
        XCTAssertTrue(app.buttons["ui48_map"].label.contains("木漏れ日の森"),
                      "Canceling the destination preview must leave the active R01 region unchanged")
        try capture("coverage_region_R02_cancelled", phase: "region_switch_cancel_no_commit")

        app.terminate()
        relaunch(4)
        _ = screen(4)
        XCTAssertTrue(app.buttons["ui48_map"].label.contains("木漏れ日の森"),
                      "The cancelled region switch must remain unapplied after cold reload")
        try capture("coverage_region_switch_cancel_cold_readback", phase: "region_switch_cancel_cold_readback")
    }
}
