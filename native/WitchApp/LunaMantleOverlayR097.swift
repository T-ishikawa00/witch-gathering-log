import SpriteKit

/// Isolated candidate only. This accessory preserves the actor's source texture;
/// it is an independently owned transparent child aligned to the current body frame.
@MainActor enum LunaMantleOverlayR097 {
    static let appearanceKey = "LUNA_MANTLE_R097"
    static let appearanceValue = "LUNA_MANTLE_GREEN_WORK_MANTLE_CANDIDATE"
    static let nodeName = "luna_mantle_r097"
    static let qaFlag = "--qa-luna-mantle-r097"

    private static let bodyLayer = "LUNA_MANTLE_BODY_LAYER_R001"
    private static let executeLayer = "LUNA_MANTLE_EXECUTE_LAYER_R002"
    private static let supportedStates: Set<String> = [
        "walk", "idle", "anticipate", "execute", "hit", "recover", "resolve", "reading"
    ]

    /// Applies only when both the isolated QA flag and exact candidate appearance
    /// value are present. Caller supplies the body frame ID recorded after texture
    /// assignment; unknown frames fail closed and clear only this owned node.
    @discardableResult
    static func apply(
        appearanceValue: String?,
        bodyAssetID: String,
        poseState: String,
        on body: SKSpriteNode,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        developmentEnabled: Bool = false,
        resolveTexture: (String) -> SKTexture?
    ) -> Bool {
        let embeddedReading = poseState == "reading" && isPinnedReadingAsset(bodyAssetID) &&
            body.childNode(withName: "luna_book") == nil && body.childNode(withName: "luna_book_palm") == nil
        guard (developmentEnabled || (arguments.contains("--qa-isolated") && arguments.contains(qaFlag))),
              appearanceValue == self.appearanceValue,
              supportedStates.contains(poseState),
              (body.childNode(withName: "luna_book_palm") != nil || embeddedReading),
              isPinnedBodyAsset(bodyAssetID, poseState: poseState) else {
            clear(on: body)
            return false
        }
        let assetID = poseState == "execute" ? executeLayer : bodyLayer
        guard let texture = resolveTexture(assetID),
              texture.size().width == 256, texture.size().height == 256 else {
            clear(on: body)
            return false
        }
        let layer = (body.childNode(withName: nodeName) as? SKSpriteNode) ?? SKSpriteNode()
        layer.name = nodeName
        layer.texture = texture
        layer.anchorPoint = body.anchorPoint
        if let registration = readingRegistration(bodyAssetID: bodyAssetID, bodySize: body.size, bodyAnchorPoint: body.anchorPoint) {
            // The source frames show one shared shoulder landmark. The existing
            // layer is compressed vertically and translated only on this exact
            // seated route; its raster and all other pose registrations stay intact.
            layer.size = CGSize(width: body.size.width, height: body.size.height * registration.scaleY)
            layer.position = registration.offsetPoints
        } else {
            layer.size = body.size
            layer.position = .zero
        }
        layer.zPosition = 0.5 // body < mantle < book(z=1) < palm(z=2)
        layer.alpha = 1
        layer.isHidden = false
        layer.blendMode = .alpha
        layer.texture?.filteringMode = .linear
        if layer.parent == nil { body.addChild(layer) }
        if layer.userData == nil { layer.userData = NSMutableDictionary() }
        layer.userData?["lunaMantleR097"] = [
            "appearance": self.appearanceValue,
            "bodyAssetID": bodyAssetID,
            "poseState": poseState,
            "layerAssetID": assetID,
            "zPosition": 0.5,
            "canvas": [256, 256],
            "registration": readingRegistrationMetadata(bodyAssetID: bodyAssetID, bodySize: body.size, bodyAnchorPoint: body.anchorPoint)
        ] as [String: Any]
        return true
    }

    @discardableResult
    static func clear(on body: SKSpriteNode) -> Bool {
        guard let layer = body.childNode(withName: nodeName) else { return false }
        layer.removeFromParent()
        return true
    }

    static func snapshot(on body: SKSpriteNode) -> [String: Any] {
        guard let layer = body.childNode(withName: nodeName) as? SKSpriteNode else {
            return ["present": false]
        }
        var result = layer.userData?["lunaMantleR097"] as? [String: Any] ?? [:]
        result["present"] = true
        result["childCount"] = body.children.filter { $0.name == nodeName }.count
        result["visible"] = !layer.isHidden && layer.alpha > 0
        result["size"] = [layer.size.width, layer.size.height]
        result["anchor"] = [layer.anchorPoint.x, layer.anchorPoint.y]
        result["position"] = [layer.position.x, layer.position.y]
        result["bookZ"] = body.childNode(withName: "luna_book")?.zPosition ?? -1
        result["palmZ"] = body.childNode(withName: "luna_book_palm")?.zPosition ?? -1
        return result
    }

    private static func isPinnedBodyAsset(_ id: String, poseState: String) -> Bool {
        if poseState == "reading" { return isPinnedReadingAsset(id) }
        if id.hasPrefix("LUNA_BOOK_MOTION_\(poseState.uppercased())_F"), id.hasSuffix("_CANDIDATE_R001") { return true }
        if id == "LUNA_BOOK_MOTION_EXEC_RECOVER_MID_R001_CANDIDATE" && poseState == "execute" { return true }
        if id == "LUNA_EXEC_RECOVER_BRIDGE_R088_SOURCE" && poseState == "execute" { return true }
        if id == "LUNA_BOOKLESS_\(poseState.uppercased())_CANDIDATE_R001" { return true }
        if id == "LUNA__\(poseState)__256__r001" { return true }
        if id.hasPrefix("LUNA__walk_"), poseState == "walk",
           let index = Int(id.dropFirst("LUNA__walk_".count)), (0...8).contains(index) { return true }
        if id.hasPrefix("LUNA__cast_"), let index = Int(id.dropFirst("LUNA__cast_".count)), (0...7).contains(index) {
            return poseState == (index < 3 ? "anticipate" : "execute")
        }
        if id.hasPrefix("LUNA__attack_"), let index = Int(id.dropFirst("LUNA__attack_".count)), (0...8).contains(index) {
            let phase = index < 3 ? "anticipate" : (index < 6 ? "execute" : "recover")
            return poseState == phase
        }
        if id.hasPrefix("LUNA__rest_"), let index = Int(id.dropFirst("LUNA__rest_".count)), (0...8).contains(index) {
            return poseState == "idle"
        }
        return false
    }

    private static func isPinnedReadingAsset(_ id: String) -> Bool {
        (0...3).contains { id == "LUNA_READING__\($0)" }
    }

    /// Alpha bounds use [minX,minY,maxX,maxY] = [111,137,146,167] on the
    /// 256px layer. At 2x the alpha center is (257,304) on the 512px body.
    /// The approximate shoulder band read from the four body sources is centered
    /// at (247.5,293.5), so the reading-only fit compresses Y to 0.55 and applies
    /// the residual (-9.5,-11.1) SpriteKit-pixel translation at anchorY=0.5.
    /// The vertical anchor compensation keeps the same body-canvas bounds when
    /// the actual sprite uses a noncentral anchor (for example anchorY=0.04).
    private static func readingRegistration(
        bodyAssetID: String,
        bodySize: CGSize,
        bodyAnchorPoint: CGPoint
    ) -> ReadingRegistration? {
        let registeredIDs: Set<String> = [
            "LUNA_READING__0", "LUNA_READING__1", "LUNA_READING__2", "LUNA_READING__3"
        ]
        guard registeredIDs.contains(bodyAssetID) else { return nil }
        let scaleY: CGFloat = 0.55
        let anchorCompensationPoints = (0.5 - bodyAnchorPoint.y) * (1 - scaleY) * bodySize.height
        let offsetPoints = CGPoint(
            x: -9.5 * bodySize.width / 512,
            y: -11.1 * bodySize.height / 512 + anchorCompensationPoints
        )
        let offsetPixels = CGPoint(
            x: -9.5,
            y: -11.1 + (0.5 - bodyAnchorPoint.y) * (1 - scaleY) * 512
        )
        return ReadingRegistration(
            scaleY: scaleY,
            offsetPoints: offsetPoints,
            offsetSpriteKitPixels: offsetPixels
        )
    }

    private struct ReadingRegistration {
        let scaleY: CGFloat
        let offsetPoints: CGPoint
        let offsetSpriteKitPixels: CGPoint
    }

    private static func readingRegistrationMetadata(bodyAssetID: String, bodySize: CGSize, bodyAnchorPoint: CGPoint) -> [String: Any] {
        guard let registration = readingRegistration(
            bodyAssetID: bodyAssetID, bodySize: bodySize, bodyAnchorPoint: bodyAnchorPoint
        ) else { return [:] }
        return [
            "mode": "reading_shoulder_fit_anchor_compensated_r003",
            "scale": [1.0, registration.scaleY],
            "anchorPoint": [bodyAnchorPoint.x, bodyAnchorPoint.y],
            "offsetSpriteKitPixelsXY": [registration.offsetSpriteKitPixels.x, registration.offsetSpriteKitPixels.y],
            "canvasPixels": [512, 512],
            "alphaBoundsXYXY": [111, 137, 146, 167]
        ]
    }
}
