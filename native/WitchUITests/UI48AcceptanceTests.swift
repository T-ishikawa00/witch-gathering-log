import XCTest
import CryptoKit

/// UI48 evidence is split into capture-only coverage and behavioral acceptance.
/// Every launch is routed through the strict, UUID-keyed isolated QA gate.
final class UI48AcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var saveKey: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        saveKey = UUID().uuidString.lowercased()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground { app.terminate() }
    }

    private func launch(screen: Int? = nil, fixture: String? = nil) {
        var args = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + saveKey, "--qa-readback-save"]
        if let fixture { args.append("--ui48-fixture=" + fixture) }
        if let screen { args.append("--ui48-screen=\(screen)") }
        app.launchArguments = args
        app.launch()
    }

    private func waitForScreen(_ number: Int, timeout: TimeInterval = 25) -> XCUIElement {
        let id = String(format: "ui48_screen_%02d", number)
        let screen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id)).firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: timeout), "Expected UI48 screen \(number) (\(id))")
        XCTAssertFalse(app.staticTexts["この画面は準備中です"].exists, "Screen \(number) rendered the fallback placeholder")
        return screen
    }

    private func capture(_ name: String, evidence: String) throws {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        let executable = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let executableSHA = SHA256.hash(data: try Data(contentsOf: executable))
            .map { String(format: "%02x", $0) }.joined()
        let receipt: [String: String] = [
            "capture": name,
            "evidenceClass": evidence,
            "testCase": self.name,
            "saveKey": saveKey,
            "testExecutableSHA256": executableSHA,
            "launchArguments": app.launchArguments.joined(separator: " ")
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + "_identity"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Direct screen routing produces render evidence only. It does not establish that a screen's actions work.
    func testCaptureAll48ApprovedScreens() throws {
        let actionBackedResultScreens: Set<Int> = [3, 8, 9, 10, 26, 39]
        for number in 1...48 {
            if app.state == .runningForeground { app.terminate() }
            saveKey = UUID().uuidString.lowercased()
            let fixture: String
            switch number {
            case 1, 5: fixture = "fresh"
            case 2, 3: fixture = "gathering"
            case 20: fixture = "fresh"
            case 27: fixture = "empty"
            default: fixture = "full"
            }
            launch(screen: number, fixture: fixture)
            _ = waitForScreen(number, timeout: actionBackedResultScreens.contains(number) ? 150 : 25)
            var evidence = actionBackedResultScreens.contains(number) ? "isolated-real-engine-action" : "capture-only-direct-route"
            if number == 17 {
                // Capture the populated set variant after actual save commands,
                // using only this loop's isolated full-fixture save.
                for slot in 1...2 {
                    let saveSet = app.buttons["ui48_loadout_primary_\(slot)"]
                    reveal(saveSet)
                    XCTAssertTrue(saveSet.waitForExistence(timeout: 10), "S17 must expose actual primary-set save action \(slot)")
                    XCTAssertTrue(saveSet.isEnabled && saveSet.isHittable, "S17 set \(slot) must be saveable in the isolated fixture")
                    saveSet.tap()
                    waitForBusyCommandToFinish()
                }
                XCTAssertTrue(app.staticTexts["現在使用中"].waitForExistence(timeout: 8),
                              "S17 must reflect the saved active set after real save commands")
                app.scrollViews.firstMatch.swipeDown()
                evidence = "isolated-real-loadout-save"
            } else if number == 40 || number == 41 {
                // Populate the approved trial state through its real tile action;
                // keep explicit apply available but do not commit appearance.
                let previews = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_preview_"))
                reveal(previews.firstMatch)
                XCTAssertTrue(previews.firstMatch.waitForExistence(timeout: 10), "S\(number) must expose a catalog preview tile after scrolling")
                XCTAssertTrue(previews.firstMatch.isHittable, "S\(number) preview tile must be interactable")
                let tileID = previews.firstMatch.identifier.replacingOccurrences(of: "ui48_preview_", with: "")
                XCTAssertFalse(tileID.isEmpty)
                XCTAssertTrue(previews.firstMatch.label.contains("所持済み") || previews.firstMatch.label.contains("適用中"),
                              "The isolated full fixture must provide an owned catalog appearance for the capture")
                previews.firstMatch.tap()
                let trialState = app.staticTexts["試着中／まだ保存していません"]
                XCTAssertTrue(trialState.waitForExistence(timeout: 8), "S\(number) must show the actual temporary trial state")
                let apply = app.buttons["ui48_wardrobe_apply_" + tileID]
                let cancel = app.buttons["ui48_wardrobe_cancel_trial"]
                XCTAssertTrue(apply.waitForExistence(timeout: 8), "Owned trial must keep its explicit apply action visible")
                XCTAssertTrue(cancel.waitForExistence(timeout: 8), "Trial must keep its explicit cancel action visible")
                XCTAssertTrue(apply.isHittable && cancel.isHittable,
                              "The safe-area wardrobe dock actions must remain reachable independently of body scrolling")
                let scroll = app.scrollViews.firstMatch
                for _ in 0..<8 {
                    let center = CGPoint(x: trialState.frame.midX, y: trialState.frame.midY)
                    if trialState.isHittable && scroll.frame.intersection(app.frame).contains(center) { break }
                    scroll.swipeDown()
                }
                let heroCenter = CGPoint(x: trialState.frame.midX, y: trialState.frame.midY)
                XCTAssertTrue(trialState.isHittable && scroll.frame.intersection(app.frame).contains(heroCenter),
                              "S\(number) trial hero must be brought back into the visible scroll viewport before capture")
                evidence = "isolated-real-preview-no-apply"
            }
            assertScreenContent(number)
            waitForCaptureStability(number)
            try capture(String(format: "S%02d", number), evidence: evidence)
        }
    }

    func testFiveEntrancesNestedBackAndClose() throws {
        launch(fixture: "fresh")
        _ = waitForScreen(1)
        try capture("ui48_navigation_start_S01", evidence: "interaction")

        for (tab, screen) in [("探索", 4), ("仲間", 13), ("工房", 19), ("採集帳", 28), ("家", 1)] {
            let entrance = app.buttons["tab_" + tab]
            XCTAssertTrue(entrance.waitForExistence(timeout: 10), "Navigation entry missing: \(tab)")
            entrance.tap()
            _ = waitForScreen(screen)
        }

        let exploreAction = app.buttons["ui48_home_explore"]
        XCTAssertTrue(exploreAction.waitForExistence(timeout: 8))
        exploreAction.tap()
        _ = waitForScreen(4)
        let map = app.buttons["ui48_map"]
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        map.tap()
        _ = waitForScreen(5)
        let back = app.buttons["ui48_back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        _ = waitForScreen(4)
        app.buttons["tab_仲間"].tap()
        _ = waitForScreen(13)
        app.buttons["ui48_companion_inventory"].tap()
        _ = waitForScreen(14)
        let close = app.buttons["ui48_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        _ = waitForScreen(13)
        try capture("ui48_navigation_back_close", evidence: "interaction")
    }

    func testTrackingRecipeDoesNotConsumeAndPersistsAfterColdRelaunch() throws {
        launch(screen: 19, fixture: "fresh")
        _ = waitForScreen(19)
        let workshopReadouts = visibleMaterialReadouts()
        let recipeRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_recipe_"))
        XCTAssertTrue(recipeRows.firstMatch.waitForExistence(timeout: 10), "Fresh save must expose a real recipe option")
        recipeRows.firstMatch.tap()
        _ = waitForScreen(20)

        let before = visibleMaterialReadouts()
        let track = app.buttons["ui48_recipe_track"]
        XCTAssertTrue(track.waitForExistence(timeout: 8), "Recipe goal action must be available")
        track.tap()
        waitForBusyCommandToFinish()
        XCTAssertTrue(app.buttons["ui48_recipe_cancel"].waitForExistence(timeout: 10))
        XCTAssertEqual(visibleMaterialReadouts(), before, "Tracking a goal must not consume materials")
        app.buttons["ui48_recipe_cancel"].tap()
        _ = waitForScreen(19)
        XCTAssertTrue(app.staticTexts["制作の目標"].waitForExistence(timeout: 8), "Tracked goal should appear in the workshop")
        try capture("ui48_recipe_goal_saved_before_relaunch", evidence: "interaction-and-visible-save-state")

        app.terminate()
        launch(screen: 19)
        _ = waitForScreen(19)
        XCTAssertTrue(app.staticTexts["制作の目標"].waitForExistence(timeout: 10), "Tracked goal must survive a cold relaunch")
        XCTAssertEqual(visibleMaterialReadouts(), workshopReadouts, "Workshop material counts must remain unchanged after save reload")
        try capture("ui48_recipe_goal_cold_readback", evidence: "persistence-verified-visible-readback")
    }

    func testUnconnectedPurchaseAndDisplayOnlyStatesNeverEnablePurchase() throws {
        launch(screen: 45, fixture: "fresh")
        _ = waitForScreen(45)
        let purchase = app.buttons["購入確認へ"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 8))
        XCTAssertFalse(purchase.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "購入権利は付与されません")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["正式な商品・価格・購入確認先は未接続です。現在は購入できません。"].exists)
        try capture("ui48_purchase_S45_disconnected", evidence: "capture-and-disabled-control")

        let states: [(String, String)] = [
            ("完了表示", "購入権利や商品は付与されません"),
            ("キャンセル表示", "ゲーム状態は変更されません"),
            ("保留表示", "再購入を促しません"),
            ("失敗表示", "取引結果は作成されません"),
            ("復元表示", "権利の復元や付与は行いません")
        ]
        for (state, detail) in states {
            let fixture = app.buttons["ui48_purchase_fixture_" + state]
            XCTAssertTrue(fixture.waitForExistence(timeout: 8), "Missing display-only state control: \(state)")
            fixture.tap()
            XCTAssertFalse(purchase.isEnabled, "Purchase must stay disconnected in \(state)")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", detail)).firstMatch.waitForExistence(timeout: 5),
                          "Expected explicit no-transaction copy for \(state)")
            try capture("ui48_purchase_state_\(state)", evidence: "isolated-display-only-no-entitlement")
        }

        app.terminate()
        launch(screen: 45)
        _ = waitForScreen(45)
        let purchaseAfterRelaunch = app.buttons["購入確認へ"]
        XCTAssertTrue(purchaseAfterRelaunch.waitForExistence(timeout: 8))
        XCTAssertFalse(purchaseAfterRelaunch.isEnabled)
        XCTAssertTrue(app.staticTexts["正式な商品・価格・購入確認先は未接続です。現在は購入できません。"].exists)
        try capture("ui48_purchase_S45_after_cold_relaunch", evidence: "persistence-verified-disconnected-state")
    }

    func testWardrobePreviewCancelDoesNotPersist() throws {
        launch(screen: 40, fixture: "fresh")
        _ = waitForScreen(40)
        let previews = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_preview_"))
        reveal(previews.firstMatch)
        XCTAssertTrue(previews.firstMatch.waitForExistence(timeout: 10), "Wardrobe must show at least one previewable catalog entry")
        XCTAssertTrue(previews.firstMatch.isHittable, "A preview tile must be reachable after scrolling the wardrobe grid")
        let freshPreviewID = previews.firstMatch.identifier.replacingOccurrences(of: "ui48_preview_", with: "")
        XCTAssertFalse(freshPreviewID.isEmpty)
        previews.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["試着中／まだ保存していません"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未所有のため保存できません")).firstMatch.exists)
        try capture("ui48_wardrobe_temporary_preview", evidence: "interaction-preview-only")

        let cancelPreview = app.buttons["ui48_wardrobe_cancel_trial"]
        reveal(cancelPreview)
        XCTAssertTrue(cancelPreview.waitForExistence(timeout: 8), "The wardrobe must expose an explicit cancel-trial action")
        XCTAssertTrue(cancelPreview.isEnabled && cancelPreview.isHittable)
        cancelPreview.tap()
        XCTAssertTrue(app.staticTexts["現在の見た目"].waitForExistence(timeout: 8), "Cancelling a trial must restore the saved look")
        try capture("ui48_wardrobe_explicit_cancel", evidence: "interaction-cancel-preview-only")
        app.terminate()
        launch(screen: 40)
        _ = waitForScreen(40)
        XCTAssertTrue(app.staticTexts["現在の見た目"].waitForExistence(timeout: 8), "Cancelled preview must not become the saved look")
        let restoredFreshTile = app.buttons["ui48_preview_" + freshPreviewID]
        reveal(restoredFreshTile)
        XCTAssertTrue(restoredFreshTile.waitForExistence(timeout: 10), "The exact previewed catalog item must remain available after reload")
        XCTAssertTrue(restoredFreshTile.label.contains("未所有・試着のみ"), "A temporary preview must not grant cosmetic ownership")
        try capture("ui48_wardrobe_after_cancel_cold_relaunch", evidence: "persistence-verified-preview-not-saved")

        app.terminate()
        saveKey = UUID().uuidString.lowercased()
        launch(screen: 40, fixture: "full")
        _ = waitForScreen(40)
        let ownedPreviews = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_preview_"))
        reveal(ownedPreviews.firstMatch)
        XCTAssertTrue(ownedPreviews.firstMatch.waitForExistence(timeout: 10), "Full isolated fixture should expose catalog appearances")
        var selectedAppearanceID: String?
        for index in 0..<ownedPreviews.count {
            let tile = ownedPreviews.element(boundBy: index)
            let candidateID = tile.identifier.replacingOccurrences(of: "ui48_preview_", with: "")
            reveal(tile)
            guard tile.exists && tile.isHittable else { continue }
            tile.tap()
            let candidateApply = app.buttons["ui48_wardrobe_apply_" + candidateID]
            reveal(candidateApply)
            if candidateApply.waitForExistence(timeout: 3), candidateApply.isEnabled {
                selectedAppearanceID = candidateID
                break
            }
        }
        let appearanceID = try XCTUnwrap(selectedAppearanceID, "Fixture must provide an owned appearance that can be applied")
        let apply = app.buttons["ui48_wardrobe_apply_" + appearanceID]
        XCTAssertTrue(app.staticTexts["試着中／まだ保存していません"].waitForExistence(timeout: 5))
        reveal(apply)
        XCTAssertTrue(apply.isEnabled)
        XCTAssertTrue(apply.isHittable, "Owned appearance apply action must be reachable after scrolling")
        apply.tap()
        waitForBusyCommandToFinish()
        XCTAssertTrue(app.staticTexts["現在の見た目"].waitForExistence(timeout: 10), "Applying owned appearance should exit temporary preview")
        try capture("ui48_wardrobe_owned_apply", evidence: "interaction-save-backed-owned-appearance")

        app.terminate()
        launch(screen: 40)
        _ = waitForScreen(40)
        XCTAssertTrue(app.staticTexts["現在の見た目"].waitForExistence(timeout: 8))
        let restoredOwnedTile = app.buttons["ui48_preview_" + appearanceID]
        reveal(restoredOwnedTile)
        XCTAssertTrue(restoredOwnedTile.waitForExistence(timeout: 10),
                      "The applied owned appearance should remain in the catalog after cold relaunch")
        XCTAssertTrue(restoredOwnedTile.label.contains("適用中"), "The selected appearance must be visibly restored after cold relaunch")
        try capture("ui48_wardrobe_owned_cold_readback", evidence: "persistence-verified-owned-appearance")
    }

    func testFurniturePreviewFreeClaimApplyPersists() throws {
        launch(screen: 42, fixture: "fresh")
        _ = waitForScreen(42)
        // Stable catalog ID avoids depending on how SwiftUI combines the card's text labels.
        let desk = app.buttons["ui48_furniture_FURN_DESK_BOTANICAL"]
        reveal(desk)
        XCTAssertTrue(desk.waitForExistence(timeout: 10), "Furniture catalog must expose the explicitly free starter desk")
        XCTAssertTrue(desk.isHittable, "Starter desk card must be reachable in the furniture catalog")
        desk.tap()
        XCTAssertTrue(app.staticTexts["試し置き／未保存"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未所有／試し置きのみ")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "適用して保存することはできません")).firstMatch.waitForExistence(timeout: 5))
        let claim = app.buttons["ui48_furniture_claim_initial"]
        XCTAssertTrue(claim.waitForExistence(timeout: 5), "The clearly free starter furniture should have its explicit claim action")
        try capture("ui48_furniture_temporary_preview", evidence: "interaction-unowned-preview-no-save")

        app.buttons["ui48_furniture_cancel"].tap()
        XCTAssertTrue(app.staticTexts["現在の配置"].waitForExistence(timeout: 5), "Cancelling preview should restore the saved room view")
        desk.tap()
        let claimAfterCancel = app.buttons["ui48_furniture_claim_initial"]
        XCTAssertTrue(claimAfterCancel.waitForExistence(timeout: 5))
        claimAfterCancel.tap()
        waitForBusyCommandToFinish()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持済み／未配置")).firstMatch.waitForExistence(timeout: 10), "Free claim should grant only the catalogued starter furniture")
        XCTAssertTrue(app.buttons["ui48_furniture_apply"].waitForExistence(timeout: 5))
        app.buttons["ui48_furniture_apply"].tap()
        waitForBusyCommandToFinish()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持済み／配置中")).firstMatch.waitForExistence(timeout: 10), "Explicit apply should save placement for owned furniture")
        try capture("ui48_furniture_explicit_claim_and_apply", evidence: "interaction-save-backed-free-catalog-and-placement")

        app.terminate()
        launch(screen: 42)
        _ = waitForScreen(42)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所持済み／配置中")).firstMatch.waitForExistence(timeout: 10), "Owned furniture placement must survive cold relaunch")
        try capture("ui48_furniture_cold_relaunch", evidence: "persistence-verified-owned-placement")
    }

    func testWeaponAppearanceTrialCancelAndOwnedApplySurviveColdRelaunch() throws {
        launch(screen: 41, fixture: "full")
        _ = waitForScreen(41)
        let previews = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_preview_"))
        reveal(previews.firstMatch)
        XCTAssertTrue(previews.firstMatch.waitForExistence(timeout: 10), "Weapon appearance catalog must expose real entries")
        var chosenID: String?
        for index in 0..<previews.count {
            let tile = previews.element(boundBy: index)
            guard tile.exists else { continue }
            let id = tile.identifier.replacingOccurrences(of: "ui48_preview_", with: "")
            reveal(tile)
            guard tile.exists && tile.isHittable else { continue }
            tile.tap()
            let apply = app.buttons["ui48_wardrobe_apply_" + id]
            reveal(apply)
            if apply.exists && apply.isEnabled { chosenID = id; break }
            let cancel = app.buttons["ui48_wardrobe_cancel_trial"]
            if cancel.exists { cancel.tap() }
        }
        let id = try XCTUnwrap(chosenID, "Full isolated fixture must have an owned weapon appearance")
        XCTAssertTrue(app.descendants(matching: .any)["ui48_weapon_hero_" + id].waitForExistence(timeout: 8),
                      "The large weapon preview must follow the explicitly selected appearance")
        XCTAssertTrue(app.staticTexts["試着中／まだ保存していません"].waitForExistence(timeout: 8))
        let cancel = app.buttons["ui48_wardrobe_cancel_trial"]
        reveal(cancel)
        XCTAssertTrue(cancel.isEnabled && cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["現在の見た目"].waitForExistence(timeout: 8))
        try capture("ui48_weapon_preview_cancel", evidence: "interaction-preview-cancel-no-apply")

        let tile = app.buttons["ui48_preview_" + id]
        reveal(tile)
        XCTAssertTrue(tile.exists && tile.isHittable)
        tile.tap()
        XCTAssertTrue(app.staticTexts["試着中／まだ保存していません"].waitForExistence(timeout: 8))
        let apply = app.buttons["ui48_wardrobe_apply_" + id]
        reveal(apply)
        XCTAssertTrue(apply.isEnabled && apply.isHittable)
        apply.tap()
        waitForBusyCommandToFinish()
        app.terminate()
        launch(screen: 41)
        _ = waitForScreen(41)
        XCTAssertTrue(app.descendants(matching: .any)["ui48_weapon_hero_" + id].waitForExistence(timeout: 8),
                      "The large weapon preview must restore the saved appearance after relaunch")
        let restored = app.buttons["ui48_preview_" + id]
        reveal(restored)
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue(restored.label.contains("適用中"), "Explicitly applied weapon appearance must survive reload")
        try capture("ui48_weapon_appearance_cold_readback", evidence: "persistence-verified-owned-weapon-appearance")
    }

    func testJapaneseInventorySearchAndManyItemsScroll() throws {
        launch(screen: 14, fixture: "many")
        _ = waitForScreen(14)
        let itemButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_gear_"))
        XCTAssertTrue(itemButtons.firstMatch.waitForExistence(timeout: 10), "Many-item fixture must expose real gear cards")
        let search = app.textFields["ui48_gear_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "The inventory search must accept keyboard input")
        search.typeText("月")
        XCTAssertEqual(search.value as? String, "月", "Japanese input must reach the inventory filter")
        try capture("ui48_inventory_japanese_search", evidence: "interaction")

        let clear = app.buttons["消去"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "A nonempty search must expose an explicit clear action")
        clear.tap()
        XCTAssertEqual(search.value as? String, "装備名で探す", "Clear should restore the search placeholder")
        // On compact screens the keyboard covers the gear viewport. Use the
        // field's real Done action before anchoring a lazy-grid UUID; scrolling
        // while the keyboard is open can evict that UUID from the hierarchy.
        search.typeText("\n")
        let submitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [submitted], timeout: 5), .completed,
                       "Submitting inventory search must dismiss the native keyboard")

        let countReadout = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "所持 [0-9]+ 点")).firstMatch
        XCTAssertTrue(countReadout.waitForExistence(timeout: 5), "Inventory should report the live total count")
        let countDigits = countReadout.label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        XCTAssertGreaterThanOrEqual(Int(countDigits) ?? 0, 600, "The isolated many-item fixture must contain at least 600 real gear instances")

        // Prove the card grid itself moves in the
        // scroll container, rather than merely capturing its static count label.
        // Capture the card's stable UUID before scrolling. Reusing firstMatch would
        // allow XCTest to resolve a different lazy-grid card after the hierarchy moves.
        let firstCardID = itemButtons.firstMatch.identifier
        XCTAssertFalse(firstCardID.isEmpty, "Many-item card must expose its stable gear identifier")
        let firstCard = app.buttons[firstCardID]
        reveal(firstCard, attempts: 10)
        XCTAssertTrue(firstCard.isHittable, "Inventory gear cards must be reachable by scrolling")
        firstCard.tap()
        // The quality filters also have a ScrollView. Select the vertical
        // container that actually contains this stable UUID, not firstMatch.
        let inventoryScroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex
            .filter { $0.buttons[firstCardID].exists }
            .max { $0.frame.height < $1.frame.height }, "Inventory must provide a scrollable gear collection")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed,
                       "Selecting a gear card must dismiss inventory text input")
        let startingFrame = firstCard.frame
        func cardScrolledAboveViewport() -> Bool {
            !firstCard.exists || firstCard.frame.maxY < inventoryScroll.frame.minY
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<8 {
            if cardScrolledAboveViewport() { break }
            // Start in visible upper content, never in the bottom action dock.
            let top = inventoryScroll.frame.minY
            origin.withOffset(CGVector(dx: inventoryScroll.frame.midX, dy: top + 160))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: inventoryScroll.frame.midX, dy: top + 12)))
        }
        XCTAssertTrue(cardScrolledAboveViewport(), "Scrolling must move the selected UUID above the visible collection")
        if firstCard.exists { XCTAssertNotEqual(firstCard.frame, startingFrame, "The grid must move, not only dismiss the keyboard") }
        XCTAssertTrue(waitForScreen(14).exists)
        try capture("ui48_inventory_many_scrolled", evidence: "interaction-many-items-scroll")
    }

    func testEmptyInventoryExplainsStateAndKeepsNavigationAvailable() throws {
        launch(screen: 14, fixture: "empty")
        _ = waitForScreen(14)
        XCTAssertTrue(app.staticTexts["まだ、見つからないみたい。"].waitForExistence(timeout: 8))
        let clear = app.buttons["ui48_inventory_clear_filters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "Empty inventory must explain how to clear filters")
        XCTAssertTrue(app.buttons["ui48_inventory_close"].exists)
        try capture("ui48_inventory_empty", evidence: "empty-state-and-recovery-action")
        clear.tap()
        XCTAssertTrue(app.staticTexts["まだ、見つからないみたい。"].waitForExistence(timeout: 5), "A truly empty inventory remains empty after clearing filters")
        app.buttons["ui48_inventory_close"].tap()
        _ = waitForScreen(13)
        try capture("ui48_inventory_empty_closed", evidence: "interaction-back-navigation")
    }

    func testAudioSettingSurvivesColdRelaunchInIsolatedApp() throws {
        launch(screen: 46, fixture: "fresh")
        _ = waitForScreen(46)
        let music = app.sliders["ui48_music_volume"]
        reveal(music)
        XCTAssertTrue(music.waitForExistence(timeout: 8))
        XCTAssertTrue(music.isHittable)
        let beforeVolume = normalizedSliderValue(music)
        XCTAssertTrue(beforeVolume.isFinite && (0...1).contains(beforeVolume), "The live audio control must expose a valid starting value")
        let requestedVolume = beforeVolume < 0.5 ? 0.75 : 0.25
        music.adjust(toNormalizedSliderPosition: requestedVolume)
        let savedVolume = normalizedSliderValue(music)
        XCTAssertTrue(savedVolume.isFinite && (0...1).contains(savedVolume), "The live audio control must report a valid updated value")
        XCTAssertGreaterThanOrEqual(abs(savedVolume - beforeVolume), 0.1,
                                    "The live control must actually change the preference; XCTest slider gestures may quantize the requested position")
        try capture("ui48_settings_music_changed", evidence: "interaction")

        app.terminate()
        launch(screen: 46)
        _ = waitForScreen(46)
        let restoredMusic = app.sliders["ui48_music_volume"]
        XCTAssertTrue(restoredMusic.waitForExistence(timeout: 8), "Audio volume control must remain available after relaunch")
        XCTAssertEqual(normalizedSliderValue(restoredMusic), savedVolume, accuracy: 0.03,
                       "Audio preference should survive relaunch")
        try capture("ui48_settings_music_cold_readback", evidence: "persistence-verified-visible-readback")

        let musicMute = app.switches["ui48_music_mute"]
        let sfxMute = app.switches["ui48_sfx_mute"]
        XCTAssertTrue(musicMute.waitForExistence(timeout: 8), "Music mute control must be available")
        XCTAssertTrue(sfxMute.waitForExistence(timeout: 8), "SFX mute control must be available")
        musicMute.tap()
        sfxMute.tap()
        XCTAssertEqual(musicMute.value as? String, "1", "Music mute should turn on")
        XCTAssertEqual(sfxMute.value as? String, "1", "SFX mute should turn on")
        try capture("ui48_settings_both_mute_enabled", evidence: "interaction")

        app.terminate()
        launch(screen: 46)
        _ = waitForScreen(46)
        XCTAssertEqual(app.switches["ui48_music_mute"].value as? String, "1", "Music mute must persist after cold relaunch")
        XCTAssertEqual(app.switches["ui48_sfx_mute"].value as? String, "1", "SFX mute must persist after cold relaunch")
        try capture("ui48_settings_both_mute_cold_readback", evidence: "persistence-verified-visible-readback")
    }

    private func visibleMaterialReadouts() -> [String] {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/"))
            .allElementsBoundByIndex.map(\.label).sorted()
    }

    private func reveal(_ element: XCUIElement, attempts: Int = 8) {
        // Lazy SwiftUI grids do not materialize off-screen controls. Never query
        // identifier, label, or frame until the element exists in the snapshot.
        var scroll: XCUIElement?
        for _ in 0..<attempts {
            guard element.exists else {
                // A horizontal actor/category strip can coexist with the page.
                // Until a lazy tile exists, scroll the largest visible viewport;
                // choosing nil here would perform no gesture at all.
                let page = app.scrollViews.allElementsBoundByIndex.max {
                    $0.frame.intersection(app.frame).height < $1.frame.intersection(app.frame).height
                }
                if let page { page.swipeUp() } else { app.swipeUp() }
                continue
            }
            do {
                let identifier = element.identifier
                let type = element.elementType
                let label = element.label
                let matches = app.scrollViews.allElementsBoundByIndex.filter { candidate in
                    let descendants = candidate.descendants(matching: type)
                    if !identifier.isEmpty { return descendants.matching(identifier: identifier).firstMatch.exists }
                    return descendants.matching(NSPredicate(format: "label == %@", label)).firstMatch.exists
                }
                scroll = matches.max {
                    $0.frame.intersection(app.frame).height < $1.frame.intersection(app.frame).height
                }
            }
            let frame = element.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
            if element.isHittable && viewport.contains(center) { return }
            if let scroll {
                if frame.midY < scroll.frame.minY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            } else if frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        guard element.exists else {
            XCTFail("Target did not materialize after scrolling")
            return
        }
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let viewport = scroll?.frame.intersection(app.frame) ?? app.frame
        XCTAssertTrue(element.exists && element.isHittable && viewport.contains(center),
                      "Target must be visible and reachable after scrolling: \(element.identifier)")
    }

    private func normalizedSliderValue(_ slider: XCUIElement) -> Double {
        let raw = (slider.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("%"), let percent = Double(raw.dropLast()) { return percent / 100 }
        return Double(raw) ?? .nan
    }

    private func assertScreenContent(_ number: Int) {
        let titles: [Int: String] = [
            1: "魔女の家", 2: "魔女の家", 3: "森からの持ち帰り", 5: "旅の地図", 6: "森でできること",
            9: "戦いの記録", 10: "戦いの記録", 11: "新しい地域", 12: "採集先を変える",
            13: "仲間", 14: "持ちもの", 15: "装備の詳細", 16: "装備を比べる", 17: "装備セット",
            18: "持ちものを整理", 19: "小さな工房", 20: "制作の準備", 21: "制作する", 22: "分岐進化",
            23: "装備の強化", 24: "装備の研成", 25: "品質を高める", 26: "工房からの贈りもの",
            27: "持ちもの", 28: "採集帳", 29: "素材の記録", 30: "魔物の記録", 31: "暮らしと冒険の研究",
            32: "研究の準備", 33: "15の研究課題", 34: "研究課題", 35: "LR装備の収集帳",
            36: "星灯りの魔導庫", 37: "探す装備を選ぶ", 38: "提供割合と保証", 39: "鑑定の結果",
            40: "衣装の試着", 41: "武器の外観", 42: "模様替え", 43: "森の小さな商店",
            44: "商品の詳細", 45: "購入の確認", 46: "設定", 47: "保存の確認", 48: "魔女の採集帳"
        ]
        if let title = titles[number] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "S\(number) did not show its screen title: \(title)")
        }
        if number == 4 {
            XCTAssertTrue(app.buttons["ui48_map"].waitForExistence(timeout: 5), "S04 must expose the actual regional map action")
        }
        if number == 7 {
            XCTAssertTrue(app.staticTexts["4人で挑戦"].waitForExistence(timeout: 5), "S07 must show the selected enemy encounter detail")
        }
        let requiredCopy: [Int: String] = [
            3: "おかえりなさい。",
            8: "完全自動戦闘",
            9: "森に、道がひらけた。",
            10: "旅は、まだ続く。",
            26: "次の冒険の、相棒に。",
            39: "今回届いた装備"
        ]
        guard let copy = requiredCopy[number] else { return }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", copy)).firstMatch.waitForExistence(timeout: 8),
                      "Screen S\(number) did not show its expected result content")
        if number == 39 {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "今回届いた装備　[1-5]点")).firstMatch.waitForExistence(timeout: 8),
                          "S39 must show a nonempty actual isolated draw result")
        }
    }

    private func waitForBusyCommandToFinish(timeout: TimeInterval = 15) {
        let busy = app.descendants(matching: .any)["ui48_busy"]
        guard busy.waitForExistence(timeout: 1) else { return }
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: timeout), .completed, "Save-backed action did not finish")
    }

    private func waitForCaptureStability(_ number: Int) {
        // Keep S08 live: its purpose is to capture the actual automatic battle.
        guard number != 8 else { return }
        let busy = app.descendants(matching: .any)["ui48_busy"]
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 30), .completed,
                       "S\(number) command must finish before its image is captured")

        // S10's persistent defeat guidance shares copy with earlier notices. Wait only for
        // the root's explicitly transient overlay, so persistent result guidance is retained.
        guard [3, 9, 10, 26, 39].contains(number) else { return }
        let notice = app.descendants(matching: .any)["ui48_notice"]
        guard notice.waitForExistence(timeout: 0.4) else { return }
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 8), .completed,
                       "S\(number) should be captured after its transient notice disappears")
    }
}
