import XCTest

final class AccessibilityContrastDiagnosticTests: XCTestCase {
    private var app = XCUIApplication()

    func testJournalContrastOnlyComparedWithAll() throws {
        for (scrolled, settleAfterSwipe) in [(false, false), (true, false), (true, true)] {
            for auditName in ["contrast", "all"] {
                app.terminate()
                app = XCUIApplication()
                app.launchArguments = ["--qa-isolated", "--qa-save-key=ax-contrast-r001-\(UUID().uuidString)", "--screen=採集帳"]
                app.launch()
                XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout: 20))
                if scrolled { app.swipeUp() }
                if settleAfterSwipe { Thread.sleep(forTimeInterval: 1) }
                let viewport = !scrolled ? "top" : (settleAfterSwipe ? "scrolled_settled" : "scrolled_immediate")
                let label = "ax_\(viewport)_\(auditName)"
                attachScreenshot(label + "_before")
                attachTree(label + "_before_tree")
                var findings: [String] = []
                do {
                    let selected: XCUIAccessibilityAuditType = auditName == "contrast" ? .contrast : .all
                    try app.performAccessibilityAudit(for: selected) { issue in
                        findings.append("type=\(issue.auditType.rawValue) label=\(issue.element?.label ?? "") frame=\(String(describing: issue.element?.frame))\n\(issue.compactDescription)\n\(issue.detailedDescription)")
                        return true
                    }
                } catch {
                    findings.append("AUDIT_THROW: \(String(reflecting: error))")
                }
                let attachment = XCTAttachment(string: findings.isEmpty ? "No issues" : findings.joined(separator: "\n\n"))
                attachment.name = label + "_issues"
                attachment.lifetime = .keepAlways
                add(attachment)
                attachScreenshot(label + "_after")
                attachTree(label + "_after_tree")
                print("AX_DIAGNOSTIC=\(label) issueCount=\(findings.count)")
            }
        }
    }

    // The caller selects the Simulator content size. Record that setting with
    // the run; a pass at the default size must not be reported as maximum text.
    func testJournalLastChallengeReachableAtConfiguredTextSize() throws {
        app.launchArguments = ["--qa-isolated", "--qa-save-key=ax-journal-reach-\(UUID().uuidString)", "--screen=採集帳"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_採集帳"].waitForExistence(timeout: 20))
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let progress = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "雪灯草")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "Expected the reported progress text in the accessibility tree")
        // Fresh saves show a readable unlock condition instead of a disabled
        // action. Reachability must follow the actual unavailable state.
        let finalChallenge = app.descendants(matching:.any).matching(identifier:"challenge_lock_CH_R05_03").firstMatch
        guard finalChallenge.waitForExistence(timeout: 5) else {
            XCTFail("Expected the final challenge unlock condition in the accessibility tree")
            attachScreenshot("journal_final_condition_missing");attachTree("journal_final_condition_missing_tree")
            return
        }
        XCTAssertTrue(finalChallenge.label.contains("第五地域の最終ボス討伐で解放"))
        XCTAssertFalse(app.buttons["challenge_CH_R05_03"].exists)

        let progressFullyVisible = revealFully(progress, in: scroll, label: "journal_progress_scroll_steps")
        let progressAttachment = XCTAttachment(string: "scrollFrame=\(scroll.frame)\nprogressFrame=\(progress.frame)\nfullyVisible=\(progressFullyVisible)\nlabel=\(progress.label)")
        progressAttachment.name = "journal_reported_progress_reachability"
        progressAttachment.lifetime = .keepAlways
        add(progressAttachment)
        attachScreenshot("journal_reported_progress_reachability")
        attachTree("journal_reported_progress_reachability_tree")

        let fullyVisible = revealFully(finalChallenge, in: scroll, label: "journal_final_scroll_steps")

        let attachment = XCTAttachment(string: "scrollFrame=\(scroll.frame)\nfinalChallengeFrame=\(finalChallenge.frame)\nfullyVisible=\(fullyVisible)\nlabel=\(finalChallenge.label)\nenabled=\(finalChallenge.isEnabled)\nprogressFullyVisibleAtPriorCheckpoint=\(progressFullyVisible)")
        attachment.name = "journal_final_challenge_reachability"
        attachment.lifetime = .keepAlways
        add(attachment)
        attachScreenshot("journal_final_challenge_reachability")
        attachTree("journal_final_challenge_reachability_tree")
        XCTAssertTrue(fullyVisible, "Final research challenge must be fully within the scroll viewport after scrolling")
        XCTAssertTrue(progressFullyVisible, "Reported progress text must be fully within the scroll viewport at some reachable position")
    }

    private func revealFully(_ element: XCUIElement, in scroll: XCUIElement, label: String) -> Bool {
        var positions: [String] = []
        defer {
            let trace = XCTAttachment(string: positions.joined(separator: "\n"))
            trace.name = label; trace.lifetime = .keepAlways; add(trace)
        }
        for step in 0..<80 {
            let viewport = scroll.frame, target = element.frame
            positions.append("step=\(step) viewport=\(viewport) target=\(target)")
            if target.height > 0 && target.minY >= viewport.minY && target.maxY <= viewport.maxY { return true }
            guard viewport.height > 0, target.height > 0, target.height <= viewport.height else { return false }
            // A full inertial swipe can skip a 200-pt text block in a 402-pt
            // viewport. Use bounded drags and correct direction after overshoot;
            // retain the same complete-visibility requirement.
            let distance = target.midY - viewport.midY
            let fraction = min(0.4, max(0.08, abs(distance) / viewport.height))
            let startY = distance > 0 ? 0.72 : 0.28
            let endY = startY + (distance > 0 ? -fraction : fraction)
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachTree(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
