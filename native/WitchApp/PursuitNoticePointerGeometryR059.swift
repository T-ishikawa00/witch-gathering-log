import CoreGraphics

/// Shared geometry for the R04 recipient pointer. Kept CoreGraphics-only so
/// the exact path and its stroked bounds are executable in a host test.
enum PursuitNoticePointerGeometryR059 {
    static let panelHeight: CGFloat = 26
    static let panelCenterBelowRecipientEdge: CGFloat = 23
    static let panelStrokeWidth: CGFloat = 1.2
    static let pointerVisualWidth: CGFloat = 6
    static let pointerVisualHeight: CGFloat = 6
    static let pointerStrokeWidth: CGFloat = 1
    static let pointerLineCap: CGLineCap = .butt
    static let pointerLineJoin: CGLineJoin = .round
    static let pointerMiterLimit: CGFloat = 1
    static let recipientEdgeClearance: CGFloat = 4

    static func path() -> CGPath {
        let halfStroke = pointerStrokeWidth / 2
        let pathWidth = pointerVisualWidth - pointerStrokeWidth
        let pathHeight = pointerVisualHeight - pointerStrokeWidth
        let baseY = panelHeight / 2 + halfStroke
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -pathWidth / 2, y: baseY))
        path.addLine(to: CGPoint(x: 0, y: baseY + pathHeight))
        path.addLine(to: CGPoint(x: pathWidth / 2, y: baseY))
        path.closeSubpath()
        return path
    }

    static func strokedPath() -> CGPath {
        path().copy(strokingWithWidth: pointerStrokeWidth, lineCap: pointerLineCap,
                    lineJoin: pointerLineJoin, miterLimit: pointerMiterLimit)
    }

    static func noticeOriginY(anchorY: CGFloat, height: CGFloat) -> CGFloat {
        -anchorY * height - panelCenterBelowRecipientEdge
    }

    static func clearance(anchorY: CGFloat, height: CGFloat) -> CGFloat {
        let recipientLowerEdge = -anchorY * height
        let strokedTip = strokedPath().boundingBoxOfPath.maxY
        let tipInRecipient = noticeOriginY(anchorY: anchorY, height: height) + strokedTip
        return recipientLowerEdge - tipInRecipient
    }
}
