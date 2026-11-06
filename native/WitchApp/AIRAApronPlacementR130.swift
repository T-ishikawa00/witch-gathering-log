import Foundation
import CoreGraphics

/// Converts the pinned art's top-left pixel coordinates to the live body's
/// local coordinates. The authored sheet anchor is provenance, not a command
/// to move the body anchor. Authored idle/attack and walking use 12/256;
/// startup fallback frames can use 0.04. Always project from the actual node.
enum AIRAApronPlacementR130 {
    static let overlayLocalZ: CGFloat = 0.001
    static let foregroundLocalZ: CGFloat = 0.002

    struct Placement {
        let anchorTopLeft: CGPoint
        let center: CGPoint
        let bodyUnitsPerPixel: CGSize
        let imageScale: CGSize
    }

    static func project(canvas: CGSize, center: CGPoint, contentWidth: CGFloat,
                        bodySize: CGSize, bodyAnchor: CGPoint,
                        imageBounds: CGRect) -> Placement? {
        let values = [canvas.width, canvas.height, center.x, center.y, contentWidth,
                      bodySize.width, bodySize.height, bodyAnchor.x, bodyAnchor.y,
                      imageBounds.origin.x, imageBounds.origin.y,
                      imageBounds.size.width, imageBounds.size.height]
        guard values.allSatisfy({ $0.isFinite }),
              canvas.width > 0, canvas.height > 0,
              bodySize.width > 0, bodySize.height > 0,
              contentWidth > 0, contentWidth <= canvas.width,
              center.x >= 0, center.x <= canvas.width,
              center.y >= 0, center.y <= canvas.height,
              imageBounds.size.width > 0, imageBounds.size.height > 0,
              imageBounds.minX >= 0, imageBounds.minY >= 0,
              imageBounds.maxX <= 1254, imageBounds.maxY <= 1254,
              bodyAnchor.x >= 0, bodyAnchor.x <= 1,
              bodyAnchor.y >= 0, bodyAnchor.y <= 1 else { return nil }
        let units = CGSize(width: bodySize.width / canvas.width,
                           height: bodySize.height / canvas.height)
        let anchor = CGPoint(x: bodyAnchor.x * canvas.width,
                             y: (1 - bodyAnchor.y) * canvas.height)
        let scale = CGSize(width: contentWidth * units.width / imageBounds.width,
                           height: contentWidth * units.height / imageBounds.width)
        guard scale.width.isFinite, scale.height.isFinite else { return nil }
        return Placement(anchorTopLeft: anchor,
                         center: CGPoint(x: (center.x - anchor.x) * units.width,
                                         y: (anchor.y - center.y) * units.height),
                         bodyUnitsPerPixel: units, imageScale: scale)
    }

    static func validForeground(_ polygons: [[[CGFloat]]], canvas: CGSize) -> Bool {
        polygons.allSatisfy { polygon in
            polygon.count >= 3 && polygon.allSatisfy { point in
                point.count == 2 && point[0].isFinite && point[1].isFinite &&
                point[0] >= 0 && point[0] <= canvas.width &&
                point[1] >= 0 && point[1] <= canvas.height
            }
        }
    }
}
