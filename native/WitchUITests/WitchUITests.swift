import XCTest
final class WitchUITests:XCTestCase {
    let app=XCUIApplication()
    override func setUpWithError() throws {continueAfterFailure=false;app.launchArguments=["--qa-isolated","--qa-save-key=ui-"+UUID().uuidString];app.launch()}
    func capture(_ name:String){let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
    func openExploreControls() {
        let button=app.buttons["explore_controls"]
        if button.waitForExistence(timeout:5) { button.tap() }
    }
    func testExploreCompactActionsIncludePaddingInHitArea() {
        // At accessibility Dynamic Type sizes the five-tab bar becomes a
        // single menu. Follow the same adaptive route used by the navigation
        // regression instead of assuming `tab_探索` is initially exposed.
        let exploreTab=app.buttons["tab_探索"]
        if exploreTab.waitForExistence(timeout:3) {
            exploreTab.tap()
        } else {
            let menu=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","画面を選ぶ、")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout:15),"Adaptive navigation menu must be available")
            menu.tap()
            let chooseExplore=app.buttons["choose_tab_探索"]
            XCTAssertTrue(chooseExplore.waitForExistence(timeout:5))
            chooseExplore.tap()
        }
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout:10))
        let collect=app.buttons["claim_offline"]
        let controls=app.buttons["explore_controls"]
        XCTAssertTrue(collect.waitForExistence(timeout:10))
        XCTAssertTrue(controls.waitForExistence(timeout:5))
        let footer=app.buttons["tab_探索"]
        // Scroll the Explore ScrollView until both actions fit completely in
        // the area above the fixed footer, not merely until XCUI reports a
        // partially intersecting element as hittable.
        var fullyVisible=false
        for _ in 0..<10 {
            let footerTop=footer.frame.minY
            let collectFrame=collect.frame
            let controlsFrame=controls.frame
            let viewportTop=app.frame.minY
            if collect.isHittable && controls.isHittable &&
                collectFrame.minY >= viewportTop && controlsFrame.minY >= viewportTop &&
                collectFrame.maxY <= footerTop && controlsFrame.maxY <= footerTop {
                fullyVisible=true
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(fullyVisible,"Both compact Explore actions must be fully visible above the fixed navigation before tapping")
        for button in [collect,controls] {
            XCTAssertGreaterThanOrEqual(button.frame.height,44)
            XCTAssertGreaterThanOrEqual(button.frame.width,44)
            XCTAssertTrue(button.isHittable)
        }
        let geometry=XCTAttachment(string:"collect=\(collect.frame)\ncontrols=\(controls.frame)\nfooter=\(footer.frame)")
        geometry.name="explore_compact_action_hit_frames";geometry.lifetime = .keepAlways;add(geometry)
        capture("explore_compact_action_hit_frames")
        // Exercise the padded area above the visible caption, not its center.
        collect.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.08)).tap()
        XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout:5))
        capture("explore_collect_padding_tap")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(controls.waitForExistence(timeout:5))
        controls.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.08)).tap()
        XCTAssertTrue(app.buttons["explore_controls_close"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["gather_M_R01_G1"].exists)
        capture("explore_controls_padding_tap")
    }
    func testSavedRegionRestoresAcrossColdLaunch() {
        let key="saved-region-"+UUID().uuidString
        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key="+key,"--qa-fixture=challenge","--qa-persist-fixture","--screen=探索"]
        app.launch()
        XCTAssertTrue(app.buttons["region_R05"].waitForExistence(timeout:20))
        capture("saved_region_initial_r05")
        app.buttons["region_R05"].tap()
        XCTAssertTrue(app.buttons["choose_region_R02"].waitForExistence(timeout:5))
        app.buttons["choose_region_R02"].tap()
        let departure=app.staticTexts.matching(NSPredicate(format:"label ENDSWITH %@","へ出発。")).firstMatch
        XCTAssertTrue(departure.waitForExistence(timeout:10),"Wait for the expedition command to commit before terminating")
        XCTAssertTrue(app.buttons["region_R02"].exists)
        capture("saved_region_selected_r02")
        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key="+key,"--screen=探索"]
        app.launch()
        XCTAssertTrue(app.buttons["region_R02"].waitForExistence(timeout:20))
        XCTAssertFalse(app.buttons["region_R01"].exists)
        XCTAssertFalse(app.buttons["region_R05"].exists)
        openExploreControls()
        XCTAssertTrue(app.buttons["fight_E_R02_01"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["fight_E_R01_01"].exists)
        capture("saved_region_restart_r02_controls")
    }
    func testGatherCueAfterUserDismissesVisibleResult() {
        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key=gather-cue-ui-"+UUID().uuidString,"--qa-fixture=gathering-cue-r01g3","--qa-gather-frame-trace","--screen=探索"]
        app.launch()
        let collect=app.buttons["claim_offline"]
        XCTAssertTrue(collect.waitForExistence(timeout:20))
        capture("gather_cue_user_ready")
        collect.tap()
        XCTAssertTrue(app.staticTexts["今日も、小さな発見を。"].waitForExistence(timeout:10))
        let close=app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout:5));XCTAssertTrue(close.isHittable)
        capture("gather_cue_user_visible_result")
        // Allow an actual visible reading interval. The model-hook harness's
        // delay starts before UIKit necessarily presents the result sheet.
        Thread.sleep(forTimeInterval:1)
        close.tap()
        XCTAssertTrue(collect.waitForExistence(timeout:5));XCTAssertTrue(collect.isHittable)
        capture("gather_cue_user_returned_field")
        Thread.sleep(forTimeInterval:2)
        capture("gather_cue_user_settled_field")
        // Visual cue acceptance uses the continuous Simulator recording; these
        // assertions establish the real presentation/dismissal route only.
    }
    func testExploreControlsCollapsePreservesGatherTarget() {
        app.buttons["tab_探索"].tap()
        XCTAssertTrue(app.buttons["explore_controls"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["fight_E_R01_01"].exists)
        capture("explore_world_visible")
        openExploreControls()
        let material=app.buttons["gather_M_R01_G1"]
        XCTAssertTrue(material.waitForExistence(timeout:5));material.tap()
        app.buttons["explore_controls_close"].tap()
        XCTAssertTrue(app.buttons["explore_controls"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["fight_E_R01_01"].exists)
        XCTAssertTrue(app.buttons["claim_offline"].isHittable)
        XCTAssertTrue(app.staticTexts["explore_gather_target"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["explore_gather_target"].label.hasSuffix("を採集中"))
        capture("explore_selected_gather_world")
        openExploreControls()
        XCTAssertTrue(material.isEnabled)
        XCTAssertTrue(app.buttons["fight_E_R01_01"].exists)
    }
    func testEnemyPagesExposeAllSixWithoutClippedTargets() {
        app.buttons["tab_探索"].tap();openExploreControls()
        for id in ["E_R01_01","E_R01_02","E_R01_03"] {XCTAssertTrue(app.buttons["fight_"+id].waitForExistence(timeout:10));XCTAssertTrue(app.buttons["fight_"+id].isHittable)}
        capture("enemy_page_one")
        app.swipeUp()
        XCTAssertTrue(app.buttons["enemies_next"].isHittable);app.buttons["enemies_next"].tap()
        for id in ["E_R01_04","B_R01_A","B_R01_B"] {XCTAssertTrue(app.buttons["fight_"+id].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["fight_"+id].isHittable)}
        XCTAssertFalse(app.buttons["fight_E_R01_01"].exists)
        capture("enemy_page_two")
        app.buttons["enemies_previous"].tap()
        XCTAssertTrue(app.buttons["fight_E_R01_01"].isHittable)
    }
    func testRegionMenuPreservesLockedRegionAndSelection() {
        app.buttons["tab_探索"].tap();openExploreControls()
        let selector=app.buttons["region_R01"];XCTAssertTrue(selector.waitForExistence(timeout:10));selector.tap()
        let locked=app.buttons["choose_region_R02"]
        XCTAssertTrue(locked.waitForExistence(timeout:5));XCTAssertFalse(locked.isEnabled)
        capture("region_menu_locks")
        let current=app.buttons["choose_region_R01"];XCTAssertTrue(current.isEnabled);current.tap()
        XCTAssertTrue(selector.waitForExistence(timeout:5));XCTAssertTrue(app.buttons["fight_E_R01_01"].isHittable)
    }
    func testEquippedBooksAppearInLunaPortraitAndPersist() {
        for (gear,name) in [("EQ_A_01","露灯の手帳"),("EQ_A_02","水鏡の祈書"),("EQ_A_03","月綴じの大典")] {
            let key="book-portrait-"+UUID().uuidString
            app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key="+key,"--qa-fixture=book-"+gear,"--qa-persist-fixture"];app.launch()
            XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:15));app.buttons["tab_仲間"].tap()
            app.buttons["companion_C_APPRENTICE"].tap()
            let weapon=app.staticTexts["companion_equipped_weapon"]
            XCTAssertTrue(weapon.waitForExistence(timeout:5));XCTAssertEqual(weapon.label,"装備："+name)
            capture("book_portrait_"+gear)
            app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key="+key];app.launch()
            XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:15));app.buttons["tab_仲間"].tap()
            app.buttons["companion_C_APPRENTICE"].tap()
            XCTAssertTrue(weapon.waitForExistence(timeout:5));XCTAssertEqual(weapon.label,"装備："+name)
            capture("book_portrait_restart_"+gear)
        }
    }
    func testColdStartShowsLoadingUntilIsolatedLoadCompletes() {
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=launch-delay-"+UUID().uuidString,"--qa-load-delay-ms=2500"];app.launch()
        XCTAssertTrue(app.staticTexts["launch_loading"].waitForExistence(timeout:5));capture("cold_start_loading")
        XCTAssertFalse(app.buttons["tab_家"].exists,"The interactive game view must stay hidden until load completes")
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:12));capture("cold_start_ready")
    }
    func testStartupFailureOffersRetryOnlyInIsolatedOneShotFixture() {
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=launch-retry-"+UUID().uuidString,"--qa-load-failure-once"];app.launch()
        XCTAssertTrue(app.staticTexts["launch_error"].waitForExistence(timeout:10));capture("startup_error_retry")
        XCTAssertTrue(app.buttons["launch_retry"].exists)
        app.buttons["launch_retry"].tap()
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:15));capture("startup_retry_ready")
    }
    func testGatheringSummaryAndRepeatClaim() {
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=gathering-"+UUID().uuidString,"--qa-fixture=gathering"];app.launch()
        XCTAssertTrue(app.buttons["claim_offline"].waitForExistence(timeout:15));app.buttons["claim_offline"].tap()
        XCTAssertTrue(app.staticTexts["今日も、小さな発見を。"].waitForExistence(timeout:10));capture("gathering_reward_summary")
        app.buttons["閉じる"].tap();app.buttons["claim_offline"].tap()
        XCTAssertTrue(app.staticTexts["採集は、ゆっくり進行中"].waitForExistence(timeout:10));capture("gathering_repeat_no_award")
    }
    func testCandidateExperienceLevelAndStatsPersistAfterGathering() {
        app.terminate()
        // Exercise the app's selected development profile, without a QA override.
        app.launchArguments=["--qa-isolated","--qa-save-key=growth-"+UUID().uuidString,"--qa-fixture=gathering"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:20));app.buttons["tab_仲間"].tap()
        let level=app.staticTexts["companion_level"]
        XCTAssertTrue(level.waitForExistence(timeout:5));XCTAssertEqual(level.label,"Lv 1")
        let beforeStats=app.staticTexts["companion_stats"].label
        app.buttons["tab_家"].tap();app.buttons["claim_offline"].tap()
        XCTAssertTrue(app.staticTexts["今日も、小さな発見を。"].waitForExistence(timeout:10))
        capture("growth_gathering_rewards")
        app.buttons["閉じる"].tap();app.buttons["tab_仲間"].tap()
        XCTAssertTrue(level.waitForExistence(timeout:5));XCTAssertEqual(level.label,"Lv 6")
        let afterStats=app.staticTexts["companion_stats"].label
        XCTAssertNotEqual(afterStats,beforeStats)
        capture("growth_level6_stats")
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:20));app.buttons["tab_仲間"].tap()
        XCTAssertTrue(level.waitForExistence(timeout:5));XCTAssertEqual(level.label,"Lv 6")
        XCTAssertEqual(app.staticTexts["companion_stats"].label,afterStats)
        capture("growth_level6_restart")
    }
    func testLocalAdCancelFailCompleteAndSkip() {
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=ad-"+UUID().uuidString,"--screen=広告検証"];app.launch()
        let accrue=app.buttons["qa_ad_accrue_eight_hours"]
        XCTAssertTrue(accrue.waitForExistence(timeout:15));accrue.tap()
        let cancel=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","qa_ad_cancel_")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:10));cancel.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout:5));app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","qa_ad_fail_")).firstMatch.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout:5));capture("ad_qa_after_cancel_failure")
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","qa_ad_complete_")).firstMatch.tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:cancel);waitForExpectations(timeout:10)
        accrue.tap();XCTAssertTrue(cancel.waitForExistence(timeout:10));app.switches["qa_ad_skip_entitlement"].tap()
        let skip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","qa_ad_skip_")).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout:5));skip.tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:cancel);waitForExpectations(timeout:10);capture("ad_qa_skip_completed")
    }
    func testGachaTargetSelectionAndRulesPersist(){
        app.terminate();app.launchArguments=["--qa-isolated","--qa-fixture=onboarding","--qa-save-key=gacha-"+UUID().uuidString,"--screen=魔導庫"];app.launch()
        XCTAssertTrue(app.buttons["gacha_target"].waitForExistence(timeout:15))
        XCTAssertFalse(app.buttons["gacha_target"].isEnabled)
        XCTAssertFalse(app.buttons["daily_free_claim"].isEnabled)
        XCTAssertFalse(app.buttons["summon5"].isEnabled)
        capture("gacha_locked_controls")
        app.buttons["閉じる"].tap();app.buttons["tab_工房"].tap()
        app.buttons["craft_RC_EQ_W_01"].tap();app.buttons["tab_仲間"].tap();app.buttons["inventory"].tap()
        XCTAssertTrue(app.buttons["比較"].firstMatch.waitForExistence(timeout:5));app.buttons["比較"].firstMatch.tap()
        XCTAssertTrue(app.buttons["finish_comparison"].waitForExistence(timeout:5));app.buttons["finish_comparison"].tap()
        app.buttons["閉じる"].tap();app.buttons["tab_家"].tap();app.buttons["魔導庫"].tap()
        XCTAssertTrue(app.buttons["gacha_target"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["gacha_target"].isEnabled)
        XCTAssertTrue(app.buttons["daily_free_claim"].isEnabled)
        app.buttons["gacha_target"].tap()
        app.buttons["gacha_target_EQ_W_P1"].tap()
        expectation(for:NSPredicate(format:"label CONTAINS %@","霧花の毒杖"),evaluatedWith:app.buttons["gacha_target"]);waitForExpectations(timeout:10);capture("gacha_target")
        app.buttons["確率と保証を見る"].tap();XCTAssertTrue(app.staticTexts["鑑定の仕組み"].waitForExistence(timeout:5));capture("gacha_odds_guarantees")
        app.terminate();app.launch();XCTAssertTrue(app.buttons["gacha_target"].waitForExistence(timeout:15));XCTAssertTrue(app.buttons["gacha_target"].label.contains("霧花の毒杖"))
    }
    func testLargeInventoryBulkSalvageAndPersistence(){
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=inventory-"+UUID().uuidString,"--qa-fixture=inventory"];app.launch()
        XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:20));app.buttons["tab_仲間"].tap();app.buttons["inventory"].tap()
        let count=app.staticTexts["inventory_count"]
        XCTAssertTrue(count.waitForExistence(timeout:10));let before=count.label
        XCTAssertTrue(app.buttons["bulk_salvage"].exists);capture("inventory_500_items")
        app.buttons["bulk_salvage"].tap();app.buttons["キャンセル"].tap();XCTAssertEqual(count.label,before)
        app.buttons["bulk_salvage"].tap();app.buttons["まとめて分解する"].tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["bulk_salvage"]);waitForExpectations(timeout:45)
        let after=count.label;XCTAssertNotEqual(before,after);capture("inventory_bulk_salvage")
        app.terminate();app.launch();XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:20));app.buttons["tab_仲間"].tap();app.buttons["inventory"].tap()
        XCTAssertTrue(count.waitForExistence(timeout:10));XCTAssertEqual(count.label,after)
    }
    func testBattleResolutionAppearsBeforeExplorationReturns() {
        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key=resolution-"+UUID().uuidString,"--qa-fixture=challenge","--qa-persist-fixture","--qa-encounter=B_R03_A"]
        app.launch()
        let terminal=app.staticTexts["battle_resolution"]
        expectation(for:NSPredicate(format:"exists == true"),evaluatedWith:terminal)
        waitForExpectations(timeout:90)
        XCTAssertEqual(terminal.label,"戦いを乗り越えました。")
        XCTAssertFalse(app.buttons["tab_家"].isEnabled,"Do not rebuild or accept a second encounter during the result pose")
        capture("battle_resolution_before_field_return")
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["tab_家"])
        waitForExpectations(timeout:15)
        XCTAssertFalse(terminal.exists)
        XCTAssertTrue(app.staticTexts["explore_gather_target"].exists)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        capture("battle_resolution_returned_to_field")
        // The next encounter must leave the held result pose and enter play.
        openExploreControls()
        app.buttons["region_R03"].tap()
        app.buttons["choose_region_R01"].tap()
        let nextEncounter=app.buttons["fight_E_R01_01"]
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:nextEncounter)
        waitForExpectations(timeout:10)
        nextEncounter.tap()
        XCTAssertTrue(app.staticTexts["battle_progress"].waitForExistence(timeout:10))
        XCTAssertFalse(terminal.exists)
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["tab_家"])
        waitForExpectations(timeout:40)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        XCTAssertTrue(app.staticTexts["explore_gather_target"].exists)
        capture("battle_resolution_next_encounter_finished")
    }
    func testBattleResolutionReturnsSafelyAfterBackgrounding() {
        app.terminate()
        let key="resolution-background-"+UUID().uuidString
        let identity=XCTAttachment(string:key)
        identity.name="resolution_background_save_key";identity.lifetime = .keepAlways;add(identity)
        app.launchArguments=["--qa-isolated","--qa-save-key="+key,"--qa-fixture=challenge","--qa-persist-fixture","--qa-encounter=B_R03_A"]
        app.launch()
        expectation(for:NSPredicate(format:"exists == true"),evaluatedWith:app.staticTexts["battle_resolution"])
        waitForExpectations(timeout:90)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:2)
        app.activate()
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["tab_家"])
        waitForExpectations(timeout:15)
        XCTAssertFalse(app.staticTexts["battle_resolution"].exists)
        XCTAssertTrue(app.staticTexts["explore_gather_target"].exists)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        capture("battle_resolution_after_background_return")
        // The host observer additionally reads this save key's phase receipt
        // to distinguish an actual paused terminal phase from a late Home tap.
    }
    func testAutoBattleBackgroundAndRestart(){
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=battle-"+UUID().uuidString,"--qa-slow-battle"];app.launch()
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout:15));app.buttons["tab_探索"].tap();openExploreControls()
        app.buttons["fight_E_R01_01"].tap()
        let fighting=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","4人で自動戦闘中")).firstMatch
        XCTAssertTrue(fighting.waitForExistence(timeout:10));XCTAssertFalse(app.buttons["region_R01"].isEnabled);capture("battle_hp_telegraph")
        XCUIDevice.shared.press(.home);app.activate()
        let finished=NSPredicate(format:"enabled == true")
        expectation(for:finished,evaluatedWith:app.buttons["tab_家"])
        waitForExpectations(timeout:100);capture("battle_result")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","獲得:")).firstMatch.waitForExistence(timeout:5),"Victory result should list the actual persisted battle reward delta")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","苔角片 +1")).firstMatch.exists,"R01 first-enemy victory should expose its material drop")
        app.buttons["settings"].tap()
        let savedRevision=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","保存状態: revision ")).firstMatch.label
        XCTAssertFalse(savedRevision.isEmpty);app.terminate();app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:15));app.buttons["settings"].tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","保存状態: revision ")).firstMatch.label,savedRevision)
        capture("battle_restart_saved_revision")
    }
    func testChallengeSurvivesForegroundRefresh() {
        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key=challenge-foreground-"+UUID().uuidString,"--qa-fixture=challenge","--qa-persist-fixture","--qa-challenge=CH_R03_03","--qa-slow-battle"]
        app.launch()
        let playing=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","4人で自動戦闘中")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout:20))
        XCTAssertFalse(app.buttons["region_R03"].isEnabled)
        capture("challenge_foreground_before_background")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(playing.waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["region_R03"].isEnabled)
        capture("challenge_foreground_after_activation")
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["tab_家"])
        waitForExpectations(timeout:180)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        XCTAssertTrue(app.staticTexts["研究課題を達成しました。"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["region_R05"].isEnabled,"Return to the saved expedition after a research challenge")
        XCTAssertTrue(app.staticTexts["explore_gather_target"].exists,"The saved expedition's gathering target must remain visible")
        capture("challenge_foreground_completed")
        app.buttons["settings"].tap()
        let revision=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","保存状態: revision ")).firstMatch.label
        XCTAssertFalse(revision.isEmpty)
        app.terminate()
        app.launchArguments.removeAll{$0.hasPrefix("--qa-challenge=") || $0=="--qa-persist-fixture"}
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:20));app.buttons["settings"].tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","保存状態: revision ")).firstMatch.label,revision)
        capture("challenge_foreground_saved_restart")
    }
    func testResearchChallengeLockReasonAndLaunch() {
        app.buttons["tab_採集帳"].tap()
        let locked=app.descendants(matching:.any).matching(identifier:"challenge_lock_CH_R01_01").firstMatch
        for _ in 0..<6 { if locked.exists && locked.isHittable {break};app.swipeUp() }
        XCTAssertTrue(locked.exists)
        XCTAssertTrue(locked.isHittable,"The lock condition must remain readable after scrolling")
        XCTAssertTrue(locked.label.contains("第五地域の最終ボス討伐で解放"))
        XCTAssertFalse(app.buttons["challenge_CH_R01_01"].exists)
        capture("research_challenge_locked_condition")

        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key=challenge-launch-"+UUID().uuidString,"--qa-fixture=challenge","--qa-persist-fixture","--screen=採集帳"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout:20))
        let challenge=app.buttons["challenge_CH_R01_01"]
        for _ in 0..<6 { if challenge.exists && challenge.isHittable {break};app.swipeUp() }
        XCTAssertTrue(challenge.isHittable)
        XCTAssertTrue(challenge.isEnabled)
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"challenge_lock_CH_R01_01").firstMatch.exists)
        capture("research_challenge_unlocked_action")
        challenge.tap()
        let completion=app.staticTexts["研究課題を達成しました。"]
        XCTAssertTrue(completion.waitForExistence(timeout:90))
        XCTAssertTrue(app.buttons["tab_家"].isEnabled)
        capture("research_challenge_launched_and_completed")
    }
    func testResearchBenefitAndCompletionPersist() {
        func attackValue()->Int {
            app.buttons["tab_仲間"].tap();app.buttons["companion_C_WITCH"].tap()
            let stats=app.staticTexts["companion_stats"]
            XCTAssertTrue(stats.waitForExistence(timeout:5))
            let fields=stats.label.components(separatedBy:"攻撃 ")
            guard fields.count==2,let value=Int(fields[1].prefix(while:{$0.isNumber})) else { XCTFail("Attack stat is missing: "+stats.label);return -1 }
            return value
        }
        let originalAttack=attackValue()
        app.buttons["tab_採集帳"].tap()
        XCTAssertEqual(app.staticTexts["research_benefit_RS_THEORY_1"].label,"仲間全員の攻撃 +1")
        XCTAssertTrue(app.staticTexts["素材消費なし"].exists)
        XCTAssertFalse(app.buttons["research_action_RS_THEORY_2"].exists,"A gated research must explain its prerequisite")
        capture("research_benefit_before")
        let action=app.buttons["research_action_RS_THEORY_1"]
        XCTAssertTrue(action.isHittable);action.tap()
        let completed=app.descendants(matching:.any).matching(identifier:"research_complete_RS_THEORY_1").firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout:10))
        XCTAssertFalse(action.exists)
        capture("research_benefit_completed")
        XCTAssertEqual(attackValue(),originalAttack+1,"The displayed research benefit must change actual projected stats")
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout:20));app.buttons["tab_採集帳"].tap()
        XCTAssertTrue(completed.waitForExistence(timeout:5))
        XCTAssertFalse(action.exists)
        XCTAssertEqual(app.staticTexts["research_benefit_RS_THEORY_1"].label,"仲間全員の攻撃 +1")
        capture("research_benefit_saved_restart")
        XCTAssertEqual(attackValue(),originalAttack+1)
    }
    func testExhaustedRevisionBattleRejectsWithoutSaveMutationOrCrash() {
        app.terminate()
        let key="exhausted-revision-"+UUID().uuidString
        app.launchArguments=["--qa-isolated","--qa-save-key="+key,"--qa-fixture=exhausted-revision"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout:20))
        app.buttons["settings"].tap()
        let revisionLabel=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","保存状態: revision ")).firstMatch
        XCTAssertTrue(revisionLabel.waitForExistence(timeout:5))
        let initialRevision=revisionLabel.label
        XCTAssertEqual(String(initialRevision.filter(\.isNumber)),"9223372036854775807", "Unexpected revision label: \(initialRevision)")
        app.buttons["閉じる"].tap()
        app.buttons["tab_探索"].tap();openExploreControls()
        let fight=app.buttons["fight_E_R01_01"]
        XCTAssertTrue(fight.waitForExistence(timeout:5));fight.tap()
        let alert=app.alerts["確認が必要です"]
        XCTAssertTrue(alert.waitForExistence(timeout:10),"Exhausted revision should be rejected by Core and shown as a recoverable error")
        XCTAssertTrue(alert.staticTexts["この操作の条件をまだ満たしていません。装備・素材・探索の進み具合をご確認ください。"].exists)
        capture("exhausted_revision_rejected")
        alert.buttons["閉じる"].tap()
        app.buttons["settings"].tap()
        XCTAssertEqual(revisionLabel.label,initialRevision,"Rejected operation must leave the snapshot revision unchanged")
        app.buttons["閉じる"].tap()
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:20));app.buttons["settings"].tap()
        XCTAssertEqual(revisionLabel.label,initialRevision,"Relaunch must reconstruct the untouched exhausted-revision fixture")
    }
    func testGatherLockedMaterials(){
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout:15));app.buttons["tab_探索"].tap();openExploreControls()
        XCTAssertTrue(app.buttons["gather_M_R01_G1"].isEnabled)
        XCTAssertFalse(app.buttons["gather_M_R01_G3"].isEnabled)
        XCTAssertFalse(app.buttons["gather_M_R01_G4"].isEnabled)
    }
    func testCraftCompareSummonAndPersist() {
        app.terminate();let key="onboarding-"+UUID().uuidString
        app.launchArguments=["--qa-isolated","--qa-fixture=onboarding","--qa-save-key="+key];app.launch()
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout:15));app.buttons["tab_工房"].tap()
        app.buttons["craft_RC_EQ_W_01"].tap();app.buttons["tab_仲間"].tap();app.buttons["inventory"].tap()
        XCTAssertTrue(app.buttons["比較"].firstMatch.waitForExistence(timeout:5));app.buttons["比較"].firstMatch.tap()
        XCTAssertTrue(app.buttons["finish_comparison"].waitForExistence(timeout:5));capture("comparison_stats");app.buttons["finish_comparison"].tap()
        app.buttons["閉じる"].tap();app.buttons["tab_家"].tap();app.buttons["魔導庫"].tap()
        app.buttons["summon5"].tap();XCTAssertTrue(app.staticTexts["届いた装備"].waitForExistence(timeout:10));capture("five_draw_result")
        app.buttons["閉じる"].tap();app.terminate();app.launch();XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:15));capture("post_summon_restart")
    }
    func testCraftedStaffEquipsRendersAndPersistsAcrossRestart() {
        let key="weapon-projection-"+UUID().uuidString
        app.terminate();app.launchArguments=["--qa-isolated","--qa-fixture=onboarding","--qa-save-key="+key,"--qa-pose=idle"];app.launch()
        XCTAssertTrue(app.buttons["tab_工房"].waitForExistence(timeout:15));app.buttons["tab_工房"].tap()
        let craft=app.buttons["craft_RC_EQ_W_01"];XCTAssertTrue(craft.waitForExistence(timeout:10));craft.tap()
        app.buttons["tab_仲間"].tap();app.buttons["inventory"].tap()
        let inventoryCount=app.staticTexts["inventory_count"]
        XCTAssertTrue(inventoryCount.waitForExistence(timeout:10));XCTAssertTrue(inventoryCount.label.contains("5 / 表示 5"),inventoryCount.label)
        let equip=app.buttons["装備"].firstMatch;XCTAssertTrue(equip.waitForExistence(timeout:10));equip.tap()
        XCTAssertTrue(inventoryCount.waitForExistence(timeout:5))
        app.buttons["閉じる"].tap();app.buttons["tab_家"].tap();capture("equipped_branch_staff_home")
        app.terminate();app.launch();XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:15));capture("equipped_branch_staff_restart")
    }
    func testFurniturePlacementAndUse(){
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:15));app.buttons["模様替え"].tap()
        if app.buttons["無料の研究机を受け取る"].exists{app.buttons["無料の研究机を受け取る"].tap()}
        let place=app.buttons["place_desk"];XCTAssertTrue(place.waitForExistence(timeout:5));if place.label.contains("置く"){place.tap()}
        app.buttons["閉じる"].tap();capture("furniture_in_use")
        let scene=app.images["living_scene"]
        XCTAssertTrue(scene.waitForExistence(timeout:5))
        XCTAssertTrue(scene.label.contains("植物研究の机でルナが本を読んでいます。"))
        app.terminate();app.launch();XCTAssertTrue(app.buttons["模様替え"].waitForExistence(timeout:15));app.buttons["模様替え"].tap();XCTAssertTrue(app.buttons["place_desk"].label.contains("しまう"))
    }
    func testFiveTabsAndWorkshopVisible(){
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:15));capture("home")
        for name in ["探索","仲間","工房","採集帳"] {app.buttons["tab_"+name].tap();XCTAssertTrue(app.buttons["tab_家"].exists);capture(name)}
        XCTAssertTrue(app.staticTexts["暮らしと冒険の研究"].exists)
    }
    func testAccessibilityAuditHomeExploreAndShop() throws {
        for (screen,ready,label) in [("家","settings","audit_home"),("探索","region_R01","audit_explore"),("商店","森の小さな商店","audit_shop")] {
            app.terminate()
            app.launchArguments=["--qa-isolated","--qa-save-key=accessibility-"+UUID().uuidString,"--screen="+screen]
            app.launch()
            let destination = screen == "商店" ? app.staticTexts[ready] : app.buttons[ready]
            XCTAssertTrue(destination.waitForExistence(timeout:20),"\(screen) screen did not load")
            capture(label)
            var issues:[String]=[]
            do {
                try app.performAccessibilityAudit(for:.all) { issue in
                    let element=issue.element
                    issues.append("type=\(issue.auditType.rawValue) elementType=\(String(describing:element?.elementType)) identifier=\(element?.identifier ?? "") label=\(element?.label ?? "") frame=\(String(describing:element?.frame))\n\(issue.compactDescription)\n\(issue.detailedDescription)")
                    return true
                }
            } catch {
                issues.append("AUDIT_EXECUTION_ERROR: \(String(reflecting:error))")
            }
            let attachment=XCTAttachment(string:issues.isEmpty ? "No accessibility audit issues reported for \(screen)." : issues.joined(separator:"\n\n"))
            attachment.name=label+"_issues";attachment.lifetime = .keepAlways;add(attachment)
            captureAuditState(label+"_after")
            print("ACCESSIBILITY_AUDIT_SCREEN=\(screen) ISSUE_COUNT=\(issues.count)")
        }
    }
    func testAccessibilityAuditOtherMajorScreens() throws {
        for screen in ["仲間","工房","採集帳","装備","試着","模様替え","魔導庫","確率","設定"] {
            app.terminate()
            app.launchArguments=["--qa-isolated","--qa-save-key=accessibility-major-"+UUID().uuidString,"--screen="+screen]
            app.launch()
            let isTab=["仲間","工房","採集帳"].contains(screen)
            let ready=app.buttons[isTab ? "tab_"+screen:"閉じる"]
            XCTAssertTrue(ready.waitForExistence(timeout:20),"\(screen) did not finish loading")
            capture("audit_major_"+screen)
            var issues:[String]=[]
            do {
                try app.performAccessibilityAudit(for:.all) { issue in
                    let element=issue.element
                    issues.append("type=\(issue.auditType.rawValue) elementType=\(String(describing:element?.elementType)) identifier=\(element?.identifier ?? "") label=\(element?.label ?? "") frame=\(String(describing:element?.frame))\n\(issue.compactDescription)\n\(issue.detailedDescription)")
                    return true
                }
            } catch { issues.append("AUDIT_EXECUTION_ERROR: \(String(reflecting:error))") }
            // This observational test records every finding. XCTest completion
            // is not a zero-issue or Human accessibility sign-off.
            let report=XCTAttachment(string:issues.isEmpty ? "No accessibility audit issues reported for \(screen).":issues.joined(separator:"\n\n"))
            report.name="audit_major_"+screen+"_issues";report.lifetime = .keepAlways;add(report)
            let tree=XCTAttachment(string:app.debugDescription)
            tree.name="audit_major_"+screen+"_tree";tree.lifetime = .keepAlways;add(tree)
            captureAuditState("audit_major_"+screen+"_after")
            print("ACCESSIBILITY_AUDIT_MAJOR_SCREEN=\(screen) ISSUE_COUNT=\(issues.count)")
        }
    }
    func testAdaptiveNavigationAndInventoryFilters() {
        XCTAssertTrue(app.buttons["tab_家"].waitForExistence(timeout:15))
        for screen in ["探索","仲間","工房","採集帳","家","仲間"] {
            let menu=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","画面を選ぶ、")).firstMatch
            if menu.exists {
                XCTAssertTrue(menu.isHittable);menu.tap()
                let item=app.buttons["choose_tab_"+screen]
                XCTAssertTrue(item.waitForExistence(timeout:5));item.tap()
            } else { app.buttons["tab_"+screen].tap() }
            XCTAssertTrue(app.buttons["tab_"+screen].waitForExistence(timeout:5))
        }
        for _ in 0..<5 {
            if app.buttons["inventory"].isHittable {break}
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["inventory"].isHittable);app.buttons["inventory"].tap()
        XCTAssertTrue(app.staticTexts["inventory_count"].waitForExistence(timeout:10))
        let actor=app.buttons["inventory_actor_picker"]
        if actor.exists {
            actor.tap();let luna=app.buttons["ルナ"];XCTAssertTrue(luna.waitForExistence(timeout:5));luna.tap()
            XCTAssertTrue(actor.label.contains("ルナ"),actor.label)
            let quality=app.buttons["inventory_quality_picker"]
            for _ in 0..<5 { if quality.isHittable {break};app.swipeUp() }
            XCTAssertTrue(quality.isHittable);quality.tap()
            let ur=app.buttons["UR"];XCTAssertTrue(ur.waitForExistence(timeout:5));ur.tap()
            XCTAssertTrue(quality.label.contains("UR"),quality.label)
            XCTAssertTrue(app.staticTexts["inventory_count"].label.contains("表示 0"))
        }
        capture("adaptive_inventory_filters")
    }
    func testAccessibilityAuditScrolledContent() throws {
        for screen in ["探索","工房","採集帳","装備","試着"] {
            app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=accessibility-scroll-"+UUID().uuidString,"--screen="+screen];app.launch()
            let isTab=["探索","工房","採集帳"].contains(screen)
            XCTAssertTrue(app.buttons[isTab ? "tab_"+screen:"閉じる"].waitForExistence(timeout:20))
            app.swipeUp();capture("audit_scrolled_"+screen)
            var issues:[String]=[]
            do {
                try app.performAccessibilityAudit(for:.all) { issue in
                    issues.append("type=\(issue.auditType.rawValue) label=\(issue.element?.label ?? "") frame=\(String(describing:issue.element?.frame))\n\(issue.compactDescription)\n\(issue.detailedDescription)")
                    return true
                }
            } catch { issues.append("AUDIT_EXECUTION_ERROR: \(String(reflecting:error))") }
            let report=XCTAttachment(string:issues.isEmpty ? "No issues at this scrolled viewport.":issues.joined(separator:"\n\n"))
            report.name="audit_scrolled_"+screen+"_issues";report.lifetime = .keepAlways;add(report)
            captureAuditState("audit_scrolled_"+screen+"_after")
            print("ACCESSIBILITY_AUDIT_SCROLLED_SCREEN=\(screen) ISSUE_COUNT=\(issues.count)")
        }
    }
    private func captureAuditState(_ label:String) {
        // The audit may traverse/scroll content. Preserve its final viewport,
        // separately from the pre-audit screenshot, for matching issue frames.
        capture(label)
        let tree=XCTAttachment(string:app.debugDescription)
        tree.name=label+"_tree";tree.lifetime = .keepAlways;add(tree)
    }
    func testShopRestoreIsClearlyUnavailable() {
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=shop-"+UUID().uuidString,"--screen=商店"];app.launch()
        let restore=app.buttons["購入の復元（未提供）"]
        XCTAssertTrue(restore.waitForExistence(timeout:20))
        XCTAssertFalse(restore.isEnabled)
        XCTAssertTrue(app.staticTexts["衣装・有料家具の販売準備中"].exists)
        XCTAssertTrue(app.staticTexts["この開発版では料金は発生しません。"].exists)
        capture("shop_restore_unavailable")
    }
    func testAudioControlsAndMutePersistence() {
        let audioSuite="audio-"+UUID().uuidString
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=audio-"+UUID().uuidString,"--qa-audio-suite="+audioSuite];app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:15));app.buttons["settings"].tap()
        let mute=app.switches["audio_mute"],volume=app.sliders["audio_volume"]
        XCTAssertTrue(mute.waitForExistence(timeout:5));XCTAssertTrue(volume.exists)
        let initial=mute.value as? String
        mute.tap();let changed=mute.value as? String
        XCTAssertNotEqual(initial,changed);capture("audio_controls")
        app.terminate();app.launchArguments=["--qa-isolated","--qa-save-key=audio-"+UUID().uuidString,"--qa-audio-suite="+audioSuite];app.launch();XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:15));app.buttons["settings"].tap()
        XCTAssertEqual(app.switches["audio_mute"].value as? String,changed,"Mute preference should persist after app relaunch")
        app.switches["audio_mute"].tap()
    }
    func testMusicControlsPersistenceAndBackgroundResume() {
        let key="music-"+UUID().uuidString
        let identity=XCTAttachment(string:key);identity.name="music_qa_save_key";identity.lifetime = .keepAlways;add(identity)
        app.terminate()
        app.launchArguments=["--qa-isolated","--qa-save-key="+key,"--qa-audio-suite="+key,"--qa-music-diagnostics"]
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:15))
        app.buttons["settings"].tap()
        let mute=app.switches["music_mute"],volume=app.sliders["music_volume"]
        XCTAssertTrue(mute.waitForExistence(timeout:5));XCTAssertTrue(volume.exists)
        mute.tap();XCTAssertEqual(mute.value as? String,"1")
        volume.adjust(toNormalizedSliderPosition:0.3)
        let adjustedVolume=volume.value as? String
        XCTAssertNotNil(adjustedVolume)
        capture("music_controls_muted")
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:15));app.buttons["settings"].tap()
        XCTAssertEqual(app.switches["music_mute"].value as? String,"1","Music mute must survive relaunch")
        XCTAssertEqual(app.sliders["music_volume"].value as? String,adjustedVolume,"Music volume must survive relaunch")
        app.switches["music_mute"].tap()
        app.buttons["閉じる"].tap();app.buttons["tab_探索"].tap()
        XCTAssertTrue(app.buttons["region_R01"].waitForExistence(timeout:5))
        capture("music_field_before_background")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:2)
        app.activate()
        XCTAssertTrue(app.buttons["region_R01"].waitForExistence(timeout:8))
        Thread.sleep(forTimeInterval:0.6)
        app.buttons["tab_家"].tap()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout:5))
        capture("music_home_after_resume")
    }
    func testAppearancePersistsAcrossRelaunch(){
        XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:15));app.buttons["tab_仲間"].tap();app.buttons["試着"].tap()
        app.buttons["appearance_ERNA_TRAVEL"].tap();XCTAssertTrue(app.buttons["appearance_ERNA_TRAVEL"].waitForExistence(timeout:5))
        app.buttons["appearance_STAFF_MOON"].tap();capture("wardrobe")
        app.buttons["閉じる"].tap();capture("detail_costume_weapon")
        app.terminate();app.launch();XCTAssertTrue(app.buttons["tab_仲間"].waitForExistence(timeout:15));app.buttons["tab_仲間"].tap();app.buttons["試着"].tap()
        XCTAssertEqual(app.buttons["appearance_ERNA_TRAVEL"].label,"選択中");XCTAssertEqual(app.buttons["appearance_STAFF_MOON"].label,"選択中")
    }
}
