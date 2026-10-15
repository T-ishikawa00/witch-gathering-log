import Foundation
import XCTest

/// One-actor evidence capture for the R233 AXXXL selected-context ambiguity.
/// A passing test means evidence was collected, not that the UI is accepted.
final class LargeTextContextDiagnosticR247Tests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "local.witch.autonomous.r1")
    private let requestedCategory = "UICTContentSizeCategoryAccessibilityXXXL"
    private var launched = false
    private var captured = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let expected = environment["WITCH_R233_EXPECTED_SAVE_SHA256"] ?? ""
        let preflight = environment["WITCH_R233_PREFLIGHT_SAVE_SHA256"] ?? ""
        guard isSHA256(expected), expected == preflight,
              let token = environment["WITCH_R233_RUN_TOKEN"], UUID(uuidString: token) != nil else {
            throw NSError(domain: "R247Preflight", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Require matching host-pinned save hashes and a fresh R233 run token before launch"])
        }
    }

    override func tearDownWithError() throws {
        if launched && !captured {
            attachEvidence(stage: "teardown_fallback", actorID: "C_WITCH", scroll: element("companion_scroll"),
                           portrait: element("living_scene"), context: element("companion_selected_context"))
        }
        if launched && (app.state == .runningForeground || app.state == .runningBackground) { app.terminate() }
        try super.tearDownWithError()
    }

    func testCaptureContextPredicatesBeforeClassification_R247() throws {
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", requestedCategory]
        // Keep the application launch free of QA, fixture, save-key, time, or reward flags.
        app.launchEnvironment = [:]
        app.launch()
        launched = true

        let companionTab = element("tab_仲間")
        if !companionTab.waitForExistence(timeout: 12) {
            let home = element("tab_家")
            guard home.waitForExistence(timeout: 8), home.isHittable else {
                attachEvidence(stage: "companion_tab_unavailable", actorID: "C_WITCH",
                               scroll: element("companion_scroll"), portrait: element("living_scene"),
                               context: element("companion_selected_context"))
                XCTFail("Could not reach companion navigation; diagnostic evidence attached")
                return
            }
            home.tap()
            let destination = element("choose_tab_仲間")
            guard destination.waitForExistence(timeout: 8), destination.isHittable else {
                attachEvidence(stage: "companion_menu_unavailable", actorID: "C_WITCH",
                               scroll: element("companion_scroll"), portrait: element("living_scene"),
                               context: element("companion_selected_context"))
                XCTFail("Companion menu entry unavailable; diagnostic evidence attached")
                return
            }
            destination.tap()
        } else if !companionTab.isSelected && companionTab.isHittable {
            companionTab.tap()
        }

        let scroll = element("companion_scroll")
        guard scroll.waitForExistence(timeout: 12) else {
            attachEvidence(stage: "scroll_missing", actorID: "C_WITCH", scroll: scroll,
                           portrait: element("living_scene"), context: element("companion_selected_context"))
            XCTFail("Companion scroll view missing; diagnostic evidence attached")
            return
        }

        let selector = element("companion_C_WITCH")
        guard reveal(selector, in: scroll, directionWhenMissing: 1), selector.isHittable else {
            attachEvidence(stage: "witch_selector_unavailable", actorID: "C_WITCH", scroll: scroll,
                           portrait: element("living_scene"), context: element("companion_selected_context"))
            XCTFail("C_WITCH selector unavailable; diagnostic evidence attached")
            return
        }
        selector.tap()

        let portrait = element("living_scene")
        _ = reveal(portrait, in: scroll, directionWhenMissing: -1)
        // Capture screenshot, full AX hierarchy and independent geometry/label predicates
        // before any assertion classifies the selected-context result.
        attachEvidence(stage: "after_witch_selection_and_portrait_reveal", actorID: "C_WITCH",
                       scroll: scroll, portrait: portrait, context: element("companion_selected_context"))

        let context = element("companion_selected_context")
        // Evaluate only after screenshot/AX capture. Missing elements are recorded
        // as absent and their other XCUI getters are never touched.
        let contextExists = context.exists
        let portraitExists = portrait.exists
        let appRect = finiteRect(app.frame)
        let scrollRect = scroll.exists ? finiteRect(scroll.frame) : nil
        let portraitRect = portraitExists ? finiteRect(portrait.frame) : nil
        let contextRect = contextExists ? finiteRect(context.frame) : nil
        let contextLabel = contextExists ? context.label.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let contextValue = contextExists ? String(describing: context.value ?? "<nil>") : nil
        let portraitInsideViewport: Bool? = {
            guard let a = appRect, let s = scrollRect, let p = portraitRect, !p.isEmpty else { return nil }
            return s.intersection(a).insetBy(dx: 2, dy: 3).contains(p)
        }()
        let contextInsideAppFrame: Bool? = {
            guard let a = appRect, let c = contextRect, !c.isEmpty else { return nil }
            return a.contains(c)
        }()

        XCTAssertTrue(portraitExists, "Portrait existence is part of the original failure precondition")
        XCTAssertNotNil(portraitRect, "Portrait rectangle must be finite and readable")
        XCTAssertEqual(portraitInsideViewport, true, "Portrait must fit before context geometry is classified")
        XCTAssertTrue(contextExists, "AX existence: companion_selected_context")
        if contextExists {
            XCTAssertEqual(contextLabel, "表示中の仲間", "AX label is checked independently from existence and geometry")
            XCTAssertNotNil(contextRect, "Existing AX element must have a finite frame")
            XCTAssertEqual(contextInsideAppFrame, true, "AX frame must be contained by the application frame")
            XCTAssertEqual(contextValue, "エルナ", "AX selected actor value must identify C_WITCH")
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
            let startY = viewport.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (viewport.midX - scroll.frame.minX) / scroll.frame.width,
                dy: (startY - scroll.frame.minY) / scroll.frame.height))
            start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * 85)))
        }
        return target.exists && !target.frame.isEmpty && scroll.frame.intersection(app.frame).contains(target.frame)
    }

    private func attachEvidence(stage: String, actorID: String, scroll: XCUIElement,
                                portrait: XCUIElement, context: XCUIElement) {
        guard !captured else { return }
        captured = true

        // Save visual and hierarchy evidence first. No frame/label/value/type
        // access occurs until both attachments have been registered.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "R247_\(stage)_\(actorID)_screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "R247_\(stage)_\(actorID)_AX_hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        let appFrame = finiteRect(app.frame)
        let scrollExists = scroll.exists
        let portraitExists = portrait.exists
        let contextExists = context.exists
        let scrollFrame = scrollExists ? finiteRect(scroll.frame) : nil
        let portraitFrame = portraitExists ? finiteRect(portrait.frame) : nil
        let contextFrame = contextExists ? finiteRect(context.frame) : nil
        let contextType: Any = contextExists ? String(describing: context.elementType) : NSNull()
        let contextLabel: Any = contextExists ? context.label : NSNull()
        let contextValue: Any = contextExists ? String(describing: context.value ?? "<nil>") : NSNull()
        let viewport: CGRect?
        if let appFrame, let scrollFrame {
            viewport = finiteRect(scrollFrame.intersection(appFrame).insetBy(dx: 2, dy: 3))
        } else {
            viewport = nil
        }
        let contextContained: Any
        if let appFrame, let contextFrame, !contextFrame.isEmpty {
            contextContained = appFrame.contains(contextFrame)
        } else {
            contextContained = NSNull()
        }
        let portraitContained: Any
        if let viewport, let portraitFrame, !viewport.isEmpty, !portraitFrame.isEmpty {
            portraitContained = viewport.contains(portraitFrame)
        } else {
            portraitContained = NSNull()
        }
        let values: [String: Any] = [
            "schema": "r247.context_diagnostic.v3",
            "stage": stage,
            "actorID": actorID,
            "requestedContentSizeCategory": requestedCategory,
            "runtimeContentSizeCategory": "NOT_DIRECTLY_EXPOSED_BY_THIS_XCUITEST",
            "launchArguments": app.launchArguments,
            "applicationLaunchEnvironmentEmpty": app.launchEnvironment.isEmpty,
            "contextExists": contextExists,
            "contextElementType": contextType,
            "contextLabel": contextLabel,
            "contextValue": contextValue,
            "contextFrame": jsonRect(contextFrame),
            "contextFrameStatus": frameStatus(exists: contextExists, frame: contextFrame),
            "contextFullyInsideAppFrame": contextContained,
            "appFrame": jsonRect(appFrame),
            "appFrameStatus": appFrame == nil ? "NONFINITE_OR_UNAVAILABLE" : "FINITE",
            "scrollExists": scrollExists,
            "scrollFrame": jsonRect(scrollFrame),
            "scrollFrameStatus": frameStatus(exists: scrollExists, frame: scrollFrame),
            "scrollVisibleViewport": jsonRect(viewport),
            "portraitExists": portraitExists,
            "portraitFrame": jsonRect(portraitFrame),
            "portraitFrameStatus": frameStatus(exists: portraitExists, frame: portraitFrame),
            "portraitFullyInsideScrollViewport": portraitContained
        ]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let geometry = XCTAttachment(string: text)
            geometry.name = "R247_\(stage)_\(actorID)_geometry_and_predicates"
            geometry.lifetime = .keepAlways
            add(geometry)
        } else {
            let fallback = XCTAttachment(string: "R247 geometry JSON encoding failed; screenshot and AX hierarchy are retained. stage=\(stage), actor=\(actorID)")
            fallback.name = "R247_\(stage)_\(actorID)_geometry_encoding_error"
            fallback.lifetime = .keepAlways
            add(fallback)
        }
    }

    private func finiteRect(_ rect: CGRect) -> CGRect? {
        let values = [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY]
        guard values.allSatisfy({ $0.isFinite }) else { return nil }
        return rect
    }

    private func jsonRect(_ rect: CGRect?) -> Any {
        guard let rect, finiteRect(rect) != nil else { return NSNull() }
        return ["x": Double(rect.origin.x), "y": Double(rect.origin.y),
                "width": Double(rect.width), "height": Double(rect.height),
                "maxX": Double(rect.maxX), "maxY": Double(rect.maxY)]
    }

    private func frameStatus(exists: Bool, frame: CGRect?) -> String {
        guard exists else { return "NOT_QUERIED_ELEMENT_ABSENT" }
        guard let frame else { return "UNAVAILABLE_OR_NONFINITE" }
        return frame.isEmpty || frame.width <= 0 || frame.height <= 0 ? "FINITE_EMPTY" : "FINITE_NONEMPTY"
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
        }
    }
}
