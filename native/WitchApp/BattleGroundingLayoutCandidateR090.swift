import Foundation
import CoreGraphics

/// Local, unapproved composition candidate. Background source pixels, actor
/// scale and gameplay are unchanged. Coordinates are foot registration points.
enum BattleGroundingLayoutCandidateR090 {
    static func point(actorID: String, backgroundID: String, size: CGSize) -> CGPoint? {
        guard backgroundID == "BG_R04_BOSS", size.width > 0, size.height > 0 else { return nil }
        let compact = size.height / size.width < 1.45
        let positions: [String: CGPoint] = compact ? [
            "ERNA": CGPoint(x: 0.20, y: 0.45), "LUNA": CGPoint(x: 0.32, y: 0.32),
            "AIRA": CGPoint(x: 0.44, y: 0.45), "NOIR": CGPoint(x: 0.51, y: 0.33)
        ] : [
            "ERNA": CGPoint(x: 0.20, y: 0.44), "LUNA": CGPoint(x: 0.32, y: 0.32),
            "AIRA": CGPoint(x: 0.44, y: 0.44), "NOIR": CGPoint(x: 0.51, y: 0.33)
        ]
        guard let point = positions[actorID] else { return nil }
        return CGPoint(x: size.width * point.x, y: size.height * point.y)
    }
}
