import SpriteKit
import UIKit

/// Candidate readability polish for the R04 capacity-suppressed follow-up notice.
/// Ownership, placement origin, removal and lifetime stay with the existing recipient node.
@MainActor enum PursuitSuppressionNotice {
    static let nodeName = "suppressed_pursuit_notice"
    static let pointerName = "suppressed_pursuit_recipient_pointer"
    static let titleName = "suppressed_pursuit_title"
    static let recipientNameNode = "suppressed_pursuit_recipient_name"
    static let pointerWidth = PursuitNoticePointerGeometryR059.pointerVisualWidth
    static let pointerHeight = PursuitNoticePointerGeometryR059.pointerVisualHeight
    static let pointerTipClearance = PursuitNoticePointerGeometryR059.recipientEdgeClearance
    private static let rootKey = "pursuitRootID"
    private static let sourceKey = "pursuitSourceID"
    private static let targetKey = "pursuitTargetID"

    @discardableResult
    static func install(on target: SKSpriteNode, in scene: SKScene,
                        obstacleNodes: [(String, SKNode)],
                        rootID: String, sourceID: String, targetID: String) -> Bool {
        guard !contains(rootID: rootID, in: target) else { return false }

        let sceneCorners = [CGPoint(x: scene.frame.minX, y: scene.frame.minY),
                            CGPoint(x: scene.frame.minX, y: scene.frame.maxY),
                            CGPoint(x: scene.frame.maxX, y: scene.frame.minY),
                            CGPoint(x: scene.frame.maxX, y: scene.frame.maxY)]
            .map { target.convert($0, from: scene) }
        guard let firstCorner = sceneCorners.first else { return false }
        let allowedBounds = sceneCorners.dropFirst().reduce(CGRect(origin: firstCorner, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
        let placement = PursuitNoticePlacementR059Collision.placement(
            anchorX: target.anchorPoint.x, anchorY: target.anchorPoint.y,
            targetWidth: target.size.width, targetHeight: target.size.height,
            obstacles: PursuitNoticePlacementR059Collision.obstacles(from: obstacleNodes, relativeTo: target),
            allowedBounds: allowedBounds)

        let group = SKNode()
        group.name = nodeName
        group.userData = [rootKey: rootID, sourceKey: sourceID, targetKey: targetID,
                          "placementCandidate": "R059_COLLISION_R007",
                          "collisionPlacementFound": placement != nil,
                          "placementOffsetX": placement?.offset.x ?? 0,
                          "placementOffsetY": placement?.offset.y ?? 0,
                          "obstacleCount": obstacleNodes.count,
                          "connectorRequired": placement?.needsLeader ?? false,
                          "recipientTipX": placement?.recipientTip.x ?? -3,
                          "recipientTipY": placement?.recipientTip.y ?? 0]
        // If no clear position fits the viewport, preserve the previous
        // attached placement rather than hiding the notice or changing combat.
        group.position = placement?.groupOrigin ?? CGPoint(
            x: -3, y: PursuitNoticePointerGeometryR059.noticeOriginY(
                anchorY: target.anchorPoint.y, height: target.size.height))
        group.zPosition = 80

        let backing = SKShapeNode(rectOf: CGSize(width: PursuitNoticeCopyR059.panelWidth, height: PursuitNoticePointerGeometryR059.panelHeight), cornerRadius: 6)
        backing.fillColor = UIColor(red: 0.09, green: 0.08, blue: 0.12, alpha: 0.96)
        backing.strokeColor = UIColor(red: 0.96, green: 0.72, blue: 0.30, alpha: 1)
        backing.lineWidth = PursuitNoticePointerGeometryR059.panelStrokeWidth
        group.addChild(backing)

        // A restrained upward notch points from the chip to this exact parent
        // sprite. It does not move or reparent the notice and cannot cover the
        // actor because its stroked apex remains 4pt below the sprite edge.
        let pointer = SKShapeNode(path: PursuitNoticePointerGeometryR059.path())
        pointer.name = pointerName
        pointer.fillColor = backing.fillColor
        pointer.strokeColor = backing.strokeColor
        pointer.lineWidth = PursuitNoticePointerGeometryR059.pointerStrokeWidth
        pointer.lineCap = PursuitNoticePointerGeometryR059.pointerLineCap
        pointer.lineJoin = PursuitNoticePointerGeometryR059.pointerLineJoin
        pointer.miterLimit = PursuitNoticePointerGeometryR059.pointerMiterLimit
        pointer.zPosition = 1
        group.addChild(pointer)

        if let placement, placement.needsLeader {
            let start = CGPoint(x: placement.recipientTip.x - group.position.x,
                                y: placement.recipientTip.y - group.position.y)
            let end = CGPoint(x: 0,
                              y: PursuitNoticePointerGeometryR059.strokedPath().boundingBoxOfPath.maxY)
            let leaderPath = CGMutablePath()
            leaderPath.move(to: start)
            leaderPath.addLine(to: end)
            let leader = SKShapeNode(path: leaderPath)
            leader.name = "suppressed_pursuit_recipient_leader"
            leader.strokeColor = UIColor(red: 0.82, green: 0.61, blue: 0.29, alpha: 0.78)
            leader.lineWidth = PursuitNoticePlacementR059Collision.leaderWidth
            leader.lineCap = .round
            leader.zPosition = -1
            group.addChild(leader)
        }

        let title = SKLabelNode(fontNamed: "HiraginoSans-W6")
        title.name = titleName
        title.text = PursuitNoticeCopyR059.title
        title.fontSize = PursuitNoticeCopyR059.fontSize
        title.fontColor = .white
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.zPosition = 2
        group.addChild(title)

        let recipient = SKLabelNode(fontNamed: "HiraginoSans-W6")
        recipient.name = recipientNameNode
        recipient.text = PursuitNoticeCopyR059.recipientName(targetID: targetID)
        recipient.fontSize = PursuitNoticeCopyR059.fontSize
        recipient.fontColor = .white
        recipient.verticalAlignmentMode = .center
        recipient.horizontalAlignmentMode = .center
        recipient.zPosition = 2
        group.addChild(recipient)
        PursuitNoticeLabelLayoutR059.position(title: title, recipient: recipient)

        target.addChild(group)
        return true
    }

    enum DynamicReflowResult: Equatable {
        case retainedSafe
        case relocatedClear
        case noSafeSlot
        case relocatedStillUnsafe
        case skippedInvalidOwnership
    }

    /// Re-evaluates installed SpriteKit geometry after scene actions. A safe
    /// layout is retained in place; only stale/colliding/clipped layouts move.
    /// The notice group stays under the same recipient and keeps its IDs/lifetime.
    @discardableResult
    static func reflow(group: SKNode, recipient: SKSpriteNode, scene: SKScene,
                       obstacleNodes: [(String, SKNode)], sceneFrame: Int) -> DynamicReflowResult {
        guard group.name == nodeName, group.parent === recipient,
              group.userData?[rootKey] as? String != nil,
              group.userData?[sourceKey] as? String != nil,
              group.userData?[targetKey] as? String != nil else {
            return .skippedInvalidOwnership
        }
        let before = PursuitNoticeRenderedBoundsQA_R059.inspect(
            group: group, recipient: recipient, scene: scene, obstacles: obstacleNodes)
        group.userData?["r008LastCheckSceneFrame"] = sceneFrame
        group.userData?["r008LastActualCollisionIDs"] = before.actualCollisionIDs
        if before.actualLayoutSafe {
            group.userData?["placementCandidate"] = "R059_COLLISION_R008_DYNAMIC"
            let baseOrigin = CGPoint(x: -3,
                y: PursuitNoticePointerGeometryR059.noticeOriginY(
                    anchorY: recipient.anchorPoint.y, height: recipient.size.height))
            group.userData?["placementOffsetX"] = group.position.x - baseOrigin.x
            group.userData?["placementOffsetY"] = group.position.y - baseOrigin.y
            group.userData?["connectorRequired"] = group.childNode(withName: "suppressed_pursuit_recipient_leader") != nil
            group.userData?["obstacleCount"] = obstacleNodes.count
            group.userData?["r008LastDisposition"] = "retained_safe"
            return .retainedSafe
        }

        let sceneCorners = [CGPoint(x: scene.frame.minX, y: scene.frame.minY),
                            CGPoint(x: scene.frame.minX, y: scene.frame.maxY),
                            CGPoint(x: scene.frame.maxX, y: scene.frame.minY),
                            CGPoint(x: scene.frame.maxX, y: scene.frame.maxY)]
            .map { recipient.convert($0, from: scene) }
        guard let first = sceneCorners.first else {
            group.userData?["r008LastDisposition"] = "scene_bounds_unavailable"
            return .noSafeSlot
        }
        let allowedBounds = sceneCorners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        let obstacles = PursuitNoticePlacementR059Collision.obstacles(from: obstacleNodes, relativeTo: recipient)
        guard let placement = PursuitNoticePlacementR059Collision.placement(
            anchorX: recipient.anchorPoint.x, anchorY: recipient.anchorPoint.y,
            targetWidth: recipient.size.width, targetHeight: recipient.size.height,
            obstacles: obstacles, allowedBounds: allowedBounds) else {
            group.userData?["placementCandidate"] = "R059_COLLISION_R008_DYNAMIC"
            group.userData?["r008LastDisposition"] = "no_safe_slot_kept_previous_position"
            return .noSafeSlot
        }

        group.position = placement.groupOrigin
        group.userData?["placementCandidate"] = "R059_COLLISION_R008_DYNAMIC"
        group.userData?["collisionPlacementFound"] = true
        let baseOrigin = CGPoint(x: -3,
            y: PursuitNoticePointerGeometryR059.noticeOriginY(
                anchorY: recipient.anchorPoint.y, height: recipient.size.height))
        group.userData?["placementOffsetX"] = placement.groupOrigin.x - baseOrigin.x
        group.userData?["placementOffsetY"] = placement.groupOrigin.y - baseOrigin.y
        group.userData?["obstacleCount"] = obstacleNodes.count
        group.userData?["connectorRequired"] = placement.needsLeader
        group.userData?["recipientTipX"] = placement.recipientTip.x
        group.userData?["recipientTipY"] = placement.recipientTip.y
        group.userData?["r008ReflowCount"] = (group.userData?["r008ReflowCount"] as? Int ?? 0) + 1
        updateLeader(group: group, placement: placement)

        let after = PursuitNoticeRenderedBoundsQA_R059.inspect(
            group: group, recipient: recipient, scene: scene, obstacles: obstacleNodes)
        group.userData?["r008LastActualCollisionIDs"] = after.actualCollisionIDs
        if after.actualLayoutSafe {
            group.userData?["r008LastDisposition"] = "relocated_actual_bounds_clear"
            return .relocatedClear
        }
        group.userData?["r008LastDisposition"] = "relocated_but_actual_bounds_unsafe"
        return .relocatedStillUnsafe
    }

    private static func updateLeader(group: SKNode,
                                     placement: PursuitNoticePlacementR059Collision.Placement) {
        let existing = group.childNode(withName: "suppressed_pursuit_recipient_leader") as? SKShapeNode
        guard placement.needsLeader else {
            existing?.removeFromParent()
            return
        }
        let start = CGPoint(x: placement.recipientTip.x - group.position.x,
                            y: placement.recipientTip.y - group.position.y)
        let end = CGPoint(x: 0, y: PursuitNoticePointerGeometryR059.strokedPath().boundingBoxOfPath.maxY)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let leader = existing ?? SKShapeNode()
        leader.name = "suppressed_pursuit_recipient_leader"
        leader.path = path
        leader.strokeColor = UIColor(red: 0.82, green: 0.61, blue: 0.29, alpha: 0.78)
        leader.lineWidth = PursuitNoticePlacementR059Collision.leaderWidth
        leader.lineCap = .round
        leader.zPosition = -1
        if leader.parent == nil { group.addChild(leader) }
    }

    static func contains(rootID: String, in node: SKNode) -> Bool {
        var found = false
        node.enumerateChildNodes(withName: "//" + nodeName) { child, stop in
            if child.userData?[rootKey] as? String == rootID {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    static func targetIDs(rootID: String, in node: SKNode) -> [String] {
        var targets: [String] = []
        node.enumerateChildNodes(withName: "//" + nodeName) { child, _ in
            guard child.userData?[rootKey] as? String == rootID,
                  let target = child.userData?[targetKey] as? String else { return }
            targets.append(target)
        }
        return targets
    }

    static func sourceIDs(rootID: String, in node: SKNode) -> [String] {
        var sources: [String] = []
        node.enumerateChildNodes(withName: "//" + nodeName) { child, _ in
            guard child.userData?[rootKey] as? String == rootID,
                  let source = child.userData?[sourceKey] as? String else { return }
            sources.append(source)
        }
        return sources
    }

    static func count(in node: SKNode) -> Int {
        var total = 0
        node.enumerateChildNodes(withName: "//" + nodeName) { _, _ in total += 1 }
        return total
    }

    @discardableResult
    static func remove(rootID: String, from node: SKNode) -> Int {
        var matches: [SKNode] = []
        node.enumerateChildNodes(withName: "//" + nodeName) { child, _ in
            if child.userData?[rootKey] as? String == rootID { matches.append(child) }
        }
        for match in matches {
            match.removeAllActions()
            match.removeFromParent()
        }
        return matches.count
    }

    static func removeAll(from node: SKNode) {
        var matches: [SKNode] = []
        node.enumerateChildNodes(withName: "//" + nodeName) { child, _ in matches.append(child) }
        for match in matches {
            match.removeAllActions()
            match.removeFromParent()
        }
    }
}
