import XCTest

/// Read-only screenshots/geometry for the R045 split home candidate.
/// The collection/claim control is inspected but is never activated.
final class HomeAccessibilityR045Tests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHomeDefaultPreservesStandardComposition() {
        verifyStandard(label: "default", category: nil)
    }

    func testHomeLargePreservesStandardComposition() {
        verifyStandard(label: "large", category: "UICTContentSizeCategoryL")
    }

    func testHomeAXXXLSceneAndScrollableControls() {
        let key = launchHome(label: "axxxl", category: "UICTContentSizeCategoryAccessibilityXXXL")
        let scene = livingScene()
        let scroll = homeScroll()
        let sceneExists = scene.waitForExistence(timeout: 25)
        let scrollExists = scroll.waitForExistence(timeout: 10)
        let claim = app.buttons["claim_offline"]
        let claimExists = claim.waitForExistence(timeout: 10)
        let initialClaimFrame = claimExists ? claim.frame : .zero
        let initialClaimHittable = claimExists && claim.isHittable
        let initial = geometry(stage: "initial", saveKey: key, size: "AXXXL", scene: scene,
                               scroll: scroll, claimFrame: initialClaimFrame,
                               claimExists: claimExists, claimHittable: initialClaimHittable)
        // Preserve the actual failing state before any assertion can terminate the test.
        attachScreen(stage: "initial_before_assertions", key: key, size: "AXXXL")
        attachAccessibilityTree(stage: "initial_before_assertions", key: key)
        attachGeometry(initial)
        XCTAssertTrue(sceneExists, "home scene accessibility surface must load; initial evidence attached")
        XCTAssertTrue(scrollExists, "AX home scroll viewport must exist; initial evidence attached")
        XCTAssertTrue(claimExists, "claim control must be present; initial screen and accessibility tree attached")
        XCTAssertGreaterThanOrEqual(initial.sceneExposedFraction, 0.55,
            "The home scene must retain the planned upper ~58% visible area")
        XCTAssertGreaterThan(initial.scrollFrame.height, 0)
        XCTAssertLessThanOrEqual(initial.scrollFrame.height / initial.sceneFrame.height, 0.46,
            "The scroll sheet must not consume the reserved scene area")
        let label = scene.label
        for actor in ["エルナ", "ルナ", "アイラ", "ノワール"] {
            XCTAssertTrue(label.contains(actor), "Scene accessibility label should name the party member: \(actor)")
        }

        XCTAssertTrue(initialClaimHittable, "claim control should be reachable from initial AX home state")
        XCTAssertTrue(initial.scrollFrame.contains(claim.frame),
            "claim control must be wholly inside the initial visible scroll viewport")

        // Capture one intermediate scroll position without activating any controls.
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.72))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.48)))
        let mid = geometry(stage: "mid_scroll", saveKey: key, size: "AXXXL", scene: scene, scroll: scroll)
        XCTAssertGreaterThanOrEqual(mid.sceneExposedFraction, 0.55,
            "Scrolling the lower controls must not cover the reserved scene area")
        attachScreen(stage: "mid_scroll", key: key, size: "AXXXL")
        attachGeometry(mid)

        let controls: [(name: String, identifier: String?, match: String)] = [
            ("claim", "claim_offline", ""),
            ("furniture", nil, "模様替え"),
            ("magic_storage", nil, "魔導庫"),
            ("shop", nil, "衣装と家具"),
            ("explore", nil, "探索へ")
        ]
        for control in controls {
            let button = control.identifier.map { app.buttons[$0] }
                ?? app.buttons.matching(NSPredicate(format: "label CONTAINS %@", control.match)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10), "missing home control: \(control.name)")
            scrollUntilFullyVisible(button, in: scroll, scene: scene, stage: control.name, key: key)
            let state = geometry(stage: "control_\(control.name)", saveKey: key,
                                 size: "AXXXL", scene: scene, scroll: scroll)
            XCTAssertTrue(button.isHittable, "control must be reachable: \(control.name)")
            XCTAssertTrue(state.scrollFrame.contains(button.frame), "control must fit in viewport: \(control.name)")
            attachScreen(stage: "control_\(control.name)", key: key, size: "AXXXL")
            attachGeometry(state)
        }

        // Explicitly finish at the lower end and preserve evidence that the last control is visible.
        scroll.swipeUp()
        let bottom = geometry(stage: "bottom_scroll", saveKey: key, size: "AXXXL", scene: scene, scroll: scroll)
        let explore = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "探索へ")).firstMatch
        XCTAssertTrue(explore.isHittable)
        XCTAssertTrue(bottom.scrollFrame.contains(explore.frame))
        XCTAssertGreaterThanOrEqual(bottom.sceneExposedFraction, 0.55)
        attachScreen(stage: "bottom_scroll", key: key, size: "AXXXL")
        attachGeometry(bottom)
        attachIdentity(key: key, size: "AXXXL", claimTapCount: 0)
    }

    private func verifyStandard(label: String, category: String?) {
        let key = launchHome(label: label, category: category)
        let scene = livingScene()
        let scroll = homeScroll()
        let sceneExists = scene.waitForExistence(timeout: 25)
        let scrollExists = scroll.waitForExistence(timeout: 10)
        let claim = app.buttons["claim_offline"]
        let claimExists = claim.waitForExistence(timeout: 10)
        let state = geometry(stage: "standard", saveKey: key, size: label, scene: scene,
                             scroll: scroll, claimFrame: claimExists ? claim.frame : .zero,
                             claimExists: claimExists, claimHittable: claimExists && claim.isHittable)
        attachScreen(stage: "standard_before_assertions", key: key, size: label)
        attachAccessibilityTree(stage: "standard_before_assertions", key: key)
        attachGeometry(state)
        XCTAssertTrue(sceneExists, "home scene must load; initial evidence attached")
        XCTAssertTrue(scrollExists, "home scroll must load; initial evidence attached")
        XCTAssertTrue(claimExists, "claim must load; initial evidence attached")
        // Default and Large stay on the legacy full-area homeOverlayStandard branch.
        XCTAssertLessThanOrEqual(abs(state.scrollFrame.minY - state.sceneFrame.minY), 4.0,
            "Standard home scroll should still begin at the scene body's top")
        XCTAssertLessThanOrEqual(abs(state.scrollFrame.maxY - state.sceneFrame.maxY), 4.0,
            "Standard home scroll should still span the scene body")
        attachIdentity(key: key, size: label, claimTapCount: 0)
    }

    @discardableResult
    private func launchHome(label: String, category: String?) -> String {
        let key = "recipe-goal-r037-" + UUID().uuidString
        var args = ["--qa-isolated", "--qa-save-key=" + key,
                    "--qa-fixture=recipe-goal-r037", "--qa-recipe-goal=gather-shortage",
                    "--qa-persist-fixture", "--qa-recipe-goal-baseline", "--screen=家"]
        if let category { args.insert(contentsOf: ["-UIPreferredContentSizeCategoryName", category], at: 0) }
        app.launchArguments = args
        app.launch()
        return key
    }

    private func livingScene() -> XCUIElement { app.descendants(matching: .any)["living_scene"] }
    private func homeScroll() -> XCUIElement { app.scrollViews["home_scroll"] }

    private func scrollUntilFullyVisible(_ element: XCUIElement, in scroll: XCUIElement,
                                         scene: XCUIElement, stage: String, key: String) {
        var drags = 0
        for _ in 0..<12 {
            let viewport = scroll.frame.intersection(app.frame)
            if element.isHittable && viewport.contains(element.frame) { break }
            let delta: CGFloat
            if element.frame.maxY > viewport.maxY {
                delta = -min(100, max(28, element.frame.maxY - viewport.maxY + 8))
            } else if element.frame.minY < viewport.minY {
                delta = min(100, max(28, viewport.minY - element.frame.minY + 8))
            } else { break }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)))
            drags += 1
        }
        let viewport = scroll.frame.intersection(app.frame)
        XCTAssertTrue(element.isHittable, "\(stage) must be reachable; drags=\(drags), frame=\(element.frame), viewport=\(viewport)")
        XCTAssertTrue(viewport.contains(element.frame), "\(stage) must be fully visible inside home scroll viewport")
        let state = geometry(stage: "reach_\(stage)", saveKey: key, size: "AXXXL", scene: scene, scroll: scroll)
        XCTAssertGreaterThanOrEqual(state.sceneExposedFraction, 0.55,
            "Scrolling controls must not consume the reserved scene view")
    }

    private struct GeometryRecord {
        let stage: String
        let sceneFrame: CGRect
        let scrollFrame: CGRect
        let sceneExposedFraction: CGFloat
        let screenFrame: CGRect
        let claimFrame: CGRect
        let claimExists: Bool
        let claimHittable: Bool
    }

    private func geometry(stage: String, saveKey: String, size: String,
                          scene: XCUIElement, scroll: XCUIElement,
                          claimFrame: CGRect = .zero, claimExists: Bool = false,
                          claimHittable: Bool = false) -> GeometryRecord {
        let sceneFrame = scene.frame
        let scrollFrame = scroll.frame.intersection(app.frame)
        let exposed = max(0, min(sceneFrame.maxY, scrollFrame.minY) - sceneFrame.minY)
        let fraction = sceneFrame.height > 0 ? exposed / sceneFrame.height : 0
        let record = GeometryRecord(stage: stage, sceneFrame: sceneFrame, scrollFrame: scrollFrame,
                                    sceneExposedFraction: fraction, screenFrame: app.frame,
                                    claimFrame: claimFrame, claimExists: claimExists,
                                    claimHittable: claimHittable)
        let text = """
        stage=\(stage)
        saveKey=\(saveKey)
        size=\(size)
        sceneFrame=\(sceneFrame)
        scrollViewport=\(scrollFrame)
        claimFrame=\(claimFrame)
        claimExists=\(claimExists)
        claimHittable=\(claimHittable)
        claimFullyInsideViewport=\(scrollFrame.contains(claimFrame))
        sceneExposedFraction=\(fraction)
        screenFrame=\(app.frame)
        claimTapCount=0
        classification=SYNTHETIC_QA_FIXTURE_NOT_EARNED
        operations=read_only_home_navigation
        """
        let attachment = XCTAttachment(string: text)
        attachment.name = "home_r045_geometry_\(stage)_\(saveKey)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return record
    }

    private func attachGeometry(_ value: GeometryRecord) {
        let attachment = XCTAttachment(string: "stage=\(value.stage)\nscene=\(value.sceneFrame)\nscroll=\(value.scrollFrame)\nclaim=\(value.claimFrame)\nclaimExists=\(value.claimExists)\nclaimHittable=\(value.claimHittable)\nclaimFullyInsideViewport=\(value.scrollFrame.contains(value.claimFrame))\nsceneExposedFraction=\(value.sceneExposedFraction)\nscreen=\(value.screenFrame)")
        attachment.name = "home_r045_geometry_summary_\(value.stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachAccessibilityTree(stage: String, key: String) {
        let attachment = XCTAttachment(string: "stage=\(stage)\nsaveKey=\(key)\n\(app.debugDescription)")
        attachment.name = "home_r045_accessibility_tree_\(stage)_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachScreen(stage: String, key: String, size: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home_r045_\(stage)_\(size)_\(key)"
        shot.lifetime = .keepAlways
        add(shot)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = "home_r045_AX_\(stage)_\(key)"
        ax.lifetime = .keepAlways
        add(ax)
    }

    private func attachIdentity(key: String, size: String, claimTapCount: Int) {
        let attachment = XCTAttachment(string: "saveKey=\(key)\nsize=\(size)\nclassification=SYNTHETIC_QA_FIXTURE_NOT_EARNED\noperations=read_only_home_navigation\nclaimTapCount=\(claimTapCount)")
        attachment.name = "home_r045_identity_\(key)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(claimTapCount, 0)
    }
}
