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
    /// Bounded development-route evidence for the R214 visual-hit experiment.
    var onVisualHitLifecycleR214: (([String: Any]) -> Void)?

    struct R214EventContext {
        let replayID: String?
        let eventSequence: Int?
        let rootActionID: String?
        let sceneFrame: Int
        let sceneTime: Double
        let sceneGeneration: Int
    }
    private struct R214PendingVisualHit {
        let first: R214EventContext
        let execute: R214EventContext
        var eventSequences: [Int]
        var additionalCount: Int
    }
    private struct R214ActiveDeferredHit {
        let pending: R214PendingVisualHit
        let startedUptime: TimeInterval
        let declaredDuration: Double?
    }
    private struct R214ActiveImmediateHit {
        let context: R214EventContext
        let execute: R214EventContext?
        let startedUptime: TimeInterval
        let declaredDuration: Double?
    }
    private struct R214ExecuteStart {
        let context: R214EventContext
        let uptime: TimeInterval
        let declaredDuration: Double?
        let canDeferVisualHit: Bool
    }
    private var r214ExecuteStart: R214ExecuteStart?
    private var r214PendingVisualHit: R214PendingVisualHit?
    private var r214ActiveDeferredHit: R214ActiveDeferredHit?
    private var r214ActiveImmediateHit: R214ActiveImmediateHit?
    private var r214ImmediateHitExecuteContext: R214EventContext?
    private var r214LatestSceneClock: (frame: Int, time: Double, generation: Int)?
    private var r214PlaybackGeneration: UInt64 = 0
    private var r214AcceptedPlaybackGeneration: UInt64 = 0
    private var r214ExpectedPartRigGeneration: UInt64?
    private let r214InstrumentationEnabled: Bool
    private let r214DeferralEnabled: Bool

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
    // R137 is simulator-only, exact-actor, explicit-flag candidate state.
    private let qaJellyMeshFlagPresent: Bool
    private let qaJellyIsolatedFlagPresent: Bool
    private let qaJellyMeshEnabled: Bool
    private var qaJellyMeshReason = "not_requested"
    private var qaJellyMeshApplied = false
    private var qaJellyMeshRig: JellyfishMeshRigR135QA?
    private var qaJellyWalkOriginalTexture: SKTexture?
    private var qaJellyWalkOriginalSize: CGSize?
    private var qaJellyWalkOriginalAnchor: CGPoint?
    private var qaJellyWalkOriginalWarpGeometry: SKWarpGeometry?
    private var qaJellyWalkOriginalSubdivisionLevels: Int?
    private var qaJellyWalkRestoredSubdivisionLevels: Int?
    private var qaJellyWalkPaths: [String] = []
    // R259 keeps the existing R135 route intact and adds a separately keyed R254 profile comparison.
    private let qaJellyR254Requested: Bool
    private let qaJellyR254Enabled: Bool
    private let qaJellyR254Profile: JellyfishMeshRigR254QA.WalkProfile?
    private var qaJellyR254Applied = false
    private var qaJellyR254Reason = "not_requested"
    private var qaJellyR254Rig: JellyfishMeshRigR254QA?
    private var qaJellyR254OriginalTexture: SKTexture?
    private var qaJellyR254OriginalSize: CGSize?
    private var qaJellyR254OriginalAnchor: CGPoint?
    private var qaJellyR254OriginalWarp: SKWarpGeometry?
    private var qaJellyR254OriginalSubdivision: Int?
    private var qaJellyR254RestoredSubdivision: Int?
    private var qaJellyR254RestorationVerified = false
    private var qaJellyR254WalkPaths: [String] = []

    /// `artRoot` is the directory exposed to SpriteKit as the Art bundle folder,
    /// containing `runtime_index.json`, `Enemies/` and `ActorStills/`.
    init(actorID: String, artRoot: URL, size: CGSize? = nil) throws {
        self.actorID = actorID
#if targetEnvironment(simulator)
        let qaArgs = ProcessInfo.processInfo.arguments
        #if DEBUG && STANDARD_PLAY_R169
        self.r214InstrumentationEnabled = true
        // A baseline override exists only in the bounded DEBUG comparison route.
        self.r214DeferralEnabled = !qaArgs.contains("--r214-hit-deferral=off")
        #else
        self.r214InstrumentationEnabled = false
        self.r214DeferralEnabled = true
        #endif
        self.qaMothCandidateFlagPresent = qaArgs.contains("--qa-moth-idle-registration-r050")
        self.qaMothIsolatedFlagPresent = qaArgs.contains("--qa-isolated")
        self.qaMothRegistrationEnabled = MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: qaArgs, isSimulator: true)
        self.qaMothRegistrationReason = qaMothRegistrationEnabled ? "local_candidate_pending_exact_clip" : "isolated_baseline_override"
        self.qaJellyMeshFlagPresent = qaArgs.contains("--qa-jelly-mesh-r135")
        self.qaJellyIsolatedFlagPresent = qaArgs.contains("--qa-isolated")
        self.qaJellyMeshEnabled = qaArgs.filter { $0 == "--qa-isolated" }.count == 1
            && qaArgs.filter { $0 == "--qa-jelly-mesh-r135" }.count == 1
            && actorID == JellyfishMeshRigR135QA.actorID
        self.qaJellyMeshReason = qaJellyMeshEnabled ? "awaiting_exact_walk_clip_guard" :
            (qaJellyMeshFlagPresent ? "both_flags_and_exact_actor_required" : "not_requested")
        let r254Args = qaArgs.filter { $0 == "--qa-jelly-mesh-r254" }
        let profileArgs = qaArgs.filter { $0.hasPrefix("--qa-jelly-profile=") }
        let profileValue = profileArgs.first?.split(separator: "=", maxSplits: 1).last.map(String.init)
        self.qaJellyR254Requested = !r254Args.isEmpty || !profileArgs.isEmpty
        self.qaJellyR254Profile = profileValue.flatMap(JellyfishMeshRigR254QA.WalkProfile.init(rawValue:))
        self.qaJellyR254Enabled = qaArgs.filter { $0 == "--qa-isolated" }.count == 1
            && r254Args.count == 1
            && qaArgs.filter { $0 == "--qa-jelly-sequence-r259" }.count == 1
            && profileArgs.count == 1 && self.qaJellyR254Profile != nil
            && !qaArgs.contains("--qa-jelly-mesh-r135")
            && !qaArgs.contains("--qa-jelly-sequence-r137")
            && qaArgs.filter { $0 == "--art-audit=ACT_E_R02_03" }.count == 1
            && qaArgs.filter { $0.hasPrefix("--qa-save-key=") }.count == 1
            && UUID(uuidString: String((qaArgs.first { $0.hasPrefix("--qa-save-key=") } ?? "--qa-save-key=")
                .dropFirst("--qa-save-key=".count))) != nil
            && actorID == JellyfishMeshRigR254QA.actorID
        self.qaJellyR254Reason = qaJellyR254Enabled ? "awaiting_exact_walk_clip_guard" :
            (qaJellyR254Requested ? "both_r259_flags_profile_and_exact_actor_required" : "not_requested")
#else
        self.r214InstrumentationEnabled = false
        self.r214DeferralEnabled = true
        self.qaMothCandidateFlagPresent = false
        self.qaMothIsolatedFlagPresent = false
        self.qaMothRegistrationEnabled = MothIdleAnchorRegistrationR050.usesLocalCandidate(arguments: [], isSimulator: false)
        self.qaJellyMeshFlagPresent = false
        self.qaJellyIsolatedFlagPresent = false
        self.qaJellyMeshEnabled = false
        self.qaJellyMeshReason = "simulator_only"
        self.qaJellyR254Requested = false
        self.qaJellyR254Enabled = false
        self.qaJellyR254Profile = nil
        self.qaJellyR254Reason = "simulator_only"
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
                                     normalEntryBackendR068:normalEntryBackend.rawValue,
                                     r214CompletionGenerationGuardEnabled: self.r214DeferralEnabled)
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
            });rig.onClipCompleted={[weak self] name, generation in
                guard let self else { return }
                if self.r214DeferralEnabled && self.r214ExpectedPartRigGeneration != generation { return }
                if let completed = EnemyMotionState(rawValue: name) { self.finishFiniteActionR214(completed) }
                else { self.returnToRest(after:name) }
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

    func noteExecuteStartedR214(_ context: R214EventContext) {
        guard activeState == .execute else { return }
        let duration = declaredDurationR214(for: .execute)
        let loops = (clips[EnemyMotionState.execute.rawValue]?["loop"] as? Bool) ?? false
        let canDeferVisualHit = !loops && (duration.map { $0.isFinite && $0 > 0 } ?? false)
        let start = R214ExecuteStart(context: context, uptime: ProcessInfo.processInfo.systemUptime,
                                     declaredDuration: duration, canDeferVisualHit: canDeferVisualHit)
        r214ExecuteStart = start
        emitVisualHitLifecycleR214("execute_started", context: context, extra: [
            "declaredDurationSeconds": start.declaredDuration.map { $0 as Any } ?? NSNull(),
            "backend": backendNameR214(for: .execute)
        ])
    }

    /// Defers only the sprite hit animation. Callers have already applied HP,
    /// audio, event ordering, and impact/effect presentation.
    @discardableResult
    func deferVisualHitDuringExecuteR214(_ context: R214EventContext) -> Bool {
        guard r214DeferralEnabled, activeState == .execute, let execute = r214ExecuteStart,
              execute.canDeferVisualHit else { return false }
        if var pending = r214PendingVisualHit {
            if let sequence = context.eventSequence, pending.eventSequences.count < 16 {
                pending.eventSequences.append(sequence)
            } else {
                pending.additionalCount += 1
            }
            r214PendingVisualHit = pending
        } else {
            r214PendingVisualHit = R214PendingVisualHit(
                first: context, execute: execute.context,
                eventSequences: context.eventSequence.map { [$0] } ?? [], additionalCount: 0)
        }
        emitVisualHitLifecycleR214("hit_visual_deferred", context: context, extra: [
            "executeEventSequence": r214ExecuteStart?.context.eventSequence.map { $0 as Any } ?? NSNull(),
            "executeRootActionID": r214ExecuteStart?.context.rootActionID ?? "",
            "pendingVisualHitCount": r214PendingVisualHit?.eventSequences.count ?? 1
        ])
        return true
    }

    func clearVisualHitDeferralR214(reason: String, triggeringEventSequence: Int? = nil) {
        if let pending = r214PendingVisualHit {
            emitVisualHitLifecycleR214("hit_visual_cancelled", context: pending.first, extra: [
                "reason": reason, "triggeringEventSequence": triggeringEventSequence.map { $0 as Any } ?? NSNull(),
                "cancellationSceneFrame": r214LatestSceneClock?.frame ?? -1,
                "cancellationSceneTime": r214LatestSceneClock?.time as Any? ?? NSNull(),
                "cancellationSceneGeneration": r214LatestSceneClock?.generation ?? -1,
                "executeEventSequence": pending.execute.eventSequence.map { $0 as Any } ?? NSNull(),
                "executeRootActionID": pending.execute.rootActionID ?? "",
                "coalescedHitEventSequences": pending.eventSequences,
                "additionalHitEventCount": pending.additionalCount
            ])
        }
        if let active = r214ActiveDeferredHit {
            emitVisualHitLifecycleR214("hit_visual_cancelled", context: active.pending.first, extra: [
                "reason": reason, "stage": "after_start_before_completion",
                "triggeringEventSequence": triggeringEventSequence.map { $0 as Any } ?? NSNull(),
                "cancellationSceneFrame": r214LatestSceneClock?.frame ?? -1,
                "cancellationSceneTime": r214LatestSceneClock?.time as Any? ?? NSNull(),
                "cancellationSceneGeneration": r214LatestSceneClock?.generation ?? -1,
                "executeEventSequence": active.pending.execute.eventSequence.map { $0 as Any } ?? NSNull(),
                "executeRootActionID": active.pending.execute.rootActionID ?? "",
                "coalescedHitEventSequences": active.pending.eventSequences,
                "additionalHitEventCount": active.pending.additionalCount,
                "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - active.startedUptime)
            ])
        }
        if let active = r214ActiveImmediateHit {
            emitVisualHitLifecycleR214("hit_visual_cancelled", context: active.context, extra: [
                "presentationMode": "immediate", "reason": reason,
                "triggeringEventSequence": triggeringEventSequence.map { $0 as Any } ?? NSNull(),
                "stage": "after_start_before_completion",
                "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - active.startedUptime)
            ])
        }
        if let execute = r214ExecuteStart, activeState == .execute {
            emitVisualHitLifecycleR214("execute_superseded", context: execute.context, extra: [
                "reason": reason, "triggeringEventSequence": triggeringEventSequence.map { $0 as Any } ?? NSNull(),
                "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - execute.uptime),
                "observedSceneDurationSeconds": r214LatestSceneClock.map { max(0, $0.time - execute.context.sceneTime) as Any } ?? NSNull(),
                "supersedingSceneFrame": r214LatestSceneClock?.frame ?? -1,
                "supersedingSceneGeneration": r214LatestSceneClock?.generation ?? -1,
                "declaredDurationSeconds": execute.declaredDuration.map { $0 as Any } ?? NSNull()
            ])
        }
        r214PendingVisualHit = nil
        r214ActiveDeferredHit = nil
        r214ActiveImmediateHit = nil
        r214ExecuteStart = nil
    }

    func recordImmediateHitSupersedingExecuteR214(_ context: R214EventContext) {
        guard r214InstrumentationEnabled, activeState == .execute, let execute = r214ExecuteStart else { return }
        emitVisualHitLifecycleR214("execute_superseded_by_hit", context: execute.context, extra: [
            "hitEventSequence": context.eventSequence.map { $0 as Any } ?? NSNull(),
            "hitRootActionID": context.rootActionID ?? "",
            "hitSceneFrame": context.sceneFrame, "hitSceneGeneration": context.sceneGeneration,
            "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - execute.uptime),
            "observedSceneDurationSeconds": max(0, context.sceneTime - execute.context.sceneTime),
            "declaredDurationSeconds": execute.declaredDuration.map { $0 as Any } ?? NSNull()
        ])
        r214ImmediateHitExecuteContext = execute.context
        r214ExecuteStart = nil
        r214PendingVisualHit = nil
    }

    func noteImmediateHitTransitionR214(_ context: R214EventContext, accepted: Bool) {
        guard r214InstrumentationEnabled else { return }
        guard accepted else {
            emitVisualHitLifecycleR214("hit_visual_rejected", context: context, extra: ["presentationMode": "immediate"])
            r214ImmediateHitExecuteContext = nil
            return
        }
        let execute = r214ImmediateHitExecuteContext
        r214ImmediateHitExecuteContext = nil
        let duration = declaredDurationR214(for: .hit)
        r214ActiveImmediateHit = R214ActiveImmediateHit(context: context, execute: execute,
            startedUptime: ProcessInfo.processInfo.systemUptime, declaredDuration: duration)
        emitVisualHitLifecycleR214("hit_visual_started", context: context, extra: [
            "presentationMode": "immediate", "accepted": true,
            "executeEventSequence": execute?.eventSequence.map { $0 as Any } ?? NSNull(),
            "declaredDurationSeconds": duration.map { $0 as Any } ?? NSNull(),
            "backend": backendNameR214(for: .hit)
        ])
    }

    private func nextR214PlaybackToken() -> UInt64 { r214PlaybackGeneration &+ 1 }

    @discardableResult
    private func acceptR214Transition(_ state: EnemyMotionState, token: UInt64? = nil,
                                      partRigGeneration: UInt64? = nil) -> UInt64? {
        // Presentation bookkeeping runs independently from diagnostic collection.
        if state == .resolve {
            clearVisualHitDeferralR214(reason: "resolve")
        } else if r214ActiveDeferredHit != nil || r214PendingVisualHit != nil {
            clearVisualHitDeferralR214(reason: "superseded_by_\(state.rawValue)")
        } else if state == .hit, r214ActiveImmediateHit != nil {
            clearVisualHitDeferralR214(reason: "superseded_by_hit")
        } else if r214ExecuteStart != nil {
            clearVisualHitDeferralR214(reason: "execute_superseded_by_\(state.rawValue)")
        }
        if state != .hit { r214ImmediateHitExecuteContext = nil }
        let acceptedToken = token ?? nextR214PlaybackToken()
        if r214DeferralEnabled {
            r214PlaybackGeneration = acceptedToken
            r214AcceptedPlaybackGeneration = acceptedToken
        }
        r214ExpectedPartRigGeneration = partRigGeneration
        return acceptedToken
    }

    func resetVisualHitDeferralR214() {
        clearVisualHitDeferralR214(reason: "controller_reset")
        r214LatestSceneClock = nil
    }

    func updateR214SceneClock(frame: Int, time: Double, generation: Int) {
        r214LatestSceneClock = (frame, time, generation)
    }

    private func backendNameR214(for state: EnemyMotionState) -> String {
        if partRig != nil {
            return (clips[state.rawValue]?["mode"] as? String) == "registered_keyposes_v1"
                ? "registered_poses" : "part_rig"
        }
        return "sprite_clip"
    }

    private func declaredDurationR214(for state: EnemyMotionState) -> Double? {
        let clip = clips[state.rawValue]
        let usesRegisteredPoses = partRig != nil && (clip?["mode"] as? String) == "registered_keyposes_v1"
        if partRig != nil && !usesRegisteredPoses {
            if let rigDuration = partRig?.duration(of: state.rawValue), rigDuration.isFinite, rigDuration > 0 {
                return rigDuration
            }
            return nil
        }
        guard let clip else { return nil }
        for key in ["duration_seconds", "duration"] {
            if let number = clip[key] as? NSNumber {
                let value = number.doubleValue
                if value.isFinite && value > 0 { return value }
            }
        }
        if let paths = clip["frames"] as? [String], !paths.isEmpty,
           let fps = (clip["fps"] as? NSNumber)?.doubleValue, fps.isFinite, fps > 0 {
            return Double(paths.count) / fps
        }
        return nil
    }

    private func emitVisualHitLifecycleR214(_ kind: String, context: R214EventContext,
                                            extra: [String: Any] = [:]) {
        guard r214InstrumentationEnabled else { return }
        var row: [String: Any] = [
            "kind": kind, "actorID": actorID,
            "eventSequence": context.eventSequence.map { $0 as Any } ?? NSNull(),
            "rootActionID": context.rootActionID ?? "",
            "sceneFrame": context.sceneFrame, "sceneTime": context.sceneTime,
            "sceneGeneration": context.sceneGeneration
        ]
        if let replayID = context.replayID { row["replayID"] = replayID }
        row.merge(extra) { _, new in new }
        onVisualHitLifecycleR214?(row)
    }

    private func finishFiniteActionR214(_ state: EnemyMotionState, preserveImmediateCompletionOrder: Bool = false) {
        if state == .hit, let active = r214ActiveDeferredHit {
            emitVisualHitLifecycleR214("hit_visual_completed", context: active.pending.first, extra: [
                "executeEventSequence": active.pending.execute.eventSequence.map { $0 as Any } ?? NSNull(),
                "executeRootActionID": active.pending.execute.rootActionID ?? "",
                "deferredHitEventSequences": active.pending.eventSequences,
                "additionalHitEventCount": active.pending.additionalCount,
                "declaredDurationSeconds": active.declaredDuration.map { $0 as Any } ?? NSNull(),
                "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - active.startedUptime),
                "completionSceneFrame": r214LatestSceneClock?.frame ?? -1,
                "completionSceneGeneration": r214LatestSceneClock?.generation ?? -1
            ])
            r214ActiveDeferredHit = nil
        }
        if state == .hit, let active = r214ActiveImmediateHit {
            emitVisualHitLifecycleR214("hit_visual_completed", context: active.context, extra: [
                "presentationMode": "immediate",
                "executeEventSequence": active.execute?.eventSequence.map { $0 as Any } ?? NSNull(),
                "declaredDurationSeconds": active.declaredDuration.map { $0 as Any } ?? NSNull(),
                "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - active.startedUptime),
                "completionSceneFrame": r214LatestSceneClock?.frame ?? -1,
                "completionSceneGeneration": r214LatestSceneClock?.generation ?? -1
            ])
            r214ActiveImmediateHit = nil
        }
        let execute = state == .execute ? r214ExecuteStart : nil
        let pendingHit = state == .execute ? r214PendingVisualHit : nil
        if let execute {
            emitVisualHitLifecycleR214("execute_completed", context: execute.context, extra: [
                "declaredDurationSeconds": execute.declaredDuration.map { $0 as Any } ?? NSNull(),
                "observedWallDurationSeconds": max(0, ProcessInfo.processInfo.systemUptime - execute.uptime),
                "observedSceneDurationSeconds": r214LatestSceneClock.map { max(0, $0.time - execute.context.sceneTime) as Any } ?? NSNull(),
                "completionSceneFrame": r214LatestSceneClock?.frame ?? -1,
                "completionSceneTime": r214LatestSceneClock?.time as Any? ?? NSNull(),
                "completionSceneGeneration": r214LatestSceneClock?.generation ?? -1,
                "completionBackend": backendNameR214(for: state)
            ])
        }
        if state == .execute { r214ExecuteStart = nil; r214PendingVisualHit = nil }
        if preserveImmediateCompletionOrder {
            qaRenderBoundActionCompleted?(state)
            activeState = state == .resolve ? .resolve : nil
            activeClipKey = nil
            returnToRest(after: state.rawValue)
            return
        }
        qaRenderBoundActionCompleted?(state)
        if let pendingHit, state == .execute {
            let accepted = play(.hit, restart: true)
            emitVisualHitLifecycleR214(accepted ? "hit_visual_started_after_execute" : "hit_visual_rejected_after_execute",
                context: pendingHit.first, extra: [
                    "executeEventSequence": execute?.context.eventSequence.map { $0 as Any } ?? NSNull(),
                    "executeRootActionID": execute?.context.rootActionID ?? "",
                    "deferredHitEventSequences": pendingHit.eventSequences,
                    "additionalHitEventCount": pendingHit.additionalCount,
                    "accepted": accepted,
                    "observedSceneDurationSecondsBeforeHit": execute.flatMap { start in
                        r214LatestSceneClock.map { max(0, $0.time - start.context.sceneTime) as Any }
                    } ?? NSNull(),
                    "hitStartSceneFrame": r214LatestSceneClock?.frame ?? -1,
                    "hitStartSceneGeneration": r214LatestSceneClock?.generation ?? -1
                ])
            if accepted {
                r214ActiveDeferredHit = R214ActiveDeferredHit(pending: pendingHit,
                    startedUptime: ProcessInfo.processInfo.systemUptime,
                    declaredDuration: declaredDurationR214(for: .hit))
                return
            }
        }
        returnToRest(after: state.rawValue)
    }

    /// Attempts to play the requested authored clip. Returns `false` and calls
    /// `onUnsupportedState` when the exact clip is absent; caller owns fallback policy.
    @discardableResult
    func play(_ state: EnemyMotionState, restart: Bool = false) -> Bool {
        // R214 treats a repeated non-restarting request as a no-op. Do not
        // cancel a pending hit or invalidate its completion token in that case.
        if r214InstrumentationEnabled, activeState == state, !restart { return true }
        if qaJellyMeshApplied && (state != .walk || restart) {
            clearJellyMeshWalk(reason: "cleared_on_state_exit", restoreCatalogFrame: true)
        }
        if qaJellyR254Applied && (state != .walk || restart) {
            clearJellyR254Walk(reason: "cleared_on_state_exit")
        }
        if (qaMothCandidateFlagPresent || qaMothIsolatedFlagPresent), qaMothRegistrationEnabled,
           !(actorID == MothIdleAnchorRegistrationR050.actorID && state == .idle),
           !qaMothRegistrationApplied {
            qaMothRegistrationReason = "not_target_actor_idle_pair"
        }
        if let rig=partRig {
            if activeState == state && !restart {return true}
            if let clip=clips[state.rawValue],clip["mode"] as? String == "registered_keyposes_v1",let registeredPoses {
                let callbackToken = nextR214PlaybackToken()
                guard registeredPoses.play(clip,completion:{[weak self] in
                    guard let self, self.activeState == state else { return }
                    if self.r214DeferralEnabled && self.r214AcceptedPlaybackGeneration != callbackToken { return }
                    self.finishFiniteActionR214(state)
                }) else {
                    onUnsupportedState?(.framesMissing(actorID:actorID,state:state));return false
                }
                rig.stop();rig.node.isHidden=true;activeState=state
                _ = acceptR214Transition(state, token: callbackToken)
                return true
            }
            if state == .walk,
               (rig.hasWalkMeshCandidate || clips["walk"]?["mode"] as? String == "part_rig_leg_overlay_candidate_v1"),
               rig.availableStates.contains("walk") {
                guard rig.play("walk",restart:restart) else{return false}
                registeredPoses?.stop();rig.node.isHidden=false;activeState=state
                _ = acceptR214Transition(state, partRigGeneration: rig.r214PlaybackGeneration)
                return true
            }
            let clip = state == .walk && rig.availableStates.contains("flight") ? "flight" : state.rawValue
            guard rig.play(clip,restart:restart) else{return false}
            registeredPoses?.stop();rig.node.isHidden=false;activeState=state
            _ = acceptR214Transition(state, partRigGeneration: rig.r214PlaybackGeneration)
            return true
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
        let callbackToken = nextR214PlaybackToken()
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
        if qaJellyR254Enabled, actorID == JellyfishMeshRigR254QA.actorID, state == .walk,
           let profile = qaJellyR254Profile,
           let reason = tryJellyR254Walk(clip: clip, paths: paths, frames: frames, profile: profile) {
            if reason == "applied_r254_profile_\(profile.rawValue)" { return true }
            qaJellyR254Reason = reason
            node.warpGeometry = nil
            node.texture = frames[0]
        }
        if qaJellyMeshEnabled, actorID == JellyfishMeshRigR135QA.actorID, state == .walk,
           let reason = tryJellyMeshWalk(clip: clip, paths: paths, frames: frames, actionKey: key) {
            if reason == "applied_r135_amp10" {
                _ = acceptR214Transition(state, token: callbackToken)
                return true
            }
            qaJellyMeshReason = reason
            // Failed validation is a recorded fallback to the exact ordinary walk clip.
            node.warpGeometry = nil
            node.texture = frames[0]
        }
        if qaMothRegistrationEnabled, actorID == MothIdleAnchorRegistrationR050.actorID,
           state == .idle, let plan = mothRegistrationPlan(clip: clip, paths: paths, textures: frames) {
            if runMothRegisteredIdle(plan: plan, frames: frames, fps: fps, key: key) {
                _ = acceptR214Transition(state, token: callbackToken)
                return true
            }
        }
        let animate = SKAction.animate(with: frames, timePerFrame: 1.0 / fps,
                                      resize: false, restore: false)
        if loop {
            _ = acceptR214Transition(state, token: callbackToken)
            node.run(.repeatForever(animate), withKey: key)
        } else {
            node.run(.sequence([animate, .run { [weak self] in
                guard let self, self.activeClipKey == key, self.activeState == state else { return }
                guard self.r214DeferralEnabled else {
                    // Preserve the pre-R214 callback/state-clear/rest order in
                    // every route where deferral is disabled, including the
                    // instrumented same-build baseline.
                    self.finishFiniteActionR214(state, preserveImmediateCompletionOrder: true)
                    return
                }
                guard self.r214AcceptedPlaybackGeneration == callbackToken else { return }
                // A terminal pose remains the active state after its frames end.
                // Final HP reconciliation must not restart it from frame zero.
                self.activeState = state == .resolve ? .resolve : nil
                self.activeClipKey = nil
                self.finishFiniteActionR214(state)
            }]), withKey: key)
            _ = acceptR214Transition(state, token: callbackToken)
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

    private func tryJellyR254Walk(clip: [String: Any], paths: [String], frames: [SKTexture],
                                  profile: JellyfishMeshRigR254QA.WalkProfile) -> String? {
        guard qaJellyR254Enabled, actorID == JellyfishMeshRigR254QA.actorID else { return nil }
        qaJellyR254WalkPaths = paths
        let expected = [
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/walk_a.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/walk_b.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/mid_walkb_idle_a_r002.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/idle_a.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/idle_b.png"
        ]
        guard paths == expected, frames.count == 5,
              clip["frame_count"] as? Int == 5,
              (clip["fps"] as? NSNumber)?.doubleValue == 10,
              (clip["duration_seconds"] as? NSNumber)?.doubleValue == 0.5,
              clip["loop"] as? Bool == true,
              let canvas = clip["canvas_px"] as? [Double], canvas == [384, 256],
              let anchor = clip["anchor"] as? [Double], anchor == [192, 97.5],
              clip["partRig"] == nil, node.warpGeometry == nil else {
            return "fallback_exact_catalog_walk_contract_or_geometry_mismatch"
        }
        guard ProcessInfo.processInfo.arguments.filter({ $0 == "--qa-isolated" }).count == 1,
              ProcessInfo.processInfo.arguments.filter({ $0 == "--qa-jelly-mesh-r254" }).count == 1,
              ProcessInfo.processInfo.arguments.filter({ $0 == "--qa-jelly-sequence-r259" }).count == 1,
              ProcessInfo.processInfo.arguments.filter({ $0 == "--qa-jelly-profile=\(profile.rawValue)" }).count == 1 else {
            return "fallback_exact_r259_flags_or_profile_mismatch"
        }
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("CandidateMotion/R135", isDirectory: true) else {
            return "fallback_candidate_bundle_directory_missing"
        }
        guard let matte = try? Data(contentsOf: root.appendingPathComponent("candidate_matte.png")),
              let mesh = try? Data(contentsOf: root.appendingPathComponent("mesh_weights_editable.json")),
              let clips = try? Data(contentsOf: root.appendingPathComponent("clips_editable.json")) else {
            return "fallback_candidate_resource_missing_or_unreadable"
        }
        do {
            let rig = try JellyfishMeshRigR254QA(sourceTextureData: matte, meshData: mesh, clipsData: clips)
            guard rig.sourceTexture != nil else { return "fallback_candidate_texture_decode_failed" }
            qaJellyR254OriginalTexture = frames.first
            qaJellyR254OriginalSize = node.size
            qaJellyR254OriginalAnchor = node.anchorPoint
            qaJellyR254OriginalWarp = node.warpGeometry
            qaJellyR254OriginalSubdivision = node.subdivisionLevels
            qaJellyR254RestoredSubdivision = nil
            qaJellyR254RestorationVerified = false
            qaJellyR254Rig = rig
            try rig.installWalk(on: node, profile: profile)
            activeState = .walk
            activeClipKey = JellyfishMeshRigR254QA.walkActionKey
            qaJellyR254Applied = true
            qaJellyR254Reason = "applied_r254_profile_\(profile.rawValue)"
            return qaJellyR254Reason
        } catch {
            qaJellyR254Rig = nil
            return "fallback_candidate_pin_or_mesh_validation_failed_\(String(reflecting: error))"
        }
    }

    private func clearJellyR254Walk(reason: String) {
        guard qaJellyR254Applied else { return }
        qaJellyR254Rig?.clear(on: node)
        node.warpGeometry = qaJellyR254OriginalWarp
        if let level = qaJellyR254OriginalSubdivision {
            node.subdivisionLevels = level
            qaJellyR254RestoredSubdivision = level
        }
        if let texture = qaJellyR254OriginalTexture { node.texture = texture }
        if let size = qaJellyR254OriginalSize { node.size = size }
        if let anchor = qaJellyR254OriginalAnchor { node.anchorPoint = anchor }
        qaJellyR254RestorationVerified =
            (qaJellyR254OriginalTexture.map { node.texture === $0 } ?? false) &&
            (qaJellyR254OriginalSize.map { node.size == $0 } ?? false) &&
            (qaJellyR254OriginalAnchor.map { node.anchorPoint == $0 } ?? false) &&
            (qaJellyR254OriginalSubdivision.map { node.subdivisionLevels == $0 } ?? false) &&
            ((qaJellyR254OriginalWarp == nil && node.warpGeometry == nil) ||
             (qaJellyR254OriginalWarp != nil && node.warpGeometry === qaJellyR254OriginalWarp))
        qaJellyR254Applied = false
        qaJellyR254Reason = reason
        qaJellyR254Rig = nil
        qaJellyR254OriginalTexture = nil
        qaJellyR254OriginalSize = nil
        qaJellyR254OriginalAnchor = nil
        qaJellyR254OriginalWarp = nil
        qaJellyR254OriginalSubdivision = nil
        if activeClipKey == JellyfishMeshRigR254QA.walkActionKey { activeClipKey = nil }
    }

    private func tryJellyMeshWalk(clip: [String: Any], paths: [String], frames: [SKTexture],
                                  actionKey: String) -> String? {
        guard qaJellyMeshEnabled, actorID == JellyfishMeshRigR135QA.actorID else { return nil }
        qaJellyWalkPaths = paths
        let expected = [
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/walk_a.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/walk_b.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/mid_walkb_idle_a_r002.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/idle_a.png",
            "GeneratedCandidates/ACT_E_R02_03/walk_midpoint_candidate_r002/idle_b.png"
        ]
        guard paths == expected, frames.count == 5,
              clip["frame_count"] as? Int == 5,
              (clip["fps"] as? NSNumber)?.doubleValue == 10,
              (clip["duration_seconds"] as? NSNumber)?.doubleValue == 0.5,
              clip["loop"] as? Bool == true,
              let canvas = clip["canvas_px"] as? [Double], canvas == [384, 256],
              let anchor = clip["anchor"] as? [Double], anchor == [192, 97.5],
              clip["partRig"] == nil, node.warpGeometry == nil else {
            return "fallback_exact_catalog_walk_contract_or_geometry_mismatch"
        }
        guard ProcessInfo.processInfo.arguments.filter({ $0 == "--qa-isolated" }).count == 1,
              ProcessInfo.processInfo.arguments.filter({ $0 == "--qa-jelly-mesh-r135" }).count == 1 else {
            return "fallback_exact_flags_mismatch"
        }
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("CandidateMotion/R135", isDirectory: true) else {
            return "fallback_candidate_bundle_directory_missing"
        }
        let matteURL = root.appendingPathComponent("candidate_matte.png")
        let meshURL = root.appendingPathComponent("mesh_weights_editable.json")
        let clipsURL = root.appendingPathComponent("clips_editable.json")
        guard let matteData = try? Data(contentsOf: matteURL),
              let meshData = try? Data(contentsOf: meshURL),
              let clipsData = try? Data(contentsOf: clipsURL) else {
            return "fallback_candidate_resource_missing_or_unreadable"
        }
        do {
            let rig = try JellyfishMeshRigR135QA(sourceTextureData: matteData,
                                                 meshData: meshData, clipsData: clipsData)
            guard rig.sourceTexture != nil else { return "fallback_candidate_texture_decode_failed" }
            qaJellyWalkOriginalTexture = frames.first
            qaJellyWalkOriginalSize = node.size
            qaJellyWalkOriginalAnchor = node.anchorPoint
            qaJellyWalkOriginalWarpGeometry = node.warpGeometry
            qaJellyWalkOriginalSubdivisionLevels = node.subdivisionLevels
            qaJellyWalkRestoredSubdivisionLevels = nil
            qaJellyMeshRig = rig
            try rig.installWalk(on: node)
            activeState = .walk
            activeClipKey = JellyfishMeshRigR135QA.walkActionKey
            qaJellyMeshApplied = true
            qaJellyMeshReason = "applied_r135_amp10"
            // `actionKey` is the catalog key removed immediately above. It is deliberately
            // not reused as candidate timeline identity.
            _ = actionKey
            return "applied_r135_amp10"
        } catch {
            qaJellyMeshRig = nil
            return "fallback_candidate_pin_or_mesh_validation_failed_\(String(reflecting: error))"
        }
    }

    private func clearJellyMeshWalk(reason: String, restoreCatalogFrame: Bool) {
        guard qaJellyMeshApplied else { return }
        qaJellyMeshRig?.clear(on: node)
        node.warpGeometry = qaJellyWalkOriginalWarpGeometry
        if let subdivisionLevels = qaJellyWalkOriginalSubdivisionLevels {
            node.subdivisionLevels = subdivisionLevels
            qaJellyWalkRestoredSubdivisionLevels = subdivisionLevels
        }
        if restoreCatalogFrame, let texture = qaJellyWalkOriginalTexture { node.texture = texture }
        if let size = qaJellyWalkOriginalSize { node.size = size }
        if let anchor = qaJellyWalkOriginalAnchor { node.anchorPoint = anchor }
        qaJellyMeshApplied = false
        qaJellyMeshReason = reason
        qaJellyWalkOriginalTexture = nil
        qaJellyWalkOriginalSize = nil
        qaJellyWalkOriginalAnchor = nil
        qaJellyWalkOriginalWarpGeometry = nil
        qaJellyWalkOriginalSubdivisionLevels = nil
        if activeClipKey == JellyfishMeshRigR135QA.walkActionKey { activeClipKey = nil }
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
        let selectedStateClip = activeState.flatMap { clips[$0.rawValue] }
        let usesRegisteredPoses = partRig != nil && (selectedStateClip?["mode"] as? String) == "registered_keyposes_v1"
        let presentationBackend = partRig == nil ? "sprite" : (usesRegisteredPoses ? "registered_poses" : "part_rig")
        var snapshot:[String:Any] = ["state":activeState?.rawValue ?? "none","frameIndex":index ?? -1,
                "framePath":index.map{paths[$0]} ?? "","isPartRig":partRig != nil,
                "presentationBackend":presentationBackend,
                "resolveDuration":resolveDuration,"alpha":node.alpha,
                "spriteActionRunning": activeClipKey.map { node.action(forKey: $0) != nil } ?? false,
                "activeClipKey": activeClipKey ?? ""]
        if let partRig {
            var rigSnapshot = partRig.presentationSnapshot
            rigSnapshot["rigAttachedToActorRoot"] = partRig.node.parent === node
            snapshot["partRig"] = rigSnapshot
        }
        if let registeredPoses {
            var poseSnapshot = registeredPoses.presentationSnapshot
            poseSnapshot["rendererAttachedToActorRoot"] = registeredPoses.node.parent === node
            snapshot["registeredPoses"] = poseSnapshot
        }
        if qaJellyMeshFlagPresent || qaJellyIsolatedFlagPresent || qaJellyMeshApplied {
            var jelly = qaJellyMeshRig?.snapshot(on: node) ?? [:]
            jelly["candidateFlagPresent"] = qaJellyMeshFlagPresent
            jelly["isolatedFlagPresent"] = qaJellyIsolatedFlagPresent
            jelly["enabled"] = qaJellyMeshEnabled
            jelly["applied"] = qaJellyMeshApplied
            jelly["reason"] = qaJellyMeshReason
            jelly["actorID"] = actorID
            jelly["state"] = activeState?.rawValue ?? "none"
            jelly["catalogWalkSourceFrameCount"] = qaJellyWalkPaths.count
            jelly["catalogWalkPaths"] = qaJellyWalkPaths
            jelly["catalogWalkGeometryRestored"] = !qaJellyMeshApplied && node.warpGeometry === qaJellyWalkOriginalWarpGeometry
            jelly["candidateActionRunning"] = node.action(forKey: JellyfishMeshRigR135QA.walkActionKey) != nil
            jelly["nodeSize"] = [Double(node.size.width), Double(node.size.height)]
            jelly["nodeAnchor"] = [Double(node.anchorPoint.x), Double(node.anchorPoint.y)]
            jelly["subdivisionLevelsRestored"] = !qaJellyMeshApplied &&
                (qaJellyWalkRestoredSubdivisionLevels == nil || node.subdivisionLevels == qaJellyWalkRestoredSubdivisionLevels)
            snapshot["qaJellyMeshR135"] = jelly
        }
        if qaJellyR254Requested || qaJellyR254Applied {
            var jelly = qaJellyR254Rig?.snapshot(on: node) ?? [:]
            jelly["requested"] = qaJellyR254Requested
            jelly["enabled"] = qaJellyR254Enabled
            jelly["applied"] = qaJellyR254Applied
            jelly["reason"] = qaJellyR254Reason
            jelly["actorID"] = actorID
            jelly["state"] = activeState?.rawValue ?? "none"
            jelly["walkProfileRequested"] = qaJellyR254Profile?.rawValue ?? "none"
            jelly["catalogWalkSourceFrameCount"] = qaJellyR254WalkPaths.count
            jelly["catalogWalkPaths"] = qaJellyR254WalkPaths
            jelly["catalogWalkGeometryRestored"] = !qaJellyR254Applied && (node.warpGeometry === qaJellyR254OriginalWarp || (qaJellyR254OriginalWarp == nil && node.warpGeometry == nil))
            jelly["candidateActionRunning"] = node.action(forKey: JellyfishMeshRigR254QA.walkActionKey) != nil
            jelly["nodeSize"] = [Double(node.size.width), Double(node.size.height)]
            jelly["nodeAnchor"] = [Double(node.anchorPoint.x), Double(node.anchorPoint.y)]
            jelly["subdivisionLevelsRestored"] = !qaJellyR254Applied &&
                (qaJellyR254RestoredSubdivision == nil || node.subdivisionLevels == qaJellyR254RestoredSubdivision)
            jelly["allOriginalNodeStateRestored"] = !qaJellyR254Applied && qaJellyR254RestorationVerified
            snapshot["qaJellyMeshR254"] = jelly
        }
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
        if qaJellyR254Applied, qaJellyR254Enabled, actorID == JellyfishMeshRigR254QA.actorID, state == .walk {
            return EnemyLoopBoundaryMode(state: "walk", presentationKind: "jellyfish_weighted_mesh_r254_profile_candidate",
                supported: true, loops: true, frameCount: JellyfishMeshRigR254QA.walkFrameCount - 1,
                expectedFPS: 24, expectedPeriodSeconds: Double(JellyfishMeshRigR254QA.walkDuration),
                framePaths: [], phaseMetric: "qaJellyMeshR254.frameIndex+phase+geometryFingerprint+profile",
                timelineBasis: "single_source_texture_weighted_mesh_action_clock")
        }
        if qaJellyMeshApplied, qaJellyMeshEnabled,
           actorID == JellyfishMeshRigR135QA.actorID, state == .walk {
            return EnemyLoopBoundaryMode(state: "walk",
                presentationKind: "jellyfish_weighted_mesh_candidate",
                supported: true, loops: true, frameCount: JellyfishMeshRigR135QA.walkFrameCount - 1,
                expectedFPS: 24, expectedPeriodSeconds: Double(JellyfishMeshRigR135QA.walkDuration),
                framePaths: [], phaseMetric: "qaJellyMeshR135.frameIndex+phase+geometryFingerprint",
                timelineBasis: "single_source_texture_weighted_mesh_action_clock")
        }
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
        resetVisualHitDeferralR214()
        if r214DeferralEnabled { r214PlaybackGeneration &+= 1; r214AcceptedPlaybackGeneration = r214PlaybackGeneration }
        if qaJellyR254Applied { clearJellyR254Walk(reason: "cleared_by_stop") }
        if qaJellyMeshApplied { clearJellyMeshWalk(reason: "cleared_by_stop", restoreCatalogFrame: true) }
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
