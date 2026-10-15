import CoreGraphics

/// Isolated layout math for the existing herb-table bitmap. It never changes the
/// logical furniture ID or source pixels. Alpha bounds are measured in source pixels.
enum HomeFurnitureFitR138 {
    struct Transform {
        let uniformScale: CGFloat
        let position: CGPoint
        let policy: String
    }

    static let sourceCanvas = CGSize(width: 1374, height: 1145)
    static let baselineAlpha = CGRect(x: 64, y: 0, width: 1297, height: 1125)
    static let candidateAlpha = CGRect(x: 157, y: 158, width: 1102, height: 884)

    enum Variant: String, CaseIterable {
        case matchVisibleWidth = "match_visible_width"
        case matchVisibleArea = "match_visible_area"
    }

    static func transform(variant: Variant, baselineNodeHeight: CGFloat,
                          baselinePosition: CGPoint, canvas: CGSize = sourceCanvas,
                          baselineBounds: CGRect = baselineAlpha,
                          candidateBounds: CGRect = candidateAlpha) -> Transform {
        let widthScale = baselineBounds.width / candidateBounds.width
        let heightScale = baselineBounds.height / candidateBounds.height
        let scale: CGFloat
        switch variant {
        case .matchVisibleWidth:
            scale = widthScale
        case .matchVisibleArea:
            scale = (widthScale * heightScale).squareRoot()
        }
        let baselineNodeWidth = baselineNodeHeight * canvas.width / canvas.height
        let baselineCenterX = (baselineBounds.midX / canvas.width - 0.5) * baselineNodeWidth
        let candidateCenterX = (candidateBounds.midX / canvas.width - 0.5) * baselineNodeWidth
        let baselineBottomY = (0.5 - baselineBounds.maxY / canvas.height) * baselineNodeHeight
        let candidateBottomY = (0.5 - candidateBounds.maxY / canvas.height) * baselineNodeHeight * scale
        let position = CGPoint(x: baselinePosition.x + baselineCenterX - candidateCenterX * scale,
                               y: baselinePosition.y + baselineBottomY - candidateBottomY)
        return Transform(uniformScale: scale, position: position, policy: variant.rawValue)
    }
}
