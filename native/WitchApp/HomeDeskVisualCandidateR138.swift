import SpriteKit

/// QA-only transform of the existing herb table; no furniture catalog/save mutation.
@MainActor enum HomeDeskVisualCandidateR138 {
    static let assetID = "FURN_DESK_HERB_WORKTABLE_R001"
    static let nodeName = "qa_home_desk_r138"
    static var variant: HomeFurnitureFitR138.Variant? {
        let a = ProcessInfo.processInfo.arguments
        guard a.contains("--qa-isolated"), !a.contains("--qa-home-desk-r124") else { return nil }
        let width = a.contains("--qa-home-desk-r138-width")
        let area = a.contains("--qa-home-desk-r138-area")
        guard width != area else { return nil }
        return width ? .matchVisibleWidth : .matchVisibleArea
    }
    static var requested: Bool { variant != nil }
    static func supports(texture: SKTexture?) -> Bool {
        texture?.size() == HomeFurnitureFitR138.sourceCanvas
    }
    static func apply(to node: SKSpriteNode) -> Bool {
        guard let variant, supports(texture: node.texture), node.anchorPoint == CGPoint(x: 0.5, y: 0.5),
              node.size.height.isFinite, node.size.height > 0, node.position.x.isFinite,
              node.position.y.isFinite, node.xScale == 1, node.yScale == 1 else { return false }
        let originalPosition = node.position
        let result = HomeFurnitureFitR138.transform(variant: variant,
            baselineNodeHeight: node.size.height, baselinePosition: originalPosition)
        guard result.uniformScale.isFinite, result.uniformScale > 0,
              result.position.x.isFinite, result.position.y.isFinite else { return false }
        node.name = nodeName
        node.setScale(result.uniformScale)
        node.position = result.position
        if node.userData == nil { node.userData = NSMutableDictionary() }
        node.userData?["r138Fit"] = ["policy": result.policy,
            "originalPosition": [originalPosition.x, originalPosition.y],
            "uniformScale": result.uniformScale] as [String: Any]
        return true
    }
    static func snapshot(node: SKSpriteNode?, sceneSize: CGSize, logicalPlaced: Bool) -> [String: Any] {
        guard let node else {
            return ["present": false, "logicalPlaced": logicalPlaced, "candidateOnly": true,
                "requestedPolicy": variant?.rawValue ?? "none_or_conflicting_flags"]
        }
        return ["present": true, "logicalPlaced": logicalPlaced, "assetID": assetID,
            "sourceCanvas": [HomeFurnitureFitR138.sourceCanvas.width, HomeFurnitureFitR138.sourceCanvas.height],
            "textureSize": [node.texture?.size().width ?? 0, node.texture?.size().height ?? 0],
            "nodeSize": [node.size.width, node.size.height], "scale": [node.xScale, node.yScale],
            "position": [node.position.x, node.position.y], "anchor": [node.anchorPoint.x, node.anchorPoint.y],
            "z": node.zPosition, "sceneSize": [sceneSize.width, sceneSize.height],
            "fit": node.userData?["r138Fit"] ?? [:], "candidateOnly": true,
            "baselineAlpha": [64, 0, 1297, 1125], "candidateAlpha": [157, 158, 1102, 884],
            "occlusionQuality": "REQUIRES_NATIVE_VISUAL_REVIEW"]
    }
}
