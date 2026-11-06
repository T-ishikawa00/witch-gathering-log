import CoreGraphics
import SpriteKit

/// QA readback of installed R059 notice nodes; never calls the placement solver.
enum PursuitNoticeRenderedBoundsQA_R059 {
    struct Result {
        let candidateInstalled: Bool
        let displaced: Bool
        let connectorRequired: Bool
        let attachmentWithinRecipient: Bool
        let collisionPlacementFound: Bool
        let recipientConnectorClearance: CGFloat?
        let leaderEndsAtPanelTip: Bool
        let actualCollisionIDs: [String]
        let requiredLeaderPresent: Bool
        let legacyPointerClearance: CGFloat?
        let actualBoundsInsideScene: Bool
        let recipientBodyClear: Bool
        let placementMarker: String?

        /// Uses installed SpriteKit nodes and their current transformed frames.
        /// It deliberately ignores stored solver metadata.
        var actualLayoutSafe: Bool {
            guard actualBoundsInsideScene, actualCollisionIDs.isEmpty,
                  recipientBodyClear, attachmentWithinRecipient else { return false }
            if connectorRequired {
                return requiredLeaderPresent && leaderEndsAtPanelTip &&
                    recipientConnectorClearance.map { abs($0 - 4) <= 0.75 } == true
            }
            return !requiredLeaderPresent && legacyPointerClearance.map { abs($0 - 4) <= 0.75 } == true
        }

        var passed: Bool {
            guard actualBoundsInsideScene else { return false }
            if !candidateInstalled {
                return !requiredLeaderPresent && legacyPointerClearance.map { abs($0 - 4) <= 0.75 } == true
            }
            if placementMarker == "R059_COLLISION_R008_DYNAMIC" { return actualLayoutSafe }
            guard collisionPlacementFound, actualCollisionIDs.isEmpty, recipientBodyClear, attachmentWithinRecipient else { return false }
            if connectorRequired {
                return requiredLeaderPresent && leaderEndsAtPanelTip &&
                    recipientConnectorClearance.map { abs($0 - 4) <= 0.75 } == true
            }
            return !requiredLeaderPresent && legacyPointerClearance.map { abs($0 - 4) <= 0.75 } == true
        }
    }

    private static func rectInScene(_ node: SKNode, scene: SKScene) -> CGRect? {
        guard let parent = node.parent else { return nil }
        let r = node.frame
        let corners = [CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.minX,y:r.maxY),
                       CGPoint(x:r.maxX,y:r.minY), CGPoint(x:r.maxX,y:r.maxY)]
            .map { scene.convert($0, from: parent) }
        guard let first = corners.first else { return nil }
        return corners.dropFirst().reduce(CGRect(origin:first,size:.zero)) { $0.union(CGRect(origin:$1,size:.zero)) }
    }

    private static func endpoints(_ path: CGPath) -> (CGPoint, CGPoint)? {
        var points:[CGPoint]=[]
        path.applyWithBlock { element in
            let e=element.pointee
            switch e.type {
            case .moveToPoint,.addLineToPoint: points.append(e.points[0])
            default: break
            }
        }
        guard points.count >= 2, let first=points.first, let last=points.last else { return nil }
        return (first,last)
    }

    static func inspect(group:SKNode,recipient:SKSpriteNode,scene:SKScene,
                        obstacles:[(String,SKNode)]) -> Result {
        let marker = group.userData?["placementCandidate"] as? String
        let candidateInstalled = marker == "R059_COLLISION_R007" || marker == "R059_COLLISION_R008_DYNAMIC"
        let found=candidateInstalled ? (group.userData?["collisionPlacementFound"] as? Bool ?? false) : true
        let baseOrigin = CGPoint(x: -3,
            y: PursuitNoticePointerGeometryR059.noticeOriginY(
                anchorY: recipient.anchorPoint.y, height: recipient.size.height))
        let ox = marker == "R059_COLLISION_R008_DYNAMIC"
            ? group.position.x - baseOrigin.x
            : (group.userData?["placementOffsetX"] as? CGFloat ?? 0)
        let oy = marker == "R059_COLLISION_R008_DYNAMIC"
            ? group.position.y - baseOrigin.y
            : (group.userData?["placementOffsetY"] as? CGFloat ?? 0)
        let displaced = (found || marker == "R059_COLLISION_R008_DYNAMIC") && hypot(ox,oy)>0.01
        let connectorRequired = marker == "R059_COLLISION_R008_DYNAMIC"
            ? group.childNode(withName: "suppressed_pursuit_recipient_leader") != nil
            : (group.userData?["connectorRequired"] as? Bool ?? false)
        var attachmentWithinRecipient=false
        let pointer=group.childNode(withName:"suppressed_pursuit_recipient_pointer") as? SKShapeNode
        let leader=group.childNode(withName:"suppressed_pursuit_recipient_leader") as? SKShapeNode
        let lowerEdge = -recipient.anchorPoint.y * recipient.size.height
        var connectorClearance:CGFloat?
        var panelTipMatch=false
        var pointerClearance:CGFloat?
        if let pointer,let path=pointer.path {
            let stroked=path.copy(strokingWithWidth:pointer.lineWidth,lineCap:pointer.lineCap,
                                  lineJoin:pointer.lineJoin,miterLimit:pointer.miterLimit)
            let tip=stroked.boundingBoxOfPath.maxY
            let tipInRecipient=group.convert(CGPoint(x:0,y:tip),to:recipient)
            pointerClearance=lowerEdge-tipInRecipient.y
            let minX = -recipient.anchorPoint.x * recipient.size.width
            let maxX = minX + recipient.size.width
            attachmentWithinRecipient = tipInRecipient.x >= minX && tipInRecipient.x <= maxX
            if let leader,let leaderPath=leader.path,let ep=endpoints(leaderPath) {
                let start=leader.convert(ep.0,to:recipient)
                let end=leader.convert(ep.1,to:recipient)
                connectorClearance=lowerEdge-start.y
                attachmentWithinRecipient = start.x >= minX && start.x <= maxX
                panelTipMatch=abs(end.x-tipInRecipient.x)<=0.75 && abs(end.y-tipInRecipient.y)<=0.75
            }
        }
        let renderedChildren=group.children
        let visibleRects=renderedChildren.compactMap { rectInScene($0,scene:scene) }
        let boundsInsideScene = !visibleRects.isEmpty && visibleRects.allSatisfy { scene.frame.insetBy(dx:-0.5,dy:-0.5).contains($0) }
        let pointerRects = ["suppressed_pursuit_recipient_pointer"].compactMap { name in
            group.childNode(withName:name).flatMap { rectInScene($0,scene:scene) }
        }
        let leaderRects = ["suppressed_pursuit_recipient_leader"].compactMap { name in
            group.childNode(withName:name).flatMap { rectInScene($0,scene:scene) }
        }
        let collisionRects = pointerRects + leaderRects
        let backing=group.children.first { $0 is SKShapeNode && $0.name == nil }
        let panelRects=backing.flatMap { rectInScene($0,scene:scene) }.map{[$0]} ?? []
        let noticeRects=panelRects+collisionRects
        let recipientRect = rectInScene(recipient, scene: scene)
        let recipientBodyClear = recipientRect.map { body in
            // Panel and pointer keep the solver's 2pt clearance outside the
            // unexpanded recipient. The connector is a deliberate exception
            // only to that buffer: its actual SpriteKit frame must remain
            // outside the actual body, so a malformed line crossing the actor
            // still fails while the 4pt endpoint contract remains possible.
            let panelAndPointer = panelRects + pointerRects
            return panelAndPointer.allSatisfy {
                !$0.insetBy(dx: -2, dy: -2).intersects(body)
            } && leaderRects.allSatisfy { !$0.intersects(body) }
        } ?? false
        var collisionIDs:[String]=[]
        for (id,node) in obstacles {
            guard let r=rectInScene(node,scene:scene) else { continue }
            if noticeRects.contains(where:{$0.insetBy(dx:-2,dy:-2).intersects(r.insetBy(dx:-2,dy:-2))}) { collisionIDs.append(id) }
        }
        return Result(candidateInstalled:candidateInstalled,displaced:displaced,connectorRequired:connectorRequired,
                      attachmentWithinRecipient:attachmentWithinRecipient,collisionPlacementFound:found,
                      recipientConnectorClearance:connectorClearance,leaderEndsAtPanelTip:panelTipMatch,
                      actualCollisionIDs:collisionIDs.sorted(),requiredLeaderPresent:leader != nil,
                      legacyPointerClearance:pointerClearance,actualBoundsInsideScene:boundsInsideScene,
                      recipientBodyClear:recipientBodyClear, placementMarker:marker)
    }
}
