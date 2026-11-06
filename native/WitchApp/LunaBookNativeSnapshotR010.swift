import SpriteKit

/// Read-only same-render snapshot for isolated native LUNA book QA.
/// Call from LivingScene.didFinishUpdate; this helper never advances actions.
@MainActor enum LunaBookNativeSnapshotR010 {
    static func capture(sceneFrame: Int, sceneTime: TimeInterval, requestedState: String,
                        body: SKSpriteNode?, hand: CGPoint?) -> [String: Any] {
        guard let body else {
            return ["sceneFrame": sceneFrame, "sceneTime": sceneTime,
                    "requestedState": requestedState, "bodyExists": false,
                    "bookExists": false, "palmExists": false, "handAnchorNormalizedBottomLeft": NSNull()]
        }
        let frame = ActorBodyFrame.current(on: body)
        let book = body.childNode(withName: "luna_book") as? SKSpriteNode
        let palm = body.childNode(withName: "luna_book_palm") as? SKCropNode
        let foreground = palm?.children.first as? SKSpriteNode
        let mask = palm?.maskNode
        let meta = body.userData?["lunaBookR010"] as? [String: Any] ?? [:]
        let metadataAssetID = meta["bodyAssetID"] as? String ?? ""
        let actualTextureAssetID = frame?.assetID ?? ""
        func point(_ p: CGPoint?) -> Any {
            guard let p, p.x.isFinite, p.y.isFinite else { return NSNull() }
            return [Double(p.x), Double(p.y)]
        }
        func node(_ n: SKNode?) -> [String: Any] {
            guard let n else { return ["exists": false] }
            let p = n.position
            var chain:[String] = []
            var visible = true
            var cursor:SKNode? = n
            while let current = cursor {
                chain.append(current.name ?? String(describing:type(of:current)))
                if current.isHidden || current.alpha <= 0 { visible = false }
                cursor = current.parent
            }
            return ["exists": true, "parentName": n.parent?.name ?? "",
                    "parentIsBody": n.parent === body, "ancestorChain": chain, "effectiveVisible": visible,
                    "hidden": n.isHidden, "alpha": Double(n.alpha),
                    "x": Double(p.x), "y": Double(p.y),
                    "z": Double(n.zPosition), "rotation": Double(n.zRotation),
                    "hasTexture": (n as? SKSpriteNode)?.texture != nil,
                    "metadata": n.userData?["lunaBookR010"] as? [String: Any] ?? [:]]
        }
        let walk = body.action(forKey: "party_walk_clip") != nil
        let cast = body.action(forKey: "party_cast_clip") != nil
        let rest = body.action(forKey: "party_rest_clip") != nil
        return ["sceneFrame": sceneFrame, "sceneTime": sceneTime,
                "requestedState": requestedState, "bodyExists": true,
                "bodyVisible": !body.isHidden && body.alpha > 0,
                "bodyFrameAssetID": actualTextureAssetID,
                "bodyFrameIndex": frame?.frameIndex ?? -1,
                "bodyCanvas": frame.map { [Double($0.canvasSize.width), Double($0.canvasSize.height)] } ?? [0,0],
                "bodyMetadata": meta,
                "bodyMetadataMatchesActualTexture": !metadataAssetID.isEmpty && metadataAssetID == actualTextureAssetID,
                "book": node(book), "palm": node(palm), "foreground": node(foreground),
                "palmMaskExists": mask != nil,
                "palmMaskChildCount": mask?.children.count ?? 0,
                "palmMaskChildren": (mask?.children ?? []).map { ["name":$0.name ?? "", "x":Double($0.position.x), "y":Double($0.position.y)] },
                "handAnchorNormalizedBottomLeft": point(hand),
                "actions": ["walk": walk, "cast": cast, "rest": rest],
                "fallbackWalkActive": walk && book == nil && palm == nil]
    }
}
