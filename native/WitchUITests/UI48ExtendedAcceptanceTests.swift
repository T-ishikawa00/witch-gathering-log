import XCTest
import CryptoKit

/// Additional save-backed UI paths for screens that the core UI48 suite only captures.
/// All state is created behind the isolated, UUID-keyed Simulator QA gate.
final class UI48ExtendedAcceptanceTests: XCTestCase {
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
        app.launchArguments = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey,
                              "--qa-readback-save", "--ui48-fixture=" + fixture,
                              "--ui48-screen=\(screen)"]
        app.launch()
    }

    @discardableResult
    private func waitForScreen(_ number: Int, timeout: TimeInterval = 25) -> XCUIElement {
        let id = String(format: "ui48_screen_%02d", number)
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "Expected UI48 screen S\(number)")
        XCTAssertFalse(app.staticTexts["この画面は準備中です"].exists, "S\(number) rendered a placeholder")
        return result
    }

    private func tap(_ id: String, timeout: TimeInterval = 10) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing UI action: \(id)")
        XCTAssertTrue(button.isEnabled, "UI action must be enabled: \(id)")
        let ancestors = app.scrollViews.allElementsBoundByIndex.filter { $0.buttons[id].exists }
        let page = ancestors.max { $0.frame.height < $1.frame.height }
        let strip = ancestors.min { $0.frame.height < $1.frame.height }
        func visibleViewport() -> CGRect {
            ancestors.reduce(app.frame) { $0.intersection($1.frame) }
        }
        for _ in 0..<14 {
            let viewport = visibleViewport()
            let center = CGPoint(x: button.frame.midX, y: button.frame.midY)
            if button.isHittable && viewport.contains(center) { break }
            let pageViewport = page?.frame.intersection(app.frame) ?? app.frame
            if center.y < pageViewport.minY || center.y > pageViewport.maxY {
                if center.y < pageViewport.midY { page?.swipeDown() } else { page?.swipeUp() }
            } else if center.x < viewport.minX || center.x > viewport.maxX, let strip {
                if center.x < viewport.midX { strip.swipeRight() } else { strip.swipeLeft() }
            } else if let page {
                if center.y < pageViewport.midY { page.swipeDown() } else { page.swipeUp() }
            } else if center.y < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        let viewport = visibleViewport()
        XCTAssertTrue(viewport.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)), "Action center must be visible: \(id)")
        XCTAssertTrue(button.isHittable, "UI action must be reachable: \(id)")
        button.tap()
    }

    private func waitForSave() {
        let busy = app.descendants(matching: .any)["ui48_busy"]
        guard busy.waitForExistence(timeout: 1) else { return }
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 30), .completed, "Save-backed UI action did not finish")
    }

    private func researchMaterialAmounts() -> [String] {
        let pattern = try! NSRegularExpression(pattern: "[0-9]+\\s*/\\s*[0-9]+")
        return app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/"))
            .allElementsBoundByIndex.compactMap { element in
                let label = element.label
                let range = NSRange(label.startIndex..<label.endIndex, in: label)
                guard let match = pattern.firstMatch(in: label, range: range),
                      let swiftRange = Range(match.range, in: label) else { return nil }
                return String(label[swiftRange]).replacingOccurrences(of: " ", with: "")
            }.sorted()
    }

    private func capture(_ name: String) throws {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let executable = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let hash = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        let body: [String: String] = ["capture": name, "saveKey": saveKey,
            "testExecutableSHA256": hash, "launchArguments": app.launchArguments.joined(separator: " ")]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = name + "_identity"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    private func progressLabel(on screen: Int) -> String {
        let arrow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "→")).firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: 8), "S\(screen) must expose the current-to-next progression")
        return arrow.label
    }

    private func assertUpgradeAndColdReadback(screen: Int, actionID: String, progressPrefix: String? = nil) throws {
        launch(screen)
        _ = waitForScreen(screen)
        let before = progressLabel(on: screen)
        if let progressPrefix {
            XCTAssertTrue(before.contains(progressPrefix), "Unexpected live progression for S\(screen): \(before)")
        }
        tap(actionID)
        _ = waitForScreen(26, timeout: 30)
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "しました")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), "The confirmed operation must show its saved result")
        try capture(String(format: "extended_S%02d_saved_result", screen))

        app.terminate()
        launch(screen)
        _ = waitForScreen(screen)
        let after = progressLabel(on: screen)
        XCTAssertNotEqual(after, before, "The changed gear progression must survive cold reload")
        try capture(String(format: "extended_S%02d_cold_readback", screen))
    }

    func testEnhancementS23PersistsAcrossColdRelaunch() throws {
        try assertUpgradeAndColdReadback(screen: 23, actionID: "ui48_upgrade_commit_enhance", progressPrefix: "強化 +")
    }

    func testRefinementS24PersistsAcrossColdRelaunch() throws {
        try assertUpgradeAndColdReadback(screen: 24, actionID: "ui48_refinement_commit", progressPrefix: "研成 ")
    }

    func testQualityPromotionS25PersistsAcrossColdRelaunch() throws {
        // The selected fixture gear may have different current quality. progressLabel
        // already requires a real A → B progression; persistence compares it after reload.
        try assertUpgradeAndColdReadback(screen: 25, actionID: "ui48_upgrade_commit_promoteQuality")
    }

    func testEvolutionS22PersistsSameGearIdentityAcrossColdRelaunch() throws {
        launch(22)
        _ = waitForScreen(22)
        let recipeRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_evolution_branch_"))
        XCTAssertTrue(recipeRows.firstMatch.waitForExistence(timeout: 8), "Selected gear must expose its live evolution recipe options")
        tap(recipeRows.firstMatch.identifier)
        let confirm = app.buttons["ui48_evolution_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Selecting a catalog evolution must show its real requirements")
        XCTAssertTrue(confirm.isEnabled, "Full isolated fixture must satisfy the selected evolution recipe")
        tap("ui48_evolution_confirm")
        _ = waitForScreen(26, timeout: 30)
        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "へ進化しました")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8), "Evolution result must identify the saved output gear")
        let evolvedName = String(result.label.dropLast("へ進化しました".count))
        XCTAssertFalse(evolvedName.isEmpty)
        try capture("extended_S22_evolution_saved_result")

        app.terminate()
        launch(15)
        _ = waitForScreen(15)
        XCTAssertTrue(app.staticTexts[evolvedName].waitForExistence(timeout: 8), "Same gear instance must reload with its evolved catalog identity")
        try capture("extended_S22_evolution_cold_readback")
    }

    func testResearchConsumesItsLiveMaterialsAndPersists() throws {
        launch(31)
        _ = waitForScreen(31)
        // RS_THEORY_1 is explicitly cost-free in the approved runtime catalog. Use the
        // first material-consuming topic so this test proves a real spend and readback.
        let topic = app.buttons["ui48_research_RS_THEORY_2"]
        XCTAssertTrue(topic.waitForExistence(timeout: 10), "Research index must expose its material-consuming second topic")
        XCTAssertTrue(topic.isEnabled)
        topic.tap()
        _ = waitForScreen(32)

        let amounts = researchMaterialAmounts()
        XCTAssertFalse(amounts.isEmpty, "Research detail must show live owned/required material values")
        let study = app.buttons["研究する"]
        XCTAssertTrue(study.waitForExistence(timeout: 8))
        XCTAssertTrue(study.isEnabled, "The full isolated fixture must permit the selected research action")
        study.tap()
        waitForSave()
        XCTAssertTrue(app.staticTexts["この研究は習得済みです。"].waitForExistence(timeout: 10), "Successful research must be reflected in the current saved state")
        let after = researchMaterialAmounts()
        XCTAssertNotEqual(after, amounts, "Research must consume the displayed material cost")
        try capture("extended_S31_research_completed")

        app.terminate()
        launch(31)
        _ = waitForScreen(31)
        let restoredTopic = app.buttons["ui48_research_RS_THEORY_2"]
        XCTAssertTrue(restoredTopic.waitForExistence(timeout: 10), "Cold reload must allow the same saved research topic to be selected again")
        restoredTopic.tap()
        _ = waitForScreen(32)
        XCTAssertTrue(app.staticTexts["この研究は習得済みです。"].waitForExistence(timeout: 10), "Research completion must survive cold relaunch")
        try capture("extended_S32_research_cold_readback")
    }

    func testChallengeListS33SelectionAndCancellationDoNotStartBattle() throws {
        launch(33)
        _ = waitForScreen(33)
        XCTAssertTrue(app.staticTexts["15の研究課題"].waitForExistence(timeout: 8))
        let regionIDs = (1...5).map { String(format: "R%02d", $0) }
        var challengeIDs: [String] = []
        for regionID in regionIDs {
            let region = app.buttons["ui48_challenge_region_\(regionID)"]
            XCTAssertTrue(region.waitForExistence(timeout: 8), "S33 must expose catalog region \(regionID)")
            region.tap()
            let rows = app.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
                "ui48_challenge_", "ui48_challenge_region_"))
            let ids = rows.allElementsBoundByIndex.map(\.identifier)
                .filter { !$0.isEmpty && !$0.hasPrefix("ui48_challenge_region_") }
            XCTAssertEqual(ids.count, 3, "Region \(regionID) must show its three live catalog tasks")
            challengeIDs.append(contentsOf: ids)
        }
        XCTAssertEqual(challengeIDs.count, 15, "The five region tabs must expose all 15 live catalog tasks")
        app.buttons["ui48_challenge_region_R01"].tap()
        let firstChallenge = app.buttons[challengeIDs[0]]
        XCTAssertTrue(firstChallenge.waitForExistence(timeout: 8))
        firstChallenge.tap()
        _ = waitForScreen(34)
        XCTAssertTrue(app.staticTexts["課題の記録"].waitForExistence(timeout: 8))
        let challengeAction = app.buttons["完全自動戦闘で挑戦"]
        let replayAction = app.buttons["もう一度挑戦する"]
        let unlockAction = app.buttons["解放に必要な魔物を確認"]
        XCTAssertTrue(challengeAction.exists || replayAction.exists || unlockAction.exists,
                      "Challenge detail should present its actual challenge action or locked-state guidance")
        app.buttons["ui48_back"].tap()
        _ = waitForScreen(33)
        XCTAssertFalse(app.descendants(matching: .any)["ui48_screen_08"].exists, "Leaving challenge detail must not start combat")
        try capture("extended_S33_S34_challenge_selected_cancelled")
    }

    func testVaultTargetSelectionDoesNotSpendTicketsAndHonorsConditionalConfirmation() throws {
        launch(36)
        _ = waitForScreen(36)
        let ticketText = app.staticTexts["ui48_vault_free_balance"]
        XCTAssertTrue(ticketText.waitForExistence(timeout: 8))
        let beforeTickets = ticketText.label
        let targetCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "目標を選ぶだけでは鑑定しません")).firstMatch
        XCTAssertTrue(targetCard.waitForExistence(timeout: 8), "Vault must route into the live target selector")
        let originalGoal = targetCard.label
        let scroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height })
        let dockTop = app.buttons["ui48_vault_draw_1"].frame.minY - 10
        let viewport = CGRect(x: scroll.frame.minX, y: scroll.frame.minY,
                              width: scroll.frame.width, height: dockTop - scroll.frame.minY)
        let visibleCard = targetCard.frame.intersection(viewport)
        XCTAssertGreaterThan(visibleCard.height, 12, "The visible target card must offer a real tap area above the dock")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        try capture("extended_S36_target_visible_portion_before_tap")
        origin.withOffset(CGVector(dx: visibleCard.midX, dy: visibleCard.midY)).tap()
        _ = waitForScreen(37)
        tap("ui48_back")
        _ = waitForScreen(36)
        XCTAssertEqual(app.staticTexts["ui48_vault_free_balance"].label, beforeTickets,
                       "Tapping the visible goal card must never spend tickets")
        for _ in 0..<8 {
            if viewport.contains(targetCard.frame) { break }
            origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 20))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 20)))
        }
        XCTAssertTrue(viewport.contains(targetCard.frame), "Scrolling must fully reveal the target card above the dock")
        XCTAssertTrue(targetCard.isHittable)
        try capture("extended_S36_target_fully_revealed_before_tap")
        targetCard.tap()
        _ = waitForScreen(37)

        for category in ["staff", "book", "smith", "familiar", "all"] {
            tap("ui48_target_category_" + category)
            let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_vault_target_"))
            XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 8), "S37 must expose real catalog targets for \(category)")
        }
        tap("ui48_target_category_staff")
        let targetOptions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_vault_target_"))
        XCTAssertGreaterThan(targetOptions.count, 1, "S37 must expose more than one actual staff target")
        let selectedID = targetOptions.element(boundBy: 1).identifier
        tap(selectedID)
        XCTAssertEqual(ticketText.exists, false, "Choosing a card must stay on S37 until explicit confirmation")
        _ = waitForScreen(37)
        try capture("extended_S37_target_preview_no_commit")
        tap("変更せず戻る")
        _ = waitForScreen(36)
        XCTAssertEqual(targetCard.label, originalGoal, "Cancelling target selection must discard the temporary choice")
        XCTAssertEqual(app.staticTexts["ui48_vault_free_balance"].label, beforeTickets)
        try capture("extended_S36_S37_target_selection_no_ticket_spend")
        app.terminate()
        launch(36)
        _ = waitForScreen(36)
        XCTAssertEqual(targetCard.label, originalGoal)
        XCTAssertEqual(app.staticTexts["ui48_vault_free_balance"].label, beforeTickets)
        try capture("extended_S36_target_cold_readback_no_ticket_spend")

        // Confirm the previously cancelled candidate once, after proving that
        // the ordinary cancel path retained the original target across reload.
        for _ in 0..<8 {
            if viewport.contains(targetCard.frame) { break }
            origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 20))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 20)))
        }
        XCTAssertTrue(viewport.contains(targetCard.frame))
        targetCard.tap()
        _ = waitForScreen(37)
        tap("ui48_target_category_staff")
        tap(selectedID)
        tap("この装備を目標に設定")
        let resetAlert = app.alerts["目標を切り替えますか？"]
        if resetAlert.waitForExistence(timeout: 2) {
            XCTAssertTrue(resetAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保証が解除されます")).firstMatch.exists)
            resetAlert.buttons["戻る"].tap()
            _ = waitForScreen(37)
            tap("この装備を目標に設定")
            XCTAssertTrue(resetAlert.waitForExistence(timeout: 5))
            resetAlert.buttons["切り替える"].tap()
        }
        _ = waitForScreen(36)
        waitForSave()
        let confirmedGoal = targetCard.label
        XCTAssertNotEqual(confirmedGoal, originalGoal, "Explicit confirmation must update the saved target")
        XCTAssertEqual(app.staticTexts["ui48_vault_free_balance"].label, beforeTickets)
        try capture("extended_S36_target_explicit_confirmed")
        app.terminate()
        launch(36)
        _ = waitForScreen(36)
        XCTAssertEqual(targetCard.label, confirmedGoal)
        XCTAssertEqual(app.staticTexts["ui48_vault_free_balance"].label, beforeTickets)
        try capture("extended_S36_target_confirmed_cold_readback")
    }

    func testShopProductDetailAndPurchaseStateRemainDisconnected() throws {
        launch(43)
        _ = waitForScreen(43)
        XCTAssertTrue(app.staticTexts["販売準備中です。価格・商品数・購入権利は未設定で、現在は購入できません。"].waitForExistence(timeout: 8))
        tap("ui48_shop_category_鑑定券")
        XCTAssertTrue(app.staticTexts["ui48_shop_tickets_unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["購入確認へ"].exists)
        try capture("extended_S43_tickets_unconnected")
        tap("提供割合・保証を見る")
        _ = waitForScreen(38)
        tap("ui48_back")
        _ = waitForScreen(43)
        tap("ui48_shop_category_便利機能")
        XCTAssertTrue(app.staticTexts["ui48_shop_convenience_unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["購入確認へ"].exists)
        try capture("extended_S43_convenience_unconnected")
        tap("設定を開く")
        _ = waitForScreen(46)
        tap("ui48_back")
        _ = waitForScreen(43)
        let furnitureCategory = app.buttons["ui48_shop_category_家具"]
        XCTAssertTrue(furnitureCategory.waitForExistence(timeout: 8))
        tap("ui48_shop_category_家具")
        let product = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "価格未設定／購入未接続")).firstMatch
        XCTAssertTrue(product.waitForExistence(timeout: 8), "Shop must show a real catalog product row without invented price data")
        product.tap()
        _ = waitForScreen(44)
        XCTAssertTrue(app.staticTexts["価格未設定／購入未接続"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["現行版は未接続"].waitForExistence(timeout: 8))
        tap("購入状態を見る")
        _ = waitForScreen(45)
        let purchase = app.buttons["購入確認へ"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 8))
        XCTAssertFalse(purchase.isEnabled, "Unconnected product must never start a transaction")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "購入権利は付与されません")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["隔離UI表示試験"].exists, "Ordinary shop navigation must never expose transaction-state fixtures")
        for status in ["確認中", "完了表示", "保留表示", "失敗表示", "復元表示"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", status)).firstMatch.exists,
                           "A disconnected ordinary purchase screen must not display the transaction-state example: \(status)")
        }
        try capture("extended_S43_S44_S45_shop_disconnected")
    }
}
