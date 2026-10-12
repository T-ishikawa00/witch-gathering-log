import SpriteKit
import UIKit
import ImageIO
import CryptoKit

/// Art states are runtime requests, not a claim that every actor has an authored clip.
enum EnemyMotionState: String, CaseIterable {
    case idle, walk, flight, anticipate, execute, recover, hit, resolve

    static let requiredStates: [EnemyMotionState] = [
        .idle, .walk, .anticipate, .execute, .recover, .hit, .resolve
    ]
}

enum EnemyMotionError: Error, LocalizedError {
    case indexMissing
    case actorMissing(String)
    case stillMissing(String)
    case clipMissing(actorID: String, state: EnemyMotionState)
    case framesMissing(actorID: String, state: EnemyMotionState)

    var errorDescription: String? {
        switch self {
        case .indexMissing: return "Art/runtime_index.json was not found."
        case .actorMissing(let id): return "No runtime index entry for \(id)."
        case .stillMissing(let id): return "No full-body fallback PNG for \(id)."
        case .clipMissing(let id, let state): return "\(id) has no authored \(state.rawValue) clip."
        case .framesMissing(let id, let state): return "The \(state.rawValue) clip for \(id) has no loadable frames."
        }
    }
}

/// Loads one of the 30 stable enemy IDs from Art/runtime_index.json and plays
/// explicitly declared frame, rig, or registered-pose clips. A still alone is
/// never silently promoted to a walk/idle animation.
@MainActor
final class EnemyMotionController {
    let node: SKSpriteNode
    let actorID: String
    let availableStates: Set<EnemyMotionState>
    var onUnsupportedState: ((EnemyMotionError) -> Void)?
    /// Installed only by the opt-in R084 observer; fired by the existing
    /// SpriteKit completion callback before the same didFinishUpdate.
    var qaRenderBoundActionCompleted: ((EnemyMotionState) -> Void)?

    private let artRoot: URL
    private let clips: [String: [String: Any]]
    private var textures: [String: SKTexture] = [:]
    private var partRig:EnemyPartRig?
    private var registeredPoses:EnemyRegisteredPoses?
    private var activeState: EnemyMotionState?
    private var activeClipKey: String?
    private var defaultCanvas=CGSize(width:1,height:1)
    private var defaultAnchor=CGPoint(x:0.5,y:0.1)
    private var fittedHeight:CGFloat=1
    private let qaMothCandidateFlagPresent: Bool
    private let qaMothIsolatedFlagPresent: Bool
    private let qaMothRegistrationEnabled: Bool
    private var qaMothRegistrationApplied = false
    private var qaMothRegistrationReason = "not_requested"
    private var qaMothRegistrationToken: UUID?
    private var qaMothAnchorPlan: MothIdleAnchorPlanR050?
    private var qaMothAnchorFrameIndex: Int?
    private var qaMothLogicalFrameIndex: Int?

    /// `artRoot` is the directory exposed to SpriteKit as the Art bundle folder,
    /// containing `runtime_index.json`, `Enemies/` and `ActorStills/`.
    init(actorID: String, artRoot: URL, size: CGSize? = nil) throws {
        self.actorID = actorID
#if targetEnvironment(simulator)
        let qaArgs = ProcessInfo.processInfo.arguments
        self.qaMothCandidateFlagPresent = qaArgs.contains("--qa-moth-idle-registration-r050")
        self.qaMothIsolatedFlagPresent = qaArgs.contains("--qa-isolated")
        self.qaMothRegistrationEnabled = MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: qaArgs, isSimulator: true)
        self.qaMothRegistrationReason = qaMothRegistrationEnabled ? "local_candidate_pending_exact_clip" : "isolated_baseline_override"
#else
        self.qaMothCandidateFlagPresent = false
        self.qaMothIsolatedFlagPresent = false
        self.qaMothRegistrationEnabled = MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: [], isSimulator: false)
#endif
        self.artRoot = artRoot
        let indexURL = artRoot.appendingPathComponent("runtime_index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [String: Any],
              let entry = entries[actorID] as? [String: Any] else {
            if FileManager.default.fileExists(atPath: indexURL.path) {
                throw EnemyMotionError.actorMissing(actorID)
            }
            throw EnemyMotionError.indexMissing
        }

        let clipMap = entry["clips"] as? [String: [String: Any]] ?? [:]
        self.clips = clipMap
        if let rigPath=entry["partRig"] as? String {
            #if targetEnvironment(simulator)
            let qaArguments = ProcessInfo.processInfo.arguments
            let qaDragonGaitR038Enabled = DragonGaitR038QA.isLegacyEnabled(arguments: qaArguments)
            let qaDragonDistalLegR007Enabled = DragonDistalLegR007QA.isEnabled(arguments: qaArguments)
            let explicitR064RequestValid = DragonFourLegStanceR064QA.isEnabled(arguments: qaArguments, actorID: actorID)
            let normalEntryBackend = DragonNormalEntryBackendR068.select(
                arguments: qaArguments, isSimulator: true, actorID: actorID,
                explicitR064RequestValid: explicitR064RequestValid)
            let qaDragonFourLegR064Enabled = normalEntryBackend == .r064LocalDefaultCandidate ||
                normalEntryBackend == .r064ExplicitQACandidate
            let qaWalkMeshEnabled = DragonGaitR038QA.enablesR004(arguments: qaArguments)
            #else
            let qaWalkMeshEnabled = false
            let qaDragonGaitR038Enabled = false
            let qaDragonDistalLegR007Enabled = false
            let qaDragonFourLegR064Enabled = false
            let normalEntryBackend = DragonNormalEntryBackendR068.Selection.unaffected
            #endif
            let rig=try EnemyPartRig(definitionURL:artRoot.appendingPathComponent(rigPath),artRoot:artRoot,
                                     walkOverlay:clipMap["walk"],qaWalkMeshCandidateEnabled:qaWalkMeshEnabled,
                                     qaDragonGaitR038Enabled:qaDragonGaitR038Enabled,
                                     qaDragonDistalLegR007Enabled:qaDragonDistalLegR007Enabled,
                                     qaDragonFourLegR064Enabled:qaDragonFourLegR064Enabled,
                                     normalEntryBackendR068:normalEntryBackend.rawValue)
            self.partRig=rig;self.node=SKSpriteNode(color:.clear,size:rig.canvasSize);self.node.name=actorID
            self.node.anchorPoint=rig.normalizedAnchor;self.node.addChild(rig.node)
            let poses=EnemyRegisteredPoses(root:artRoot,referenceCanvas:rig.canvasSize)
            registeredPoses=poses;self.node.addChild(poses.node)
            var rigStates = Set(rig.availableStates.compactMap(EnemyMotionState.init(rawValue:)))
            // Preserve the legacy request contract: ground-walk can fall back to flight.
            // Expose flight explicitly as well so candidate walks do not make it unreachable.
            if rig.availableStates.contains("flight") { rigStates.insert(.walk) }
            self.availableStates=rigStates.union(clipMap.compactMap{ key,value in
                value["mode"] as? String == "registered_keyposes_v1" ? EnemyMotionState(rawValue:key):nil
            });rig.onClipCompleted={[weak self] name in
                guard let self else { return }
                if let completed = EnemyMotionState(rawValue: name) { self.qaRenderBoundActionCompleted?(completed) }
                self.returnToRest(after:name)
            };return
        }
        self.availableStates = Set(clipMap.keys.compactMap(EnemyMotionState.init(rawValue:)))

        let stillPath = entry["selectedPNG"] as? String
        let statePaths = entry["sequenceFrames"] as? [String: Any]
        let firstClipPath = (clipMap["idle"]?["frames"] as? [String])?.first
            ?? clipMap.sorted(by: { $0.key < $1.key }).compactMap { $0.value["frames"] as? [String] }.flatMap { $0 }.first
        guard let path = firstClipPath ?? stillPath ?? statePaths?.values.compactMap({ $0 as? [String] }).flatMap({ $0 }).first,
              let stillTexture = Self.texture(path: path, root: artRoot) else {
            throw EnemyMotionError.stillMissing(actorID)
        }
        self.node = SKSpriteNode(texture: stillTexture)
        self.node.name = actorID
        if let canvas=entry["canvas_px"] as? [Double],canvas.count==2,canvas[0]>0,canvas[1]>0 {
            let anchor=(entry["anchor"] as? [Double]) ?? ((entry["anchor"] as? [String:Any])?["value_px"] as? [Double])
            if let anchor,anchor.count==2{self.node.anchorPoint=CGPoint(x:anchor[0]/canvas[0],y:1-anchor[1]/canvas[1])}
            else{self.node.anchorPoint=CGPoint(x:0.5,y:0.1)}
        }else{self.node.anchorPoint=CGPoint(x:0.5,y:0.1)}
        defaultCanvas=stillTexture.size();defaultAnchor=node.anchorPoint
        if let size { self.node.size = size }
        fittedHeight=node.size.height
    }

    /// Attempts to play the requested authored clip. Returns `false` and calls
    /// `onUnsupportedState` when the exact clip is absent; caller owns fallback policy.
    @discardableResult
    func play(_ state: EnemyMotionState, restart: Bool = false) -> Bool {
        if (qaMothCandidateFlagPresent || qaMothIsolatedFlagPresent), qaMothRegistrationEnabled,
           !(actorID == MothIdleAnchorRegistrationR050.actorID && state == .idle),
           !qaMothRegistrationApplied {
            qaMothRegistrationReason = "not_target_actor_idle_pair"
        }
        if let rig=partRig {
            if activeState == state && !restart {return true}
            if let clip=clips[state.rawValue],clip["mode"] as? String == "registered_keyposes_v1",let registeredPoses {
                guard registeredPoses.play(clip,completion:{[weak self] in
                    guard let self,self.activeState==state else{return}
                    self.qaRenderBoundActionCompleted?(state)
                    self.returnToRest(after:state.rawValue)
                }) else {
                    onUnsupportedState?(.framesMissing(actorID:actorID,state:state));return false
                }
                rig.stop();rig.node.isHidden=true;activeState=state;return true
            }
            if state == .walk,
               (rig.hasWalkMeshCandidate || clips["walk"]?["mode"] as? String == "part_rig_leg_overlay_candidate_v1"),
               rig.availableStates.contains("walk") {
                guard rig.play("walk",restart:restart) else{return false}
                registeredPoses?.stop();rig.node.isHidden=false;activeState=state;return true
            }
            let clip = state == .walk && rig.availableStates.contains("flight") ? "flight" : state.rawValue
            guard rig.play(clip,restart:restart) else{return false}
            registeredPoses?.stop();rig.node.isHidden=false;activeState=state;return true
        }
        guard let clip = clips[state.rawValue] else {
            onUnsupportedState?(.clipMissing(actorID: actorID, state: state))
            return false
        }
        if activeState == state && !restart { return true }
        guard let paths = clip["frames"] as? [String], !paths.isEmpty else {
            onUnsupportedState?(.framesMissing(actorID: actorID, state: state))
            return false
        }
        let frames = paths.compactMap { texture(for: $0) }
        guard frames.count == paths.count, !frames.isEmpty else {
            onUnsupportedState?(.framesMissing(actorID: actorID, state: state))
            return false
        }

        let fps = (clip["fps"] as? NSNumber)?.doubleValue ?? 24.0
        guard fps > 0 else {
            onUnsupportedState?(.framesMissing(actorID: actorID, state: state))
            return false
        }
        let loop = clip["loop"] as? Bool ?? false
        let key = "witch.enemy.clip"
        node.removeAction(forKey: key)
        clearMothRegistration(resetAnchor: false)
        activeState = state
        activeClipKey = key
        // Clips may have a different export canvas from the preserved still.
        // Reset the base geometry for old clips without per-clip metadata.
        // Otherwise a new walk anchor leaks into preserved idle/hit artwork.
        node.size=CGSize(width:fittedHeight*defaultCanvas.width/defaultCanvas.height,height:fittedHeight)
        node.anchorPoint=defaultAnchor
        if let canvas=clip["canvas_px"] as? [Double],canvas.count==2,canvas[0]>0,canvas[1]>0 {
            node.size.width=node.size.height*canvas[0]/canvas[1]
            if let anchor=clip["anchor"] as? [Double],anchor.count==2 {
                node.anchorPoint=CGPoint(x:anchor[0]/canvas[0],y:1-anchor[1]/canvas[1])
            }
        }
        if let scale=(clip["display_scale"] as? NSNumber)?.doubleValue,scale.isFinite,scale>=0.25,scale<=4 {
            node.size.width *= scale;node.size.height *= scale
        }
        node.texture=frames[0]
        if qaMothRegistrationEnabled, actorID == MothIdleAnchorRegistrationR050.actorID,
           state == .idle, let plan = mothRegistrationPlan(clip: clip, paths: paths, textures: frames) {
            if runMothRegisteredIdle(plan: plan, frames: frames, fps: fps, key: key) { return true }
        }
        let animate = SKAction.animate(with: frames, timePerFrame: 1.0 / fps,
                                      resize: false, restore: false)
        if loop {
            node.run(.repeatForever(animate), withKey: key)
        } else {
            node.run(.sequence([animate, .run { [weak self] in
                guard let self, self.activeClipKey == key, self.activeState == state else { return }
                self.qaRenderBoundActionCompleted?(state)
                // A terminal pose remains the active state after its frames end.
                // Final HP reconciliation must not restart it from frame zero.
                self.activeState = state == .resolve ? .resolve : nil
                self.activeClipKey = nil
                self.returnToRest(after:state.rawValue)
            }]), withKey: key)
        }
        return true
    }

    /// Validate the exact idle resource tuple before the provisional local R050
    /// registration alters anchors. Any mismatch keeps the authored clip path.
    private func mothRegistrationPlan(clip: [String: Any], paths: [String],
                                     textures: [SKTexture]) -> MothIdleAnchorPlanR050? {
        guard paths.count == textures.count else {
            qaMothRegistrationReason = "loaded_frame_count_mismatch"; return nil
        }
        guard let canvas = clip["canvas_px"] as? [Double], canvas.count == 2,
              let anchor = clip["anchor"] as? [Double], anchor.count == 2 else {
            qaMothRegistrationReason = "clip_canvas_or_anchor_missing"; return nil
        }
        guard let declaredFrameCount = clip["frame_count"] as? Int,
              let duration = (clip["duration_seconds"] as? NSNumber)?.doubleValue else {
            qaMothRegistrationReason = "clip_count_or_duration_missing"; return nil
        }
        let fps = (clip["fps"] as? NSNumber)?.doubleValue ?? .nan
        let displayScale = (clip["display_scale"] as? NSNumber)?.doubleValue ?? 1
        let loops = clip["loop"] as? Bool ?? false
        var frameFacts: [MothIdleAnchorFrameR050] = []
        for (path, texture) in zip(paths, textures) {
            let url = artRoot.appendingPathComponent(path)
            guard let bytes = try? Data(contentsOf: url) else {
                qaMothRegistrationReason = "source_bytes_unreadable"; return nil
            }
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  width == 512, height == 512,
                  texture.size().width == 512, texture.size().height == 512 else {
                qaMothRegistrationReason = "source_or_texture_canvas_mismatch"; return nil
            }
            frameFacts.append(.init(path: path, sha256: digest,
                                    canvasWidth: width, canvasHeight: height))
        }
        let facts = MothIdleAnchorClipFactsR050(actorID: actorID, state: "idle", frames: frameFacts,
            canvasWidth: canvas[0], canvasHeight: canvas[1], anchorTopLeftX: anchor[0],
            anchorTopLeftY: anchor[1], declaredFrameCount: declaredFrameCount, fps: fps,
            durationSeconds: duration, displayScale: displayScale, loops: loops)
        switch MothIdleAnchorRegistrationR050.validatedPlan(facts: facts) {
        case .allowed(let plan):
            qaMothRegistrationReason = "validated_exact_pins"
            return plan
        case .rejected(let reason):
            qaMothRegistrationReason = reason
            return nil
        case .notRequested:
            qaMothRegistrationReason = "flags_not_enabled"
            return nil
        }
    }

    @discardableResult
    private func runMothRegisteredIdle(plan: MothIdleAnchorPlanR050, frames: [SKTexture],
                                       fps: Double, key: String) -> Bool {
        guard frames.count == plan.frames.count, fps == plan.fps else {
            qaMothRegistrationReason = "runtime_plan_shape_mismatch"; return false
        }
        let token = UUID()
        qaMothRegistrationToken = token
        qaMothAnchorPlan = plan
        qaMothRegistrationApplied = true
        qaMothAnchorFrameIndex = 0
        qaMothLogicalFrameIndex = 0
        qaMothRegistrationReason = "applied_candidate"
        applyMothFrameAndAnchor(0, plan: plan, frames: frames, token: token, key: key)

        // One ordered action clock owns both texture and anchor. This avoids
        // independent animate/customAction clocks drifting at frame boundaries.
        let frameSteps = plan.frames.indices.map { index in
            SKAction.sequence([
                SKAction.run { [weak self] in
                    guard let self, self.qaMothRegistrationToken == token,
                          self.activeClipKey == key, self.activeState == .idle else { return }
                    self.applyMothFrameAndAnchor(index, plan: plan, frames: frames,
                                                 token: token, key: key)
                },
                SKAction.wait(forDuration: plan.frameDurationSeconds)
            ])
        }
        node.run(.repeatForever(.sequence(frameSteps)), withKey: key)
        return true
    }

    private func applyMothFrameAndAnchor(_ index: Int, plan: MothIdleAnchorPlanR050,
                                         frames: [SKTexture], token: UUID, key: String) {
        guard qaMothRegistrationToken == token, activeClipKey == key, activeState == .idle,
              plan.frames.indices.contains(index), frames.indices.contains(index) else { return }
        let frame = plan.frames[index]
        node.texture = frames[index]
        node.anchorPoint = CGPoint(x: frame.normalizedAnchorX, y: frame.normalizedAnchorYBottomUp)
        qaMothAnchorFrameIndex = index
        qaMothLogicalFrameIndex = index
    }

    private func clearMothRegistration(resetAnchor: Bool) {
        qaMothRegistrationToken = nil
        qaMothAnchorPlan = nil
        qaMothAnchorFrameIndex = nil
        qaMothLogicalFrameIndex = nil
        qaMothRegistrationApplied = false
        if resetAnchor { node.anchorPoint = defaultAnchor }
        if qaMothRegistrationEnabled { qaMothRegistrationReason = "cleared_on_state_exit" }
    }

    /// Warms registered-pose image textures and exercises their existing shader
    /// through an off-scene snapshot. The active rig/state and gameplay node stay
    /// untouched; actors without registered clips are not applicable.
    func prepareRegisteredPoseRendering(in view: SKView, captureSnapshots: Bool = true,
                                        shouldContinue: @escaping () -> Bool = { true }) async -> RegisteredPosePreparationResult? {
        guard partRig != nil, let registeredPoses else { return nil }
        let registeredClips = EnemyMotionState.allCases.compactMap { clips[$0.rawValue] }
            .filter { $0["mode"] as? String == "registered_keyposes_v1" }
        guard !registeredClips.isEmpty else { return nil }
        let result = await registeredPoses.prepareForFirstRender(clips: registeredClips, in: view,
                                                                 captureSnapshots: captureSnapshots,
                                                                 shouldContinue: shouldContinue)
        return result
    }

    private func returnToRest(after state:String){
        guard state != "resolve",state != "idle",state != "walk" else{return}
        if state=="execute",play(.recover,restart:true){return}
        _ = play(.idle,restart:true)
    }
    var resolveDuration:Double {
        if let clip=clips[EnemyMotionState.resolve.rawValue] {
            if clip["mode"] as? String == "registered_keyposes_v1",
               let seconds=(clip["duration"] as? NSNumber)?.doubleValue,seconds.isFinite,seconds>0 {return seconds}
            if let paths=clip["frames"] as? [String],
               let fps=(clip["fps"] as? NSNumber)?.doubleValue,fps.isFinite,fps>0 {return Double(paths.count)/fps}
        }
        return partRig?.duration(of:"resolve") ?? 0
    }
    var presentationSnapshot:[String:Any] {
        let paths=activeState.flatMap{clips[$0.rawValue]?["frames"] as? [String]} ?? []
        let index=partRig == nil ? paths.firstIndex{textures[$0] === node.texture} : nil
        var snapshot:[String:Any] = ["state":activeState?.rawValue ?? "none","frameIndex":index ?? -1,
                "framePath":index.map{paths[$0]} ?? "","isPartRig":partRig != nil,
                "resolveDuration":resolveDuration,"alpha":node.alpha,
                "spriteActionRunning": activeClipKey.map { node.action(forKey: $0) != nil } ?? false,
                "activeClipKey": activeClipKey ?? ""]
        if let partRig {snapshot["partRig"]=partRig.presentationSnapshot}
        if let registeredPoses {snapshot["registeredPoses"]=registeredPoses.presentationSnapshot}
        if actorID == MothIdleAnchorRegistrationR050.actorID || qaMothCandidateFlagPresent || qaMothIsolatedFlagPresent {
            let logicalIndex = qaMothLogicalFrameIndex
            let actualTexturePaths = paths.filter { textures[$0] === node.texture }
            let actualTexturePath = actualTexturePaths.count == 1 ? (actualTexturePaths.first ?? "") : ""
            let logicalFrame = qaMothAnchorPlan.flatMap { plan in
                logicalIndex.flatMap { i in plan.frames.indices.contains(i) ? plan.frames[i] : nil }
            }
            let logicalPath = logicalFrame?.path ?? ""
            let textureMatchesLogicalPath = actualTexturePaths.count == 1
                && !logicalPath.isEmpty && actualTexturePath == logicalPath
            let anchorMatchesLogicalFrame = logicalFrame.map { frame in
                abs(Double(node.anchorPoint.x) - frame.normalizedAnchorX) < 0.000001
                    && abs(Double(node.anchorPoint.y) - frame.normalizedAnchorYBottomUp) < 0.000001
            } ?? false
            snapshot["qaMothIdleRegistration"] = [
                "candidateFlagPresent": qaMothCandidateFlagPresent,
                "localDevelopmentDefault": true,
                "formalArtAdoption": false,
                "isolatedFlagPresent": qaMothIsolatedFlagPresent,
                "enabled": qaMothRegistrationEnabled,
                "applied": qaMothRegistrationApplied,
                "reason": qaMothRegistrationReason,
                "anchorFrameIndex": qaMothAnchorFrameIndex ?? -1,
                "logicalFrameIndex": qaMothLogicalFrameIndex ?? -1,
                "textureFrameIndex": index ?? -1,
                "anchorPointNormalized": [Double(node.anchorPoint.x), Double(node.anchorPoint.y)],
                "clipBaseAnchorPointNormalized": qaMothAnchorPlan.map {
                    [$0.baseAnchorNormalizedX, $0.baseAnchorNormalizedYBottomUp]
                } ?? [],
                "defaultAnchorPointNormalized": [Double(defaultAnchor.x), Double(defaultAnchor.y)],
                "sourceOffsetPxTopDown": qaMothAnchorPlan.flatMap { plan in
                    qaMothAnchorFrameIndex.flatMap { i in plan.frames.indices.contains(i) ?
                        [plan.frames[i].sourceOffsetX, plan.frames[i].sourceOffsetYTopDown] : nil }
                } ?? [],
                "framePath": qaMothAnchorPlan.flatMap { plan in
                    qaMothAnchorFrameIndex.flatMap { i in plan.frames.indices.contains(i) ? plan.frames[i].path : nil }
                } ?? "",
                "logicalFramePath": logicalPath,
                "actualTextureMatchedPath": actualTexturePath,
                "actualTextureMatchedPaths": actualTexturePaths,
                "textureIdentityAmbiguous": actualTexturePaths.count > 1,
                "texturePathMatchesLogicalFrame": textureMatchesLogicalPath,
                "anchorMatchesLogicalFrame": anchorMatchesLogicalFrame
            ] as [String: Any]
        }
        return snapshot
    }
    var currentMotionState: EnemyMotionState? { activeState }
    func loopBoundaryMode(for state: EnemyMotionState) -> EnemyLoopBoundaryMode {
        if let partRig, let mode = partRig.loopBoundaryMode(for: state.rawValue) { return mode }
        guard let clip = clips[state.rawValue],
              let paths = clip["frames"] as? [String] else {
            return EnemyLoopBoundaryMode(state: state.rawValue, presentationKind: "missing", supported: false,
                loops: false, frameCount: 0, expectedFPS: 0, expectedPeriodSeconds: 0,
                framePaths: [], phaseMetric: "unavailable", timelineBasis: "missing_clip")
        }
        let fps = (clip["fps"] as? NSNumber)?.doubleValue ?? 24
        let validFPS = fps.isFinite && fps > 0
        let loop = clip["loop"] as? Bool ?? false
        let count = paths.count
        return EnemyLoopBoundaryMode(state: state.rawValue, presentationKind: "sprite_frames",
            supported: true, loops: loop, frameCount: count, expectedFPS: fps,
            expectedPeriodSeconds: validFPS ? Double(count) / fps : 0, framePaths: paths,
            phaseMetric: "presentation.frameIndex+framePath", timelineBasis: "runtime_sprite_clip")
    }
    func beginGroundedEntryIfRequested() -> Bool {
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-dragon-mesh-r004"),
              args.contains("--qa-dragon-grounded-entry-r005"),
              let partRig, partRig.hasWalkMeshCandidate,
              partRig.playGroundedEntryCandidate() else { return false }
        registeredPoses?.stop(); partRig.node.isHidden = false; activeState = .walk
        return true
        #else
        return false
        #endif
    }
    func groundedEntryOffset(in scene: SKScene) -> CGPoint? { partRig?.groundedEntryOffset(in: scene) }
    func beginNormalEntryFootpathR068R002() -> Bool {
        partRig?.beginNormalEntryFootpathR068R002(actorRoot: node) ?? false
    }
    func applyNormalEntryFootpathR068R002(elapsed: Double, entryStartRootScene: CGPoint,
                                          currentRootScene: CGPoint, homeRootScene: CGPoint,
                                          scene: SKScene) -> [String: Any]? {
        partRig?.applyNormalEntryFootpathR068R002(elapsed: elapsed,
            entryStartRootScene: entryStartRootScene, currentRootScene: currentRootScene,
            homeRootScene: homeRootScene, scene: scene)
    }
    func restoreNormalEntryFootpathR068R002() {
        partRig?.restoreNormalEntryFootpathR068R002()
    }
    func entryTraceSnapshot(in scene: SKScene) -> [String: Any] {
        ["state": activeState?.rawValue ?? "none", "rig": partRig?.entryTraceSnapshot(in: scene) ?? [:]]
    }
    /// Stops a clip without changing position, scale, or gameplay-owned scene state.
    var intrinsicAspectRatio:CGFloat {let s=node.texture?.size() ?? node.size;return s.width/max(1,s.height)}
    var isPartRig:Bool {partRig != nil}
    func fit(height:CGFloat) {
        fittedHeight=height
        if partRig != nil {node.setScale(height/max(1,node.size.height))}
        else {let t=node.texture?.size() ?? CGSize(width:1,height:1);node.size=CGSize(width:height*t.width/t.height,height:height)}
    }
    func stop() {
        partRig?.stop()
        registeredPoses?.stop()
        partRig?.node.isHidden=false
        if let activeClipKey { node.removeAction(forKey: activeClipKey) }
        clearMothRegistration(resetAnchor: true)
        activeClipKey = nil
        activeState = nil
    }

    private func texture(for relativePath: String) -> SKTexture? {
        if let cached = textures[relativePath] { return cached }
        guard let value = Self.texture(path: relativePath, root: artRoot) else { return nil }
        textures[relativePath] = value
        return value
    }

    private static func texture(path: String, root: URL) -> SKTexture? {
        let url = root.appendingPathComponent(path)
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:512,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{return nil}
        let texture = SKTexture(cgImage:cg)
        texture.filteringMode = .linear
        return texture
    }
}
