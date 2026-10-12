import CoreGraphics
import SpriteKit

/// Conservative local-layout solver for the R059 suppression notice candidate.
/// Input rectangles are expressed in recipient-node coordinates. The helper
/// does not move actors and never changes notice ownership or lifetime.
enum PursuitNoticePlacementR059Collision {
    struct Obstacle {
        let id: String
        let rect: CGRect
    }

    struct Placement {
        let recipientTip: CGPoint
        let needsLeader: Bool
        let groupOrigin: CGPoint
        let panelRect: CGRect
        let pointerRect: CGRect
        let leaderRect: CGRect
        let occupiedRect: CGRect
        let offset: CGPoint
        let checkedObstacleIDs: [String]

        var displaced: Bool { abs(offset.x) > 0.01 || abs(offset.y) > 0.01 }
    }

    static let panelSize = CGSize(width: PursuitNoticeCopyR059.panelWidth,
                                  height: PursuitNoticePointerGeometryR059.panelHeight)
    static let clearance: CGFloat = 2
    static let leaderWidth: CGFloat = 1.2
    static let maxDisplacement: CGFloat = 128

    /// SpriteKit `frame` is in the node's parent coordinate system. Transform
    /// all four corners so rotation/scale/anchor changes are included.
    static func localBounds(of node: SKNode, relativeTo recipient: SKNode) -> CGRect? {
        guard let parent = node.parent else { return nil }
        let frame = node.frame
        let points = [
            CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY),
            CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY)
        ].map { recipient.convert($0, from: parent) }
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    static func placement(anchorX: CGFloat = 0.5, anchorY: CGFloat, targetWidth: CGFloat,
                          targetHeight: CGFloat,
                          obstacles: [Obstacle], allowedBounds: CGRect,
                          baseX: CGFloat = -3) -> Placement? {
        let targetEdgeY = -anchorY * targetHeight
        let recipientRect = CGRect(x: -anchorX * targetWidth, y: -anchorY * targetHeight,
                                   width: targetWidth, height: targetHeight)
        let base = CGPoint(x: baseX,
                           y: PursuitNoticePointerGeometryR059.noticeOriginY(anchorY: anchorY,
                                                                             height: targetHeight))
        let safeBounds = allowedBounds.insetBy(dx: clearance, dy: clearance)

        // Favor small offsets while testing both the empty floor below the
        // party and side pockets. The returned leader remains connected to the
        // exact recipient edge; the original pointer notch stays on the panel.
        let xs: [CGFloat] = [0, -32, 32, -56, 56, -80, 80, -104, 104]
        let ys: [CGFloat] = [0, -20, -40, -60, -80, -100, -120, 20, 40]
        let offsets = xs.flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
            .filter { hypot($0.x, $0.y) <= maxDisplacement }
            .sorted {
                let a = hypot($0.x, $0.y), b = hypot($1.x, $1.y)
                if abs(a - b) > 0.01 { return a < b }
                // For equal-distance candidates, try moving down before moving
                // sideways; that keeps the target pointer's horizontal route.
                if abs($0.x) != abs($1.x) { return abs($0.x) < abs($1.x) }
                return $0.y < $1.y
            }

        for offset in offsets {
            let origin = CGPoint(x: base.x + offset.x, y: base.y + offset.y)
            let panel = CGRect(x: origin.x - panelSize.width / 2,
                               y: origin.y - panelSize.height / 2,
                               width: panelSize.width, height: panelSize.height)
            let pointer = CGRect(x: origin.x - PursuitNoticePointerGeometryR059.pointerVisualWidth / 2,
                                 y: origin.y + panelSize.height / 2,
                                 width: PursuitNoticePointerGeometryR059.pointerVisualWidth,
                                 height: PursuitNoticePointerGeometryR059.pointerVisualHeight)
            // A moved panel must never fold back over its recipient. The
            // leader begins outside the sprite edge and is checked separately.
            guard !panel.union(pointer).insetBy(dx: -clearance, dy: -clearance).intersects(recipientRect) else { continue }
            // Attach to the closest point on the same recipient's lower edge.
            // A fixed center anchor can be blocked by a neighboring sprite even
            // when a short, direct pointer safely fits farther along that edge.
            let edgeInset = min(CGFloat(6), targetWidth / 4)
            let recipientTip = CGPoint(x: min(max(origin.x, recipientRect.minX + edgeInset),
                                               recipientRect.maxX - edgeInset),
                                       y: targetEdgeY - PursuitNoticePointerGeometryR059.recipientEdgeClearance)
            let panelTip = CGPoint(x: origin.x, y: origin.y + PursuitNoticePointerGeometryR059.strokedPath().boundingBoxOfPath.maxY)
            let needsLeader = hypot(recipientTip.x - panelTip.x, recipientTip.y - panelTip.y) > 0.75
            let leader = CGRect(x: min(recipientTip.x, panelTip.x), y: min(recipientTip.y, panelTip.y),
                                width: max(leaderWidth, abs(recipientTip.x - panelTip.x)),
                                height: max(leaderWidth, abs(recipientTip.y - panelTip.y)))
                .insetBy(dx: -leaderWidth / 2, dy: -leaderWidth / 2)
            let occupied = (needsLeader ? panel.union(pointer).union(leader) : panel.union(pointer)).insetBy(dx: -clearance, dy: -clearance)
            guard safeBounds.contains(occupied) else { continue }
            // Test the visible components independently. Testing their union
            // bounding box would report false collisions in the open gap
            // between a long leader and a displaced panel.
            let components = needsLeader ? [panel, pointer, leader] : [panel, pointer]
            let visibleComponents = components.map { $0.insetBy(dx: -clearance, dy: -clearance) }
            let collisions = obstacles.filter { obstacle in
                visibleComponents.contains { $0.intersects(obstacle.rect.insetBy(dx: -clearance, dy: -clearance)) }
            }
            guard collisions.isEmpty else { continue }
            return Placement(recipientTip: recipientTip, needsLeader: needsLeader, groupOrigin: origin, panelRect: panel, pointerRect: pointer, leaderRect: leader,
                             occupiedRect: occupied, offset: offset, checkedObstacleIDs: obstacles.map(\.id))
        }
        return nil
    }

    static func obstacles(from nodes: [(String, SKNode)], relativeTo recipient: SKNode) -> [Obstacle] {
        nodes.compactMap { id, node in
            guard let rect = localBounds(of: node, relativeTo: recipient) else { return nil }
            return Obstacle(id: id, rect: rect)
        }
    }
}
