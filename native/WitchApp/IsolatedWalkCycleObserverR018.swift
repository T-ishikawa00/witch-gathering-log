import Foundation
import SpriteKit

/// QA-only observer for a separately requested walk renderer check. The caller
/// must start the existing LivingScene.playWalk action in an isolated scene.
/// It never changes texture, pivot, duration, or gameplay state.
@MainActor final class IsolatedWalkCycleObserverR018 {
    private weak var scene: SKScene?
    private weak var body: SKSpriteNode?
    private let outputURL: URL
    private let saveKey: String
    private let generation: Int
    private var coverage = MotionCoverageR018(expectedWalkFrameCount: 9)
    private var rows: [[String: Any]] = []
    private var completionFrame: Int?
    private var flushed = false
    private var marker: SKNode?

    init?(scene: SKScene, body: SKSpriteNode, outputDirectory: URL,
          saveKey: String, sceneGeneration: Int) {
        guard EquipmentMotionTraceRequest.isSafe(saveKey),
              body.action(forKey: "party_walk_clip") != nil else { return nil }
        self.scene = scene
        self.body = body
        self.outputURL = outputDirectory.appendingPathComponent("walk_cycle_r018_\(saveKey)_\(UUID().uuidString.lowercased()).json")
        self.saveKey = saveKey
        self.generation = sceneGeneration
        rows.reserveCapacity(180)
        let badge = SKNode()
        badge.name = "qa_walk_cycle_r018_marker"
        badge.zPosition = 20_000
        let backing = SKShapeNode(rectOf: CGSize(width: 112, height: 26), cornerRadius: 3)
        backing.fillColor = .black.withAlphaComponent(0.88)
        backing.strokeColor = .white.withAlphaComponent(0.9)
        backing.lineWidth = 1
        badge.addChild(backing)
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = "qa_walk_cycle_r018_marker_text"
        label.text = "R18 0000"
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        badge.addChild(label)
        badge.position = CGPoint(x: 68, y: scene.size.height - 76)
        scene.addChild(badge)
        marker = badge
    }

    /// Returns true exactly once when a terminal receipt has been written.
    func sample(sceneFrame: Int, sceneTime: TimeInterval, sceneGeneration: Int) -> Bool {
        guard !flushed, let body else { return false }
        guard sceneGeneration == generation else { flush(status: "INCOMPLETE_SCENE_GENERATION_CHANGED"); return true }
        if let completionFrame {
            guard sceneFrame > completionFrame else { return false }
            body.removeAction(forKey: "party_walk_clip") // stops only the isolated QA action after its evidence is captured
            guard let terminal = ActorBodyFrame.current(on: body),
                  body.action(forKey: "party_walk_clip") == nil else {
                flush(status: "INCOMPLETE_WALK_ACTION_CLEANUP_NOT_OBSERVED")
                return true
            }
            rows.append([
                "sequence": rows.count, "sceneFrame": sceneFrame, "sceneTime": sceneTime,
                "sceneGeneration": sceneGeneration, "actorID": "AIRA",
                "assetID": terminal.assetID, "localFrameIndex": terminal.frameIndex,
                "actionActive": false, "postActionCleanupSample": true,
                "bodyPosition": [Double(body.position.x), Double(body.position.y)],
                "bodySize": [Double(body.size.width), Double(body.size.height)],
                "bodyAnchor": [Double(body.anchorPoint.x), Double(body.anchorPoint.y)],
                "actionKeys": ["party_walk_clip", "party_rest_clip", "party_cast_clip"].filter { body.action(forKey: $0) != nil }
            ])
            flush(status: "CAPTURED_ISOLATED_WALK_TWO_CYCLES")
            return true
        }
        let rendered = ActorBodyFrame.current(on: body)
        guard let rendered else { flush(status: "INCOMPLETE_BODY_FRAME_MISSING"); return true }
        let active = body.action(forKey: "party_walk_clip") != nil
        let result = coverage.observeWalk(.init(sceneGeneration: sceneGeneration, sceneFrame: sceneFrame,
            actorID: "AIRA", actionActive: active, bodyAssetID: rendered.assetID,
            frameIndex: rendered.frameIndex))
        let seq = rows.count
        (marker?.childNode(withName: "qa_walk_cycle_r018_marker_text") as? SKLabelNode)?.text = String(format: "R18 %04d", seq)
        rows.append([
            "sequence": seq, "sceneFrame": sceneFrame, "sceneTime": sceneTime,
            "sceneGeneration": sceneGeneration, "actorID": "AIRA",
            "assetID": rendered.assetID, "localFrameIndex": rendered.frameIndex,
            "actionActive": active, "bodyPosition": [Double(body.position.x), Double(body.position.y)],
            "bodySize": [Double(body.size.width), Double(body.size.height)],
            "bodyAnchor": [Double(body.anchorPoint.x), Double(body.anchorPoint.y)],
            "actionKeys": ["party_walk_clip", "party_rest_clip", "party_cast_clip"].filter { body.action(forKey: $0) != nil },
            "coverage": String(describing: result), "markerText": String(format: "R18 %04d", seq)
        ])
        switch result {
        case .complete: completionFrame = sceneFrame
        case .incomplete(let reason): flush(status: "INCOMPLETE_\(reason)"); return true
        case .observing:
            if rows.count >= 240 { flush(status: "INCOMPLETE_RENDER_SAMPLE_DEADLINE"); return true }
        }
        return false
    }

    func abort(reason: String) { flush(status: "INCOMPLETE_\(reason)") }

    private func flush(status: String) {
        guard !flushed else { return }
        flushed = true
        marker?.removeFromParent()
        marker = nil
        let payload: [String: Any] = [
            "schema": "equipment-isolated-walk-r018",
            "status": status,
            "captureScope": "isolated_existing_playWalk_renderer_not_ordinary_gameplay",
            "saveKey": saveKey,
            "actorID": "AIRA",
            "expectedFramePaths": (0..<9).map { "GeneratedArt/PartyWalk/AIRA__walk_\($0).png" },
            "requiredCycles": 2,
            "sourceAction": "LivingScene.playWalk -> CharacterLocomotion.play",
            "rows": rows
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: outputURL, options: .atomic)
    }
}
