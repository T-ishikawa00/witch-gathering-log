import Foundation
import CoreGraphics

/// Independent test oracle for a direct child actor's local-to-scene transform.
/// Runtime geometry is mandatory: a clip can replace its static index anchor.
/// This helper is used only by the simulator presentation regression probe.
enum EffectAnchorProjectionQA {
    static func project(_ normalized: CGPoint, geometry: [String: Any]) -> CGPoint? {
        func number(_ key: String) -> CGFloat? {
            guard let value = geometry[key] as? NSNumber,
                  value.doubleValue.isFinite else { return nil }
            return CGFloat(value.doubleValue)
        }
        guard normalized.x.isFinite, normalized.y.isFinite,
              let x = number("x"), let y = number("y"),
              let width = number("width"), let height = number("height"),
              let anchorX = number("anchorX"), let anchorY = number("anchorY"),
              let scaleX = number("xScale"), let scaleY = number("yScale"),
              let angle = number("zRotation"), width > 0, height > 0 else { return nil }
        let localX = (normalized.x - anchorX) * width * scaleX
        let localY = (normalized.y - anchorY) * height * scaleY
        return CGPoint(x: x + localX * cos(angle) - localY * sin(angle),
                       y: y + localX * sin(angle) + localY * cos(angle))
    }
}
