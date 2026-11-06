import SpriteKit

/// QA-only renderer candidate for the existing LUNA no-book clips.
/// It overlays the already-created mantle layer; it never substitutes or edits
/// the actor texture, and it never creates a book or a palm node.
@MainActor enum LunaMantleBooklessR127 {
    static let qaFlag = "--qa-luna-mantle-offsets-r127"
    static let appearanceValue = "LUNA_MANTLE_GREEN_WORK_MANTLE_CANDIDATE"
    static let nodeName = "luna_mantle_offsets_r127"

    private static let bodyLayerAssetID = "LUNA_MANTLE_BODY_LAYER_R001"
    private static let executeLayerAssetID = "LUNA_MANTLE_EXECUTE_LAYER_R002"
    private static let expectedCanvas = CGSize(width: 256, height: 256)
    private static let expectedAnchorY: CGFloat = 12.0 / 256.0
    /// Source-canvas coordinates use PNG convention (+y down). Only the three
    /// execute poses move; every other R126 frame remains at the old origin.
    private static let executeOffsetsSourcePixels: [String: CGPoint] = [
        "GeneratedArt/PartyAttack/LUNA__attack_03.png": CGPoint(x: -30, y: 8),
        "GeneratedArt/PartyAttack/LUNA__attack_04.png": CGPoint(x: -45, y: 9),
        "GeneratedArt/PartyAttack/LUNA__attack_05.png": CGPoint(x: -43, y: 9)
    ]

    private struct FrameKey {
        let pose: String
        let localIndex: Int
    }

    /// Whitelist mirrors the frozen PartyRest/PartyAttack/PartyWalk manifests.
    /// PartyRest and PartyAttack report a 0...2 clip-local index; PartyWalk
    /// reports its 0...8 sequence index. Full bundle-relative paths are used.
    private static let frames: [String: FrameKey] = {
        var values: [String: FrameKey] = [:]
        let rest: [(String, Range<Int>)] = [
            ("idle", 0..<3), ("hit", 3..<6), ("resolve", 6..<9)
        ]
        for (pose, range) in rest {
            for ordinal in range {
                values["GeneratedArt/PartyRest/LUNA__rest_\(String(format: "%02d", ordinal)).png"] =
                    FrameKey(pose: pose, localIndex: ordinal % 3)
            }
        }
        let attack: [(String, Range<Int>)] = [
            ("anticipate", 0..<3), ("execute", 3..<6), ("recover", 6..<9)
        ]
        for (pose, range) in attack {
            for ordinal in range {
                values["GeneratedArt/PartyAttack/LUNA__attack_\(String(format: "%02d", ordinal)).png"] =
                    FrameKey(pose: pose, localIndex: ordinal % 3)
            }
        }
        for ordinal in 0..<9 {
            values["GeneratedArt/PartyWalk/LUNA__walk_\(ordinal).png"] =
                FrameKey(pose: "walk", localIndex: ordinal)
        }
        return values
    }()

    static func isEnabled(appearanceValue requestedAppearance: String?, arguments: [String] = ProcessInfo.processInfo.arguments,
                          developmentEnabled: Bool = false) -> Bool {
        (developmentEnabled || (arguments.contains("--qa-isolated") && arguments.contains(qaFlag)))
            && requestedAppearance == Self.appearanceValue
    }

    static func isEmptyBookSlot(_ equippedGearID: String?) -> Bool {
        equippedGearID?.isEmpty ?? true
    }

    /// Applies only to a positively identified, bookless frame. Callers must
    /// first run LunaBookPresentationCleanupR004 on the no-book transition.
    /// A stale book or palm makes this fail closed; this helper owns only its
    /// mantle child and will never remove either book-renderer node.
    @discardableResult
    static func apply(
        appearanceValue requestedAppearance: String?,
        bodyAssetID: String,
        frameIndex: Int,
        equippedBookGearID: String?,
        on body: SKSpriteNode,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        developmentEnabled: Bool = false,
        resolveTexture: (String) -> SKTexture?
    ) -> Bool {
        guard isEnabled(appearanceValue: requestedAppearance, arguments: arguments, developmentEnabled: developmentEnabled),
              isEmptyBookSlot(equippedBookGearID),
              let frame = frames[bodyAssetID], frame.localIndex == frameIndex,
              body.childNode(withName: "luna_book") == nil,
              body.childNode(withName: "luna_book_palm") == nil,
              body.size.width.isFinite, body.size.width > 0,
              body.size.height.isFinite, body.size.height > 0,
              abs(body.anchorPoint.x - 0.5) < 0.0001,
              abs(body.anchorPoint.y - expectedAnchorY) < 0.0001 else {
            clear(on: body)
            return false
        }

        let assetID = frame.pose == "execute" ? executeLayerAssetID : bodyLayerAssetID
        guard let texture = resolveTexture(assetID), texture.size() == expectedCanvas else {
            clear(on: body)
            return false
        }

        let layer = (body.childNode(withName: nodeName) as? SKSpriteNode) ?? SKSpriteNode()
        layer.name = nodeName
        layer.texture = texture
        // The mantle is a 256-square overlay registered to the body's shared
        // 244/256 foot line. Some authored LUNA rest/attack canvases are 320x256;
        // keep the overlay uniformly scaled by body height instead of stretching.
        layer.size = CGSize(width: body.size.height, height: body.size.height)
        layer.anchorPoint = CGPoint(x: 0.5, y: body.anchorPoint.y)
        let sourceOffset = executeOffsetsSourcePixels[bodyAssetID] ?? .zero
        let pointScale = body.size.height / expectedCanvas.height
        let spriteKitOffset = CGPoint(x: sourceOffset.x * pointScale,
                                      y: -sourceOffset.y * pointScale)
        layer.position = spriteKitOffset
        layer.zPosition = 0.5
        layer.alpha = 1
        layer.isHidden = false
        layer.blendMode = .alpha
        layer.texture?.filteringMode = .linear
        if layer.parent == nil { body.addChild(layer) }
        if layer.userData == nil { layer.userData = NSMutableDictionary() }
        layer.userData?["lunaMantleOffsetsR127"] = [
            "appearance": self.appearanceValue,
            "bodyAssetID": bodyAssetID,
            "frameIndex": frameIndex,
            "poseState": frame.pose,
            "layerAssetID": assetID,
            "canvas": [256, 256],
            "uniformScaleByBodyHeight": true,
            "offsetSourcePixels": [sourceOffset.x, sourceOffset.y],
            "offsetSpriteKitPoints": [spriteKitOffset.x, spriteKitOffset.y],
            "bookNodeAbsent": true,
            "palmNodeAbsent": true
        ] as [String: Any]
        return true
    }

    @discardableResult
    static func clear(on body: SKSpriteNode) -> Bool {
        guard let layer = body.childNode(withName: nodeName) else { return false }
        layer.removeFromParent()
        return true
    }

    static func snapshot(on body: SKSpriteNode, equippedBookGearID: String?) -> [String: Any] {
        let frame = ActorBodyFrame.current(on: body)
        var result: [String: Any] = [
            "present": false,
            "equippedBookGearID": equippedBookGearID ?? "",
            "slotIsEmpty": isEmptyBookSlot(equippedBookGearID),
            "bookNodeAbsent": body.childNode(withName: "luna_book") == nil,
            "palmNodeAbsent": body.childNode(withName: "luna_book_palm") == nil,
            "currentBodyAssetID": frame?.assetID ?? "",
            "currentBodyFrameIndex": frame?.frameIndex ?? -1,
            "childCount": body.children.filter { $0.name == nodeName }.count
        ]
        guard let layer = body.childNode(withName: nodeName) as? SKSpriteNode else { return result }
        for (key, value) in layer.userData?["lunaMantleOffsetsR127"] as? [String: Any] ?? [:] {
            if result[key] == nil { result[key] = value }
        }
        result["present"] = true
        result["visible"] = !layer.isHidden && layer.alpha > 0
        result["size"] = [layer.size.width, layer.size.height]
        result["anchor"] = [layer.anchorPoint.x, layer.anchorPoint.y]
        result["position"] = [layer.position.x, layer.position.y]
        result["z"] = layer.zPosition
        return result
    }

    static func poseAndLocalIndex(for bodyAssetID: String) -> (pose: String, localIndex: Int)? {
        guard let value = frames[bodyAssetID] else { return nil }
        return (value.pose, value.localIndex)
    }

    static func positionOffsetSourcePixels(for bodyAssetID: String) -> CGPoint {
        executeOffsetsSourcePixels[bodyAssetID] ?? .zero
    }

    static var whitelistedBodyAssetIDs: [String] { frames.keys.sorted() }
}
