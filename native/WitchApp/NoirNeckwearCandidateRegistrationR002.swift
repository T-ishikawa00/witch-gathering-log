import Foundation
import SpriteKit

/// QA-only per-frame registration for the unapproved NOIR neckwear candidate.
/// It consumes actual PartyRest/PartyAttack/PartyWalk body-frame paths and never
/// edits the body pixels, actor origin, clip timing, or equipment ownership.
@MainActor enum NoirNeckwearCandidateRegistrationR002 {
    static let assetID = "NOIR_NECKWEAR_MOSS_R001"
    static let canvasPixels: CGFloat = 1254
    static let alphaCenterPixels = CGPoint(x: 628.5 * 256 / 1254, y: 748.5 * 256 / 1254)
    static let alphaWidthPixels: CGFloat = 377 * 256 / 1254
    static let targetAlphaWidthPixels: CGFloat = 64
    static let uniformScale = targetAlphaWidthPixels / alphaWidthPixels
    static let nodeName = "noir_neckwear_candidate_r002"
    static var requested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--qa-isolated") && arguments.contains("--qa-noir-neckwear-r124")
    }

    static func snapshot(on body: SKSpriteNode) -> [String: Any] {
        guard let layer = body.childNode(withName: nodeName) as? SKSpriteNode else { return ["present": false] }
        var result = layer.userData?["noirNeckwearR002"] as? [String: Any] ?? [:]
        result["present"] = true
        result["visible"] = !layer.isHidden && layer.alpha > 0
        result["childCount"] = body.children.filter { $0.name == nodeName }.count
        result["position"] = [layer.position.x, layer.position.y]
        result["size"] = [layer.size.width, layer.size.height]
        result["anchor"] = [layer.anchorPoint.x, layer.anchorPoint.y]
        result["z"] = layer.zPosition
        result["assetID"] = assetID
        return result
    }


    struct Registration {
        let path: String
        let sha256: String
        let canvas: CGSize
        let anchorTopLeftPixels: CGPoint
        let targetAlphaCenterTopLeftPixels: CGPoint
        let rotationDegrees: CGFloat
    }

    /// Each center is a source-frame estimate from the existing red scarf/neck
    /// area. Rotation is intentionally small and conservative; native fit remains
    /// unverified. Unknown body paths clear this owned layer fail-closed.
    static let registrations: [String: Registration] = {
        let raw: [(String, String, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            ("GeneratedArt/PartyRest/NOIR__rest_00.png", "0a7fcc791b417a5b151f4f5e669efe603432226d0709ea79aa01517d066f783d", 320, 256, 156, 160, -8),
            ("GeneratedArt/PartyRest/NOIR__rest_01.png", "3dfc1060abe373d62b999415acf9d154b0d5bfb16a8f1ae34aab1a6999c8bdad", 320, 256, 150, 158, -8),
            ("GeneratedArt/PartyRest/NOIR__rest_02.png", "828cb8d53c92642a85d1f687fd6af333fc874624f771606eb5ffb31aa1900ec1", 320, 256, 146, 159, -7),
            ("GeneratedArt/PartyRest/NOIR__rest_03.png", "fcdd43506856340887479ee405f7ac9cc7a98ade8043bd760171269f39cb8193", 320, 256, 148, 151, -5),
            ("GeneratedArt/PartyRest/NOIR__rest_04.png", "fb215f5f611382d7a6925403e13e3d5cb3f63528a4c551e3790e0fe90fa1eb6c", 320, 256, 158, 153, -4),
            ("GeneratedArt/PartyRest/NOIR__rest_05.png", "9646b93c53653f83856abd14cefdd7ac18ee3b488e61cf4831d1d61f09277e34", 320, 256, 154, 157, -7),
            ("GeneratedArt/PartyRest/NOIR__rest_06.png", "d4eba79af38b2d45eb4712b2ddede4f5c8ebe14e5dd42dab724f4049a16ad3b1", 320, 256, 142, 163, 0),
            ("GeneratedArt/PartyRest/NOIR__rest_07.png", "715ee4d2f7f5fbc816f862615a6681e511c2c24e37e1c159e7fc7a47885500eb", 320, 256, 157, 170, -3),
            ("GeneratedArt/PartyRest/NOIR__rest_08.png", "b6166468dd4fd09e0b3c5e775d83033696ba9b60e256d86ea7d9ef0a2ae627f8", 320, 256, 164, 154, 0),

            ("GeneratedArt/PartyAttack/NOIR__attack_00.png", "c088713f72a243403d261a6b87e8356350ea77231a8f94c039c59e303dc6b825", 320, 256, 153, 162, -8),
            ("GeneratedArt/PartyAttack/NOIR__attack_01.png", "51fa6ec463b8fdc152acdadc678f73eba89816c70fc7d69ade958fe138a8698f", 320, 256, 145, 158, -2),
            ("GeneratedArt/PartyAttack/NOIR__attack_02.png", "26b22fe55522b07893d2c2de19c0d5a3daf039cf7fcbc5d1791ac95dd7d52645", 320, 256, 145, 165, -2),
            ("GeneratedArt/PartyAttack/NOIR__attack_03.png", "a16055b0d1b1f773a61ecb9d92fd6996885eea023ade4d19e865f0582b0e887e", 320, 256, 148, 158, -4),
            ("GeneratedArt/PartyAttack/NOIR__attack_04.png", "d5b8ed6a1d07770cc45de6ceea0dbba6aad0abaa0d4e6bf22a43275d958e8595", 320, 256, 144, 162, -4),
            ("GeneratedArt/PartyAttack/NOIR__attack_05.png", "22e4c2509d511fc46269c7db2b3771df7ff8866103528b178fc0c1d1ceda31b1", 320, 256, 145, 164, -4),
            ("GeneratedArt/PartyAttack/NOIR__attack_06.png", "4a9966a9a8b69863154d4791dae843f4cd60a6c95dbfe8445badef75ae2a788b", 320, 256, 151, 163, -3),
            ("GeneratedArt/PartyAttack/NOIR__attack_07.png", "aaf986d8900c58eda03cb6b8e03e9c54418c5652c941cb96671c9a10b2309a28", 320, 256, 153, 164, -7),
            ("GeneratedArt/PartyAttack/NOIR__attack_08.png", "d57801f6b087067b174cea3e9051f464d48ec5d627092835d1102065abc89703", 320, 256, 149, 159, -8),

            ("GeneratedArt/PartyWalk/NOIR__walk_0.png", "9f705cb909742b80837a8a51cb9ecd44bb09df3925b6240f1be5aa99ab0fe2a9", 256, 256, 139, 159, -8),
            ("GeneratedArt/PartyWalk/NOIR__walk_2.png", "a54d25444d05a2d647f73972cfa0a26293ee4bf5852b33f4cd9bbaa301860de5", 256, 256, 141, 160, -8),
            ("GeneratedArt/PartyWalk/NOIR__walk_3.png", "d52ad1cdb3d19199913a58b422e569be9c92b94d6801ec200697437f90b7e26f", 256, 256, 144, 162, -7),
            ("GeneratedArt/PartyWalk/NOIR__walk_4.png", "01abaa2f71e39e0c7cc1da1368a3509f8158197e2e42bb4a1bb656bb351f0ab0", 256, 256, 139, 161, -8),
            ("GeneratedArt/PartyWalk/NOIR__walk_5.png", "0313d0e1b3dfc2463bfcedd4442d960f07697b17402025a492326ca7fa50912d", 256, 256, 145, 165, -7),
            ("GeneratedArt/PartyWalk/NOIR__walk_6.png", "c48e7c892dbd997cf6fd3052b4d2d25f4ac07d2a401e39a9ada92b02a83d0f92", 256, 256, 146, 159, -8),
            ("GeneratedArt/PartyWalk/NOIR__walk_7.png", "ed6158b332d21c62137447ab2972e9563b3fa9da7f2c3ffa0fd8bb0a889116f9", 256, 256, 139, 158, -6),
            ("GeneratedArt/PartyWalk/NOIR__walk_8.png", "bb248c70fba0b251abdc36b72d3dde8ed0ec17ac59519f3b0a8381afee215f87", 256, 256, 140, 159, -8)
        ]
        return Dictionary(uniqueKeysWithValues: raw.map { row in
            (row.0, Registration(path: row.0, sha256: row.1,
                canvas: CGSize(width: row.2, height: row.3),
                anchorTopLeftPixels: CGPoint(x: row.2 / 2, y: 244),
                targetAlphaCenterTopLeftPixels: CGPoint(x: row.4, y: row.5),
                rotationDegrees: row.6))
        })
    }()

    @discardableResult
    static func apply(texture: SKTexture?, body: SKSpriteNode,
                      displayedBodyFramePath: String) -> Bool {
        guard requested, let row = registrations[displayedBodyFramePath],
              let texture,
              abs(texture.size().width - canvasPixels) < 0.01,
              abs(texture.size().height - canvasPixels) < 0.01,
              body.size.width > 0, body.size.height > 0,
              abs(body.size.width / body.size.height - row.canvas.width / row.canvas.height) < 0.002,
              abs(body.anchorPoint.x - row.anchorTopLeftPixels.x / row.canvas.width) < 0.002,
              abs(body.anchorPoint.y - (1 - row.anchorTopLeftPixels.y / row.canvas.height)) < 0.002 else {
            clear(on: body)
            return false
        }

        let node = (body.childNode(withName: nodeName) as? SKSpriteNode) ?? SKSpriteNode()
        node.name = nodeName
        node.texture = texture
        node.size = CGSize(width: body.size.height * uniformScale,
                           height: body.size.height * uniformScale)
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let bodyScale = body.size.height / row.canvas.height
        let target = CGPoint(
            x: (row.targetAlphaCenterTopLeftPixels.x / row.canvas.width - body.anchorPoint.x) * body.size.width,
            y: (1 - row.targetAlphaCenterTopLeftPixels.y / row.canvas.height - body.anchorPoint.y) * body.size.height)
        let alphaOffset = CGPoint(
            x: (alphaCenterPixels.x - 128) * bodyScale * uniformScale,
            y: -(alphaCenterPixels.y - 128) * bodyScale * uniformScale)
        let radians = row.rotationDegrees * .pi / 180
        let rotatedAlphaOffset = CGPoint(
            x: alphaOffset.x * cos(radians) - alphaOffset.y * sin(radians),
            y: alphaOffset.x * sin(radians) + alphaOffset.y * cos(radians))
        node.position = CGPoint(x: target.x - rotatedAlphaOffset.x,
                                y: target.y - rotatedAlphaOffset.y)
        node.zRotation = radians
        node.zPosition = 0.15
        node.alpha = 1
        node.isHidden = false
        node.blendMode = .alpha
        node.texture?.filteringMode = .linear
        if node.parent == nil { body.addChild(node) }
        if node.userData == nil { node.userData = NSMutableDictionary() }
        node.userData?[
            "noirNeckwearR002"] = [
                "bodyFramePath": row.path,
                "bodyFrameSHA256": row.sha256,
                "canvas": [row.canvas.width, row.canvas.height],
                "targetAlphaCenterTopLeftPixels": [row.targetAlphaCenterTopLeftPixels.x, row.targetAlphaCenterTopLeftPixels.y],
                "uniformScale": uniformScale,
                "rotationDegrees": row.rotationDegrees,
                "attachmentStatus": "SOURCE_ESTIMATE_NATIVE_VISUAL_PENDING"
            ] as [String: Any]
        return true
    }

    @discardableResult
    static func clear(on body: SKSpriteNode) -> Bool {
        guard let node = body.childNode(withName: nodeName) else { return false }
        node.removeFromParent()
        return true
    }
}
