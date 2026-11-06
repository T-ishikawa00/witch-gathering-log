import XCTest
import CryptoKit

/// Exercises host-prepared save states through the real isolated startup path.
/// These tests deliberately omit screen/fixture routing for recovery cases so a
/// missing host fixture fails instead of being replaced by a synthetic state.
final class UI48EnvironmentAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!
    private var saveKey = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground { app.terminate() }
    }

    private func launch(key: String, fixture: String? = nil, largeText: Bool = false) {
        saveKey = key
        app = XCUIApplication()
        app.launchArguments = ["--ui48-qa", "--qa-isolated", "--qa-save-key=" + key,
                              "--qa-readback-save"]
        if let fixture { app.launchArguments.append("--ui48-fixture=" + fixture) }
        // Content size is set and recorded by the host's simctl UI setting.
        // Do not introduce unvalidated value arguments into the strict QA gate.
        app.launch()
    }

    private func faultSaveKey(slot: Int) throws -> String {
        let raw = Bundle(for: type(of: self)).object(forInfoDictionaryKey: "UI48FaultRun")
        let run: Int?
        if let number = raw as? NSNumber { run = number.intValue }
        else if let text = raw as? String { run = Int(text) }
        else { run = nil }
        guard let run, run > 0, (47...49).contains(slot) else {
            XCTFail("Missing or invalid UI48FaultRun in the frozen UI test bundle; refusing to use a shared save key")
            throw NSError(domain: "UI48FaultRun", code: 1)
        }
        return String(format: "48000000-0000-4000-8000-%04d%08d", run, slot)
    }

    @discardableResult
    private func screen(_ number: Int, timeout: TimeInterval = 30) -> XCUIElement {
        let identifier = String(format: "ui48_screen_%02d", number)
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected real startup/navigation state S\(number) (\(identifier)); host-prepared save fixture may be missing")
        return element
    }

    private func homeScreen(timeout: TimeInterval = 30) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["ui48_screen_01", "ui48_screen_02"])
        ).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Recovery must continue to a real home state S01 or S02")
        XCTAssertFalse(app.staticTexts["この画面は準備中です"].exists)
        return element
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 12) {
        let control = app.buttons[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: timeout), "Expected actionable control \(identifier)")
        XCTAssertTrue(control.isEnabled, "Expected enabled control \(identifier)")
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !control.isHittable {
            let frame = control.frame
            if scroll.exists {
                if frame.midY < scroll.frame.minY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            } else if frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(control.isHittable, "Expected reachable control \(identifier)")
        control.tap()
    }

    private func capture(_ name: String) throws {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)

        let executable = try XCTUnwrap(Bundle(for: type(of: self)).executableURL)
        let sha = SHA256.hash(data: try Data(contentsOf: executable))
            .map { String(format: "%02x", $0) }.joined()
        let receipt: [String: String] = [
            "capture": name,
            "testCase": self.name,
            "saveKey": saveKey,
            "testExecutableSHA256": sha,
            "launchArguments": app.launchArguments.joined(separator: " "),
            "evidenceClass": "host-prepared-isolated-save-runtime"
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        json.name = name + "_identity"
        json.lifetime = .keepAlways
        add(json)
    }

    private func launchError() -> XCUIElement {
        app.staticTexts["ui48_launch_error"]
    }

    private func retryFailedLoad() {
        tap("もう一度読み込む")
        // Loading may complete between accessibility snapshots for a small local
        // file. Its absence here cannot establish a failed retry.
        XCTAssertTrue(launchError().waitForExistence(timeout: 30),
                      "Retry should settle back into the failed-load screen")
    }

    func testCorruptPrimaryUsesPreviousThenCommitsAndReadsBack() throws {
        let key = try faultSaveKey(slot: 47)
        launch(key: key)
        _ = screen(47)
        XCTAssertTrue(app.staticTexts["直前の正常な保存"].exists,
                      "The preseeded corrupt-primary/valid-previous fixture must actually restore its previous generation")
        XCTAssertTrue(app.staticTexts["保全しています"].exists,
                      "Recovery must retain the original damaged generation")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "直前の正常なセーブから復元しました")).firstMatch.exists,
                      "S47 must explain that recovery loaded the previous valid save")
        try capture("environment_corrupt_primary_recovered_S47")

        tap("内容を確認して続ける")
        _ = homeScreen()
        app.buttons["tab_工房"].tap()
        _ = screen(19)
        let recipeRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ui48_recipe_"))
        XCTAssertTrue(recipeRows.firstMatch.waitForExistence(timeout: 12), "Recovered game must expose its real workshop recipes")
        recipeRows.firstMatch.tap()
        _ = screen(20)
        tap("ui48_recipe_track")
        let busy = app.descendants(matching: .any)["ui48_busy"]
        if busy.waitForExistence(timeout: 1) {
            let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 30), .completed, "Goal tracking did not finish saving")
        }
        tap("ui48_recipe_cancel")
        _ = screen(19)
        XCTAssertTrue(app.staticTexts["制作の目標"].waitForExistence(timeout: 10), "The explicit tracked-goal command should be visible in the workshop")
        try capture("environment_recovered_save_commit_S19")

        app.terminate()
        launch(key: key)
        _ = homeScreen()
        app.buttons["tab_工房"].tap()
        _ = screen(19)
        XCTAssertTrue(app.staticTexts["制作の目標"].waitForExistence(timeout: 10), "The committed gameplay change must survive reload of the isolated key")
        try capture("environment_recovery_commit_readback_S19")
    }

    func testInvalidPrimaryAndPreviousRemainFailedAcrossRetry() throws {
        let key = try faultSaveKey(slot: 48)
        launch(key: key)
        _ = screen(48)
        XCTAssertTrue(app.staticTexts["準備を完了できませんでした"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["旅の記録を読み込んでいます。保存内容を確認してから、家へ進みます。"].exists,
                       "Terminal load failure must not retain an in-progress loading explanation")
        XCTAssertTrue(app.staticTexts["セーブは変更していません。読み込みをやり直せます。"].exists,
                      "Both-invalid fixture must show the real non-mutating startup failure")
        let initialDiagnostic = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "noValidRecoveryGeneration")).firstMatch
        XCTAssertTrue(initialDiagnostic.waitForExistence(timeout: 8), "Both-invalid host fixture must fail with the recovery-generation diagnostic")
        try capture("environment_both_invalid_failed_S48")

        retryFailedLoad()
        _ = screen(48, timeout: 30)
        XCTAssertTrue(initialDiagnostic.waitForExistence(timeout: 8), "Retry must not manufacture a valid save from invalid generations")
        tap("詳しい状態を見る")
        _ = screen(47)
        XCTAssertTrue(app.staticTexts["失敗"].exists)
        XCTAssertTrue(app.staticTexts["未確定"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "noValidRecoveryGeneration")).firstMatch.exists)
        XCTAssertFalse(app.buttons["内容を確認して続ける"].exists, "A failed load must not offer continuation")
        try capture("environment_both_invalid_details_S47")
    }

    func testFutureSchemaIsPreservedAndNeverOverwrittenByRetryOrDetails() throws {
        let key = try faultSaveKey(slot: 49)
        launch(key: key)
        _ = screen(48)
        XCTAssertTrue(app.staticTexts["準備を完了できませんでした"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["旅の記録を読み込んでいます。保存内容を確認してから、家へ進みます。"].exists,
                       "Terminal load failure must not retain an in-progress loading explanation")
        XCTAssertTrue(launchError().label.contains("対応していない形式"), "Future-schema failure must be explained to the player")
        let futureDiagnostic = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "unsupportedFutureSchemaVersion")).firstMatch
        XCTAssertTrue(futureDiagnostic.waitForExistence(timeout: 8), "Preseeded future schema must reach the real future-version decoder path")
        try capture("environment_future_schema_failed_S48")

        retryFailedLoad()
        _ = screen(48, timeout: 30)
        XCTAssertTrue(futureDiagnostic.waitForExistence(timeout: 8), "Retry must preserve and reject the same unsupported schema")
        tap("詳しい状態を見る")
        _ = screen(47)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "unsupportedFutureSchemaVersion")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["失敗"].exists)
        XCTAssertFalse(app.buttons["内容を確認して続ける"].exists, "Unsupported future saves must never continue through the failed-load screen")
        try capture("environment_future_schema_details_S47")
    }

    func testLargeTextNavigationJapaneseEmptySearchAndSettings() throws {
        let key = UUID().uuidString.lowercased()
        launch(key: key, fixture: "full", largeText: true)
        _ = screen(1)
        let goal = app.buttons["ui48_home_goal"]
        let guidance = app.staticTexts["ui48_home_guidance"]
        XCTAssertTrue(goal.waitForExistence(timeout: 8))
        XCTAssertTrue(guidance.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(goal.frame.maxY, guidance.frame.minY,
                                 "Expanded home guidance must flow below the goal, never cover its actionable card")
        let expandedTitle = app.staticTexts["ui48_goal_accessibility_title"]
        if expandedTitle.exists {
            XCTAssertGreaterThanOrEqual(expandedTitle.frame.width, goal.frame.width * 0.75,
                                        "Decorative icons must not squeeze the enlarged goal into a narrow text column")
        }
        try capture("environment_large_text_home_S01")

        for (tab, number) in [("探索", 4), ("仲間", 13), ("工房", 19), ("採集帳", 28)] {
            let entrance = app.buttons["tab_" + tab]
            XCTAssertTrue(entrance.waitForExistence(timeout: 10), "Missing primary entrance \(tab)")
            XCTAssertTrue(entrance.isHittable, "Primary entrance \(tab) must remain reachable with accessibility text size")
            XCTAssertLessThanOrEqual(entrance.frame.height, 96,
                                     "Navigation labels must not become vertical stacks that consume the content viewport")
            entrance.tap()
            let heading = screen(number)
            XCTAssertLessThanOrEqual(heading.frame.height, 110,
                                     "Pinned screen heading must leave room for scrollable game content at maximum text size")
            try capture("environment_large_text_\(tab)_S\(number)")
        }
        app.buttons["tab_仲間"].tap()
        _ = screen(13)
        tap("ui48_companion_inventory")
        _ = screen(14)
        let search = app.textFields["ui48_gear_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Inventory search should remain reachable under large text")
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Japanese search must open the native keyboard")
        search.typeText("存在しない装備\n")
        XCTAssertEqual(search.value as? String, "存在しない装備", "Committed Japanese input should be retained by the real search field")
        XCTAssertTrue(app.staticTexts["まだ、見つからないみたい。"].waitForExistence(timeout: 8), "Unmatched committed query must render the real empty result state")
        try capture("environment_large_text_japanese_empty_search_S14")
        tap("ui48_inventory_clear_filters")
        XCTAssertFalse(app.staticTexts["まだ、見つからないみたい。"].waitForExistence(timeout: 2), "Clearing search should restore the real inventory results")

        // Settings is intentionally a home-header action. Return through the
        // ordinary base entrance instead of expecting a settings button on S14.
        tap("ui48_close")
        _ = screen(13)
        tap("tab_家")
        _ = screen(1)
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Settings route should remain available")
        settings.tap()
        _ = screen(46)
        let music = app.sliders["ui48_music_volume"]
        XCTAssertTrue(music.waitForExistence(timeout: 8), "Settings volume control should exist under large text")
        XCTAssertTrue(music.isHittable, "Settings control should remain reachable under large text")
        let before = music.value as? String
        music.adjust(toNormalizedSliderPosition: 0.37)
        XCTAssertNotEqual(music.value as? String, before, "Changing the live volume slider should update its displayed value")
        try capture("environment_large_text_settings_slider_S46")
    }
}
