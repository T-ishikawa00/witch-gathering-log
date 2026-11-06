import Foundation
import SpriteKit

/// QA-only per-render trace for AIRA's S03. The opt-in full-battle scope also
/// samples all party actors; this observer never adjusts animation timing/poses.
@MainActor final class EquipmentMotionTraceQA {
    static let schema = EquipmentMotionTraceRequest.schema
    private var outputSchema: String {
        capturesFullBattle ? EquipmentMotionTraceRequest.fullBattleSchema : Self.schema
    }
    static let rowLimit = 5_400
    private static let phaseContract = ["walk", "anticipate", "execute", "recover", "idle"]

    private weak var scene: SKScene?
    private weak var body: SKSpriteNode?
    private let request: EquipmentMotionTraceRequest
    var capturesFullBattle: Bool { request.captureScope == .fullBattleParty }
    private let runID = UUID().uuidString.lowercased()
    private let startedAt = ISO8601DateFormatter().string(from: Date())
    private let startedUptime = ProcessInfo.processInfo.systemUptime
    private let outputURL: URL
    private var rows: [[String: Any]] = []
    private var phaseIndex = 0
    private var completionPending: String?
    private var completionReason: String?
    private var terminalSampleNeeded = false
    // R018: the ordinary full-battle observer stays alive through the authored
    // AIRA resolve clip and its terminal hold. This only observes SKAction state.
    private let r018ResolveAssets = ["AIRA__rest_06.png", "AIRA__rest_07.png", "AIRA__rest_08.png"]
    private var r018ResolveNextIndex = 0
    private var r018ResolveActionEnded = false
    private var r018ResolveFailure: String?
    private var r018ResolveFirstSceneFrame: Int?
    private let r018ResolveFrameDeadline = 180
    private var phaseContractCompletedAtSequence: Int?
    private var incompletePartySnapshotRows = 0
    private let expectedPartyActorIDs: Set<String> = ["ERNA", "LUNA", "AIRA", "NOIR"]
    private var expectedPartyCastRoots: [[String: String]] = []
    private var anticipatedRootByActor: [String: (root: String, sceneFrame: Int)] = [:]
    private var observedPartyCombatEvents: [[String: Any]] = []
    private var observedPartyCastActors: Set<String> = []
    private var validatedPartyCastRoots: Set<String> = []

    private func castRootKey(actorID: String, rootActionID: String) -> String {
        EquipmentMotionTraceRootSummary.key(actorID: actorID, rootActionID: rootActionID)
    }

    func setExpectedPartyCastRoots(_ roots: [[String: String]]) {
        guard capturesFullBattle else { return }
        expectedPartyCastRoots = roots
    }

    func recordPartyCombatEvent(kind: String, actorID: String, rootActionID: String?, sceneFrame: Int) {
        guard capturesFullBattle, expectedPartyActorIDs.contains(actorID), let rootActionID, !rootActionID.isEmpty else { return }
        if kind == "cast_start",
           anticipatedRootByActor[actorID]?.root != rootActionID {
            // A pending cast can only be completed by its own next rendered
            // execute/recover before another cast starts for this actor.
            anticipatedRootByActor.removeValue(forKey: actorID)
        }
        observedPartyCombatEvents.append(["eventKind": kind, "actorID": actorID,
                                          "rootActionID": rootActionID, "sceneFrame": sceneFrame])
    }
    private var finalMarkerSetAtFrame: Int?
    private var finalMarkerConfirmationFrame: Int?
    private var marker: SKNode?
    private var markerGeneration = -1
    private var markerReattachCount = 0
    private var markerLifecycleEvents: [[String: Any]] = []
    private var flushed = false

    init(scene: SKScene, body: SKSpriteNode?, request: EquipmentMotionTraceRequest,
          outputDirectory: URL, sceneGeneration: Int) {
        self.scene = scene
        self.body = body
        self.request = request
        self.outputURL = outputDirectory.appendingPathComponent("equipment_motion_\(request.saveKey)_\(runID).json")
        rows.reserveCapacity(1_800)
        _ = ensureMarker(on: scene, generation: sceneGeneration, sceneFrame: nil)
    }

    private func ensureMarker(on scene: SKScene, generation: Int, sceneFrame: Int?) -> Bool {
        let wasDetached = marker != nil && marker?.parent !== scene
        var eventToRecord: String?
        if marker == nil {
            let group = SKNode()
            group.name = "qa_equipment_motion_trace_marker"
            group.zPosition = 20_000
            let back = SKShapeNode(rectOf: CGSize(width: 112, height: 26), cornerRadius: 3)
            back.name = "qa_equipment_motion_trace_marker_back"
            back.fillColor = .black.withAlphaComponent(0.88)
            back.strokeColor = .white.withAlphaComponent(0.9)
            back.lineWidth = 1
            group.addChild(back)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.name = "qa_equipment_motion_trace_marker_text"
            label.fontSize = 14
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            group.addChild(label)
            marker = group
            scene.addChild(group)
            eventToRecord = "initial_attach"
        } else if wasDetached, let marker {
            marker.removeFromParent()
            scene.addChild(marker)
            markerReattachCount += 1
            eventToRecord = "reattach"
        }
        marker?.position = CGPoint(x: 68, y: scene.size.height - 76)
        markerGeneration = generation
        if let eventToRecord { recordMarkerEvent(eventToRecord, scene: scene, generation: generation, sceneFrame: sceneFrame) }
        return wasDetached
    }

    private func recordMarkerEvent(_ event: String, scene: SKScene, generation: Int, sceneFrame: Int?) {
        let position = marker?.position ?? .zero
        markerLifecycleEvents.append(["event":event, "sceneGeneration":generation,
                                      "sceneFrame":sceneFrame as Any? ?? NSNull(),
                                      "position": [Double(position.x), Double(position.y)],
                                      "parentMatchesScene": marker?.parent === scene,
                                      "uptime": ProcessInfo.processInfo.systemUptime])
    }

    /// Called by LivingScene.didFinishUpdate, after SpriteKit actions have run.
    func sample(sceneTime: TimeInterval, sceneFrame: Int, state: String, scene currentScene: SKScene,
                body currentBody: SKSpriteNode?, sceneGeneration: Int,
                partyCastStates: [[String: Any]] = []) {
        guard !flushed else { return }
        let markerReattached = ensureMarker(on: currentScene, generation: sceneGeneration, sceneFrame: sceneFrame)

        if completionPending != nil && !terminalSampleNeeded {
            if capturesFullBattle, completionPending == "CAPTURED_FULL_BATTLE",
               !r018ResolveActionEnded, r018ResolveFailure == nil {
                if markerReattached {
                    completionPending = "INCOMPLETE_TERMINAL_MARKER_REBUILT"
                    marker?.removeFromParent()
                    marker = nil
                    flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
                    return
                }
                // battleFinished is called immediately before pose(resolve).
                // Keep the existing marker and sample only while that held
                // resolve state is naturally playing; no gameplay action is
                // added, restarted, or extended.
                if state != "resolve" {
                    r018ResolveFailure = "resolve_state_ended_before_authored_clip_completed"
                    completionPending = "INCOMPLETE_RESOLVE_CLIP_OR_TERMINAL_HOLD"
                }
            }
            if capturesFullBattle, completionPending == "INCOMPLETE_RESOLVE_CLIP_OR_TERMINAL_HOLD" {
                marker?.removeFromParent()
                marker = nil
                flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
                return
            }
            if capturesFullBattle, completionPending == "CAPTURED_FULL_BATTLE",
               !r018ResolveActionEnded {
                // Fall through and capture the next actual resolve render.
            } else {
            // A scene rebuild between the terminal sample and this callback
            // breaks the marker-to-render evidence chain. Retain the raw rows,
            // but do not report a confirmed terminal render for a new marker.
            if markerReattached {
                marker?.removeFromParent()
                marker = nil
                flush(status: "INCOMPLETE_TERMINAL_MARKER_REBUILT", sceneGeneration: sceneGeneration)
                return
            }
            // A completion row's marker remains attached until the following
            // didFinishUpdate. That interval contains one rendered frame; remove
            // and flush only at this next callback. No battle action is extended.
            if finalMarkerSetAtFrame != nil, finalMarkerConfirmationFrame == nil {
                finalMarkerConfirmationFrame = sceneFrame
            }
            marker?.removeFromParent()
            marker = nil
            flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
            return
            }
        }
        guard let currentBody else {
            completionPending = "INCOMPLETE_ACTOR_NODE_MISSING"
            completionReason = "actor_node_missing_during_capture"
            return
        }
        let actorNodeRebound = currentBody !== body
        if actorNodeRebound { body = currentBody }

        let seq = rows.count
        let markerText = String(format: "S03 %04d", seq)
        (marker?.childNode(withName: "qa_equipment_motion_trace_marker_text") as? SKLabelNode)?.text = markerText
        let frame = ActorBodyFrame.current(on: currentBody)
        let regMap = currentBody.userData?["equipmentDetailRegistrationQA"] as? [String: Any] ?? [:]
        let registration = regMap[EquipmentMotionTraceRequest.gearID] as? [String: Any] ?? [:]
        let holder = currentBody.childNode(withName: "gear_detail:" + EquipmentMotionTraceRequest.gearID)
        let part = holder?.childNode(withName: "part") as? SKSpriteNode
        let bodyCenter = currentBody.convert(CGPoint.zero, to: currentScene)
        let detailCenter = part?.convert(CGPoint.zero, to: currentScene)
        let axisPoint = part.map { $0.convert(CGPoint(x: $0.size.width * 0.5, y: 0), to: currentScene) }
        let detailAngle: Double? = {
            guard let detailCenter, let axisPoint else { return nil }
            return Double(atan2(axisPoint.y - detailCenter.y, axisPoint.x - detailCenter.x))
        }()
        let detailWorldCorners: [[Double]] = part.map { node in
            let hw = node.size.width * 0.5, hh = node.size.height * 0.5
            return [CGPoint(x:-hw,y:-hh),CGPoint(x:hw,y:-hh),CGPoint(x:hw,y:hh),CGPoint(x:-hw,y:hh)].map { point in
                let p = node.convert(point, to: currentScene)
                return [Double(p.x), Double(p.y)]
            }
        } ?? []
        // These corners are node-transform bounds, not the warped raster bounds.
        let bodyWorldCorners: [[Double]] = {
            let x0 = -currentBody.anchorPoint.x * currentBody.size.width
            let y0 = -currentBody.anchorPoint.y * currentBody.size.height
            let x1 = x0 + currentBody.size.width, y1 = y0 + currentBody.size.height
            return [CGPoint(x:x0,y:y0),CGPoint(x:x1,y:y0),CGPoint(x:x1,y:y1),CGPoint(x:x0,y:y1)].map { point in
                let p = currentBody.convert(point, to: currentScene)
                return [Double(p.x), Double(p.y)]
            }
        }()
        let registrationAsset = registration["bodyAssetID"] as? String ?? ""
        let registrationFrame = registration["bodyFrameIndex"] as? Int ?? -1
        let registrationMatches = registrationAsset == (frame?.assetID ?? "") && registrationFrame == (frame?.frameIndex ?? -1)
        let maskNode = (holder as? SKCropNode)?.maskNode
        let ancestors = ancestorVisibility(from: part ?? holder ?? currentBody, stoppingAt: currentScene, relation: "part")
            + (maskNode.map { ancestorVisibility(from: $0, stoppingAt: currentScene, relation: "crop_mask") } ?? [])
        let warp = warpSnapshot(currentBody)
        let markerPosition = marker?.position ?? .zero
        let progressBefore = phaseIndex
        let acceptedPhase = phaseIndex < Self.phaseContract.count && state == Self.phaseContract[phaseIndex]
        let progressAfter = acceptedPhase ? phaseIndex + 1 : phaseIndex
        var row: [String: Any] = [:]
        row["sequence"] = seq; row["phase"] = "didFinishUpdate"; row["sceneTime"] = sceneTime
        row["sceneFrame"] = sceneFrame; row["uptime"] = ProcessInfo.processInfo.systemUptime
        row["elapsedUptime"] = ProcessInfo.processInfo.systemUptime - startedUptime
        row["sceneGeneration"] = sceneGeneration; row["actorNodeRebound"] = actorNodeRebound
        row["markerReattached"] = markerReattached; row["markerGeneration"] = markerGeneration
        row["markerReattachCount"] = markerReattachCount
        row["markerPosition"] = [Double(markerPosition.x), Double(markerPosition.y)]
        row["videoMarker"] = markerText; row["videoMarkerVisible"] = marker?.parent === currentScene
        row["actorID"] = EquipmentMotionTraceRequest.actorID; row["gearID"] = EquipmentMotionTraceRequest.gearID
        if capturesFullBattle {
            let observedActors = Set(partyCastStates.compactMap { $0["actorID"] as? String })
            let malformedSnapshot = partyCastStates.contains { snapshot in
                guard snapshot["bodyExists"] as? Bool == true,
                      let assetID = snapshot["bodyAssetID"] as? String, !assetID.isEmpty,
                      let frameIndex = snapshot["bodyFrameIndex"] as? Int, frameIndex >= 0 else { return true }
                return false
            }
            if partyCastStates.count != expectedPartyActorIDs.count || observedActors != expectedPartyActorIDs || malformedSnapshot {
                incompletePartySnapshotRows += 1
            }
            for snapshot in partyCastStates {
                guard let actor = snapshot["actorID"] as? String,
                      expectedPartyActorIDs.contains(actor),
                      let pose = snapshot["poseState"] as? String else { continue }
                if pose == "anticipate",
                   snapshot["holdingAnticipate"] as? Bool == true,
                   let root = snapshot["pendingRootActionID"] as? String,
                   expectedPartyCastRoots.contains(where: { $0["actorID"] == actor && $0["rootActionID"] == root }) {
                    anticipatedRootByActor[actor] = (root, sceneFrame)
                }
                if ["execute", "recover"].contains(pose),
                   PartyCastRenderedEvidenceR006.matches(
                       actorID: actor, poseState: pose, assetID: snapshot["bodyAssetID"] as? String ?? "",
                       frameIndex: snapshot["bodyFrameIndex"] as? Int ?? -1,
                       castActionActive: snapshot["activePartyCastAction"] as? Bool == true,
                       restActionActive: snapshot["activePartyRestAction"] as? Bool == true
                   ),
                   let anticipated = anticipatedRootByActor[actor],
                   let expected = expectedPartyCastRoots.first(where: { $0["actorID"] == actor && $0["rootActionID"] == anticipated.root }),
                   observedPartyCombatEvents.contains(where: {
                       $0["actorID"] as? String == actor &&
                       $0["rootActionID"] as? String == anticipated.root &&
                       $0["eventKind"] as? String == expected["terminalKind"] &&
                       ($0["sceneFrame"] as? Int ?? Int.max) >= anticipated.sceneFrame &&
                       ($0["sceneFrame"] as? Int ?? Int.max) < sceneFrame
                   }) {
                    observedPartyCastActors.insert(actor)
                    validatedPartyCastRoots.insert(castRootKey(actorID: actor, rootActionID: anticipated.root))
                }
            }
            row["partyCastTraceSchema"] = "party-cast-state-r002"
            row["partyCastStates"] = partyCastStates
            row["partyCastStateActorIDs"] = partyCastStates.compactMap { $0["actorID"] as? String }.sorted()
        }
        row["fixture"] = request.fixture; row["encounterID"] = request.encounterID
        row["observedMode"] = state; row["poseStateSnapshot"] = state
        row["phaseContractProgressBefore"] = progressBefore
        row["phaseContractAccepted"] = acceptedPhase
        row["phaseContractProgressAfter"] = progressAfter
        row["bodyAssetID"] = frame?.assetID ?? ""; row["localFrameIndex"] = frame?.frameIndex ?? -1
        row["canvas"] = [frame?.canvasSize.width ?? 0, frame?.canvasSize.height ?? 0]
        row["registrationStatus"] = registration["status"] as? String ?? "missing_registration"
        row["registrationSource"] = registration["registrationSource"] as? String ?? "missing"
        row["registrationState"] = registration["state"] as? String ?? ""
        row["registrationBodyAssetID"] = registrationAsset; row["registrationFrameIndex"] = registrationFrame
        row["registrationMatchesRenderedBodyFrame"] = registrationMatches
        row["registrationMismatchReason"] = registrationMatches ? "" : "registration_does_not_match_observed_actor_body_frame"
        row["normalizedPoint"] = registration["normalizedPoint"] ?? []
        row["normalizedSize"] = registration["normalizedSize"] ?? []
        row["normalizedHeight"] = registration["normalizedHeight"] ?? 0
        row["angleRadians"] = registration["angleRadians"] ?? 0
        row["registrationVisible"] = registration["visible"] as? Bool ?? false
        row["partExists"] = part != nil
        row["holderHidden"] = holder.map { $0.isHidden as Any } ?? NSNull()
        row["holderAlpha"] = holder.map { Double($0.alpha) as Any } ?? NSNull()
        row["partHidden"] = part.map { $0.isHidden as Any } ?? NSNull()
        row["partAlpha"] = part.map { Double($0.alpha) as Any } ?? NSNull()
        row["bodyHidden"] = currentBody.isHidden; row["bodyAlpha"] = Double(currentBody.alpha)
        row["ancestorVisibility"] = ancestors; row["cropMaskExists"] = maskNode != nil
        row["cropMaskHidden"] = maskNode.map { $0.isHidden as Any } ?? NSNull()
        row["cropMaskAlpha"] = maskNode.map { Double($0.alpha) as Any } ?? NSNull()
        row["renderabilityStatus"] = renderabilityStatus(part: part, holder: holder, body: currentBody, ancestors: ancestors)
        row["partWorldCenter"] = detailCenter.map { [Double($0.x), Double($0.y)] } ?? []
        row["partWorldAxisPoint"] = axisPoint.map { [Double($0.x), Double($0.y)] } ?? []
        row["partWorldCorners"] = detailWorldCorners; row["partWorldAngleRadians"] = detailAngle ?? 0
        row["bodyWorldOrigin"] = [Double(bodyCenter.x), Double(bodyCenter.y)]
        row["unwarpedBodyNodeWorldCorners"] = bodyWorldCorners
        row["bodyWorldCornersMeaning"] = "unwarped_node_transform_bounds_not_raster_mesh_bounds"
        row["bodyWarpGeometry"] = warp
        row["bodyPosition"] = [Double(currentBody.position.x), Double(currentBody.position.y)]
        row["bodySize"] = [Double(currentBody.size.width), Double(currentBody.size.height)]
        row["bodyRotation"] = Double(currentBody.zRotation)
        row["actionKeys"] = ["party_walk_clip", "party_cast_clip", "party_rest_clip"].filter { currentBody.action(forKey: $0) != nil }
        rows.append(row)
        phaseIndex = progressAfter
        if phaseIndex == Self.phaseContract.count && phaseContractCompletedAtSequence == nil {
            phaseContractCompletedAtSequence = seq
        }
        if terminalSampleNeeded {
            terminalSampleNeeded = false
            if !capturesFullBattle {
                finalMarkerSetAtFrame = sceneFrame
            }
        } else if phaseIndex == Self.phaseContract.count && request.captureScope.stopsWhenFivePhaseSequenceCompletes {
            completionPending = "CAPTURED_SEQUENCE"
            finalMarkerSetAtFrame = sceneFrame
        } else if rows.count >= Self.rowLimit {
            completionPending = "INCOMPLETE_ROW_LIMIT"
            completionReason = "row_limit_reached_before_battle_completion"
        }
        if capturesFullBattle, completionPending == "CAPTURED_FULL_BATTLE",
           !terminalSampleNeeded, !r018ResolveActionEnded, r018ResolveFailure == nil {
            observeR018Resolve(state: state, frame: frame, body: currentBody, sceneFrame: sceneFrame)
        }
    }

    private func observeR018Resolve(state: String, frame: ActorBodyFrame.Sample?,
                                    body: SKSpriteNode, sceneFrame: Int) {
        guard state == "resolve", let frame else {
            r018ResolveFailure = "resolve_body_sample_missing"
            completionPending = "INCOMPLETE_RESOLVE_CLIP_OR_TERMINAL_HOLD"
            return
        }
        if r018ResolveFirstSceneFrame == nil { r018ResolveFirstSceneFrame = sceneFrame }
        if sceneFrame - (r018ResolveFirstSceneFrame ?? sceneFrame) > r018ResolveFrameDeadline {
            r018ResolveFailure = "resolve_clip_observation_deadline_exceeded"
            completionPending = "INCOMPLETE_RESOLVE_CLIP_OR_TERMINAL_HOLD"
            return
        }
        let file = (frame.assetID as NSString).lastPathComponent
        let actionActive = body.action(forKey: "party_rest_clip") != nil
        if r018ResolveNextIndex < r018ResolveAssets.count {
            let previous = r018ResolveNextIndex - 1
            if previous >= 0, frame.assetID.hasSuffix(r018ResolveAssets[previous]),
               frame.frameIndex == previous, actionActive {
                return // repeated renders of the same authored frame are expected
            }
            guard frame.assetID.hasSuffix(r018ResolveAssets[r018ResolveNextIndex]),
                  frame.frameIndex == r018ResolveNextIndex, actionActive else {
                r018ResolveFailure = "resolve_authored_frame_order_or_action_mismatch"
                completionPending = "INCOMPLETE_RESOLVE_CLIP_OR_TERMINAL_HOLD"
                return
            }
            r018ResolveNextIndex += 1
            return
        }
        guard file == r018ResolveAssets[2], frame.frameIndex == 2 else {
            r018ResolveFailure = "resolve_terminal_pose_not_held_after_action"
            completionPending = "INCOMPLETE_RESOLVE_CLIP_OR_TERMINAL_HOLD"
            return
        }
        // rest_08 has a 240 ms authored dwell. didFinishUpdate can continue to
        // observe frame 2 while party_rest_clip is still active; this is ordinary
        // rendering, not a failed terminal hold. Require a later inactive frame 2.
        guard !actionActive else { return }
        r018ResolveActionEnded = true
        finalMarkerSetAtFrame = sceneFrame
    }

    /// Called by LivingScene after the actual battle event playback finishes.
    /// The next rendered update is sampled as the terminal row; one following
    /// update confirms the marker was rendered before the trace is flushed.
    func battleFinished(won: Bool) {
        guard capturesFullBattle, !flushed, completionPending == nil else { return }
        if incompletePartySnapshotRows > 0 {
            completionPending = "INCOMPLETE_PARTY_OBSERVATION_GAP"
            completionReason = "battle_finished_with_missing_party_snapshot_rows"
        } else {
            // Capture completion and cast-chain validation are separate fields.
            // A finished battle can be captured even when some actors had no
            // event-backed cast transition; that evidence remains incomplete.
            completionPending = "CAPTURED_FULL_BATTLE"
            completionReason = won ? "battle_finished_victory" : "battle_finished_defeat"
        }
        terminalSampleNeeded = true
    }

    /// Lifecycle interruptions are incomplete evidence, never a successful
    /// battle capture. Flush buffered rows without claiming terminal rendering.
    func abort(reason: String, sceneGeneration: Int) {
        guard !flushed else { return }
        completionPending = "INCOMPLETE_\(reason)"
        completionReason = reason
        terminalSampleNeeded = false
        marker?.removeFromParent()
        marker = nil
        flush(status: completionPending ?? "INCOMPLETE", sceneGeneration: sceneGeneration)
    }

    private func ancestorVisibility(from node: SKNode, stoppingAt scene: SKScene, relation: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var cursor: SKNode? = node
        while let current = cursor {
            result.append(["relation": relation, "name": current.name ?? "", "nodeType": String(describing: type(of: current)),
                           "isHidden": current.isHidden, "alpha": Double(current.alpha)])
            if current === scene { break }
            cursor = current.parent
        }
        return result
    }

    private func renderabilityStatus(part: SKSpriteNode?, holder: SKNode?, body: SKSpriteNode,
                                     ancestors: [[String: Any]]) -> String {
        guard let part, let holder else { return "unknown_missing_part_or_holder" }
        if part.isHidden { return "hidden_part" }
        if holder.isHidden { return "hidden_holder" }
        if body.isHidden { return "hidden_body" }
        if part.alpha <= 0 || holder.alpha <= 0 || body.alpha <= 0 { return "zero_alpha" }
        if let crop = holder as? SKCropNode {
            guard let mask = crop.maskNode else { return "unknown_crop_mask_missing" }
            if mask.isHidden { return "hidden_crop_mask" }
            if mask.alpha <= 0 { return "zero_alpha_crop_mask" }
        }
        for item in ancestors {
            if item["isHidden"] as? Bool == true { return "hidden_ancestor" }
            if let alpha = item["alpha"] as? Double, alpha <= 0 { return "zero_alpha_ancestor" }
        }
        return "visible_by_node_flags_only"
    }

    private func warpSnapshot(_ body: SKSpriteNode) -> [String: Any] {
        guard let grid = body.warpGeometry as? SKWarpGeometryGrid else {
            return ["present": false, "gridDimensionsKnown": false, "columns": NSNull(), "rows": NSNull(),
                    "vertexCount": 0, "sourcePositions": NSNull(), "destinationPositions": NSNull()]
        }
        var sources: [[Double]] = [], destinations: [[Double]] = []
        var allFinite = true, maxDeltaX = 0.0, maxDeltaY = 0.0
        for index in 0..<grid.vertexCount {
            let source = grid.sourcePosition(at: index), destination = grid.destPosition(at: index)
            let sx = Double(source.x), sy = Double(source.y), dx = Double(destination.x), dy = Double(destination.y)
            allFinite = allFinite && sx.isFinite && sy.isFinite && dx.isFinite && dy.isFinite
            maxDeltaX = max(maxDeltaX, abs(dx - sx) * Double(body.size.width))
            maxDeltaY = max(maxDeltaY, abs(dy - sy) * Double(body.size.height))
            sources.append([sx, sy]); destinations.append([dx, dy])
        }
        let known = grid.vertexCount == 35
        return ["present": true, "gridDimensionsKnown": known,
                "columns": known ? 4 as Any : NSNull(), "rows": known ? 6 as Any : NSNull(),
                "vertexCount": grid.vertexCount, "allFinite": allFinite,
                "maxDeltaArtworkPixels": [maxDeltaX, maxDeltaY],
                "sourcePositions": sources, "destinationPositions": destinations]
    }

    private func flush(status: String, sceneGeneration: Int) {
        guard !flushed else { return }
        flushed = true
        var payload: [String: Any] = [
            "schema": outputSchema, "status": status, "runID": runID,
            "saveKey": request.saveKey, "fixture": request.fixture,
            "encounterID": request.encounterID, "actorID": EquipmentMotionTraceRequest.actorID,
            "gearID": EquipmentMotionTraceRequest.gearID,
            "startedAt": startedAt, "startedUptime": startedUptime,
            "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "outputFilename": outputURL.lastPathComponent,
            "sceneGenerationAtFinish": sceneGeneration,
            "modeContract": Self.phaseContract,
            "finalMarkerRenderedFrameCount": finalMarkerSetAtFrame != nil && finalMarkerConfirmationFrame != nil ? 1 : 0,
            "finalMarkerSetAtSceneFrame": finalMarkerSetAtFrame as Any? ?? NSNull(),
            "finalMarkerConfirmationSceneFrame": finalMarkerConfirmationFrame as Any? ?? NSNull(),
            "markerReattachCount": markerReattachCount,
            "markerLifecycleEvents": markerLifecycleEvents,
            "rowLimit": Self.rowLimit, "registrationFrameMismatchCount": rows.filter { $0["registrationMatchesRenderedBodyFrame"] as? Bool == false }.count,
            "rows": rows
        ]
        if capturesFullBattle {
            payload["captureScope"] = request.captureScope.rawValue
            payload["completionReason"] = completionReason as Any? ?? NSNull()
            payload["phaseContractCompletedAtSequence"] = phaseContractCompletedAtSequence as Any? ?? NSNull()
            payload["incompletePartySnapshotRows"] = incompletePartySnapshotRows
            payload["expectedPartyActorIDs"] = expectedPartyActorIDs.sorted()
            payload["expectedPartyCastRoots"] = expectedPartyCastRoots
            payload["observedPartyCombatEvents"] = observedPartyCombatEvents
            payload["observedPartyCastActorIDs"] = observedPartyCastActors.sorted()
            payload["missingPartyCastActorIDs"] = expectedPartyActorIDs.subtracting(observedPartyCastActors).sorted()
            let rootSummary = EquipmentMotionTraceRootSummary.make(expectedRoots: expectedPartyCastRoots,
                                                                   validatedRootKeys: validatedPartyCastRoots,
                                                                   expectedActors: expectedPartyActorIDs)
            payload.merge(rootSummary.payloadFields) { _, newValue in newValue }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
        } catch { print("EquipmentMotionTraceQA write failed: \(error)") }
    }
}
