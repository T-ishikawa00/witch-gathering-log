import Foundation
import XCTest

/// Read-only UI inspection of the existing host-pinned development save.
/// The host must verify the exact save and prior-file inventory before launch.
final class LargeTextCompanionReachabilityR233Tests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "local.witch.autonomous.r1")
    private let actors: [(id: String, name: String)] = [
        ("C_WITCH", "エルナ"),
        ("C_APPRENTICE", "ルナ"),
        ("C_SMITH", "アイラ"),
        ("C_FAMILIAR", "ノワール")
    ]
    private let wallBudget: TimeInterval = 540
    private var startedAt: TimeInterval = 0
    private var screenshotCount = 0
    private var didLaunch = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        startedAt = ProcessInfo.processInfo.systemUptime
        let environment = ProcessInfo.processInfo.environment
        let expectedSave = environment["WITCH_R233_EXPECTED_SAVE_SHA256"] ?? ""
        let preflightSave = environment["WITCH_R233_PREFLIGHT_SAVE_SHA256"] ?? ""
        guard isStrictSHA256(expectedSave), isStrictSHA256(preflightSave), expectedSave == preflightSave else {
            throw NSError(domain: "R233Preflight", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Host must pin the current development save immediately before the test; expected and preflight SHA-256 values must match"])
        }
        guard let token = environment["WITCH_R233_RUN_TOKEN"],
              UUID(uuidString: token) != nil else {
            throw NSError(domain: "R233Preflight", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Host must provide a fresh, unique R233 run UUID and exclusive output directory"])
        }
    }

    override func tearDownWithError() throws {
        if didLaunch && (app.state == .runningForeground || app.state == .runningBackground) {
            app.terminate()
        }
        try super.tearDownWithError()
    }

    func testFourCompanionContextsAndScrollableSummariesAtAccessibilityXXXL_R233() throws {
        // This is the only app argument: UIKit Dynamic Type. No QA, fixture,
        // save, time, reward, or gameplay override is passed to the app.
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment = [:]
        XCTAssertEqual(app.launchArguments, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.launchEnvironment.isEmpty)
        app.launch()
        didLaunch = true

        XCTAssertTrue(identified("tab_家").waitForExistence(timeout: 30), app.debugDescription)
        navigateToCompanions()
        let scroll = app.scrollViews["companion_scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 12), "The accessibility-size companion screen must expose its real scroll view")
        XCTAssertGreaterThan(scroll.frame.height, 0)

        for actor in actors {
            // Query by identifier across AX element types: accessibility-size
            // SwiftUI controls may surface as Button or PopUpButton.
            let selector = identified("companion_" + actor.id)
            XCTAssertTrue(reveal(selector, in: scroll, maxSteps: 40, actorID: actor.id, phase: "selector"),
                          "Actor selector must be scroll-reachable: \(actor.id)\n\(app.debugDescription)")
            XCTAssertTrue(selector.isHittable, "Actor selector must be actionable after reveal: \(actor.id)")
            selector.tap()
            XCTAssertEqual(selector.value as? String, "選択中", "The selected actor identity must match \(actor.id)")

            let portrait = app.descendants(matching: .any).matching(identifier: "living_scene").firstMatch
            XCTAssertTrue(reveal(portrait, in: scroll, maxSteps: 40, actorID: actor.id, phase: "portrait"),
                          "Portrait viewport must be scroll-reachable: \(actor.id)\n\(app.debugDescription)")
            XCTAssertTrue(isFullyVisible(portrait, in: scroll), "Portrait must fit inside the visible scroll viewport for \(actor.id)")
            XCTAssertTrue(isFullyVisibleInApp(identified("companion_selected_context")), "Actor context must remain visible beside portrait")
            capture("xxxl_\(actor.id)_portrait")

            let stats = identified("companion_stats")
            let level = identified("companion_level")
            let weapon = identified("companion_equipped_weapon")
            XCTAssertTrue(reveal(stats, in: scroll, maxSteps: 40, actorID: actor.id, phase: "summary"),
                          "Combat summary must be scroll-reachable: \(actor.id)\n\(app.debugDescription)")
            // Keep the evidence even when a neighboring summary field does not
            // fit: the failing screen then shows the actual large-text state.
            capture("xxxl_\(actor.id)_summary")
            // The selected name is pinned outside the scroll viewport for
            // accessibility sizes, so each detail can be read independently
            // without losing the actor context. Do not require all fields to
            // fit together in an XXXL viewport.
            let context = identified("companion_selected_context")
            XCTAssertTrue(context.exists && isFullyVisibleInApp(context), "Selected actor context must stay visible for \(actor.id)")
            XCTAssertEqual(context.value as? String, actor.name, "Pinned context must identify the selected actor")
            XCTAssertTrue(reveal(weapon, in: scroll, maxSteps: 40, actorID: actor.id, phase: "weapon"),
                          "Equipped item must be scroll-reachable for \(actor.id)\n\(app.debugDescription)")
            XCTAssertTrue(hasReadableVisibleLabel(weapon, in: scroll), "Equipped item must be readable for \(actor.id)")
            XCTAssertTrue(isFullyVisibleInApp(context), "Actor context must remain visible beside the equipped item")
            XCTAssertTrue(reveal(level, in: scroll, maxSteps: 40, actorID: actor.id, phase: "level"),
                          "Level must be scroll-reachable for \(actor.id)\n\(app.debugDescription)")
            XCTAssertTrue(hasReadableVisibleLabel(level, in: scroll), "Level must be readable for \(actor.id)")
            XCTAssertTrue(isFullyVisibleInApp(context), "Actor context must remain visible beside level")
            XCTAssertTrue(reveal(stats, in: scroll, maxSteps: 40, actorID: actor.id, phase: "stats"),
                          "Stats must be scroll-reachable for \(actor.id)\n\(app.debugDescription)")
            XCTAssertTrue(hasReadableVisibleLabel(stats, in: scroll), "Stats must be readable for \(actor.id)")
            XCTAssertTrue(isFullyVisibleInApp(context), "Actor context must remain visible beside stats")
            let compare = app.buttons["inventory"]
            XCTAssertTrue(reveal(compare, in: scroll, maxSteps: 40, actorID: actor.id, phase: "comparison_entry"),
                          "Equipment comparison entry must be scroll-reachable for \(actor.id)\n\(app.debugDescription)")
            XCTAssertTrue(compare.isHittable, "Equipment comparison entry must be actionable for \(actor.id)")
            XCTAssertTrue(isFullyVisibleInApp(context), "Actor context must remain visible at the comparison entry")
            // The selector's selected value and pinned context verify actor identity.
            // LazyVGrid selectors leave the accessibility tree below the fold;
            // do not query an offscreen selector after scrolling to the summary.
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, wallBudget,
                              "R233 is bounded to nine minutes; preserve partial screenshots on timeout")
        }

        XCTAssertEqual(screenshotCount, 8, "Expected exactly two viewport screenshots for each of four companions")
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, wallBudget)
    }

    private func navigateToCompanions() {
        let tab = identified("tab_仲間")
        if tab.waitForExistence(timeout: 2) {
            if !tab.isSelected {
                XCTAssertTrue(tab.isHittable, app.debugDescription)
                tab.tap()
            }
        } else {
            // At accessibility Dynamic Type the current footer Menu carries
            // the current tab identifier. Query by identifier across AX types.
            let menu = identified("tab_家")
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "Adaptive footer Menu must remain reachable\n\(app.debugDescription)")
            XCTAssertTrue(menu.isHittable, app.debugDescription)
            menu.tap()
            let destination = identified("choose_tab_仲間")
            XCTAssertTrue(destination.waitForExistence(timeout: 8), "Adaptive footer must expose companion destination")
            XCTAssertTrue(destination.isHittable, app.debugDescription)
            destination.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "living_scene").firstMatch
            .waitForExistence(timeout: 12), "Companion portrait scene is required")
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, maxSteps: Int,
                        actorID: String, phase: String) -> Bool {
        guard withinBudget(actorID: actorID, phase: phase, reason: "before reveal") else { return false }
        guard scroll.waitForExistence(timeout: min(8, remainingBudget)) else {
            attachFailure(actorID: actorID, phase: phase, reason: "companion_scroll missing")
            return false
        }
        for step in 0..<maxSteps {
            guard withinBudget(actorID: actorID, phase: phase, reason: "before drag \(step + 1)") else { return false }
            if isFullyVisible(element, in: scroll) { return true }
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 2, dy: 3)
            guard !viewport.isEmpty, scroll.frame.width > 0, scroll.frame.height > 0 else {
                attachFailure(actorID: actorID, phase: phase, reason: "empty scroll viewport")
                return false
            }
            let target = element.exists ? element.frame : .zero
            let direction: CGFloat
            if !element.exists || target.isEmpty {
                // The only lazy content is the selector grid above the portrait.
                direction = phase == "selector" ? 1 : (step.isMultiple(of: 2) ? -1 : 1)
            } else if target.maxY > viewport.maxY {
                direction = -1
            } else if target.minY < viewport.minY {
                direction = 1
            } else {
                direction = step.isMultiple(of: 2) ? -1 : 1
            }
            let distance: CGFloat
            if element.exists && !target.isEmpty {
                distance = min(120, max(32, direction < 0 ? target.maxY - viewport.maxY + 18 : viewport.minY - target.minY + 18))
            } else {
                distance = step.isMultiple(of: 2) ? 90 : -90
            }
            let startY = min(max(viewport.midY, viewport.minY + abs(distance) / 2 + 6), viewport.maxY - abs(distance) / 2 - 6)
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (viewport.midX - scroll.frame.minX) / scroll.frame.width,
                dy: (startY - scroll.frame.minY) / scroll.frame.height))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * abs(distance))))
        }
        guard withinBudget(actorID: actorID, phase: phase, reason: "after \(maxSteps) drags") else { return false }
        guard isFullyVisible(element, in: scroll) else {
            attachFailure(actorID: actorID, phase: phase, reason: "not visible after \(maxSteps) drags")
            return false
        }
        return true
    }

    private var remainingBudget: TimeInterval {
        max(0, wallBudget - (ProcessInfo.processInfo.systemUptime - startedAt))
    }

    private func withinBudget(actorID: String, phase: String, reason: String) -> Bool {
        guard remainingBudget > 0 else {
            attachFailure(actorID: actorID, phase: phase, reason: "540-second wall budget exceeded: \(reason)")
            return false
        }
        return true
    }

    private func attachFailure(actorID: String, phase: String, reason: String) {
        let label = "R233_FAILURE_\(actorID)_\(phase)"
        if screenshotCount < 8 && didLaunch {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = label
            screenshot.lifetime = .keepAlways
            add(screenshot)
            screenshotCount += 1
        }
        let diagnostic = XCTAttachment(string: "actor=\(actorID)\nphase=\(phase)\nreason=\(reason)\n\(app.debugDescription)")
        diagnostic.name = "\(label)_AX"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
    }

    private func isStrictSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        }
    }

    private func identified(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func hasReadableVisibleLabel(_ element: XCUIElement, expected: String? = nil,
                                         in scroll: XCUIElement) -> Bool {
        guard isFullyVisible(element, in: scroll) else { return false }
        let rendered = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rendered.isEmpty else { return false }
        if let expected { return rendered == expected }
        return true
    }

    private func isFullyVisibleInApp(_ element: XCUIElement) -> Bool {
        guard element.exists, !element.frame.isEmpty else { return false }
        let viewport = app.frame.insetBy(dx: 2, dy: 3)
        return viewport.contains(element.frame)
    }

    /// Geometric visibility only. Hit-testing is asserted separately for
    /// controls that the player can activate.
    private func isFullyVisible(_ element: XCUIElement, in scroll: XCUIElement) -> Bool {
        guard element.exists, !element.frame.isEmpty, scroll.exists else { return false }
        let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 2, dy: 3)
        return viewport.contains(element.frame)
    }

    private func capture(_ name: String) {
        guard screenshotCount < 8 else { XCTFail("R233 screenshot cap exceeded"); return }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "R233_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        screenshotCount += 1
    }
}
