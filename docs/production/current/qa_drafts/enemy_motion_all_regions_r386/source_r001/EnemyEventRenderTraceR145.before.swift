import Foundation
import SpriteKit

/// Isolated evidence collector for actual R01 battles. It observes calls already
/// made by the game and post-action scene snapshots; it never schedules motion.
@MainActor
struct EnemyEventRenderRequestR145 {
    static let flag = "--qa-enemy-event-render-trace-r145"
    static let encounterToActor: [String: String] = [
        "E_R01_01": "ACT_E_R01_01", "E_R01_02": "ACT_E_R01_02",
        "E_R01_03": "ACT_E_R01_03", "E_R01_04": "ACT_E_R01_04",
        "B_R01_A": "ACT_B_R01_A", "B_R01_B": "ACT_B_R01_B"
    ]

    let encounterID: String
    let actorID: String
    let saveKey: String
    let outputDirectory: URL
    let runID: String

    enum ParseFailure: String, Error {
        case simulatorOnly = "SIMULATOR_ONLY"
        case exactFlagsRequired = "EXACT_FLAGS_REQUIRED"
        case encounterNotAllowlisted = "ENCOUNTER_NOT_ALLOWLISTED"
        case uuidSaveBindingInvalid = "UUID_SAVE_BINDING_INVALID"
    }

    static func parse(arguments: [String], isSimulator: Bool, encounterID: String,
                      saveFilename: String?, outputDirectory: URL?) -> Result<EnemyEventRenderRequestR145, ParseFailure> {
        let flags = arguments.filter { $0 == flag }
        let isolated = arguments.filter { $0 == "--qa-isolated" }
        let keys = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard isSimulator else { return .failure(.simulatorOnly) }
        guard flags.count == 1, isolated.count == 1 else { return .failure(.exactFlagsRequired) }
        guard let actorID = encounterToActor[encounterID] else { return .failure(.encounterNotAllowlisted) }
        guard keys.count == 1, let raw = keys.first?.dropFirst("--qa-save-key=".count),
              let uuid = UUID(uuidString: String(raw)), uuid.uuidString.lowercased() == String(raw),
              let saveFilename, saveFilename == "qa-\(raw)-save.json",
              let outputDirectory, outputDirectory.isFileURL else { return .failure(.uuidSaveBindingInvalid) }
        return .success(.init(encounterID: encounterID, actorID: actorID, saveKey: String(raw),
                              outputDirectory: outputDirectory, runID: UUID().uuidString.lowercased()))
    }
}

@MainActor
final class EnemyEventRenderTraceR145 {
    static let maxDuration = 180.0
    static let maxFrameRows = 12_000
    static let maxEstimatedBytes = 8 * 1024 * 1024
    static let markerName = "enemy_event_render_r145_marker"

    struct ActorFrame: Codable {
        let actorID: String
        let state: String
        let frameIndex: Int
        let framePath: String
        let activeClipKey: String
        let actionRunning: Bool
        let texturePresent: Bool
        let nodeAttached: Bool
        let hidden: Bool
        let alpha: Double
        let position: [Double]
        let size: [Double]
        let anchor: [Double]
        let sceneRect: [Double]
        let visibleFraction: Double
        let availableStates: [String]
        let linkedEventSequence: Int?
        let latestRequestedState: String
        let latestRequestKind: String
        let finiteReturnAfterRequest: Bool
    }

    let request: EnemyEventRenderRequestR145
    private(set) var status = "ARMED"
    private(set) var events: [[String: Any]] = []
    private(set) var transitions: [[String: Any]] = []
    private(set) var frameRows: [[String: Any]] = []
    private var nextEventSequence = 0
    private var nextMarkerSequence = 0
    private var estimatedBytes = 0
    private var startSceneTime: Double?
    private var startUptime = ProcessInfo.processInfo.systemUptime
    private var initialGeneration: Int?
    private var terminalReason: String?
    private var terminalMarkerFrame: Int?
    private var lastSampleFrame: Int?
    private var lastSampleTime: Double?
    private var lastSampleGeneration: Int?
    private var marker: SKShapeNode?
    private var latestRequestByActor: [String: (sequence: Int?, state: String, time: Double, kind: String, observedAfterRequest: Bool)] = [:]
    private var observedStates: [String: Set<String>] = [:]

    init(request: EnemyEventRenderRequestR145) { self.request = request }

    var isTerminal: Bool {
        status == "CAPTURED_BATTLE_FINISHED" ||
        (status.hasPrefix("INCOMPLETE_") && !status.hasSuffix("_PENDING"))
    }

    @discardableResult
    func attach(to scene: SKScene, generation: Int) -> Bool {
        guard status == "ARMED", scene.view?.window != nil, scene.size.width > 0, scene.size.height > 0,
              scene.childNode(withName: Self.markerName) == nil else { return false }
        let backing = SKShapeNode(rectOf: CGSize(width: 116, height: 22), cornerRadius: 3)
        backing.name = Self.markerName
        backing.fillColor = SKColor.black.withAlphaComponent(0.78)
        backing.strokeColor = .white
        backing.lineWidth = 0.5
        backing.position = CGPoint(x: 68, y: scene.size.height - 22)
        backing.zPosition = 100_000
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = Self.markerName + "_label"
        label.fontSize = 12
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.text = "E145 ARMED"
        backing.addChild(label)
        scene.addChild(backing)
        marker = backing
        initialGeneration = generation
        status = "CAPTURING"
        return true
    }

    /// Records the raw event as delivered to LivingScene.present. The sequence is
    /// local to this actual encounter and never substitutes for rootActionID.
    func recordPresentedEvent(tick: Int, kind: String, sourceID: String, targetID: String,
                              amount: Int, rootActionID: String?, timestampMs: Int?,
                              displaySourceID: String, displayTargetID: String,
                              sceneFrame: Int, sceneTime: Double, generation: Int) -> Int? {
        guard status == "CAPTURING",
              displaySourceID == request.actorID || displayTargetID == request.actorID else { return nil }
        guard events.count < 4_000 else { requestFinish("EVENT_ROW_LIMIT"); return nil }
        nextEventSequence += 1
        let sequence = nextEventSequence
        events.append(["sequence": sequence, "tick": tick, "kind": kind,
                       "sourceID": sourceID, "targetID": targetID, "amount": amount,
                       "rootActionID": (rootActionID as Any?) ?? NSNull(), "timestampMs": (timestampMs as Any?) ?? NSNull(),
                       "displaySourceID": displaySourceID, "displayTargetID": displayTargetID,
                       "sceneFrame": sceneFrame, "sceneTime": sceneTime, "sceneGeneration": generation])
        estimatedBytes += 256 + kind.utf8.count + sourceID.utf8.count + targetID.utf8.count + (rootActionID?.utf8.count ?? 0)
        if estimatedBytes > Self.maxEstimatedBytes { requestFinish("ESTIMATED_BYTE_LIMIT") }
        return sequence
    }

    func recordTransition(eventSequence: Int?, actorID: String, requestedState: String,
                          accepted: Bool?, observedState: String, requestKind: String, sceneFrame: Int,
                          sceneTime: Double, generation: Int) {
        guard status == "CAPTURING", actorID == request.actorID else { return }
        let row: [String: Any] = ["eventSequence": eventSequence as Any? ?? NSNull(),
                                  "actorID": actorID, "requestedState": requestedState,
                                  "accepted": accepted as Any? ?? NSNull(), "observedStateAtRequest": observedState,
                                  "requestKind": requestKind,
                                  "sceneFrame": sceneFrame, "sceneTime": sceneTime,
                                  "sceneGeneration": generation]
        transitions.append(row)
        // Unknown acceptance is still preserved in transitionRequests, but it
        // cannot establish a causal link for later idle rows. Only controller
        // calls that explicitly returned true seed that link.
        if accepted == true {
            latestRequestByActor[actorID] = (eventSequence, requestedState, sceneTime, requestKind, false)
        }
        estimatedBytes += 192 + requestedState.utf8.count + requestKind.utf8.count
        if estimatedBytes > Self.maxEstimatedBytes { requestFinish("ESTIMATED_BYTE_LIMIT") }
    }

    func requestFinish(_ reason: String) {
        guard status == "CAPTURING", terminalReason == nil else { return }
        terminalReason = reason
        status = reason == "BATTLE_FINISHED" ? "FINISH_PENDING" : "INCOMPLETE_PENDING"
    }

    /// Called once from didFinishUpdate after ordinary actions and scene geometry.
    /// The row is a SpriteKit post-action snapshot, not a claim about OCR/video sync.
    func sample(scene: SKScene, sceneFrame: Int, sceneTime: Double, spriteKitTime: Double,
                generation: Int, motions: [String: EnemyMotionController]) {
        guard status == "CAPTURING" || status == "FINISH_PENDING" || status == "INCOMPLETE_PENDING" else { return }
        if let initialGeneration, generation != initialGeneration {
            abort(reason: "SCENE_REBUILT", sceneGeneration: generation); return
        }
        if startSceneTime == nil { startSceneTime = sceneTime }
        let elapsedWall = ProcessInfo.processInfo.systemUptime - startUptime
        if let startSceneTime, sceneTime - startSceneTime > Self.maxDuration { requestFinish("SCENE_DURATION_LIMIT") }
        if elapsedWall > Self.maxDuration { requestFinish("WALL_DURATION_LIMIT") }

        if let terminalMarkerFrame, sceneFrame > terminalMarkerFrame {
            marker?.removeFromParent(); marker = nil
            finalize(sceneFrame: sceneFrame, sceneTime: sceneTime, generation: generation)
            return
        }
        guard frameRows.count < Self.maxFrameRows else {
            requestFinish("FRAME_ROW_LIMIT")
            nextMarkerSequence += 1
            (marker?.childNode(withName: Self.markerName + "_label") as? SKLabelNode)?.text = "E145 LIMIT \(nextMarkerSequence)"
            if terminalMarkerFrame == nil { terminalMarkerFrame = sceneFrame }
            return
        }

        nextMarkerSequence += 1
        let markerText: String
        if terminalReason == nil { markerText = String(format: "E145 %05d", nextMarkerSequence) }
        else { markerText = "E145 END \(nextMarkerSequence)" }
        (marker?.childNode(withName: Self.markerName + "_label") as? SKLabelNode)?.text = markerText

        let ids = EnemyEventRenderRequestR145.encounterToActor.values.sorted()
        let snapshots: [ActorFrame] = ids.compactMap { actorID in
            guard let motion = motions[actorID] else { return nil }
            let snapshot = motion.presentationSnapshot
            let node = motion.node
            let rect = node.frame
            let bounds = scene.frame
            let visible = rect.intersection(bounds)
            let area = max(0, rect.width * rect.height)
            let fraction = area > 0 && !visible.isNull ? min(1, max(0, visible.width * visible.height / area)) : 0
            let state = snapshot["state"] as? String ?? "none"
            observedStates[actorID, default: []].insert(state)
            if var latest = latestRequestByActor[actorID], sceneTime > latest.time, state == latest.state {
                latest.observedAfterRequest = true
                latestRequestByActor[actorID] = latest
            }
            let latest = latestRequestByActor[actorID]
            let isFiniteReturnCandidate = state == "idle"
                && latest.map { $0.state != "idle" && $0.state != "walk" && $0.observedAfterRequest } == true
            return ActorFrame(actorID: actorID, state: state,
                              frameIndex: snapshot["frameIndex"] as? Int ?? -1,
                              framePath: snapshot["framePath"] as? String ?? "",
                              activeClipKey: snapshot["activeClipKey"] as? String ?? "",
                              actionRunning: snapshot["spriteActionRunning"] as? Bool ?? false,
                              texturePresent: node.texture != nil,
                              nodeAttached: node.parent === scene,
                              hidden: node.isHidden,
                              alpha: Double(node.alpha),
                              position: [Double(node.position.x), Double(node.position.y)],
                              size: [Double(node.size.width), Double(node.size.height)],
                              anchor: [Double(node.anchorPoint.x), Double(node.anchorPoint.y)],
                              sceneRect: [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)],
                              visibleFraction: fraction,
                              availableStates: motion.availableStates.map(\.rawValue).sorted(),
                              linkedEventSequence: latest?.sequence, latestRequestedState: latest?.state ?? "",
                              latestRequestKind: latest?.kind ?? "", finiteReturnAfterRequest: isFiniteReturnCandidate)
        }
        let markerVisible = marker?.parent === scene
        let row: [String: Any] = ["sceneFrame": sceneFrame, "sceneTime": sceneTime,
                                  "spriteKitTime": spriteKitTime, "sceneGeneration": generation,
                                  "samplePhase": "didFinishUpdate_post_actions_pre_render",
                                  "markerText": markerText, "markerVisible": markerVisible,
                                  "markerPosition": marker.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
                                  "actors": snapshots.map { $0.dictionary }]
        frameRows.append(row)
        estimatedBytes += 160 + snapshots.count * 384
        lastSampleFrame = sceneFrame
        lastSampleTime = sceneTime
        lastSampleGeneration = generation

        if estimatedBytes > Self.maxEstimatedBytes { requestFinish("ESTIMATED_BYTE_LIMIT") }
        if terminalReason != nil, terminalMarkerFrame == nil { terminalMarkerFrame = sceneFrame }
    }

    func abort(reason: String, sceneGeneration: Int) {
        guard status == "ARMED" || status == "CAPTURING" || status.hasSuffix("_PENDING") else { return }
        marker?.removeFromParent(); marker = nil
        let priorReason = terminalReason
        let failureReason = priorReason.map { "\($0)_THEN_\(reason)" } ?? reason
        terminalReason = failureReason
        status = "INCOMPLETE_\(failureReason)"
        writeFinal(sceneFrame: lastSampleFrame ?? -1,
                   sceneTime: lastSampleTime ?? startSceneTime ?? 0,
                   generation: lastSampleGeneration ?? sceneGeneration,
                   terminationContext: reason)
    }

    /// The existing resolution wait has already provided ordinary update rows.
    /// Finalize at this boundary before App syncScene can rebuild the scene; do
    /// not add a timing delay or claim an extra terminal-marker render.
    func finishAtBattleResolution(sceneFrame: Int, sceneTime: Double, generation: Int) {
        guard status == "CAPTURING" || status.hasSuffix("_PENDING") else { return }
        marker?.removeFromParent(); marker = nil
        if frameRows.isEmpty {
            terminalReason = "BATTLE_FINISHED_WITHOUT_RENDERED_ROWS"
            status = "INCOMPLETE_BATTLE_FINISHED_WITHOUT_RENDERED_ROWS"
        } else if terminalReason == nil || terminalReason == "BATTLE_FINISHED" {
            terminalReason = "BATTLE_FINISHED"
            status = "CAPTURED_BATTLE_FINISHED"
        } else {
            status = "INCOMPLETE_\(terminalReason ?? "UNKNOWN")"
        }
        writeFinal(sceneFrame: lastSampleFrame ?? sceneFrame,
                   sceneTime: lastSampleTime ?? sceneTime,
                   generation: lastSampleGeneration ?? generation,
                   terminationContext: "PRESENT_BATTLE_RESOLUTION_BOUNDARY_NO_EXTRA_MARKER_FRAME")
    }

    private func finalize(sceneFrame: Int, sceneTime: Double, generation: Int) {
        guard status == "FINISH_PENDING" || status == "INCOMPLETE_PENDING" else { return }
        status = terminalReason == "BATTLE_FINISHED" ? "CAPTURED_BATTLE_FINISHED" : "INCOMPLETE_\(terminalReason ?? "UNKNOWN")"
        writeFinal(sceneFrame: sceneFrame, sceneTime: sceneTime, generation: generation)
    }

    private func writeFinal(sceneFrame: Int, sceneTime: Double, generation: Int,
                            terminationContext: String = "NEXT_DID_FINISH_UPDATE_AFTER_TERMINAL_MARKER") {
        let actorIDs = EnemyEventRenderRequestR145.encounterToActor.values.sorted()
        let missing = Dictionary(uniqueKeysWithValues: actorIDs.map { id in
            (id, EnemyMotionState.requiredStates.map(\.rawValue).filter { !observedStates[id, default: []].contains($0) })
        })
        let payload: [String: Any] = ["schema": "enemy-event-render-r145-v1", "status": status,
            "finishReason": terminalReason ?? "SCENE_REBUILT", "runID": request.runID,
            "encounterID": request.encounterID, "expectedActorID": request.actorID,
            "saveKey": request.saveKey, "saveFilename": "qa-\(request.saveKey)-save.json",
            "processID": ProcessInfo.processInfo.processIdentifier,
            "initialSceneGeneration": initialGeneration as Any? ?? NSNull(), "finalSceneGeneration": generation,
            "finalSceneFrame": sceneFrame, "finalSceneTime": sceneTime,
            "terminationContext": terminationContext,
            "elapsedWallSeconds": ProcessInfo.processInfo.systemUptime - startUptime,
            "eventCount": events.count, "transitionRequestCount": transitions.count,
            "frameRowCount": frameRows.count, "estimatedBytes": estimatedBytes,
            "observedStates": observedStates.mapValues { $0.sorted() }, "unobservedAuthoredStates": missing,
            "eventRows": events, "transitionRequests": transitions, "frameRows": frameRows,
            "videoJoin": "NOT_ESTABLISHED_OCR_REQUIRED"]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              data.count <= Self.maxEstimatedBytes * 2 else {
            writeSmallFailure(sceneFrame: sceneFrame, sceneTime: sceneTime, generation: generation,
                              reason: "FINAL_JSON_INVALID_OR_TOO_LARGE")
            return
        }
        let url = request.outputDirectory.appendingPathComponent("enemy_event_render_r145_\(request.runID).json")
        do { try data.write(to: url, options: .atomic) }
        catch { writeSmallFailure(sceneFrame: sceneFrame, sceneTime: sceneTime, generation: generation,
                                  reason: "WRITE_FAILED_\(error.localizedDescription)") }
    }

    private func writeSmallFailure(sceneFrame: Int, sceneTime: Double, generation: Int, reason: String) {
        let payload: [String: Any] = ["schema": "enemy-event-render-r145-v1", "status": "INCOMPLETE_\(reason)",
            "runID": request.runID, "encounterID": request.encounterID, "expectedActorID": request.actorID,
            "saveKey": request.saveKey, "processID": ProcessInfo.processInfo.processIdentifier,
            "finalSceneGeneration": generation, "finalSceneFrame": sceneFrame, "finalSceneTime": sceneTime,
            "preservedEventCount": events.count, "preservedTransitionCount": transitions.count,
            "preservedFrameRowCount": frameRows.count, "videoJoin": "NOT_ESTABLISHED_OCR_REQUIRED"]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: request.outputDirectory.appendingPathComponent("enemy_event_render_r145_\(request.runID).json"), options: .atomic)
    }
}

private extension EnemyEventRenderTraceR145.ActorFrame {
    var dictionary: [String: Any] {
        ["actorID": actorID, "state": state, "frameIndex": frameIndex, "framePath": framePath,
         "activeClipKey": activeClipKey, "actionRunning": actionRunning, "texturePresent": texturePresent,
         "nodeAttached": nodeAttached, "hidden": hidden, "alpha": alpha, "position": position,
         "size": size, "anchor": anchor, "sceneRect": sceneRect, "visibleFraction": visibleFraction,
         "availableStates": availableStates, "linkedEventSequence": linkedEventSequence as Any? ?? NSNull(),
         "latestRequestedState": latestRequestedState, "latestRequestKind": latestRequestKind,
         "finiteReturnAfterRequest": finiteReturnAfterRequest]
    }
}
