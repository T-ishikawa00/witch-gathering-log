import XCTest
import CryptoKit
import Darwin

/// Source-only native acceptance candidate for the R146 shared-party-work UI.
/// The host runner supplies a distinct fresh save UUID for each content-size case.
/// This test never creates, deletes, or rewrites save files itself.
final class SharedPartyWorkLifecycleR146Tests: XCTestCase {
    private let app = XCUIApplication()
    private var saveKey = ""
    private var sizeName = ""
    private var startedUptime: TimeInterval = 0
    private let journeyBudget: TimeInterval = 15 * 60

    override func setUpWithError() throws {
        continueAfterFailure = false
        startedUptime = ProcessInfo.processInfo.systemUptime
        // Launch happens per test with its own host-reserved UUID.
    }

    override func tearDownWithError() throws {
        // Only stop the app instance launched by this XCTest. Save files remain for host readback.
        if app.state == .runningForeground || app.state == .runningBackground { app.terminate() }
        super.tearDown()
    }

    func testLargeRealFirstClearInvestigationCollectSwitchReopenAndRepeat() throws {
        try runEarnedJourney(expectedSize: "Large")
    }

    func testAXXXLRealFirstClearInvestigationCollectSwitchReopenAndRepeat() throws {
        try runEarnedJourney(expectedSize: "AXXXL")
    }

    private func runEarnedJourney(expectedSize: String) throws {
        startedUptime = ProcessInfo.processInfo.systemUptime
        let suffix = expectedSize == "Large" ? "LARGE" : "AXXXL"
        guard let key = ProcessInfo.processInfo.environment["WITCH_R146_SAVE_KEY_\(suffix)"],
              Self.isCanonicalUUID(key) else {
            throw NSError(domain: "R146TestConfiguration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Host must provide a fresh canonical UUID for \(expectedSize)"])
        }
        saveKey = key
        sizeName = expectedSize
        app.launchArguments = [
            "--qa-isolated", "--qa-shared-party-work-r146", "--qa-save-key=" + saveKey,
            "--screen=探索", "-UIPreferredContentSizeCategoryName",
            expectedSize == "Large" ? "UICTContentSizeCategoryL" : "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        XCTAssertFalse(app.launchArguments.contains(where: { $0.hasPrefix("--qa-fixture") || $0.contains("time") || $0.contains("grant") || $0.contains("encounter") }))
        app.launch()
        XCTAssertEqual(sizeName, expectedSize)
        XCTAssertEqual(app.launchArguments.filter { $0.hasPrefix("--qa-shared-party-work") },
                       ["--qa-shared-party-work-r146"])
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout: 30), app.debugDescription)
        hostBarrier("fresh_launch", evidence: ["dynamicType": sizeName])

        openExploreControls()
        let initialTarget = app.staticTexts["r146_shared_work_target"]
        XCTAssertTrue(initialTarget.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(initialTarget.label.contains("採集"), "A fresh save should start on its authored gathering target")
        let investigate = app.buttons["r146_work_investigate_E_R01_02"]
        XCTAssertTrue(reveal(investigate, scrollID: "explore_scroll", attempts: 14, requireHittable: false), app.debugDescription)
        XCTAssertGreaterThanOrEqual(investigate.frame.height, 44, "The disabled investigation row must keep a full-size readable target")
        XCTAssertFalse(investigate.isEnabled, "Investigation must remain locked until a normal first-clear victory is saved")
        hostBarrier("investigation_locked", evidence: ["targetID": "E_R01_02", "enabled": false])

        let fight = app.buttons["fight_E_R01_02"]
        XCTAssertTrue(reveal(fight, scrollID: "explore_scroll", attempts: 18), app.debugDescription)
        XCTAssertTrue(fight.isEnabled)
        fight.tap()
        let active = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "4人で自動戦闘中")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 20), "Must enter the ordinary dispatched battle")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: active)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 180), .completed)
        XCTAssertFalse(app.alerts["確認が必要です"].exists, "A dispatch error is not a first clear")
        hostBarrier("first_clear", evidence: ["encounterID": "E_R01_02", "route": "ordinary_UI"])

        openExploreControls()
        XCTAssertTrue(reveal(investigate, scrollID: "explore_scroll", attempts: 14), app.debugDescription)
        XCTAssertGreaterThanOrEqual(investigate.frame.height, 44)
        XCTAssertTrue(investigate.isHittable)
        XCTAssertTrue(investigate.isEnabled, "Successful first-clear must unlock investigation")
        investigate.tap()
        waitForButtonsToSettle(expected: "再調査")
        hostBarrier("investigation_selected", evidence: ["targetID": "E_R01_02", "route": "ordinary_UI"], timeout: 15)

        // This is wall-clock accrual at the authored R01 interval. No clock or
        // seconds-per-unit override is passed. Poll the actual displayed state.
        let clock = app.staticTexts["r146_shared_work_clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 15), app.debugDescription)
        let oneUnit = NSPredicate(format: "label CONTAINS %@", "完了 1単位")
        let accrued = XCTNSPredicateExpectation(predicate: oneUnit, object: clock)
        XCTAssertEqual(XCTWaiter.wait(for: [accrued], timeout: 330), .completed,
                       "Wait up to 330 seconds for one real authored work unit")
        XCTAssertTrue(clock.label.contains("完了 1単位"), "Collect immediately at the first ready unit to avoid an extra accrual")
        hostBarrier("before_collect", evidence: ["targetID": "E_R01_02", "minimumWallAccrualSeconds": 300], timeout: 15)

        let collect = app.buttons["r146_shared_work_collect"]
        XCTAssertTrue(reveal(collect, scrollID: "explore_scroll", attempts: 18), app.debugDescription)
        XCTAssertGreaterThanOrEqual(collect.frame.height, 44)
        XCTAssertTrue(collect.isHittable); XCTAssertTrue(collect.isEnabled)
        collect.tap()
        let summary = app.descendants(matching: .any)["r146_shared_work_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "灯糸")).firstMatch.waitForExistence(timeout: 8))
        hostBarrier("investigation_collected", evidence: ["materialID": "M_R01_E2", "expectedDelta": 1], timeout: 15)
        closeSummary()

        // Repeat through the same ordinary Explore control. The host compares
        // this successful CombatResult to the pre-battle save and requires zero
        // immediate material/coin reward; no synthetic encounter route is used.
        openExploreControls()
        let repeatFight = app.buttons["fight_E_R01_02"]
        XCTAssertTrue(reveal(repeatFight, scrollID: "explore_scroll", attempts: 18), app.debugDescription)
        repeatFight.tap()
        waitForOrdinaryBattleToFinish(timeout: 180)
        XCTAssertFalse(app.alerts["確認が必要です"].exists)
        hostBarrier("repeat_complete", evidence: ["encounterID": "E_R01_02", "expectedImmediateMaterialDelta": 0, "expectedImmediateCoinDelta": 0], timeout: 15)

        openExploreControls()
        let gather = app.buttons["r146_work_gather_M_R01_G1"]
        XCTAssertTrue(reveal(gather, scrollID: "explore_scroll", attempts: 14), app.debugDescription)
        XCTAssertGreaterThanOrEqual(gather.frame.height, 44)
        XCTAssertTrue(gather.isHittable)
        XCTAssertTrue(gather.isEnabled)
        gather.tap()
        waitForButtonsToSettle(expected: "採集")
        hostBarrier("gather_selected", evidence: ["materialID": "M_R01_G1", "fractionalCarryExpected": 0], timeout: 15)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab_探索"].waitForExistence(timeout: 30), app.debugDescription)
        openExploreControls()
        let reopenedGather = app.buttons["r146_work_gather_M_R01_G1"]
        XCTAssertTrue(reveal(reopenedGather, scrollID: "explore_scroll", attempts: 14))
        XCTAssertGreaterThanOrEqual(reopenedGather.frame.height, 44)
        XCTAssertTrue(reopenedGather.isHittable)
        XCTAssertTrue((reopenedGather.value as? String) == "選択中" || reopenedGather.label.contains("選択中"),
                      "The selected ordinary gather target must survive same-key cold reopen")
        hostBarrier("cold_reopen", evidence: ["selectedTarget": "gather:M_R01_G1"], timeout: 15)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedUptime, journeyBudget,
                          "One UI case is bounded to 15 minutes including the real 300-second wait")
    }

    private func waitForOrdinaryBattleToFinish(timeout: TimeInterval) {
        let active = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "4人で自動戦闘中")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 20), "Must enter the ordinary dispatched battle")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: active)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: timeout), .completed,
                       "Normal battle did not reach its presentation end")
    }

    private func openExploreControls() {
        if !app.buttons["explore_controls_close"].exists {
            let open = app.buttons["explore_controls"]
            XCTAssertTrue(open.waitForExistence(timeout: 15), app.debugDescription)
            if !open.isHittable { app.swipeUp() }
            XCTAssertTrue(open.isHittable); open.tap()
        }
        XCTAssertTrue(app.buttons["explore_controls_close"].waitForExistence(timeout: 10))
    }

    private func closeSummary() {
        let close = app.buttons["閉じる"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(app.buttons["r146_shared_work_collect"].waitForExistence(timeout: 10))
    }

    private func waitForButtonsToSettle(expected: String) {
        let target = app.staticTexts["r146_shared_work_target"]
        XCTAssertTrue(target.waitForExistence(timeout: 10),
                      "The shared work target projection must be present after selection")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed,
                       "The UI should show the target selected by the normal button")
    }

    private func reveal(_ element: XCUIElement, scrollID: String, attempts: Int, requireHittable: Bool = true) -> Bool {
        let scroll = app.scrollViews[scrollID]
        guard scroll.waitForExistence(timeout: 8) else { return false }
        for _ in 0..<attempts {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 2)
            if element.exists && viewport.contains(element.frame) && (!requireHittable || element.isHittable) { return true }
            let up = !element.exists || element.frame.maxY > viewport.maxY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -90 : 90)))
        }
        let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 1, dy: 2)
        return element.exists && viewport.contains(element.frame) && (!requireHittable || element.isHittable)
    }

    private func hostBarrier(_ phase: String, evidence: [String: Any] = [:], timeout: TimeInterval = 15) {
        let allowed = Set(["fresh_launch", "investigation_locked", "first_clear", "investigation_selected",
                           "before_collect", "investigation_collected", "gather_selected", "cold_reopen", "repeat_complete"])
        XCTAssertTrue(allowed.contains(phase))
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let marker = docs.appendingPathComponent("r146_\(saveKey)_\(phase).json")
        let ack = docs.appendingPathComponent("r146_\(saveKey)_\(phase).verified")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Never overwrite an existing marker")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ack.path), "Host ack already exists before marker")
        var payload: [String: Any] = [
            "schema": "r146-native-phase-v1", "saveKey": saveKey,
            "phase": phase, "contentSize": sizeName,
            "testPID": ProcessInfo.processInfo.processIdentifier,
            "testName": name, "observedUptime": ProcessInfo.processInfo.systemUptime,
            "elapsedWallSeconds": ProcessInfo.processInfo.systemUptime - startedUptime,
            "launchArguments": app.launchArguments,
            "fixture": NSNull(), "timeOverride": NSNull(), "grantedMaterials": false,
            "forcedBattle": false, "directEngineDispatch": false
        ]
        evidence.forEach { payload[$0.key] = $0.value }
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            XCTFail("Could not encode R146 phase marker"); return
        }
        // O_EXCL makes marker creation fail if another writer already owns the name.
        let fd = open(marker.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { XCTFail("Could not exclusively create R146 phase marker"); return }
        let written = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Darwin.write(fd, base, raw.count)
        }
        _ = close(fd)
        guard written == bytes.count else { XCTFail("Incomplete R146 phase marker write"); return }
        if ["investigation_locked", "investigation_selected", "investigation_collected", "cold_reopen"].contains(phase) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "R146_\(sizeName)_\(phase)_\(saveKey)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        let markerSHA = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let ackBytes = try? Data(contentsOf: ack),
               let object = try? JSONSerialization.jsonObject(with: ackBytes) as? [String: Any],
               object["schema"] as? String == "r146-phase-ack-v1",
               object["saveKey"] as? String == saveKey,
               object["contentSize"] as? String == sizeName,
               object["phase"] as? String == phase,
               object["markerSHA256"] as? String == markerSHA { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Host readback did not acknowledge \(phase) before timeout")
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }
}
