import Foundation
import SpriteKit

/// R018 readability experiment for three low-contrast gather props.
/// Presentation-only: it does not change source textures, collection state, or rewards.
@MainActor enum GatherNodePresentation {
    private static let snowMaterialIDs: Set<String> = ["M_R04_G1", "M_R04_G3"]
    private static let cueMaterialIDs: Set<String> = ["M_R01_G3", "M_R04_G1", "M_R04_G3"]

    private static let contactShadowName = "r018_gather_contact_shadow"
    private static let collectionCueName = "r018_gather_collection_cue"
    private static let cueInvocationKey = "r018_collection_cue_invocations"
    // Measured from the bundled 128 px present-sprite alpha bbox at alpha >= 16.
    // These are source-image top rows, not guessed scene coordinates.
    private static let cueSourceAlphaTopRow: [String: CGFloat] = [
        "M_R01_G3": 42,
        "M_R04_G1": 16,
        "M_R04_G3": 36
    ]
    private static let cueSourceCanvasHeight: CGFloat = 128

    static func qaExpectedContactShadowCount(for materialID: String) -> Int {
        snowMaterialIDs.contains(materialID) ? 1 : 0
    }

    static func qaExpectsCollectionCue(for materialID: String) -> Bool {
        cueMaterialIDs.contains(materialID)
    }

    /// Bounded readback for isolated QA. It reports only direct helper-owned nodes
    /// and the unchanged sprite registration; gameplay code does not consume it.
    static func qaSnapshot(on node: SKSpriteNode, materialID: String) -> [String: Any] {
        let shadows = node.children.filter { $0.name == contactShadowName }
        let cues = node.children.filter { $0.name == collectionCueName }
        let cue = cues.first
        return [
            "materialID": materialID,
            "expectedContactShadowCount": qaExpectedContactShadowCount(for: materialID),
            "contactShadowCount": shadows.count,
            "expectedCueAfterSuccessfulCollection": qaExpectsCollectionCue(for: materialID),
            "cueInvocationCount": node.userData?[cueInvocationKey] as? Int ?? 0,
            "cueCount": cues.count,
            "cueAlpha": cue.map { Double($0.alpha) } as Any? ?? NSNull(),
            "cueActionActive": cue?.action(forKey: "r018_finite_collection_cue") != nil,
            "spriteSize": [Double(node.size.width), Double(node.size.height)],
            "spritePosition": [Double(node.position.x), Double(node.position.y)],
            "spriteAnchor": [Double(node.anchorPoint.x), Double(node.anchorPoint.y)]
        ]
    }

    /// Adds one restrained grounding ellipse to the two pale props on snow.
    /// Dimensions are ratios of the already-fitted sprite; the art and node transform stay intact.
    static func installContactShadow(on node: SKSpriteNode, materialID: String) {
        guard snowMaterialIDs.contains(materialID), node.size.width > 0, node.size.height > 0,
              node.childNode(withName: contactShadowName) == nil else { return }

        let shadowSize = CGSize(width: node.size.width * 0.44, height: node.size.height * 0.055)
        let shadow = SKShapeNode(ellipseOf: shadowSize)
        shadow.name = contactShadowName
        shadow.fillColor = SKColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1)
        shadow.strokeColor = .clear
        shadow.lineWidth = 0
        shadow.alpha = 0.20
        shadow.isAntialiased = true
        shadow.blendMode = .alpha
        shadow.zPosition = -0.1

        // SpriteKit local origin follows anchorPoint. Place the ellipse just below
        // the image's lower edge, with a small overlap to avoid a detached gap.
        shadow.position = CGPoint(
            x: 0,
            y: -(node.size.height * node.anchorPoint.y) - shadowSize.height * 0.20
        )
        node.addChild(shadow)
    }

    /// Shows one short, non-looping three-crystal cue while the authored collected texture is visible.
    /// R01_G3 gets a darker edge to separate its warm gold particles from the warm forest floor;
    /// the snow-region blue treatment, sprite art, node geometry, and reward path remain unchanged.
    static func playCollectionCue(on node: SKSpriteNode, materialID: String) {
        guard cueMaterialIDs.contains(materialID), node.size.width > 0, node.size.height > 0 else { return }
        node.childNode(withName: collectionCueName)?.removeFromParent()
        if ProcessInfo.processInfo.arguments.contains("--qa-isolated") {
            if node.userData == nil { node.userData = NSMutableDictionary() }
            let invocationCount = node.userData?[cueInvocationKey] as? Int ?? 0
            node.userData?[cueInvocationKey] = invocationCount + 1
        }

        let cue = SKNode()
        cue.name = collectionCueName
        cue.zPosition = 1
        // SpriteKit node-local y=0 is the authored anchor, not the sprite center.
        // Start at the measured top of the visible silhouette, with particle bases
        // nearly touching its edge; this keeps the feedback outside the material.
        let topRow = cueSourceAlphaTopRow[materialID] ?? 36
        let visibleTopFromAnchor = 1 - topRow / cueSourceCanvasHeight - node.anchorPoint.y
        cue.position = CGPoint(x: 0, y: node.size.height * (visibleTopFromAnchor + 0.08))

        // Three small crystals rise just above the prop. They read as a brief
        // collection response without outlining the whole object like a target.
        let fillColor: SKColor
        let strokeColor: SKColor
        let strokeWidth: CGFloat
        if materialID == "M_R01_G3" {
            fillColor = SKColor(red: 0.84, green: 0.62, blue: 0.30, alpha: 0.90)
            strokeColor = SKColor(red: 0.30, green: 0.22, blue: 0.10, alpha: 0.92)
            strokeWidth = 1.0
        } else {
            let color = snowMaterialIDs.contains(materialID)
                ? SKColor(red: 0.36, green: 0.52, blue: 0.72, alpha: 0.96)
                : SKColor(red: 0.84, green: 0.62, blue: 0.30, alpha: 0.96)
            fillColor = color.withAlphaComponent(0.65)
            strokeColor = color
            strokeWidth = 0.98
        }
        let particles: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-0.16, -0.006, 0.078, 0.128),
            (0.00, 0.008, 0.102, 0.150),
            (0.16, -0.006, 0.078, 0.128)
        ]
        for particle in particles {
            let width = node.size.width * particle.2
            let height = node.size.height * particle.3
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height * 0.5))
            path.addLine(to: CGPoint(x: width * 0.34, y: height * 0.08))
            path.addLine(to: CGPoint(x: width * 0.16, y: -height * 0.5))
            path.addLine(to: CGPoint(x: -width * 0.22, y: -height * 0.18))
            path.closeSubpath()

            let crystal = SKShapeNode(path: path)
            crystal.fillColor = fillColor
            crystal.strokeColor = strokeColor
            crystal.lineWidth = strokeWidth
            crystal.isAntialiased = true
            crystal.blendMode = .alpha
            crystal.position = CGPoint(x: node.size.width * particle.0,
                                       y: node.size.height * particle.1)
            cue.addChild(crystal)

            let direction: CGFloat = particle.0 == 0 ? 0 : (particle.0 < 0 ? -1 : 1)
            let drift = CGPoint(x: node.size.width * 0.055 * direction,
                                y: node.size.height * 0.065)
            crystal.run(.group([
                .moveBy(x: drift.x, y: drift.y, duration: 0.36),
                .fadeOut(withDuration: 0.36)
            ]))
        }
        node.addChild(cue)

        cue.run(.sequence([
            .wait(forDuration: 0.36),
            .removeFromParent()
        ]), withKey: "r018_finite_collection_cue")
    }
}
