import XCTest

/// UI-only coverage for the R122 post-clear ResearchView. All progression is
/// explicitly synthetic QA fixture data; this suite is not earned-play evidence.
final class PostClearResearchR122UITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate() }

    func testCompletedCampaignChallengeFirstClearAndReplayLarge() {
        runChallengeReplay(category: "UICTContentSizeCategoryL")
    }

    func testCompletedCampaignChallengeFirstClearAndReplayAXXXL() {
        runChallengeReplay(category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    func testTrackedGatherShortageRoutesToSourceConfirmationLarge() {
        let key = "recipe-goal-r037-" + UUID().uuidString
        launch(arguments: recipeGoalArguments(key: key, scenario: "gather-shortage", category: "UICTContentSizeCategoryL", screen: "採集帳"))
        XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout: 20))

        let detail = app.buttons["post_clear_recipe_detail"]
        reveal(detail)
        XCTAssertTrue(detail.exists, "the persisted tracked recipe must offer a path to its catalog detail")
        let shortage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "琥珀樹脂：あと")).firstMatch
        reveal(shortage, interactive: false)
        XCTAssertTrue(shortage.exists, "the synthetic R037 fixture has no seeded R01 G3 material")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "採集先：")).firstMatch.exists)
        capture("gather_shortage_in_research", key)

        detail.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 10))
        let material = app.descendants(matching: .any).matching(identifier: "goal_material_M_R01_G3").firstMatch
        reveal(material, interactive: false)
        XCTAssertTrue(material.exists)
        let source = app.buttons["goal_gather_source_M_R01_G3_R01"]
        reveal(source)
        XCTAssertTrue(source.isEnabled, "the existing catalog says R01 is an unlocked source")
        capture("gather_source_detail_before_route", key)
        source.tap()
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["recipe_gather_handoff_summary"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["recipe_gather_apply"].exists,
                      "navigation presents an explicit confirmation; this test does not apply the route")
        capture("gather_source_confirmation_not_applied", key)
        identity(key, classification: "SYNTHETIC_QA_FIXTURE_NOT_EARNED", detail: "R037 gather-shortage; route confirmation shown, apply not tapped")
    }

    func testCompletedCampaignEvolutionGoalKeepsParentChoiceExplicitAXXXL() {
        let key = challengeKey()
        launch(arguments: challengeArguments(key: key, category: "UICTContentSizeCategoryAccessibilityXXXL", screen: "採集帳"))
        let choose = app.buttons["post_clear_choose_recipe"]
        reveal(choose)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "30 / 30")).firstMatch.exists,
                      "the endgame fixture sets all campaign encounter IDs; it is not an earned clear")
        choose.tap()
        XCTAssertTrue(app.buttons["workshop_mode_evolve_in_place"].waitForExistence(timeout: 10))
        let evolutionMode = app.buttons["workshop_mode_evolve_in_place"]
        reveal(evolutionMode)
        evolutionMode.tap()

        let recipe = app.buttons["recipe_detail_RC_EQ_W_G1"]
        reveal(recipe, timeout: 40)
        XCTAssertTrue(recipe.exists, "RC_EQ_W_G1 evolves the existing starter EQ_W_01 through normal catalog content")
        recipe.tap()
        let parent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recipe_parent_")).firstMatch
        reveal(parent, scroll: app.scrollViews["sheet_scroll_制作目標"], timeout: 40)
        XCTAssertTrue(parent.exists, "an owned matching source must be selected explicitly")
        assert44(parent)
        capture("evolution_parent_unselected", key)
        parent.tap()
        XCTAssertTrue(app.staticTexts["recipe_selected_parent"].waitForExistence(timeout: 8))
        let track = app.buttons["track_recipe_goal"]
        reveal(track, scroll: app.scrollViews["sheet_scroll_制作目標"])
        assert44(track)
        track.tap()
        XCTAssertTrue(app.staticTexts["recipe_goal_selected"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["goal_evolve"].exists)
        XCTAssertFalse(app.buttons["goal_evolve"].isEnabled,
                       "the fixture does not seed evolution materials; the test must not fabricate a ready state")
        capture("evolution_goal_tracked_with_explicit_parent", key)

        app.buttons["閉じる"].tap()
        selectTab("採集帳")
        let reopen = app.buttons["post_clear_recipe_detail"]
        reveal(reopen)
        reopen.tap()
        let reselectedParent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recipe_parent_")).firstMatch
        reveal(reselectedParent, scroll: app.scrollViews["sheet_scroll_制作目標"], timeout: 40)
        XCTAssertTrue(reselectedParent.exists, "opening from the saved ResearchView goal retains the recipe, while the source gear remains an explicit choice")
        XCTAssertFalse(app.buttons["goal_evolve"].exists, "the detail sheet must not silently choose an evolution source")
        capture("evolution_goal_reopened_parent_still_explicit", key)
        identity(key, classification: "SYNTHETIC_QA_FIXTURE_NOT_EARNED", detail: "challenge fixture campaign-complete; catalog recipe RC_EQ_W_G1; source not evolved")
    }

    private func runChallengeReplay(category: String) {
        let key = challengeKey()
        launch(arguments: challengeArguments(key: key, category: category, screen: "採集帳"))
        let campaign = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "30 / 30")).firstMatch
        reveal(campaign, interactive: false)
        XCTAssertTrue(campaign.exists, "this fixture marks campaign encounter IDs complete only for a synthetic endgame UI scenario")
        jumpToChallengeSection(key)
        let firstRewardCopy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "初回達成時に課題の報酬を受け取れます")).firstMatch
        reveal(firstRewardCopy, interactive: false, timeout: 20)
        XCTAssertTrue(firstRewardCopy.exists)
        let challenge = app.buttons["challenge_CH_R01_01"]
        reveal(challenge)
        assert44(challenge)
        challenge.tap()
        XCTAssertTrue(app.staticTexts["研究課題を達成しました。"].waitForExistence(timeout: 100))
        capture("challenge_first_clear", key)
        let dustAfterFirst = readDustThroughExistingInventory()
        XCTAssertGreaterThan(dustAfterFirst, 0, "catalog first-clear powder is granted on the first actual challenge dispatch")

        selectTab("採集帳")
        jumpToChallengeSection(key)
        let replayNote = app.staticTexts["challenge_replay_note_CH_R01_01"]
        reveal(replayNote, interactive: false)
        XCTAssertTrue(replayNote.exists)
        XCTAssertTrue(replayNote.label.contains("初回達成報酬は再付与されません"))
        let replay = app.buttons["challenge_CH_R01_01"]
        reveal(replay)
        XCTAssertEqual(replay.label, "もう一度挑む")
        assert44(replay)
        capture("challenge_replay_before_dispatch", key)
        replay.tap()
        XCTAssertTrue(app.staticTexts["研究課題を達成しました。"].waitForExistence(timeout: 100))
        let dustAfterReplay = readDustThroughExistingInventory()
        XCTAssertEqual(dustAfterReplay, dustAfterFirst, "replaying an already-cleared challenge must not award first-clear powder again")
        capture("challenge_replay_powder_unchanged", key)
        identity(key, classification: "SYNTHETIC_QA_FIXTURE_NOT_EARNED", detail: "QAScenarios.challenge seeds all campaign bosses/unlocks; actual challenge CH_R01_01 is dispatched twice")
    }

    private func jumpToChallengeSection(_ key: String) {
        let jump = app.buttons["research_section_jump_challenges_r125"]
        reveal(jump)
        assert44(jump)
        jump.tap()
        let heading = app.staticTexts["research_section_challenges_r125"]
        XCTAssertTrue(heading.waitForExistence(timeout: 8))
        let scroll = app.scrollViews["workshop_scroll"]
        let viewport = scroll.frame
        let deadline = Date().addingTimeInterval(5)
        var headingVisible = false
        while Date() < deadline {
            let frame = heading.frame
            let visible = viewport.intersection(frame)
            if frame.height > 0 && frame.width > 0 && !visible.isNull && visible.height >= frame.height - 1 && visible.width >= frame.width - 1 { headingVisible = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(headingVisible, "the jump must place the real challenge section heading in view")
        capture("challenge_section_jump", key)
    }

    private func readDustThroughExistingInventory() -> Int {
        selectTab("仲間")
        app.buttons["companion_C_WITCH"].tap()
        let inventory = app.buttons["inventory"]
        let activeScroll = app.scrollViews["workshop_scroll"].exists
            ? app.scrollViews["workshop_scroll"]
            : app.scrollViews.firstMatch
        if activeScroll.exists {
            reveal(inventory, scroll: activeScroll)
        } else {
            XCTAssertTrue(inventory.waitForExistence(timeout: 8), "the Companion summary must expose its inventory action")
            let window = app.windows.firstMatch
            XCTAssertTrue(window.exists)
            let frame = inventory.frame
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertTrue(window.frame.contains(frame), "the non-scrollable Companion action must be fully inside the app viewport")
            assert44(inventory)
        }
        inventory.tap()
        let dust = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "研成の粉")).firstMatch
        XCTAssertTrue(dust.waitForExistence(timeout: 8), "read the normal inventory projection; no QA economy endpoint is used")
        let digits = dust.label.split(separator: " ").last.map(String.init) ?? ""
        XCTAssertNotNil(Int(digits), "unexpected inventory powder label: \(dust.label)")
        let result = Int(digits) ?? -1
        app.buttons["閉じる"].tap()
        return result
    }

    private func launch(arguments: [String]) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout: 25))
    }

    private func selectTab(_ name: String) {
        let direct = app.buttons["tab_" + name]
        if direct.exists && direct.isHittable {
            direct.tap()
            return
        }
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "the adaptive accessibility footer should expose its current-tab menu")
        menu.tap()
        let destination = app.buttons["choose_tab_" + name]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
    }

    private func challengeKey() -> String { "post-clear-r122-" + UUID().uuidString }

    private func challengeArguments(key: String, category: String, screen: String) -> [String] {
        ["-UIPreferredContentSizeCategoryName", category,
         "--qa-isolated", "--qa-save-key=" + key,
         "--qa-fixture=challenge", "--qa-persist-fixture", "--screen=" + screen]
    }

    private func recipeGoalArguments(key: String, scenario: String, category: String, screen: String) -> [String] {
        ["-UIPreferredContentSizeCategoryName", category,
         "--qa-isolated", "--qa-save-key=" + key,
         "--qa-fixture=recipe-goal-r037", "--qa-recipe-goal=" + scenario,
         "--qa-persist-fixture", "--qa-recipe-goal-baseline", "--screen=" + screen]
    }

    private func reveal(_ element: XCUIElement, scroll explicitScroll: XCUIElement? = nil,
                        interactive: Bool = true, timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        var steps = 0
        while Date() < deadline {
            let scroll = explicitScroll ?? (app.scrollViews["workshop_scroll"].exists ? app.scrollViews["workshop_scroll"] : app.scrollViews.firstMatch)
            guard scroll.waitForExistence(timeout: 2) else { break }
            let viewport = scroll.frame.insetBy(dx: 1, dy: 2)
            if element.exists && !element.frame.isEmpty {
                let frame = element.frame
                let visible = interactive ? viewport.contains(frame) : viewport.intersects(frame)
                if visible && (!interactive || element.isHittable) { return }
            }
            let towardEnd = element.exists && !element.frame.isEmpty
                ? element.frame.midY >= viewport.midY : (steps % 3 != 1)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardEnd ? 0.70 : 0.30))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardEnd ? 0.42 : 0.58))
            start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
            steps += 1
        }
        let diagnostic = XCTAttachment(string: "target=\(element.identifier) exists=\(element.exists) frame=\(element.exists ? element.frame : .zero)\n\(app.debugDescription)")
        diagnostic.name = "post_clear_r122_missing_\(UUID().uuidString)"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTFail("target was not fully exposed in its active scroll view")
    }

    private func assert44(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func capture(_ name: String, _ key: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "post_clear_r122_\(name)_\(key)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func identity(_ key: String, classification: String, detail: String) {
        let attachment = XCTAttachment(string: "saveKey=\(key)\nclassification=\(classification)\ndetail=\(detail)\nseeded earned progression=false")
        attachment.name = "post_clear_r122_identity_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
