import SpriteKit

/// Centers the actual SpriteKit glyph bounds, including the font's bearing.
/// Estimated text height and alignment mode alone do not describe those bounds.
@MainActor enum PursuitNoticeLabelLayoutR059 {
    static let lineGap: CGFloat = 1

    static func position(title: SKLabelNode, recipient: SKLabelNode) {
        title.position = .zero
        recipient.position = .zero
        let titleBounds = title.frame
        let recipientBounds = recipient.frame
        let stackHeight = titleBounds.height + lineGap + recipientBounds.height
        recipient.position = CGPoint(x: -recipientBounds.midX,
                                     y: -stackHeight / 2 - recipientBounds.minY)
        title.position = CGPoint(x: -titleBounds.midX,
                                 y: -stackHeight / 2 + recipientBounds.height + lineGap - titleBounds.minY)
    }
}
