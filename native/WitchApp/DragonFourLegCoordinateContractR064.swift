import Foundation

enum DragonFourLegCoordinateContractR064 {
    static let sourceWidth: CGFloat = 455
    static let sourceHeight: CGFloat = 157
    static let hostCapturePadding: CGFloat = 8

    /// Maps top-left source pixels to the body node's local SpriteKit coordinates.
    static func bodyLocal(_ point: CGPoint, anchor: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (point.x-anchor.x)*size.width/sourceWidth,
                y: (anchor.y-point.y)*size.height/sourceHeight)
    }

    /// The offscreen preview only: source-canvas pixel to padded image pixel.
    /// Runtime mounting must never add this viewport-only offset.
    static func hostCapturePixel(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x+hostCapturePadding, y: point.y+hostCapturePadding)
    }
}

