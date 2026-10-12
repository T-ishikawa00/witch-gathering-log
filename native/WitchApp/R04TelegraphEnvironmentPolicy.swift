import Foundation
import SpriteKit

/// QA-candidate policy for existing R04 environment effects. It owns only
/// environment_effect:ENV_R04_* nodes and never changes combat event state.
@MainActor final class R04TelegraphEnvironmentPolicy {
    private(set) var suppressionTransitions = 0
    private(set) var restoreTransitions = 0
    private(set) var cueObservations = 0
    private(set) var cueObservationMaxEmitters = 0
    private(set) var observedMaxOwnedEmitters = 0
    private(set) var unexpectedVisibleDuringCue = 0
    private(set) var lastTransition = "none"
    private(set) var lastCueNodeCount = 0
    private(set) var suppressed = false
    private var latestPlacement: [String: [String: Double]] = [:]
    private var latestProtectedLaneIntersections = 0

    static let protectedLaneTopLeft = CGRect(x: 0.08, y: 0.56, width: 0.86, height: 0.34)
    static let emitterLimit = 2

    static func selectedIDs(_ ids: [String], cycle: Int) -> [String] {
        guard !ids.isEmpty else { return [] }
        return (0..<min(emitterLimit, ids.count)).map { ids[(cycle + $0) % ids.count] }
    }

    /// Returns true while an R04 cue is active and existing weather emitters
    /// have been hidden. Positions keep ambient particles in upper/side space.
    func reconcile(region: String, cueNodeCount: Int, nodes: [SKNode]) -> Bool {
        let owned = nodes.filter { node in
            guard let name = node.name, name.hasPrefix("environment_effect:ENV_R04_") else { return false }
            return (node.userData?["environmentOwner"] as? String) == "R04"
        }
        observedMaxOwnedEmitters = max(observedMaxOwnedEmitters, owned.count)
        let active = region == "R04" && cueNodeCount > 0
        lastCueNodeCount = active ? cueNodeCount : 0

        if active {
            cueObservations += 1
            cueObservationMaxEmitters = max(cueObservationMaxEmitters, owned.count)
            for node in owned { node.isHidden = true }
            if !suppressed {
                suppressionTransitions += 1
                lastTransition = "suppressed_for_active_combat_cue"
            }
            suppressed = true
            if owned.contains(where: { !$0.isHidden }) { unexpectedVisibleDuringCue += 1 }
            return true
        }

        for node in owned { node.isHidden = false }
        if suppressed {
            restoreTransitions += 1
            lastTransition = region == "R04" ? "restored_after_cue_cancel_or_end" : "restored_after_region_change"
        }
        suppressed = false
        return false
    }

    func place(_ node: SKSpriteNode, id: String, slot: Int, sceneSize: CGSize) {
        let sideX: CGFloat = slot == 0 ? 0.18 : 0.82
        let bottomOriginY: CGFloat
        switch id {
        case "ENV_R04_02": bottomOriginY = 0.64 // drift pixels sit below the authored center; this keeps their visible line above the R4 protected floor.
        case "ENV_R04_03": bottomOriginY = 0.72
        default: bottomOriginY = 0.80
        }
        let widthLimitedScale = sceneSize.width / 402 * 0.86
        // Bound the actual emitter height as well as width so compact/tiny SpriteViews
        // keep every particle above the normalized protected action lane.
        let protectedHeightLimitedScale = sceneSize.height * 0.20 / max(1, node.size.height)
        let sizeScale = min(widthLimitedScale, protectedHeightLimitedScale)
        node.setScale(sizeScale)
        node.position = CGPoint(x: sceneSize.width * sideX, y: sceneSize.height * bottomOriginY)
        node.zPosition = 8 // behind actors and all presentation cues
        node.userData = (node.userData ?? NSMutableDictionary())
        node.userData?["environmentOwner"] = "R04"
        node.userData?["environmentID"] = id
        node.userData?["environmentSlot"] = slot
        let halfWidth = node.size.width * abs(node.xScale) / 2
        let halfHeight = node.size.height * abs(node.yScale) / 2
        let normalizedBoundsTopLeft = CGRect(x: (node.position.x - halfWidth) / max(1, sceneSize.width),
                                             y: 1 - (node.position.y + halfHeight) / max(1, sceneSize.height),
                                             width: 2 * halfWidth / max(1, sceneSize.width),
                                             height: 2 * halfHeight / max(1, sceneSize.height))
        if normalizedBoundsTopLeft.intersects(Self.protectedLaneTopLeft) { latestProtectedLaneIntersections += 1 }
        latestPlacement[id] = [
            "slot": Double(slot),
            "centerXNormalizedBottomLeft": Double(node.position.x / max(1, sceneSize.width)),
            "centerYNormalizedBottomLeft": Double(node.position.y / max(1, sceneSize.height)),
            "uniformScale": Double(sizeScale),
            "zPosition": Double(node.zPosition),
            "boundsMinXNormalized": Double(normalizedBoundsTopLeft.minX),
            "boundsMinYTopLeftNormalized": Double(normalizedBoundsTopLeft.minY),
            "boundsWidthNormalized": Double(normalizedBoundsTopLeft.width),
            "boundsHeightNormalized": Double(normalizedBoundsTopLeft.height),
            "intersectsProtectedLane": normalizedBoundsTopLeft.intersects(Self.protectedLaneTopLeft) ? 1 : 0
        ]
    }

    func reset() {
        suppressionTransitions = 0
        restoreTransitions = 0
        cueObservations = 0
        cueObservationMaxEmitters = 0
        observedMaxOwnedEmitters = 0
        unexpectedVisibleDuringCue = 0
        lastTransition = "scene_reset"
        lastCueNodeCount = 0
        suppressed = false
        latestPlacement.removeAll()
        latestProtectedLaneIntersections = 0
    }

    func snapshot(currentOwnedEmitterCount: Int, currentHiddenEmitterCount: Int) -> [String: Any] {
        [
            "owner": "R04_environment_effects_only",
            "suppressed": suppressed,
            "lastTransition": lastTransition,
            "lastCueNodeCount": lastCueNodeCount,
            "suppressionTransitions": suppressionTransitions,
            "restoreTransitions": restoreTransitions,
            "cueObservations": cueObservations,
            "cueObservationMaxEmitters": cueObservationMaxEmitters,
            "currentOwnedEmitters": currentOwnedEmitterCount,
            "currentHiddenOwnedEmitters": currentHiddenEmitterCount,
            "maxOwnedEmitters": observedMaxOwnedEmitters,
            "maxAllowedEmitters": Self.emitterLimit,
            "unexpectedVisibleDuringCue": unexpectedVisibleDuringCue,
            "latestPlacementProtectedLaneIntersections": latestProtectedLaneIntersections,
            "latestPlacementByEffectID": latestPlacement,
            "protectedLaneTopLeft": [Self.protectedLaneTopLeft.minX, Self.protectedLaneTopLeft.minY,
                                      Self.protectedLaneTopLeft.width, Self.protectedLaneTopLeft.height],
            "status": "CANDIDATE_POLICY_METRICS_NOT_VISUAL_ACCEPTANCE"
        ]
    }
}
