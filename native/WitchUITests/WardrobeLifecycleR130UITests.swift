import XCTest

/// UI lifecycle coverage for the unapproved R130 AIRA apron candidate.
/// Add this file to the isolated WitchUITests target only; never enable the
/// candidate in a normal app launch.
final class WardrobeLifecycleR130UITests: XCTestCase {
    private var app = XCUIApplication()

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAiraApronThumbnailAndWardrobeLifecycle() {
        let saveKey = UUID().uuidString.lowercased()
        launchCandidate(saveKey: saveKey)
        navigateToCompanions()
        openWardrobe()
        chooseActor("アイラ")
        let appearanceID = "AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130"
        phaseBarrier("preview_baseline", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)

        // These screenshots exercise all three candidate-specific alpha-cropped
        // thumbnails without selecting or changing their saved appearances.
        captureThumbnail(actorName: "ルナ", actorID: "C_APPRENTICE",
                         appearanceID: "LUNA_MANTLE_CANDIDATE_R128", saveKey: saveKey, phase: "thumbnail_luna")
        captureThumbnail(actorName: "ノワール", actorID: "C_FAMILIAR",
                         appearanceID: "NOIR_NECKWEAR_MOSS_R001", saveKey: saveKey, phase: "thumbnail_noir")
        captureThumbnail(actorName: "アイラ", actorID: "C_SMITH",
                         appearanceID: "AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130", saveKey: saveKey, phase: "thumbnail_aira")

        // Preview and apply the AIRA candidate through the ordinary wardrobe UI.
        // captureThumbnail leaves the final (AIRA) actor selected.
        let preview = appearanceButton(appearanceID, preview: true)
        reveal(preview)
        XCTAssertEqual(preview.label, "この見た目を試す")
        preview.tap()
        XCTAssertTrue(waitForLabel(preview, "試着中"), "Preview is a transient visual state")
        attachEvidence(name: "r130_C_SMITH_preview_only", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID, phase: "preview_only")
        phaseBarrier("preview_only", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)

        let apply = appearanceButton(appearanceID, preview: false)
        reveal(apply)
        XCTAssertEqual(apply.label, "この見た目を使う", "Preview must not mark the candidate selected")
        XCTAssertTrue(apply.isEnabled)
        closeWardrobe()
        phaseBarrier("preview_closed", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)
        openWardrobe()
        chooseActor("アイラ")
        let reopenedPreview = appearanceButton(appearanceID, preview: true)
        reveal(reopenedPreview)
        XCTAssertEqual(reopenedPreview.label, "この見た目を試す", "Closing the sheet must discard preview-only state")
        let stillUnselected = appearanceButton(appearanceID, preview: false)
        reveal(stillUnselected)
        XCTAssertEqual(stillUnselected.label, "この見た目を使う")
        XCTAssertTrue(stillUnselected.isEnabled)
        attachEvidence(name: "r130_C_SMITH_preview_reopened", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID, phase: "preview_reopened")
        phaseBarrier("preview_reopened", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)

        stillUnselected.tap()
        let selected = appearanceButton(appearanceID, preview: false)
        reveal(selected)
        XCTAssertTrue(waitForLabel(selected, "選択中"), "Apply must persist through the normal wardrobe command")
        XCTAssertFalse(selected.isEnabled)
        attachEvidence(name: "r130_C_SMITH_applied", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID, phase: "applied")
        phaseBarrier("applied", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)
        closeWardrobe()

        app.terminate()
        launchCandidate(saveKey: saveKey)
        navigateToCompanions()
        openWardrobe()
        chooseActor("アイラ")
        let afterColdOpen = appearanceButton(appearanceID, preview: false)
        reveal(afterColdOpen)
        XCTAssertEqual(afterColdOpen.label, "選択中")
        XCTAssertFalse(afterColdOpen.isEnabled)
        attachEvidence(name: "r130_C_SMITH_cold_selected", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID, phase: "cold_selected")
        phaseBarrier("cold_selected", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)

        let reset = app.buttons["標準衣装に戻す"]
        reveal(reset)
        assertTapTarget(reset)
        reset.tap()
        let resetCandidate = appearanceButton(appearanceID, preview: false)
        reveal(resetCandidate)
        XCTAssertTrue(waitForLabel(resetCandidate, "この見た目を使う"), "Reset clears selection while candidate ownership remains")
        XCTAssertTrue(resetCandidate.isEnabled)
        attachEvidence(name: "r130_C_SMITH_reset", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID, phase: "reset")
        phaseBarrier("reset", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)
        closeWardrobe()

        app.terminate()
        launchCandidate(saveKey: saveKey)
        navigateToCompanions()
        openWardrobe()
        chooseActor("アイラ")
        let afterResetReopen = appearanceButton(appearanceID, preview: false)
        reveal(afterResetReopen)
        XCTAssertEqual(afterResetReopen.label, "この見た目を使う")
        XCTAssertTrue(afterResetReopen.isEnabled)
        attachEvidence(name: "r130_C_SMITH_cold_reset", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID, phase: "cold_reset")
        phaseBarrier("cold_reset", saveKey: saveKey, actorID: "C_SMITH", appearanceID: appearanceID)
    }

    private func candidateArguments(saveKey: String) -> [String] {
        [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "--qa-candidate-scene-r124",
            "--qa-isolated",
            "--qa-save-key=\(saveKey)",
            "--qa-wardrobe-candidate-r128",
            "--qa-luna-mantle-r097",
            "--qa-luna-mantle-offsets-r127",
            "--qa-noir-neckwear-r124",
            "--qa-aira-apron-r130"
        ]
    }

    private func launchCandidate(saveKey: String) {
        app.launchArguments = candidateArguments(saveKey: saveKey)
        app.launch()
        let tab = app.buttons["tab_仲間"]
        let adaptiveMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || adaptiveMenu.waitForExistence(timeout: 20),
                      "Candidate-enabled app must reach normal navigation")
    }

    private func navigateToCompanions() {
        let tab = app.buttons["tab_仲間"]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "画面を選ぶ、")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 8), "Large Dynamic Type navigation menu must be exposed")
            menu.tap()
            let choose = app.buttons["choose_tab_仲間"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            choose.tap()
        }
        XCTAssertTrue(app.buttons["試着"].waitForExistence(timeout: 8))
    }

    private func openWardrobe() {
        let entry = app.buttons["試着"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable, "Wardrobe entry must be reachable in the current layout")
        entry.tap()
        XCTAssertTrue(app.scrollViews["sheet_scroll_試着"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["wardrobe_actor_picker"].exists)
    }

    private func chooseActor(_ actorName: String) {
        let picker = app.descendants(matching: .any)["wardrobe_actor_picker"]
        XCTAssertTrue(picker.exists)
        reveal(picker)
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let menuChoice = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", actorName, "companion_")).firstMatch
        XCTAssertTrue(menuChoice.waitForExistence(timeout: 5), "Actor menu must expose \(actorName)")
        menuChoice.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", actorName), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "The wardrobe picker itself must select the intended actor")
    }

    private func captureThumbnail(actorName: String, actorID: String, appearanceID: String,
                                  saveKey: String, phase: String) {
        chooseActor(actorName)
        let titleByID = [
            "LUNA_MANTLE_CANDIDATE_R128": "ルナ・苔色の肩掛け（候補）",
            "NOIR_NECKWEAR_MOSS_R001": "ノワール・苔色の首元飾り（候補）",
            "AIRA_HARVEST_APRON_GREEN_CANDIDATE_R130": "アイラ・採集工房の前掛け（候補・未承認）"
        ]
        let title = app.staticTexts.matching(NSPredicate(format: "label == %@", titleByID[appearanceID] ?? "")).firstMatch
        reveal(title)
        let preview = appearanceButton(appearanceID, preview: true)
        reveal(preview)
        XCTAssertTrue(title.exists && !title.frame.isEmpty && title.isHittable,
                      "Candidate title must be visible with its cropped thumbnail: \(appearanceID)")
        XCTAssertEqual(title.label, titleByID[appearanceID])
        assertTapTarget(preview)
        let scroll = app.scrollViews["sheet_scroll_試着"]
        let viewport = scroll.frame.insetBy(dx: 1, dy: 2)
        XCTAssertTrue(fullyInside(title.frame, container: viewport), "Thumbnail title must be wholly in the active scroll viewport")
        XCTAssertTrue(fullyInside(preview.frame, container: viewport), "Candidate action must be wholly in the active scroll viewport")
        attachEvidence(name: "r130_\(actorID)_\(appearanceID)_thumbnail", saveKey: saveKey,
                       actorID: actorID, appearanceID: appearanceID, phase: phase)
        phaseBarrier(phase, saveKey: saveKey, actorID: actorID, appearanceID: appearanceID)
    }

    private func closeWardrobe() {
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "閉じる")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertFalse(app.scrollViews["sheet_scroll_試着"].waitForExistence(timeout: 2))
    }

    private func appearanceButton(_ id: String, preview: Bool) -> XCUIElement {
        // SwiftUI propagates the enclosing row identifier to its buttons.
        let labels = preview ? ["この見た目を試す", "試着中"] : ["この見た目を使う", "選択中"]
        return app.buttons.matching(identifier: "appearance_" + id)
            .matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews["sheet_scroll_試着"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(30)
        var steps = 0
        while Date() < deadline {
            let viewport = scroll.frame.insetBy(dx: 1, dy: 2)
            if element.exists && !element.frame.isEmpty && viewport.contains(element.frame) && element.isHittable { return }
            let towardEnd = element.exists && !element.frame.isEmpty ? element.frame.midY >= viewport.midY : steps % 3 != 1
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardEnd ? 0.70 : 0.30))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardEnd ? 0.42 : 0.58))
            start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
            steps += 1
        }
        let targetDescription = element.exists ? "target=\(element.identifier) frame=\(element.frame)" : "target_missing"
        let diagnostic = XCTAttachment(string: "\(targetDescription)\n\(app.debugDescription)")
        diagnostic.name = "r128_missing_control"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTFail("Control must be fully visible inside the active scroll viewport and hittable")
    }

    private func assertTapTarget(_ element: XCUIElement) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.width + 1e-9, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height + 1e-9, 44)
        XCTAssertTrue(fullyInside(element.frame, container: app.frame))
    }

    private func fullyInside(_ frame: CGRect, container: CGRect) -> Bool {
        frame.minX >= container.minX && frame.minY >= container.minY &&
        frame.maxX <= container.maxX && frame.maxY <= container.maxY
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
    }

    private func attachEvidence(name: String, saveKey: String, actorID: String,
                                appearanceID: String, phase: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let identity = XCTAttachment(string: "saveKey=\(saveKey)\nactorID=\(actorID)\nappearanceID=\(appearanceID)\nphase=\(phase)\nlaunchArguments=\(app.launchArguments.joined(separator: " "))")
        identity.name = name + "_identity"
        identity.lifetime = .keepAlways
        add(identity)
    }

    /// Exchange markers inside the UI runner's own Documents container. The
    /// outer host reads only the app's exact QA save; it never modifies it.
    private func phaseBarrier(_ phase: String, saveKey: String, actorID: String, appearanceID: String) {
        guard let token = ProcessInfo.processInfo.environment["WITCH_R130_RUN_TOKEN"], UUID(uuidString: token) != nil else {
            XCTFail("Unique WITCH_R130_RUN_TOKEN is required"); return
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("R130-" + token, isDirectory: true)
        let marker = directory.appendingPathComponent("\(saveKey)_\(phase).json")
        let release = directory.appendingPathComponent("\(saveKey)_\(phase)_verified.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: marker.path), !FileManager.default.fileExists(atPath: release.path) else {
                XCTFail("A phase marker must never reuse stale evidence"); return
            }
            let payload: [String: String] = ["saveKey": saveKey, "phase": phase, "runToken": token,
                "actorID": actorID, "appearanceID": appearanceID,
                "testProcessID": String(ProcessInfo.processInfo.processIdentifier)]
            try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: marker, options: [.atomic])
        } catch { XCTFail("Could not publish phase marker: \(error)"); return }
        let expected = phase == "preview_baseline" ? "BASELINE_CAPTURED" :
            (["thumbnail_luna", "thumbnail_noir", "thumbnail_aira", "preview_only",
              "preview_closed", "preview_reopened"].contains(phase) ? "BYTE_IDENTICAL" : "STATE_VERIFIED")
        let deadline = ProcessInfo.processInfo.systemUptime + 45
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let data = try? Data(contentsOf: release),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               object["saveKey"] == saveKey, object["phase"] == phase,
               object["runToken"] == token, object["actorID"] == actorID,
               object["appearanceID"] == appearanceID, object["status"] == expected { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Runner did not verify persistence at \(phase)")
    }
}
