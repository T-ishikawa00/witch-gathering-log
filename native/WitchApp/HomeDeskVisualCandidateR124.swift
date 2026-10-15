import SpriteKit

/// A visual comparison only; the existing logical furniture and save remain authoritative.
@MainActor enum HomeDeskVisualCandidateR124 {
    static let assetID = "FURN_DESK_HERB_WORKTABLE_R001"
    static let nodeName = "qa_home_desk_r124"
    static var requested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--qa-isolated") && arguments.contains("--qa-home-desk-r124")
    }
    static func snapshot(node: SKSpriteNode?, sceneSize: CGSize, logicalPlaced: Bool) -> [String: Any] {
        guard let node else { return ["present": false, "logicalPlaced": logicalPlaced] }
        return ["present": true, "logicalPlaced": logicalPlaced, "assetID": assetID,
                "size": [node.size.width, node.size.height],
                "nodeSize": [node.size.width, node.size.height],
                "textureSize": [node.texture?.size().width ?? 0, node.texture?.size().height ?? 0],
                "scale": [node.xScale, node.yScale],
                "position": [node.position.x, node.position.y],
                "anchor": [node.anchorPoint.x, node.anchorPoint.y],
                "z": node.zPosition, "sceneSize": [sceneSize.width, sceneSize.height],
                "heightPolicy": "scene.width * 0.39", "candidateOnly": true]
    }
}
