import Foundation
import SpriteKit
import simd

/// QA-only control-point warp proposal for ACT_B_R04_B.
///
/// Unlike R004's broad horizontal bands, this keeps the upper-body vertices
/// fixed and bends only the distal part of four low-confidence visual guide
/// paths. It changes mesh coordinates, never the source texture. It is wired only through the off-glob R038 QA adapter and is not an adopted walk cycle.
@MainActor
struct DragonLocalizedLegWarpCandidateR003 {
    static let status = "UNAPPROVED_QA_ONLY_NOT_INTEGRATED"
    static let candidateID = "dragon_localized_leg_warp_r003"
    static let bodyPartID = "body4legs_tail"
    static let bodyWidth: Float = 455
    static let bodyHeight: Float = 157
    static let columns = 32
    static let rows = 12
    static let duration: Float = 1.2
    static let sampleCount = 13
    static let stanceFraction: Float = 0.62
    static let stridePixels: Float = 5.0
    static let swingLiftPixels: Float = 5.5
    static let maxSupportRadiusPixels: Float = 10.0

    struct Frame {
        let time: Float
        let geometry: SKWarpGeometryGrid
        let maxDeltaPixels: SIMD2<Float>
        let ambiguousOverlapVertices: Int
        let positiveTriangleCount: Int
        let nonPositiveTriangleCount: Int
    }

    enum BuildError: Error {
        case invalidSourceGrid
        case invalidDestination(frame: Int)
        case foldedTriangle(frame: Int, cell: Int)
    }

    private struct LegGuide {
        let id: String
        let pointsTopLeftPx: [SIMD2<Float>]
        let phase: Float
        let support: (minX: Float, maxX: Float, minY: Float, maxY: Float)
    }

    // These four curves are derived from low-confidence visual estimates in
    // FOUR_LEG_FRAME_PLAN_R001. The fore-near ankle/paw are midpoints of its
    // A/B estimates; the hind curves use A only because B correspondence is
    // ambiguous. They are guide curves, not authored rig joints or proven
    // near/far identities.
    private static let guides: [LegGuide] = [
        .init(id: "leg_left_outer_visual_estimate",
              pointsTopLeftPx: [[58, 78], [47, 116], [47, 122], [39, 138]],
              phase: 0.0, support: (0, 84, 76, 157)),
        .init(id: "leg_left_inner_visual_estimate",
              pointsTopLeftPx: [[116, 78], [116, 111], [119.5, 124], [123.5, 138.5]],
              phase: 0.5, support: (88, 148, 100, 157)),
        .init(id: "leg_right_inner_visual_estimate",
              pointsTopLeftPx: [[171, 80], [170, 104], [174, 124], [178, 135]],
              phase: 0.5, support: (144, 220, 94, 157)),
        .init(id: "leg_right_outer_visual_estimate",
              pointsTopLeftPx: [[235, 82], [234, 106], [238, 124], [241, 140]],
              phase: 0.0, support: (196, 296, 96, 157))
    ]

    private static let gridX: [Float] = [
        0, 16, 32, 48, 64, 72, 78, 85, 90, 96, 102, 108, 114, 120, 128, 136,
        142, 145, 151, 158, 166, 174, 182, 190, 198, 204, 210, 220, 230, 240,
        260, 284, 455
    ]
    private static let gridYTop: [Float] = [0, 50, 65, 72, 78, 82, 90, 100, 110, 119, 128, 140, 157]

    static func makeFrames() throws -> [Frame] {
        let source = makeSourceGrid()
        guard source.count == (columns + 1) * (rows + 1), gridX.count == columns + 1,
              gridYTop.count == rows + 1 else { throw BuildError.invalidSourceGrid }

        var frames: [Frame] = []
        frames.reserveCapacity(sampleCount)
        for frameIndex in 0..<sampleCount {
            let t = duration * Float(frameIndex) / Float(sampleCount - 1)
            var destination: [SIMD2<Float>] = []
            destination.reserveCapacity(source.count)
            var maxDelta = SIMD2<Float>(repeating: 0)
            var overlapCount = 0

            for sourcePoint in source {
                let sourcePx = SIMD2<Float>(sourcePoint.x * bodyWidth,
                                            (1 - sourcePoint.y) * bodyHeight)
                let influences = guides.compactMap { guide -> (LegGuide, Float, Float)? in
                    guard sourcePx.x >= guide.support.minX, sourcePx.x <= guide.support.maxX,
                          sourcePx.y >= guide.support.minY, sourcePx.y <= guide.support.maxY else { return nil }
                    let (distance, progress) = distanceToGuide(sourcePx, guide.pointsTopLeftPx)
                    guard distance < maxSupportRadiusPixels else { return nil }
                    let radial = 1 - smoothStep(4.0, maxSupportRadiusPixels, distance)
                    let distal = smoothStep(0.22, 0.56, progress)
                    let influence = radial * distal
                    guard influence > 0.001 else { return nil }
                    return (guide, influence, progress)
                }.sorted { $0.1 > $1.1 }

                var delta = SIMD2<Float>(repeating: 0)
                if let strongest = influences.first {
                    // A vertex contested by two leg supports is left unchanged.
                    // This avoids inventing which fused limb is in front.
                    if influences.count > 1, influences[1].1 > 0.18 {
                        overlapCount += 1
                    } else {
                        let offset = gaitOffset(time: t, phase: strongest.0.phase)
                        delta = SIMD2<Float>(offset.x * strongest.1, offset.y * strongest.1)
                    }
                }

                let resultPx = sourcePx + delta
                guard resultPx.x.isFinite, resultPx.y.isFinite,
                      resultPx.x >= 0, resultPx.x <= bodyWidth,
                      resultPx.y >= 0, resultPx.y <= bodyHeight else {
                    throw BuildError.invalidDestination(frame: frameIndex)
                }
                maxDelta.x = max(maxDelta.x, abs(delta.x))
                maxDelta.y = max(maxDelta.y, abs(delta.y))
                destination.append(SIMD2<Float>(resultPx.x / bodyWidth,
                                                1 - resultPx.y / bodyHeight))
            }

            let triangleCounts = try validateTriangles(source: source,
                                                       destination: destination,
                                                       frameIndex: frameIndex)
            frames.append(Frame(time: t,
                                geometry: SKWarpGeometryGrid(__columns: columns,
                                                             rows: rows,
                                                             sourcePositions: source,
                                                             destPositions: destination),
                                maxDeltaPixels: maxDelta,
                                ambiguousOverlapVertices: overlapCount,
                                positiveTriangleCount: triangleCounts.positive,
                                nonPositiveTriangleCount: triangleCounts.nonPositive))
        }
        return frames
    }

    private static func makeSourceGrid() -> [SIMD2<Float>] {
        var result: [SIMD2<Float>] = []
        result.reserveCapacity((columns + 1) * (rows + 1))
        // Match SpriteKit grid ordering: bottom row to top row, left to right.
        for row in 0...rows {
            let sourceTopRow = rows - row
            let normalizedY = 1 - gridYTop[sourceTopRow] / bodyHeight
            for x in gridX { result.append(SIMD2<Float>(x / bodyWidth, normalizedY)) }
        }
        return result
    }

    private static func gaitOffset(time: Float, phase: Float) -> SIMD2<Float> {
        let raw = time / duration + phase
        let cycle = raw - floor(raw)
        if cycle < stanceFraction {
            let u = cycle / stanceFraction
            return SIMD2<Float>(stridePixels * (0.5 - u), 0)
        }
        let u = (cycle - stanceFraction) / (1 - stanceFraction)
        let eased = smoothStep(0, 1, u)
        let lift = -swingLiftPixels * sin(Float.pi * u)
        return SIMD2<Float>(stridePixels * (-0.5 + eased), lift)
    }

    private static func distanceToGuide(_ p: SIMD2<Float>, _ points: [SIMD2<Float>]) -> (Float, Float) {
        var bestDistance = Float.greatestFiniteMagnitude
        var bestProgress: Float = 0
        for segment in 0..<(points.count - 1) {
            let a = points[segment]
            let b = points[segment + 1]
            let ab = b - a
            let denominator = max(simd_dot(ab, ab), 0.0001)
            let local = min(1, max(0, simd_dot(p - a, ab) / denominator))
            let projected = a + ab * local
            let distance = simd_length(p - projected)
            if distance < bestDistance {
                bestDistance = distance
                bestProgress = (Float(segment) + local) / Float(points.count - 1)
            }
        }
        return (bestDistance, bestProgress)
    }

    private static func smoothStep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func validateTriangles(source: [SIMD2<Float>],
                                          destination: [SIMD2<Float>],
                                          frameIndex: Int) throws -> (positive: Int, nonPositive: Int) {
        var positive = 0
        var nonPositive = 0
        let rowStride = columns + 1
        func twiceArea(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let i0 = row * rowStride + column
                let i1 = i0 + 1
                let i2 = i0 + rowStride + 1
                let i3 = i0 + rowStride
                for triangle in [(i0, i1, i2), (i0, i2, i3)] {
                    let (a, b, c) = triangle
                    let sourceArea = twiceArea(source[a], source[b], source[c])
                    let destArea = twiceArea(destination[a], destination[b], destination[c])
                    if !destArea.isFinite || sourceArea * destArea <= 0 {
                        nonPositive += 1
                        throw BuildError.foldedTriangle(frame: frameIndex,
                                                        cell: row * columns + column)
                    }
                    positive += 1
                }
            }
        }
        return (positive, nonPositive)
    }
}
