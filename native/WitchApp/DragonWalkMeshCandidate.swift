import Foundation
import SpriteKit
import simd

/// Unapproved R004 full-body gait geometry for ACT_B_R04_B.
/// This value only creates mesh keyframes; callers remain responsible for
/// explicitly opting into it and restoring the source texture's nil warp.
@MainActor
public struct DragonWalkMeshCandidate {
    public static let candidateID = "dragon_walk_mesh_r004"
    public static let status = "UNAPPROVED_TEST_OVERLAY"
    public static let bodyPartID = "body4legs_tail"
    public static let gridDimensions = SIMD2<Int>(32, 12) // faces
    public static let vertexCount = 429
    public static let duration: TimeInterval = 1.2

    public let times: [NSNumber]
    public let grids: [SKWarpGeometryGrid]
    public let sourcePositions: [SIMD2<Float>]
    public let maxConfiguredDeltaPixels: SIMD2<Float>

    public enum ConstructionError: Error, Equatable {
        case invalidGridDimensions
        case wrongVertexCount(expected: Int, actual: Int)
        case nonFiniteVertex(frame: Int, vertex: Int)
        case invalidTriangle(frame: Int, cell: Int)
        case invalidKeyframeSchedule
    }

    private struct Limb {
        let id: String
        let x0: Float
        let x1: Float
        let core0: Float
        let core1: Float
        let hipY: Float
        let distalY: Float
        let phase: Float
        let stride: Float
        let lift: Float
    }

    private static let bodyWidth: Float = 455
    private static let bodyHeight: Float = 157
    private static let columns = 32
    private static let rows = 12
    private static let amplitudeScale: Float = 1.5

    // These are the R004 engineering supports, not authored anatomical masks.
    private static let limbs: [Limb] = [
        .init(id: "fore_far_candidate", x0: 0, x1: 85, core0: 4, core1: 70,
              hipY: 79, distalY: 118, phase: 0.00, stride: 1.6, lift: 1.6),
        .init(id: "fore_near_candidate", x0: 85, x1: 145, core0: 92, core1: 138,
              hipY: 78, distalY: 119, phase: 0.50, stride: 2.2, lift: 2.2),
        .init(id: "hind_far_candidate", x0: 145, x1: 204, core0: 152, core1: 198,
              hipY: 80, distalY: 119, phase: 0.25, stride: 1.4, lift: 1.4),
        .init(id: "hind_near_candidate", x0: 204, x1: 284, core0: 212, core1: 276,
              hipY: 82, distalY: 119, phase: 0.75, stride: 2.0, lift: 2.0)
    ]

    public init() throws {
        guard Self.columns == Self.gridDimensions.x,
              Self.rows == Self.gridDimensions.y else {
            throw ConstructionError.invalidGridDimensions
        }

        let source = Self.makeSourceGrid()
        guard source.count == Self.vertexCount else {
            throw ConstructionError.wrongVertexCount(expected: Self.vertexCount, actual: source.count)
        }

        var generatedGrids: [SKWarpGeometryGrid] = []
        var generatedTimes: [NSNumber] = []
        var largest = SIMD2<Float>(repeating: 0)

        for frame in 0...12 {
            // Match R004's Float operation order exactly: Float(period) * Float(i) / 12.
            let time = Float(Self.duration) * Float(frame) / 12
            let destination = Self.makeDestinationGrid(time: time, source: source)
            try Self.validate(source: source, destination: destination, frame: frame)
            for index in source.indices {
                largest.x = max(largest.x, abs(destination[index].x - source[index].x) * Self.bodyWidth)
                largest.y = max(largest.y, abs(destination[index].y - source[index].y) * Self.bodyHeight)
            }
            generatedGrids.append(SKWarpGeometryGrid(
                __columns: Self.columns,
                rows: Self.rows,
                sourcePositions: source,
                destPositions: destination
            ))
            generatedTimes.append(NSNumber(value: Double(time)))
        }

        guard generatedGrids.count == 13,
              generatedTimes.count == 13,
              generatedTimes.first?.doubleValue == 0,
              generatedTimes.last?.doubleValue == Double(Float(Self.duration)) else {
            throw ConstructionError.invalidKeyframeSchedule
        }

        sourcePositions = source
        grids = generatedGrids
        times = generatedTimes
        maxConfiguredDeltaPixels = largest
    }

    /// Read a compact snapshot from SpriteKit's current node getter. Vertices
    /// are restricted to the lower body rows and the four candidate leg bands.
    /// This reports the node's current mesh property; it is not GPU raster data.
    public static func readbackSnapshot(from node: SKSpriteNode) -> ReadbackSnapshot? {
        guard let geometry = node.warpGeometry as? SKWarpGeometryGrid,
              geometry.vertexCount == vertexCount else { return nil }

        let xs = sourceGridXCoordinates()
        let yTop = sourceGridTopYCoordinates()
        var source: [SIMD2<Float>] = []
        var destination: [SIMD2<Float>] = []
        source.reserveCapacity(vertexCount)
        destination.reserveCapacity(vertexCount)
        var maxAllVertexDelta = SIMD2<Float>(repeating: 0)

        for index in 0..<vertexCount {
            let sourcePoint = geometry.sourcePosition(at: index)
            let destinationPoint = geometry.destPosition(at: index)
            guard sourcePoint.x.isFinite, sourcePoint.y.isFinite,
                  destinationPoint.x.isFinite, destinationPoint.y.isFinite else { return nil }
            let deltaX = (destinationPoint.x - sourcePoint.x) * bodyWidth
            let deltaY = (sourcePoint.y - destinationPoint.y) * bodyHeight
            maxAllVertexDelta.x = max(maxAllVertexDelta.x, abs(deltaX))
            maxAllVertexDelta.y = max(maxAllVertexDelta.y, abs(deltaY))
            source.append(sourcePoint)
            destination.append(destinationPoint)
        }

        let lowerIndices = sourceIndices(columns: xs, rowsTop: yTop)
        var maxLowerDelta = SIMD2<Float>(repeating: 0)
        for index in lowerIndices {
            let deltaX = (destination[index].x - source[index].x) * bodyWidth
            let deltaY = (source[index].y - destination[index].y) * bodyHeight
            maxLowerDelta.x = max(maxLowerDelta.x, abs(deltaX))
            maxLowerDelta.y = max(maxLowerDelta.y, abs(deltaY))
        }

        let sampleVertices = lowerReadbackSamples(xs: xs, rowsTop: yTop).map { sample in
            let index = sample.index
            let sourcePoint = source[index]
            let destinationPoint = destination[index]
            return ReadbackVertex(legID: sample.legID,
                                  landmark: sample.landmark,
                                  index: index,
                                  sourceArtworkPixels: sample.artworkPoint,
                                  sourceNormalized: [sourcePoint.x, sourcePoint.y],
                                  destinationNormalized: [destinationPoint.x, destinationPoint.y],
                                  deltaArtworkPixels: [(destinationPoint.x - sourcePoint.x) * bodyWidth,
                                                       (sourcePoint.y - destinationPoint.y) * bodyHeight])
        }

        let triangleCounts = triangleAreaCounts(source: source, destination: destination)
        return ReadbackSnapshot(candidateID: candidateID,
                                bodyPartID: bodyPartID,
                                gridFaces: [columns, rows],
                                totalVertexCount: geometry.vertexCount,
                                finiteVertexCount: source.count,
                                lowerVertexCountUsedForMaxDelta: lowerIndices.count,
                                positiveTriangleCount: triangleCounts.positive,
                                nonPositiveTriangleCount: triangleCounts.nonPositive,
                                totalTriangleCount: triangleCounts.total,
                                sampledLowerVertexCount: sampleVertices.count,
                                sampledLowerVertices: sampleVertices,
                                maxAllVertexDeltaArtworkPixels: [maxAllVertexDelta.x, maxAllVertexDelta.y],
                                maxLowerDeltaArtworkPixels: [maxLowerDelta.x, maxLowerDelta.y])
    }

    public struct ReadbackSnapshot: Codable, Equatable {
        public let candidateID: String
        public let bodyPartID: String
        public let gridFaces: [Int]
        public let totalVertexCount: Int
        public let finiteVertexCount: Int
        public let lowerVertexCountUsedForMaxDelta: Int
        public let positiveTriangleCount: Int
        public let nonPositiveTriangleCount: Int
        public let totalTriangleCount: Int
        public let sampledLowerVertexCount: Int
        public let sampledLowerVertices: [ReadbackVertex]
        public let maxAllVertexDeltaArtworkPixels: [Float]
        public let maxLowerDeltaArtworkPixels: [Float]
    }

    public struct ReadbackVertex: Codable, Equatable {
        public let legID: String
        public let landmark: String
        public let index: Int
        public let sourceArtworkPixels: [Float]
        public let sourceNormalized: [Float]
        public let destinationNormalized: [Float]
        public let deltaArtworkPixels: [Float]
    }

    private struct ReadbackSample {
        let legID: String
        let landmark: String
        let artworkPoint: [Float]
        let index: Int
    }

    private static func makeSourceGrid() -> [SIMD2<Float>] {
        // Exact R004 nonuniform grid coordinates in top-left artwork pixels.
        let xs = sourceGridXCoordinates()
        let yTop = sourceGridTopYCoordinates()
        precondition(xs.count == columns + 1 && yTop.count == rows + 1)

        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity(vertexCount)
        for row in 0...rows {
            let normalizedY = 1 - yTop[rows - row] / bodyHeight
            for col in 0...columns {
                positions.append(SIMD2(xs[col] / bodyWidth, normalizedY))
            }
        }
        return positions
    }

    private static func sourceGridXCoordinates() -> [Float] {
        [0, 16, 32, 48, 64, 72, 78, 85, 90, 96, 102, 108, 114, 120, 128, 136, 142,
         145, 151, 158, 166, 174, 182, 190, 198, 204, 210, 220, 230, 240, 260, 284, 455]
    }

    private static func sourceGridTopYCoordinates() -> [Float] {
        [0, 50, 65, 72, 78, 82, 90, 100, 110, 119, 128, 140, 157]
    }

    private static func sourceIndices(columns xs: [Float], rowsTop: [Float]) -> [Int] {
        // Keep y >= 72px (the lower-body band) and x within the authored grid's
        // four leg-support span. This intentionally excludes upper-body points.
        let selectedColumns = xs.indices.filter { xs[$0] <= 284 }
        let selectedRows = (0...rows).filter { rowsTop[$0] >= 72 }
        var result: [Int] = []
        result.reserveCapacity(selectedColumns.count * selectedRows.count)
        for topRow in selectedRows {
            let spriteKitRow = rows - topRow
            for col in selectedColumns {
                result.append(spriteKitRow * (columns + 1) + col)
            }
        }
        return result
    }

    private static func lowerReadbackSamples(xs: [Float], rowsTop: [Float]) -> [ReadbackSample] {
        // Four reproducible mesh samples per candidate support: one proximal
        // reference plus knee/ankle/paw-height rows. These are mesh sample
        // locations, not claims of authored anatomical landmarks.
        let samples: [(String, String, Float, Float)] = [
            ("fore_far_candidate", "proximal_reference", 48, 82),
            ("fore_far_candidate", "knee_height", 48, 110),
            ("fore_far_candidate", "ankle_height", 48, 128),
            ("fore_far_candidate", "paw_height", 48, 140),
            ("fore_near_candidate", "proximal_reference", 114, 82),
            ("fore_near_candidate", "knee_height", 114, 110),
            ("fore_near_candidate", "ankle_height", 114, 128),
            ("fore_near_candidate", "paw_height", 114, 140),
            ("hind_far_candidate", "proximal_reference", 174, 82),
            ("hind_far_candidate", "knee_height", 174, 110),
            ("hind_far_candidate", "ankle_height", 174, 128),
            ("hind_far_candidate", "paw_height", 174, 140),
            ("hind_near_candidate", "proximal_reference", 240, 82),
            ("hind_near_candidate", "knee_height", 240, 110),
            ("hind_near_candidate", "ankle_height", 240, 128),
            ("hind_near_candidate", "paw_height", 240, 140)
        ]

        return samples.map { legID, landmark, x, y in
            let col = xs.enumerated().min { abs($0.element - x) < abs($1.element - x) }!.offset
            let topRow = rowsTop.enumerated().min { abs($0.element - y) < abs($1.element - y) }!.offset
            let spriteKitRow = rows - topRow
            return ReadbackSample(legID: legID,
                                  landmark: landmark,
                                  artworkPoint: [xs[col], rowsTop[topRow]],
                                  index: spriteKitRow * (columns + 1) + col)
        }
    }

    private static func triangleAreaCounts(source: [SIMD2<Float>],
                                           destination: [SIMD2<Float>]) -> (positive: Int, nonPositive: Int, total: Int) {
        func signedDoubleArea(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        var positive = 0
        var nonPositive = 0
        for row in 0..<rows {
            for col in 0..<columns {
                let bottomLeft = row * (columns + 1) + col
                let bottomRight = bottomLeft + 1
                let topLeft = bottomLeft + columns + 1
                let topRight = topLeft + 1
                let triangles = [(bottomLeft, bottomRight, topRight),
                                 (bottomLeft, topRight, topLeft),
                                 (bottomLeft, bottomRight, topLeft),
                                 (bottomRight, topRight, topLeft)]
                for triangle in triangles {
                    let sourceArea = signedDoubleArea(source[triangle.0], source[triangle.1], source[triangle.2])
                    let destinationArea = signedDoubleArea(destination[triangle.0], destination[triangle.1], destination[triangle.2])
                    if sourceArea > 0 && destinationArea > 0 { positive += 1 }
                    else { nonPositive += 1 }
                }
            }
        }
        return (positive, nonPositive, columns * rows * 4)
    }

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func gait(_ phase: Float) -> (stride: Float, swing: Float) {
        let p = phase - floor(phase)
        let stance: Float = 0.68
        if p < stance {
            let u = p / stance
            let eased = u * u * (3 - 2 * u)
            return (1 - 2 * eased, 0)
        }
        let u = (p - stance) / (1 - stance)
        let eased = u * u * (3 - 2 * u)
        return (-1 + 2 * eased, pow(sin(Float.pi * u), 2))
    }

    private static func makeDestinationGrid(time: Float, source: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var destination = source
        let normalizedTime = time / Float(duration)

        for limb in limbs {
            let motion = gait(normalizedTime + limb.phase)
            for index in source.indices {
                let original = source[index]
                let x = original.x * bodyWidth
                let yTop = (1 - original.y) * bodyHeight
                let horizontal = smooth(limb.x0, limb.core0, x)
                    * (1 - smooth(limb.core1, limb.x1, x))
                let vertical = smooth(limb.hipY, limb.hipY + 29, yTop)
                let weight = horizontal * vertical
                let dx = amplitudeScale * limb.stride * motion.stride * weight
                // Convert top-left positive-down motion to normalized SpriteKit y-up.
                let dyTop = -amplitudeScale * limb.lift * motion.swing * weight
                destination[index] = SIMD2(destination[index].x + dx / bodyWidth,
                                           destination[index].y - dyTop / bodyHeight)
            }
        }
        return destination
    }

    private static func validate(source: [SIMD2<Float>],
                                 destination: [SIMD2<Float>],
                                 frame: Int) throws {
        guard source.count == vertexCount, destination.count == vertexCount else {
            throw ConstructionError.wrongVertexCount(expected: vertexCount,
                                                     actual: min(source.count, destination.count))
        }
        for index in source.indices {
            let a = source[index], b = destination[index]
            guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else {
                throw ConstructionError.nonFiniteVertex(frame: frame, vertex: index)
            }
        }

        func signedDoubleArea(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        for row in 0..<rows {
            for col in 0..<columns {
                let bottomLeft = row * (columns + 1) + col
                let bottomRight = bottomLeft + 1
                let topLeft = bottomLeft + columns + 1
                let topRight = topLeft + 1
                let triangles = [(bottomLeft, bottomRight, topRight),
                                 (bottomLeft, topRight, topLeft),
                                 (bottomLeft, bottomRight, topLeft),
                                 (bottomRight, topRight, topLeft)]
                for triangle in triangles {
                    let sourceArea = signedDoubleArea(source[triangle.0], source[triangle.1], source[triangle.2])
                    let destinationArea = signedDoubleArea(destination[triangle.0], destination[triangle.1], destination[triangle.2])
                    guard sourceArea > 0, destinationArea > 0 else {
                        throw ConstructionError.invalidTriangle(frame: frame, cell: row * columns + col)
                    }
                }
            }
        }
    }
}
