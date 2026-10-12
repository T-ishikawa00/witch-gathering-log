import SpriteKit
import UIKit

/// Presentation candidate. The committed mark owns its lifetime; no timer here
/// predicts a hit, grants damage or changes the marked actor's position.
@MainActor enum MagnetMarkIndicator {
    static let nodeName = "magnet_mark_indicator"
    static func noticeName(rootID: String) -> String { "magnet_notice:" + rootID }

    static func install(on cue: SKSpriteNode, groundOffset: CGPoint) {
        cue.childNode(withName: nodeName)?.removeFromParent()
        let group = SKNode()
        group.name = nodeName
        group.position = groundOffset
        let dark = SKShapeNode(ellipseOf: CGSize(width: 46, height: 15))
        dark.strokeColor = UIColor(red: 0.10, green: 0.06, blue: 0.19, alpha: 0.95)
        dark.lineWidth = 5
        dark.fillColor = .clear
        group.addChild(dark)
        let rim = SKShapeNode(ellipseOf: CGSize(width: 46, height: 15))
        rim.strokeColor = UIColor(red: 0.86, green: 0.73, blue: 1, alpha: 1)
        rim.lineWidth = 1.8
        rim.fillColor = UIColor(red: 0.60, green: 0.38, blue: 0.96, alpha: 0.12)
        group.addChild(rim)
        // A short word provides identity without relying on colour alone. Keep
        // it below the feet so the backing cannot cover the actor's clothing.
        let backing = SKShapeNode(rectOf: CGSize(width: 36, height: 19), cornerRadius: 5)
        backing.position = CGPoint(x: 0, y: -18)
        backing.fillColor = UIColor(red: 0.10, green: 0.06, blue: 0.19, alpha: 0.96)
        backing.strokeColor = rim.strokeColor
        backing.lineWidth = 1
        group.addChild(backing)
        let label = SKLabelNode(fontNamed: "HiraginoSans-W6")
        label.text = "磁印"
        label.fontSize = 11
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = backing.position
        group.addChild(label)
        cue.addChild(group)
    }

    static func remove(from cue: SKSpriteNode) {
        cue.childNode(withName: nodeName)?.removeFromParent()
    }
}
