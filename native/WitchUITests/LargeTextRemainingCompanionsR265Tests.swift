import Foundation
import XCTest

/// Evidence-only extension of R247 coverage. One ordinary, pre-existing save per case.
/// Passing means the requested UI predicates were observed, not visual-quality approval.
final class LargeTextRemainingCompanionsR265Tests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "local.witch.autonomous.r1")
    private let category = "UICTContentSizeCategoryAccessibilityXXXL"
    private var launched = false
    private var captured = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let expected = env["WITCH_R265_EXPECTED_SAVE_SHA256"] ?? ""
        let preflight = env["WITCH_R265_PREFLIGHT_SAVE_SHA256"] ?? ""
        guard isSHA256(expected), expected == preflight,
              let token = env["WITCH_R265_RUN_TOKEN"], UUID(uuidString: token) != nil else {
            throw NSError(domain: "R265Preflight", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Host must bind the unchanged ordinary save hash and a fresh run token before launch"])
        }
    }

    override func tearDownWithError() throws {
        if launched && !captured {
            capture(stage: "teardown", actorID: "UNKNOWN", expectedName: "UNKNOWN")
        }
        if launched && (app.state == .runningForeground || app.state == .runningBackground) { app.terminate() }
        try super.tearDownWithError()
    }

    func testApprenticeContextAtAXXXL_R265() throws { inspect(actorID: "C_APPRENTICE", name: "ルナ") }
    func testFamiliarContextAtAXXXL_R265() throws { inspect(actorID: "C_FAMILIAR", name: "ノワール") }
    func testSmithContextAtAXXXL_R265() throws { inspect(actorID: "C_SMITH", name: "アイラ") }

    private func inspect(actorID: String, name: String) {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
        // No QA, fixture, save-key, time, reward, or purchase flags reach the app.
        app.launchEnvironment = [:]
        app.launch()
        launched = true

        let tab = element("tab_仲間")
        if !tab.waitForExistence(timeout: 12) {
            let home = element("tab_家")
            guard home.waitForExistence(timeout: 8), home.isHittable else {
                capture(stage: "home_unavailable", actorID: actorID, expectedName: name)
                XCTFail("Could not open companion screen")
                return
            }
            home.tap()
            let destination = element("choose_tab_仲間")
            guard destination.waitForExistence(timeout: 8), destination.isHittable else {
                capture(stage: "companion_navigation_unavailable", actorID: actorID, expectedName: name)
                XCTFail("Companion navigation unavailable")
                return
            }
            destination.tap()
        } else if !tab.isSelected && tab.isHittable {
            tab.tap()
        }

        let scroll = element("companion_scroll")
        guard scroll.waitForExistence(timeout: 12) else {
            capture(stage: "scroll_missing", actorID: actorID, expectedName: name)
            XCTFail("companion_scroll missing")
            return
        }
        let selector = element("companion_" + actorID)
        let initialDirection: CGFloat = actorID == "C_APPRENTICE" ? 1 : -1
        guard reveal(selector, in: scroll, directionWhenMissing: initialDirection), selector.isHittable else {
            capture(stage: "selector_unavailable", actorID: actorID, expectedName: name)
            XCTFail("Selector unavailable for \(actorID)")
            return
        }
        selector.tap()

        let portrait = element("living_scene")
        _ = reveal(portrait, in: scroll, directionWhenMissing: -1)
        // Preserve screenshot and AX tree before querying element properties/asserting.
        capture(stage: "selected_context_and_portrait", actorID: actorID, expectedName: name)

        let context = element("companion_selected_context")
        let contextExists = context.exists
        let portraitExists = portrait.exists
        let appRect = finiteRect(app.frame)
        let contextRect = contextExists ? finiteRect(context.frame) : nil
        let portraitRect = portraitExists ? finiteRect(portrait.frame) : nil
        let scrollRect = scroll.exists ? finiteRect(scroll.frame) : nil
        let contextLabel = contextExists ? context.label.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let contextValue = contextExists ? String(describing: context.value ?? "<nil>") : nil
        let contextInApp: Bool? = {
            guard let appRect, let contextRect, !contextRect.isEmpty else { return nil }
            return appRect.contains(contextRect)
        }()
        let portraitInViewport: Bool? = {
            guard let appRect, let scrollRect, let portraitRect else { return nil }
            return scrollRect.intersection(appRect).insetBy(dx: 2, dy: 3).contains(portraitRect)
        }()

        XCTAssertTrue(contextExists, "Expected companion_selected_context")
        if contextExists {
            XCTAssertEqual(contextLabel, "表示中の仲間")
            XCTAssertEqual(contextValue, name, "Selected actor ID \(actorID) must map to \(name)")
        }
        XCTAssertEqual(contextInApp, true, "Context banner must be fully inside app bounds")
        XCTAssertTrue(portraitExists, "living_scene portrait must exist")
        XCTAssertNotNil(portraitRect, "Portrait bounds must be finite")
        XCTAssertEqual(portraitInViewport, true, "Portrait must fit in the visible scroll viewport")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func reveal(_ target: XCUIElement, in scroll: XCUIElement, directionWhenMissing: CGFloat) -> Bool {
        guard scroll.exists, scroll.frame.width > 0, scroll.frame.height > 0 else { return false }
        for step in 0..<24 {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 2, dy: 3)
            if target.exists && !target.frame.isEmpty && viewport.contains(target.frame) { return true }
            guard !viewport.isEmpty else { return false }
            let direction: CGFloat
            if !target.exists || target.frame.isEmpty { direction = directionWhenMissing }
            else if target.frame.maxY > viewport.maxY { direction = -1 }
            else if target.frame.minY < viewport.minY { direction = 1 }
            else { direction = step.isMultiple(of: 2) ? -1 : 1 }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (viewport.midX - scroll.frame.minX) / scroll.frame.width,
                dy: (viewport.midY - scroll.frame.minY) / scroll.frame.height))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * 85)))
        }
        return target.exists && !target.frame.isEmpty && scroll.frame.intersection(app.frame).contains(target.frame)
    }

    private func capture(stage: String, actorID: String, expectedName: String) {
        guard !captured else { return }
        captured = true
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "R265_\(stage)_\(actorID)_PNG"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "R265_\(stage)_\(actorID)_AX"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        let appRect = finiteRect(app.frame)
        let context = element("companion_selected_context")
        let portrait = element("living_scene")
        let contextExists = context.exists
        let portraitExists = portrait.exists
        let contextRect = contextExists ? finiteRect(context.frame) : nil
        let portraitRect = portraitExists ? finiteRect(portrait.frame) : nil
        let contextLabel: Any = contextExists ? context.label : NSNull()
        let contextValue: Any = contextExists ? String(describing: context.value ?? "<nil>") : NSNull()
        let portraitLabel: Any = portraitExists ? portrait.label : NSNull()
        let geometry: [String: Any] = [
            "schema": "r265.companion_context_geometry.v1", "stage": stage,
            "actorID": actorID, "expectedDisplayName": expectedName,
            "requestedCategory": category, "runtimeCategory": "NOT_DIRECTLY_EXPOSED_BY_XCUITEST",
            "appFrame": jsonRect(appRect), "contextExists": contextExists,
            "contextLabel": contextLabel, "contextValue": contextValue,
            "contextFrame": jsonRect(contextRect), "portraitExists": portraitExists,
            "portraitLabel": portraitLabel,
            "portraitFrame": jsonRect(portraitRect)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "R265_\(stage)_\(actorID)_geometry"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func finiteRect(_ r: CGRect) -> CGRect? {
        let v = [r.origin.x, r.origin.y, r.width, r.height, r.maxX, r.maxY]
        return v.allSatisfy { $0.isFinite } ? r : nil
    }

    private func jsonRect(_ r: CGRect?) -> Any {
        guard let r else { return NSNull() }
        return ["x": Double(r.minX), "y": Double(r.minY), "width": Double(r.width), "height": Double(r.height)]
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
        }
    }
}
