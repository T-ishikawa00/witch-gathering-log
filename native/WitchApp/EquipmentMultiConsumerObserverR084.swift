import Foundation
import SpriteKit
import UIKit

/// Per-render audit extension for isolated full-battle gear batches. It reads
/// existing actor child nodes and renderer registration only; it never places,
/// animates, equips, or changes any gameplay state.
@MainActor final class EquipmentMultiConsumerObserverR084 {
    static let schema = "equipment-multi-consumer-render-r084-v3"
    static let phaseSet: Set<String> = ["idle", "walk", "anticipate", "execute", "recover", "hit", "resolve"]
    private let request: EquipmentMultiConsumerRequestR084
    private let outputURL: URL
    private var rows: [[String: Any]] = []
    private var previousSceneFrame = -1
    private var failed = false
    private var marker: SKNode?
    // Strong retention prevents ObjectIdentifier reuse within this bounded trace.
    private var pixelCache: [ObjectIdentifier: (SKTexture, String, [Int])] = [:]
    private func pixelProof(_ texture: SKTexture?) -> (String, [Int]) {
        guard let texture else { return ("", []) }
        let key = ObjectIdentifier(texture)
        if let cached = pixelCache[key] { return (cached.1, cached.2) }
        let decoded = texture.cgImage()
        let digest = EquipmentMultiConsumerPixelDigestR084.sha256(decoded) ?? ""
        let size = [decoded.width, decoded.height]
        pixelCache[key] = (texture, digest, size)
        return (digest, size)
    }

    init(request: EquipmentMultiConsumerRequestR084, scene: SKScene, outputDirectory: URL) {
        self.request = request
        self.outputURL = outputDirectory.appendingPathComponent("equipment_multi_\(request.saveKey)_\(UUID().uuidString.lowercased()).json")
        let group = SKNode(); group.name = "qa_equipment_multi_consumer_marker"; group.zPosition = 20_001
        let back = SKShapeNode(rectOf: CGSize(width: 112, height: 26), cornerRadius: 3)
        back.fillColor = .black.withAlphaComponent(0.88); back.strokeColor = .white.withAlphaComponent(0.9); back.lineWidth = 1
        group.addChild(back)
        let label = SKLabelNode(fontNamed: "Menlo-Bold"); label.name = "qa_equipment_multi_consumer_marker_text"
        label.fontSize = 14; label.fontColor = .white; label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center; group.addChild(label)
        group.position = CGPoint(x: 68, y: 96)
        scene.addChild(group); marker = group
    }

    private func visibilityProof(_ node: SKNode?, through scene: SKScene) -> ([[String: Any]], Bool, Double, Bool) {
        guard let node else { return ([], false, 0, false) }
        var chain: [[String: Any]] = []
        var visible = true
        var alpha = 1.0
        var reachedScene = false
        var cursor: SKNode? = node
        while let current = cursor {
            let currentAlpha = Double(current.alpha)
            chain.append(["name": current.name ?? "", "isPart": current === node,
                          "isScene": current === scene, "hidden": current.isHidden,
                          "alpha": currentAlpha, "parentExists": current.parent != nil])
            visible = visible && !current.isHidden && currentAlpha > 0
            alpha *= currentAlpha
            if current === scene { reachedScene = true; break }
            cursor = current.parent
        }
        return (chain, visible, alpha, reachedScene)
    }

    private func worldCorners(node: SKSpriteNode, in scene: SKScene) -> [[Double]] {
        let hw = node.size.width / 2, hh = node.size.height / 2
        return [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh),
                CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)].map {
            let p = node.convert($0, to: scene)
            return [Double(p.x), Double(p.y)]
        }
    }

    private func expectedCorners(body: SKSpriteNode, registration: [String: Any], scene: SKScene) -> [[Double]] {
        guard let point = registration["normalizedPoint"] as? [Double], point.count == 2,
              let height = registration["normalizedHeight"] as? Double else { return [] }
        let center = CGPoint(x: (point[0] - body.anchorPoint.x) * body.size.width,
                             y: (point[1] - body.anchorPoint.y) * body.size.height)
        let size = body.size.height * height
        let angle = registration["angleRadians"] as? Double ?? 0
        let hw = size / 2, hh = size / 2
        return [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh),
                CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)].map { corner in
            let x = corner.x * cos(angle) - corner.y * sin(angle) + center.x
            let y = corner.x * sin(angle) + corner.y * cos(angle) + center.y
            let p = body.convert(CGPoint(x: x, y: y), to: scene)
            return [Double(p.x), Double(p.y)]
        }
    }

    func sample(scene: SKScene, sceneFrame: Int, sceneTime: TimeInterval,
                bodiesBySpriteID: [String: SKSpriteNode], stateBySpriteID: [String: String]) {
        guard !failed else { return }
        guard sceneFrame > previousSceneFrame, sceneTime.isFinite else { failed = true; return }
        previousSceneFrame = sceneFrame
        let markerText = String(format: "EQ53 %04d", rows.count)
        if marker?.parent !== scene, let marker { marker.removeFromParent(); scene.addChild(marker) }
        (marker?.childNode(withName: "qa_equipment_multi_consumer_marker_text") as? SKLabelNode)?.text = markerText
        var actorRows: [[String: Any]] = []
        let consumers = request.variant.consumers.sorted {
            if $0.owner != $1.owner { return $0.owner < $1.owner }
            if $0.gearID != $1.gearID { return $0.gearID < $1.gearID }
            return $0.slot < $1.slot
        }
        for consumer in consumers {
            guard let body = bodiesBySpriteID[consumer.sprite] else {
                actorRows.append(["ownerID": consumer.owner, "spriteActorID": consumer.sprite,
                                  "gearID": consumer.gearID, "slot": consumer.slot,
                                  "sampleStatus": "actor_body_missing"])
                continue
            }
            let phase = stateBySpriteID[consumer.sprite] ?? "unknown"
            let bodyFrame = ActorBodyFrame.current(on: body)
            let map = body.userData?["equipmentDetailRegistrationQA"] as? [String: Any] ?? [:]
            let registration = map[consumer.gearID] as? [String: Any] ?? [:]
            let holder = body.childNode(withName: "gear_detail:" + consumer.gearID)
            let part = holder?.childNode(withName: "part") as? SKSpriteNode
            let resourcePath = registration["resourcePath"] as? String ?? ""
            let resourceSHA = registration["resourceSHA256"] as? String ?? ""
            let partTexture = part?.texture
            let pixel = pixelProof(partTexture)
            let renderedPixelSHA = pixel.0
            let registeredPixelSHA = registration["decodedPixelSHA256"] as? String ?? ""
            let registrationAsset = registration["bodyAssetID"] as? String ?? ""
            let registrationFrame = registration["bodyFrameIndex"] as? Int ?? -1
            let worldCenter = part.map { $0.convert(CGPoint.zero, to: scene) }
            let bodyOrigin = body.convert(CGPoint.zero, to: scene)
            let bodyX = body.convert(CGPoint(x: 1, y: 0), to: scene)
            let bodyY = body.convert(CGPoint(x: 0, y: 1), to: scene)
            let visibility = visibilityProof(part, through: scene)
            actorRows.append(EquipmentMultiConsumerSampleRecordR084.make(
                ownerID: consumer.owner, spriteActorID: consumer.sprite,
                gearID: consumer.gearID, slot: consumer.slot, phase: phase,
                sceneFrame: sceneFrame, sceneTime: sceneTime,
                bodyAssetID: bodyFrame?.assetID ?? "", bodyFrameIndex: bodyFrame?.frameIndex ?? -1,
                bodyCanvas: [bodyFrame?.canvasSize.width ?? 0, bodyFrame?.canvasSize.height ?? 0],
                actorBodyExists: body.parent != nil, actorBodyNodeName: body.name ?? "",
                registration: registration,
                registrationMatchesRenderedBodyFrame: registrationAsset == (bodyFrame?.assetID ?? "") && registrationFrame == (bodyFrame?.frameIndex ?? -1),
                holderExists: holder != nil, partExists: part != nil,
                holderParentMatchesActor: holder?.parent === body,
                partParentMatchesHolder: part?.parent === holder,
                holderHidden: holder?.isHidden as Any? ?? NSNull(),
                holderAlpha: holder.map { Double($0.alpha) as Any } ?? NSNull(),
                partHidden: part?.isHidden as Any? ?? NSNull(),
                partAlpha: part.map { Double($0.alpha) as Any } ?? NSNull(),
                partPosition: part.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
                partSize: part.map { [Double($0.size.width), Double($0.size.height)] } ?? [],
                partRotation: part.map { Double($0.zRotation) } ?? 0,
                partWorldCenter: worldCenter.map { [Double($0.x), Double($0.y)] } ?? [],
                bodySize: [Double(body.size.width), Double(body.size.height)],
                bodyAnchor: [Double(body.anchorPoint.x), Double(body.anchorPoint.y)],
                bodyToSceneBasis: [Double(bodyOrigin.x), Double(bodyOrigin.y),
                                   Double(bodyX.x - bodyOrigin.x), Double(bodyX.y - bodyOrigin.y),
                                   Double(bodyY.x - bodyOrigin.x), Double(bodyY.y - bodyOrigin.y)],
                expectedPartWorldCorners: part.map { _ in expectedCorners(body: body, registration: registration, scene: scene) } ?? [],
                partWorldCorners: part.map { worldCorners(node: $0, in: scene) } ?? [],
                ancestorVisibility: visibility.0, visibilityChainReachesScene: visibility.3,
                effectiveVisible: visibility.1, effectiveAlpha: visibility.2,
                textureDecoded: !pixel.0.isEmpty,
                decodedTexturePixelSize: pixel.1,
                texturePixelSHA256: renderedPixelSHA,
                resolvedResourcePixelSHA256: registeredPixelSHA,
                renderedPixelsMatchResolvedResource: !registeredPixelSHA.isEmpty && renderedPixelSHA == registeredPixelSHA,
                resourcePath: resourcePath, resourceSHA256: resourceSHA
            ))
        }
        rows.append(["sequence": rows.count, "sceneFrame": sceneFrame, "sceneTime": sceneTime,
                     "videoMarker": markerText, "videoMarkerVisible": marker?.parent === scene,
                     "variantID": request.variant.id, "actors": actorRows])
        if rows.count >= 5400 { failed = true }
    }

    @discardableResult func finish(sceneFrame: Int, sceneTime: TimeInterval, reason: String = "COMPLETED") -> Bool {
        if reason != "COMPLETED" { failed = true }
        let payload: [String: Any] = [
            "completionReason": reason,
            "schema": Self.schema, "status": failed ? "INCOMPLETE_OBSERVER" : "CAPTURED_ROWS_REQUIRES_OFFLINE_VALIDATION", "variantID": request.variant.id,
            "fixture": request.variant.fixtureID, "saveKey": request.saveKey,
            "encounterID": request.evidenceMode == "natural_full_battle" ? request.encounterID as Any : NSNull(),
            "evidenceMode": request.evidenceMode,
            "naturalCombatEvidence": request.evidenceMode == "natural_full_battle",
            "scope": request.evidenceMode == "natural_full_battle"
                ? "isolated_qa_fixture_normal_resolveEncounter_and_playback"
                : "isolated_qa_fixture_forced_pose_showcase_no_combat",
            "humanApproved": false, "candidateAdopted": false,
            "expectedConsumerKeys": request.variant.consumers.map { "\($0.owner)|\($0.gearID)" }.sorted(),
            "expectedConsumerCount": request.variant.consumers.count,
            "requiredPhases": Self.phaseSet.sorted(), "rowLimit": 5400,
            "finalSceneFrame": sceneFrame, "finalSceneTime": sceneTime, "rows": rows,
            "observerFailure": failed ? "observer_sequence_invalid_or_row_limit" : NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              (try? data.write(to: outputURL, options: .withoutOverwriting)) != nil else { return false }
        return true
    }
}
