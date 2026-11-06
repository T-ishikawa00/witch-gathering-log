import Foundation
import SpriteKit

/// Read-only sample of the ordinary R050 moth renderer. This request only
/// enables observation; it is deliberately not consulted by EnemyMotion's
/// candidate-registration decision.
@MainActor
final class MothPassiveRenderObserverR058 {
    static let flagPrefix = "--qa-effect-routes-r058="
    static let schema = "current-effect-route-moth-passive-r058-v1"
    static let samplePeriod: TimeInterval = 0.125
    static let rowLimit = 480

    let challengeID: String
    let saveKey: String
    let actorID = MothIdleAnchorRegistrationR050.actorID
    private(set) var rows: [[String: Any]] = []
    private(set) var status = "ARMED"
    private(set) var battleStart: [String: Any] = [:]
    private(set) var terminal: [String: Any] = [:]
    private var lastSampleTime: TimeInterval?
    private var lastState: String?
    private var sceneGeneration: Int?
    private var appliedSeen = false
    private var idleAppliedSeen = false

    private init(challengeID: String, saveKey: String) {
        self.challengeID = challengeID
        self.saveKey = saveKey
    }

    static func make(arguments: [String]) -> MothPassiveRenderObserverR058? {
        guard arguments.contains("--qa-isolated") else { return nil }
        let flags = arguments.filter { $0.hasPrefix(flagPrefix) }
        guard flags.count == 1,
              String(flags[0].dropFirst(flagPrefix.count)) == "CH_R02_03" else { return nil }
        // This observer is intentionally isolated from direct dispatch, fixture,
        // art-audit, and registration-control modes.
        guard !arguments.contains(where: {
            $0.hasPrefix("--qa-challenge=") || $0.hasPrefix("--qa-fixture=") ||
            $0 == "--qa-moth-idle-registration-r050" || $0 == "--qa-moth-idle-baseline-r050" ||
            $0.hasPrefix("--art-audit=")
        }) else { return nil }
        let keys = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard keys.count == 1 else { return nil }
        let key = String(keys[0].dropFirst("--qa-save-key=".count))
        guard UUID(uuidString: key) != nil else { return nil }
        return MothPassiveRenderObserverR058(challengeID: "CH_R02_03", saveKey: key.lowercased())
    }

    func beginBattle(sceneTime: TimeInterval, sceneClock: TimeInterval, sceneFrame: Int,
                     sceneGeneration: Int, actorPresent: Bool) {
        rows.removeAll(keepingCapacity: true)
        lastSampleTime = nil
        lastState = nil
        appliedSeen = false
        idleAppliedSeen = false
        self.sceneGeneration = sceneGeneration
        status = actorPresent ? "OBSERVING" : "TARGET_ACTOR_MISSING_AT_BATTLE_START"
        battleStart = ["sceneTime": sceneTime, "sceneClock": sceneClock,
                       "sceneFrame": sceneFrame, "sceneGeneration": sceneGeneration,
                       "actorPresent": actorPresent]
        terminal = [:]
    }

    func sample(sceneTime: TimeInterval, sceneClock: TimeInterval, sceneFrame: Int,
                sceneGeneration: Int, motion: EnemyMotionController?, node: SKSpriteNode?) {
        guard status == "OBSERVING" else { return }
        guard rows.count < Self.rowLimit else { status = "ROW_LIMIT_REACHED"; return }
        guard let motion, let node else {
            appendMissing(sceneTime: sceneTime, sceneClock: sceneClock, sceneFrame: sceneFrame,
                          sceneGeneration: sceneGeneration)
            return
        }
        let presentation = motion.presentationSnapshot
        let state = presentation["state"] as? String ?? "none"
        let registration = presentation["qaMothIdleRegistration"] as? [String: Any] ?? [:]
        let applied = registration["applied"] as? Bool ?? false
        let stateChanged = lastState != state
        let sampleDue = lastSampleTime.map { sceneTime - $0 >= Self.samplePeriod - 0.000001 } ?? true
        // Keep cadence bounded during idle while recording the first post-idle
        // frame immediately, so cleanup is not inferred from a later snapshot.
        guard sampleDue || stateChanged else { return }
        var row: [String: Any] = [
            "saveKey": saveKey, "challengeID": challengeID, "actorID": MothIdleAnchorRegistrationR050.actorID,
            "sceneTime": sceneTime, "sceneClock": sceneClock, "sceneFrame": sceneFrame,
            "sceneGeneration": sceneGeneration, "motionState": state,
            "renderCallback": "SKScene.didFinishUpdate_postActions_preRender",
            "renderNodeName": node.name ?? "", "nodeAttachedToScene": node.scene != nil,
            "nodeHidden": node.isHidden, "nodeAlpha": Double(node.alpha),
            "nodePosition": [Double(node.position.x), Double(node.position.y)],
            "nodeSize": [Double(node.size.width), Double(node.size.height)],
            "nodeAnchorPoint": [Double(node.anchorPoint.x), Double(node.anchorPoint.y)],
            "nodeTextureSize": node.texture.map { [Double($0.size().width), Double($0.size().height)] } ?? [0.0, 0.0],
            "registrationApplied": applied,
            "candidateRegistrationEnabled": registration["enabled"] ?? false,
            "logicalFrameIndex": registration["logicalFrameIndex"] ?? -1,
            "anchorFrameIndex": registration["anchorFrameIndex"] ?? -1,
            "textureFrameIndex": registration["textureFrameIndex"] ?? -1,
            "framePath": registration["framePath"] ?? "",
            "logicalFramePath": registration["logicalFramePath"] ?? "",
            "actualTextureMatchedPath": registration["actualTextureMatchedPath"] ?? "",
            "texturePathMatchesLogicalFrame": registration["texturePathMatchesLogicalFrame"] ?? false,
            "anchorMatchesLogicalFrame": registration["anchorMatchesLogicalFrame"] ?? false,
            "anchorPointNormalized": registration["anchorPointNormalized"] ?? [],
            "registrationReason": registration["reason"] ?? ""
        ]
        // Record the untouched renderer diagnostics for offline consistency checks.
        row["enemyPresentation"] = presentation
        rows.append(row)
        lastSampleTime = sceneTime
        lastState = state
        if applied { appliedSeen = true }
        if state == "idle" && applied { idleAppliedSeen = true }
        if MothPassiveRenderStateR058.isObservedIdleExitCleanup(
            idleAppliedFrameSeen: idleAppliedSeen,
            state: state,
            applied: applied,
            reason: registration["reason"] as? String ?? ""
        ) {
            terminal = ["kind": "idle_exit_cleanup", "sceneTime": sceneTime,
                        "sceneClock": sceneClock, "sceneFrame": sceneFrame,
                        "registrationApplied": false,
                        "logicalFrameIndex": registration["logicalFrameIndex"] ?? -1,
                        "anchorFrameIndex": registration["anchorFrameIndex"] ?? -1,
                        "nodeAnchorPoint": [Double(node.anchorPoint.x), Double(node.anchorPoint.y)],
                        "defaultAnchorPoint": registration["defaultAnchorPointNormalized"] ?? []]
            status = "OBSERVED_IDLE_EXIT_CLEANUP"
        }
    }

    private func appendMissing(sceneTime: TimeInterval, sceneClock: TimeInterval, sceneFrame: Int,
                               sceneGeneration: Int) {
        let due = lastSampleTime.map { sceneTime - $0 >= Self.samplePeriod - 0.000001 } ?? true
        guard due || lastState != "missing" else { return }
        rows.append(["saveKey": saveKey, "challengeID": challengeID,
                     "actorID": MothIdleAnchorRegistrationR050.actorID,
                     "sceneTime": sceneTime, "sceneClock": sceneClock, "sceneFrame": sceneFrame,
                     "sceneGeneration": sceneGeneration, "motionState": "missing",
                     "registrationApplied": false])
        lastSampleTime = sceneTime
        lastState = "missing"
    }

    func receipt() -> [String: Any] {
        ["schema": Self.schema, "status": status, "challengeID": challengeID,
         "saveKey": saveKey, "actorID": MothIdleAnchorRegistrationR050.actorID,
         "observerOnly": true, "registrationEnableFlagUsed": false,
         "sampleStage": "SKScene.didFinishUpdate_postActions_preRender",
         "samplePeriodSeconds": Self.samplePeriod, "rowLimit": Self.rowLimit,
         "battleStart": battleStart, "terminal": terminal, "rows": rows,
         "sceneGenerationAtStart": sceneGeneration ?? -1,
         "appliedFrameObserved": appliedSeen,
         "idleAppliedFrameObserved": idleAppliedSeen,
         "idleExitCleanupObserved": terminal["kind"] as? String == "idle_exit_cleanup"]
    }
}
