import Foundation
import SpriteKit
#if canImport(CryptoKit)
import CryptoKit
#endif

struct SyntheticDash2TailRequestR047 {
    let saveKey: String
    let outputDirectory: URL
    let rootActionID: String
    let targetEnemyID: String
    let targetCastStartIndex: Int
    let targetImpactIndex: Int
    let targetCastStartTimestampMs: Int
    let targetImpactTimestampMs: Int
    let tailMilliseconds: Int
}

/// Separate observer for the deliberately truncated R047 presentation prefix.
/// It records the event callback and actual SpriteKit frames without fabricating
/// a pending-root value after direct, where the ordinary lifecycle clears it.
@MainActor final class SyntheticDash2TailTraceR047 {
    static let schema = "party-motion-r043-synthetic-prefix-tail-r047"
    private let request: SyntheticDash2TailRequestR047
    private let sceneGeneration: Int
    private var directFrame: Int?
    private var directSceneTime: TimeInterval?
    private var directSpriteKitTime: TimeInterval?
    private(set) var videoMarkerID: String?
    private(set) var videoMarkerRequestedSceneFrame: Int?
    private(set) var videoMarkerFirstRenderedSceneFrame: Int?
    private var samples: [[String: Any]] = []
    private var abortReason: String?

    init(request: SyntheticDash2TailRequestR047, sceneGeneration: Int) {
        self.request = request
        self.sceneGeneration = sceneGeneration
    }

    @discardableResult
    func recordPresented(_ event: CombatEvent, sceneFrame: Int, sceneTime: TimeInterval,
                         spriteKitTime: TimeInterval) -> Bool {
        guard event.kind == "direct", event.sourceID == SyntheticDash2VisualTailR047.actorID,
              event.rootActionID == request.rootActionID,
              event.targetID == request.targetEnemyID else { return false }
        guard directFrame == nil else { abortReason = "DUPLICATE_TARGET_DIRECT"; return false }
        directFrame = sceneFrame
        directSceneTime = sceneTime
        directSpriteKitTime = spriteKitTime
        videoMarkerID = "R047-DIRECT-" + request.saveKey
        videoMarkerRequestedSceneFrame = sceneFrame
        return true
    }

    func sample(sceneFrame: Int, sceneTime: TimeInterval, spriteKitTime: TimeInterval,
                currentGeneration: Int, sceneActive: Bool, poseState: String, body: SKSpriteNode?,
                markerVisible: Bool, markerSequence: Int?, markerPosition: [Double], markerSize: [Double]) {
        guard abortReason == nil, let directFrame, let directSceneTime else { return }
        guard currentGeneration == sceneGeneration else { abortReason = "SCENE_REBUILT"; return }
        guard sceneActive else { abortReason = "SCENE_INACTIVE"; return }
        guard sceneFrame > directFrame, sceneTime >= directSceneTime,
              let body, body.parent != nil, let frame = ActorBodyFrame.current(on: body) else { return }
        if markerVisible, videoMarkerFirstRenderedSceneFrame == nil {
            videoMarkerFirstRenderedSceneFrame = sceneFrame
        }
        samples.append([
            "actorID": "NOIR", "poseState": poseState,
            "sceneFrame": sceneFrame, "sceneTime": sceneTime, "spriteKitCurrentTime": spriteKitTime,
            "videoMarkerSequence": markerSequence as Any? ?? NSNull(),
            "videoMarkerText": markerSequence.map { String(format: "R47 %04d", $0) } as Any? ?? NSNull(),
            "videoMarkerAttached": markerVisible, "videoMarkerPositionScene": markerPosition,
            "videoMarkerSizeScene": markerSize,
            "sceneGeneration": currentGeneration, "sceneActive": true,
            "bodyExists": true, "bodyAssetID": frame.assetID,
            "bodyFrameIndex": frame.frameIndex,
            "bodyCanvas": [Double(frame.canvasSize.width), Double(frame.canvasSize.height)],
            "videoSyncMarkerID": videoMarkerID ?? "",
            "videoSyncMarkerRequestedSceneFrame": videoMarkerRequestedSceneFrame ?? -1,
            "videoSyncMarkerFirstRenderedSceneFrame": videoMarkerFirstRenderedSceneFrame as Any? ?? NSNull(),
            "videoSyncMarkerVisible": markerVisible
        ])
    }

    func finish(observedMilliseconds: Int, currentGeneration: Int, sceneActive: Bool, cancelled: Bool = false, reason: String? = nil) -> [String: Any] {
        if currentGeneration != sceneGeneration { abortReason = "SCENE_REBUILT" }
        if !sceneActive { abortReason = "SCENE_INACTIVE" }
        let poses = samples.compactMap { $0["poseState"] as? String }
        let chain = hasRequiredChain(poses)
        if let reason { abortReason = reason }
        if cancelled { abortReason = "TASK_CANCELLED" }
        let status = abortReason.map { "INCOMPLETE_\($0)" }
            ?? (directFrame == nil ? "INCOMPLETE_TARGET_DIRECT_NOT_PRESENTED"
                : observedMilliseconds < request.tailMilliseconds ? "INCOMPLETE_TAIL_SHORT"
                : chain ? "CAPTURED_SYNTHETIC_PREFIX_TAIL" : "INCOMPLETE_POSE_CHAIN")
        let sampleData = (try? JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys])) ?? Data()
        try? sampleData.write(to: request.outputDirectory.appendingPathComponent("r047_\(request.saveKey)_tail_samples.json"), options: .atomic)
        let receipt: [String: Any] = [
            "schema": Self.schema, "status": status,
            "saveKey": request.saveKey, "visualActorID": "NOIR",
            "coreActorID": SyntheticDash2VisualTailR047.actorID,
            "rootActionID": request.rootActionID, "targetEnemyID": request.targetEnemyID,
            "targetCastStartIndex": request.targetCastStartIndex,
            "targetImpactIndex": request.targetImpactIndex,
            "targetCastStartTimestampMs": request.targetCastStartTimestampMs,
            "targetImpactTimestampMs": request.targetImpactTimestampMs,
            "directPresentedSceneFrame": directFrame as Any? ?? NSNull(),
            "directPresentedSceneTime": directSceneTime as Any? ?? NSNull(),
            "videoSyncMarkerID": videoMarkerID as Any? ?? NSNull(),
            "videoSyncMarkerRequestedSceneFrame": videoMarkerRequestedSceneFrame as Any? ?? NSNull(),
            "videoSyncMarkerFirstRenderedSceneFrame": videoMarkerFirstRenderedSceneFrame as Any? ?? NSNull(),
            "videoSyncMarkerScenePoint": [68.0, "sceneHeightMinus76"],
            "videoSyncMarkerSceneSize": [112.0, 26.0],
            "directPresentedSpriteKitCurrentTime": directSpriteKitTime as Any? ?? NSNull(),
            "videoSyncMarkerContract": "R047-only 112x26 black-backed white R47 NNNN marker at scene point (68,height-76); created in exact target-direct present callback, sequence advances on didFinishUpdate, and rows bind sequence/position/size/attachment to actual sceneFrame/sceneClock plus raw SpriteKit time",
            "tailMilliseconds": request.tailMilliseconds,
            "tailObservedMilliseconds": observedMilliseconds,
            "sceneGeneration": sceneGeneration, "currentSceneGeneration": currentGeneration,
            "sceneActiveAtFinish": sceneActive, "poseChainValid": chain,
            "tailSamples": samples, "sampleSHA256": R047SHA256.hex(sampleData),
            "ordinaryBattleClaim": false, "rewardGranted": false
        ]
        if let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
            try? data.write(to: request.outputDirectory.appendingPathComponent("r047_\(request.saveKey)_tail.json"), options: .atomic)
        }
        return receipt
    }

    private func hasRequiredChain(_ poses: [String]) -> Bool {
        guard let execute = poses.firstIndex(of: "execute"), execute + 1 < poses.count,
              let recover = poses[(execute + 1)..<poses.count].firstIndex(of: "recover") else { return false }
        guard recover + 1 < poses.count,
              let idle = poses[(recover + 1)..<poses.count].firstIndex(of: "idle") else { return false }
        return idle + 1 < poses.count && poses[idle + 1] == "idle"
    }
}

private enum R047SHA256 {
    static func hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        importCrypto(data)
        #else
        ""
        #endif
    }
    #if canImport(CryptoKit)
    private static func importCrypto(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    #endif
}
