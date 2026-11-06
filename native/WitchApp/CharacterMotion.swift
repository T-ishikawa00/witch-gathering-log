import SpriteKit

// Small deformation of an existing pose, with the entire foot band fixed.
// Distinct authored poses still supply limbs; this is not full skeletal animation.
@MainActor enum CharacterMotion {
    private static var cache: [String: SKWarpGeometryGrid] = [:]
    static var cachedGridCount: Int { cache.count }
    static let columns = 4
    static let rows = 6
    static let source: [SIMD2<Float>] = (0...rows).flatMap { y in
        (0...columns).map { x in SIMD2(Float(x)/Float(columns), Float(y)/Float(rows)) }
    }
    static func grid(actor: String, state: String, elapsed: Double, clock: Double) -> SKWarpGeometryGrid {
        let phaseOffsets: [String: Double] = ["ERNA":0.0,"LUNA":0.9,"AIRA":1.8,"NOIR":2.7]
        let seed: Double = phaseOffsets[actor] ?? 0.0
        let periodic = state == "idle" || state == "resolve"
        let rate = state == "resolve" ? 1.7 : 2.2
        let phase = (clock * rate + seed).truncatingRemainder(dividingBy: .pi * 2)
        let index = periodic ? min(31,Int(max(0,phase) / (.pi * 2) * 32)) : min(31,Int(max(0,elapsed) * 32 / 1.1))
        let key = actor + ":" + state + ":" + String(index)
        if let existing = cache[key] { return existing }
        let t = Float(index) * 1.1 / 32
        let angle = Double(index) / 32 * Double.pi * 2
        var lean: Float = 0
        var breath = Float(sin(angle)) * 0.003
        switch state {
        case "anticipate": lean = -0.016 * min(1,t/0.45); breath = 0
        case "execute": lean = 0.027 * exp(-t*7); breath = 0
        case "recover": lean = 0.008 * exp(-t*6)
        case "hit": lean = -0.02 * exp(-t*9); breath = 0
        case "resolve": lean = 0.004 * Float(sin(angle))
        default: break
        }
        if actor == "NOIR" { lean *= 0.7; breath *= 0.7 }
        let dest = source.map { p -> SIMD2<Float> in
            let aboveFeet = max(0,(p.y-0.17)/0.83)
            let torso = aboveFeet * aboveFeet
            return SIMD2(p.x + lean * torso, p.y + breath * torso)
        }
        let grid = SKWarpGeometryGrid(columns:columns, rows:rows, sourcePositions:source, destinationPositions:dest)
        cache[key] = grid
        return grid
    }
}
