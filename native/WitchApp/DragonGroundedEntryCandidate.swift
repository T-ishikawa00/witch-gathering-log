import Foundation
import SpriteKit
import simd

/// UNAPPROVED entry-only geometry experiment derived from the existing R004 walk.
/// It does not alter the source texture or the normal walk/flight candidate.
@MainActor
public struct DragonGroundedEntryCandidate {
    public static let candidateID = "dragon_grounded_entry_r005"
    public static let status = "UNAPPROVED_TEST_OVERLAY"
    public static let bodyPartID = DragonWalkMeshCandidate.bodyPartID
    public static let referenceVertexIndex = 34
    public static let gridDimensions = DragonWalkMeshCandidate.gridDimensions
    public static let vertexCount = DragonWalkMeshCandidate.vertexCount
    public static let duration: TimeInterval = 0.6

    public let times: [NSNumber]
    public let grids: [SKWarpGeometryGrid]
    public let sourcePositions: [SIMD2<Float>]
    public let maxConfiguredDeltaPixels: SIMD2<Float>
    public let totalTriangleCount: Int

    public enum ConstructionError: Error, Equatable {
        case wrongSourceGrid
        case invalidKeyframeSchedule
        case nonFiniteVertex(frame: Int, vertex: Int)
        case invalidTriangle(frame: Int, sample: Int, cell: Int)
        case endpointsNotIdentity
    }

    /// Reuses R004's actual source/keyframe grids. The endpoint keys are forced
    /// to identity; all horizontal keys, including frame zero, apply the requested
    /// endpoint-relative correction. The caller must compensate the initial root
    /// offset using the reference vertex. Vertical displacement follows R004
    /// through 0.4s and eases to identity over the final 0.2s.
    public init() throws {
        let walk = try DragonWalkMeshCandidate()
        guard walk.grids.count == 13,
              walk.sourcePositions.count == Self.vertexCount,
              walk.grids.allSatisfy({ $0.vertexCount == Self.vertexCount }) else {
            throw ConstructionError.wrongSourceGrid
        }
        let source = walk.sourcePositions
        let endpoint = walk.grids[6]
        var built: [SKWarpGeometryGrid] = []
        var builtTimes: [NSNumber] = []
        var maxDelta = SIMD2<Float>(repeating: 0)

        for frame in 0...6 {
            let r004 = walk.grids[frame]
            let time = Float(DragonWalkMeshCandidate.duration) * Float(frame) / 12
            let verticalFade = time <= 0.4 ? Float(1) : 1 - Self.smooth(0.4, 0.6, time)
            var destination: [SIMD2<Float>] = []
            destination.reserveCapacity(Self.vertexCount)

            for index in source.indices {
                let origin = source[index]
                let r004Point = r004.destPosition(at: index)
                let endpointPoint = endpoint.destPosition(at: index)
                let r004DX = (r004Point.x - origin.x) * 455
                let r004DY = (origin.y - r004Point.y) * 157
                let endpointDX = (endpointPoint.x - origin.x) * 455

                var dx = -r004DX + endpointDX
                var dy = r004DY * verticalFade
                if frame == 6 {
                    dx = 0
                    dy = 0
                }
                let point = SIMD2(origin.x + dx / 455, origin.y - dy / 157)
                guard point.x.isFinite, point.y.isFinite else {
                    throw ConstructionError.nonFiniteVertex(frame: frame, vertex: index)
                }
                maxDelta.x = max(maxDelta.x, abs(dx))
                maxDelta.y = max(maxDelta.y, abs(dy))
                destination.append(point)
            }

            try Self.validate(source: source, destination: destination, frame: frame, sample: 0)
            built.append(SKWarpGeometryGrid(
                __columns: Self.gridDimensions.x,
                rows: Self.gridDimensions.y,
                sourcePositions: source,
                destPositions: destination
            ))
            builtTimes.append(NSNumber(value: Double(time)))
        }

        guard built.count == 7,
              builtTimes.count == 7,
              builtTimes.first?.doubleValue == 0,
              builtTimes.last?.doubleValue == Double(Float(DragonWalkMeshCandidate.duration) * 6 / 12) else {
            throw ConstructionError.invalidKeyframeSchedule
        }
        // Only the 0.6s endpoint returns to the unwarped idle geometry. The
        // first frame is deliberately non-identity and is root-compensated by
        // the caller using referenceVertexIndex.
        for endpointIndex in [6] {
            for index in source.indices {
                let point = built[endpointIndex].destPosition(at: index)
                guard point == source[index] else { throw ConstructionError.endpointsNotIdentity }
            }
        }

        times = builtTimes
        grids = built
        sourcePositions = source
        maxConfiguredDeltaPixels = maxDelta
        totalTriangleCount = Self.gridDimensions.x * Self.gridDimensions.y * 4
    }

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func signedDoubleArea(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func validate(source: [SIMD2<Float>], destination: [SIMD2<Float>],
                                 frame: Int, sample: Int) throws {
        let columns = gridDimensions.x
        let rows = gridDimensions.y
        for row in 0..<rows {
            for col in 0..<columns {
                let lowerLeft = row * (columns + 1) + col
                let lowerRight = lowerLeft + 1
                let upperLeft = lowerLeft + columns + 1
                let upperRight = upperLeft + 1
                let triangles = [(lowerLeft, lowerRight, upperRight),
                                 (lowerLeft, upperRight, upperLeft),
                                 (lowerLeft, lowerRight, upperLeft),
                                 (lowerRight, upperRight, upperLeft)]
                for (triangleIndex, triangle) in triangles.enumerated() {
                    let sourceArea = signedDoubleArea(source[triangle.0], source[triangle.1], source[triangle.2])
                    let destinationArea = signedDoubleArea(destination[triangle.0], destination[triangle.1], destination[triangle.2])
                    guard sourceArea.isFinite, destinationArea.isFinite,
                          sourceArea > 0, destinationArea > 0 else {
                        throw ConstructionError.invalidTriangle(frame: frame, sample: sample,
                                                                cell: (row * columns + col) * 4 + triangleIndex)
                    }
                }
            }
        }
    }
}
