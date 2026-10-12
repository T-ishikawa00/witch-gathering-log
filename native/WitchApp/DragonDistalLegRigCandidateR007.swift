import Foundation
import SpriteKit
import CoreGraphics
import ImageIO
import CryptoKit
import simd

/// Off-glob R007 experiment: keeps the original torso/upper legs and partitions
/// only four source-pixel distal leg regions into movable exact-pixel textures.
/// No generated art is consumed and this type is not wired into PartRig.
public enum DragonDistalLegRigCandidateR007 {
    public static let candidateID = "dragon_distal_leg_rig_r007"
    public static let sourceSHA256 = "66cb4bc19239fb91808e163a0bceb88cf2016bc52dbfcb3dd45045f28af83065"
    public static let sourcePixels = SIMD2<Int>(455, 157)
    public static let nominalCanvas = CGSize(width: 455, height: 157)
    public static let sourcePixelsPerCanvasPoint: CGFloat = 1
    public static let duration: TimeInterval = 1.2
    public static let stanceFraction: CGFloat = 0.62

    public struct Point: Codable, Equatable {
        public let x: CGFloat
        public let y: CGFloat // nominal source-canvas pixels, origin top-left
        public init(_ x: CGFloat, _ y: CGFloat) { self.x = x; self.y = y }
    }

    public struct Segment: Codable, Equatable {
        public let id: String
        public let pivot: Point
        public let polygon: [Point] // nominal canvas; partition mask, not an art edit
        public let phase: CGFloat
        public let jointOverlapShift: Point // static opaque underlap into the knee seam
        public let rotationDegrees: CGFloat
        public let zOrderCandidate: Int
    }

    // Polygons follow visible source pixels around the four lower-leg/foot
    // silhouettes. Top edges are proposed knee seams and require art review.
    // They are deliberately disjoint in canvas X to preserve exact ownership.
    public static let segments: [Segment] = [
        Segment(id: "left_outer_distal", pivot: Point(40.5, 118.0), polygon: [
            Point(34.5,116.5), Point(46.5,119.5), Point(47,123), Point(51,128),
            Point(56,132), Point(58,137), Point(57,143), Point(53,149),
            Point(48,154), Point(43,156), Point(38,153), Point(34,149),
            Point(31,151), Point(28,156), Point(23,154), Point(19,150),
            Point(14,149), Point(10,153), Point(5,151), Point(1,148),
            Point(0,144), Point(2,140), Point(6,136), Point(12,133),
            Point(19,131), Point(25,127), Point(29,122), Point(31,119)
        ], phase: 0.0, jointOverlapShift: Point(0.0,2.0), rotationDegrees: 8.0, zOrderCandidate: 2),
        Segment(id: "left_inner_distal", pivot: Point(117.5, 118.0), polygon: [
            Point(105.5,115.5), Point(129.5,119), Point(131,123), Point(136,128),
            Point(140,132), Point(144,137), Point(144,142), Point(141,148),
            Point(137,153), Point(131,156), Point(125,156), Point(120,153),
            Point(116,156), Point(110,154), Point(106,150), Point(101,149),
            Point(98,151), Point(93,150), Point(89,147), Point(89,143),
            Point(91,138), Point(95,134), Point(99,131), Point(102,126),
            Point(104,121)
        ], phase: 0.5, jointOverlapShift: Point(0.0,2.0), rotationDegrees: -8.0, zOrderCandidate: 3),
        Segment(id: "right_inner_distal", pivot: Point(170.0, 116.0), polygon: [
            Point(162,111), Point(176,112), Point(178,117), Point(183,121),
            Point(188,126), Point(192,131), Point(193,136), Point(191,140),
            Point(187,143), Point(182,142), Point(177,139), Point(173,141),
            Point(168,139), Point(164,141), Point(160,139), Point(155,137),
            Point(154,133), Point(157,129), Point(160,125)
        ], phase: 0.5, jointOverlapShift: Point(0.0,2.0), rotationDegrees: -6.0, zOrderCandidate: 1),
        Segment(id: "right_outer_distal", pivot: Point(237.0, 117.0), polygon: [
            Point(228,116), Point(246,118), Point(249,122), Point(253,127),
            Point(257,131), Point(262,135), Point(265,139), Point(265,145),
            Point(262,151), Point(258,155), Point(252,157), Point(248,154),
            Point(244,151), Point(241,157), Point(235,156), Point(232,152),
            Point(228,155), Point(222,155), Point(218,152), Point(215,147),
            Point(215,142), Point(217,138), Point(221,135), Point(224,130),
            Point(226,125)
        ], phase: 0.0, jointOverlapShift: Point(0.0,2.0), rotationDegrees: 8.0, zOrderCandidate: 2)
    ]

    public enum BuildError: Error, Equatable {
        case wrongSourceDimensions
        case sourceHashMismatch
        case unsupportedPixelFormat
        case overlappingSegmentMasks(Int, Int)
        case emptyMask(String)
        case failedImageCreation
    }

    public struct Partition {
        public let body: CGImage
        public let segments: [String: CGImage]
        public let ownedPixelCounts: [String: Int]
        public let totalMaskedPixelCount: Int
        public let jointOverlapPixelCounts: [String: Int]
        public let recompositionByteMismatchCount: Int
    }

    /// Decodes the exact source file into a known top-left RGBA buffer and
    /// copies original premultiplied texels into one static base and four parts.
    /// It neither stores a modified asset nor interpolates/resamples pixels.
    public static func partition(source: CGImage, sourceData: Data) throws -> Partition {
        guard sha256(sourceData) == sourceSHA256 else { throw BuildError.sourceHashMismatch }
        guard source.width == sourcePixels.x, source.height == sourcePixels.y else {
            throw BuildError.wrongSourceDimensions
        }
        var original = try rgbaTopLeft(source)
        let bytesPerPixel = 4
        let totalPixels = source.width * source.height
        var owner = Array(repeating: -1, count: totalPixels)
        let scale = sourcePixelsPerCanvasPoint
        for (partIndex, segment) in segments.enumerated() {
            for y in 0..<source.height {
                for x in 0..<source.width {
                    let point = CGPoint(x: (CGFloat(x) + 0.5) / scale,
                                        y: (CGFloat(y) + 0.5) / scale)
                    guard contains(point, polygon: segment.polygon) else { continue }
                    let index = y * source.width + x
                    if owner[index] >= 0 {
                        throw BuildError.overlappingSegmentMasks(owner[index], partIndex)
                    }
                    owner[index] = partIndex
                }
            }
        }
        var base = original
        var parts = Array(repeating: Data(count: original.count), count: segments.count)
        var counts = Array(repeating: 0, count: segments.count)
        var overlapCounts = Array(repeating: 0, count: segments.count)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let pixel=y*source.width+x, offset=pixel*bytesPerPixel
                let partIndex=owner[pixel]
                let point=CGPoint(x:(CGFloat(x)+0.5)/scale,y:(CGFloat(y)+0.5)/scale)
                if partIndex >= 0 {
                    counts[partIndex] += 1
                    parts[partIndex].replaceSubrange(offset..<(offset+bytesPerPixel), with: original[offset..<(offset+bytesPerPixel)])
                    if contains(point, polygon: overlapBand(segments[partIndex])) && original[offset+3] >= 252 {
                        // Keep source texels under the moving segment as a static hinge cover.
                        overlapCounts[partIndex] += 1
                    } else {
                        base.replaceSubrange(offset..<(offset+bytesPerPixel), with: [0,0,0,0])
                    }
                }
            }
        }
        guard counts.allSatisfy({ $0 > 0 }) else {
            let missing = counts.firstIndex(of: 0) ?? 0
            throw BuildError.emptyMask(segments[missing].id)
        }
        var recomposed = base
        for bytes in parts {
            for index in stride(from: 0, to: bytes.count, by: bytesPerPixel) where bytes[index+3] > 0 {
                // Disjoint pixel ownership means source bytes can be restored exactly.
                recomposed.replaceSubrange(index..<(index+bytesPerPixel), with: bytes[index..<(index+bytesPerPixel)])
            }
        }
        var mismatch = 0
        for i in original.indices where original[i] != recomposed[i] { mismatch += 1 }
        guard let bodyImage = makeCGImage(bytes: base, width: source.width, height: source.height) else {
            throw BuildError.failedImageCreation
        }
        var segmentImages: [String: CGImage] = [:]
        for (i, segment) in segments.enumerated() {
            guard let image = makeCGImage(bytes: parts[i], width: source.width, height: source.height) else {
                throw BuildError.failedImageCreation
            }
            segmentImages[segment.id] = image
        }
        original.removeAll(keepingCapacity: false)
        return Partition(body: bodyImage, segments: segmentImages,
                         ownedPixelCounts: Dictionary(uniqueKeysWithValues: zip(segments.map(\.id), counts)),
                         totalMaskedPixelCount: counts.reduce(0,+),
                         jointOverlapPixelCounts: Dictionary(uniqueKeysWithValues: zip(segments.map(\.id), overlapCounts)),
                         recompositionByteMismatchCount: mismatch)
    }

    @MainActor
    public static func makeRig(source: CGImage, sourceData: Data) throws -> SKNode {
        let partition = try self.partition(source: source, sourceData: sourceData)
        let rig = SKNode(); rig.name = candidateID
        let body = SKSpriteNode(texture: SKTexture(cgImage: partition.body), size: nominalCanvas)
        body.name = "body4legs_tail_static_except_distal_masks"; body.anchorPoint = CGPoint(x:0.5,y:0.5); body.zPosition = 0
        rig.addChild(body)
        for segment in segments.sorted(by: { $0.zOrderCandidate < $1.zOrderCandidate }) {
            guard let cg = partition.segments[segment.id] else { continue }
            let pivot = SKNode(); pivot.name = "pivot_\(segment.id)"
            let pivotLocal = CGPoint(x: segment.pivot.x - nominalCanvas.width/2,
                                     y: nominalCanvas.height/2 - segment.pivot.y)
            pivot.position = pivotLocal
            pivot.zPosition = CGFloat(segment.zOrderCandidate) * 0.001
            let sprite = SKSpriteNode(texture: SKTexture(cgImage: cg), size: nominalCanvas)
            sprite.name = "distal_\(segment.id)"; sprite.anchorPoint = CGPoint(x:0.5,y:0.5)
            sprite.position = CGPoint(x:-pivotLocal.x,y:-pivotLocal.y)
            pivot.addChild(sprite); rig.addChild(pivot)
        }
        return rig
    }

    @MainActor
    public static func applyPose(to rig: SKNode, elapsed: TimeInterval) {
        let cycle = max(0, elapsed).truncatingRemainder(dividingBy: duration) / duration
        for segment in segments {
            guard let pivot = rig.childNode(withName: "pivot_\(segment.id)") else { continue }
            let phase = (cycle + segment.phase).truncatingRemainder(dividingBy: 1)
            guard phase > stanceFraction else {
                pivot.zRotation = 0; pivot.position = pivot.positionFor(segment.pivot)
                continue
            }
            let swing = (phase - stanceFraction) / (1 - stanceFraction)
            let wave = sin(.pi * swing)
            let sign: CGFloat = segment.phase == 0 ? 1 : -1
            let pivotRest = CGPoint(x:segment.pivot.x-nominalCanvas.width/2,
                                    y:nominalCanvas.height/2-segment.pivot.y)
            // Hinge only: no independent translation that could detach the knee seam.
            pivot.position = pivotRest
            pivot.zRotation = sign * segment.rotationDegrees * wave * .pi / 180
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data:data).map { String(format:"%02x", $0) }.joined()
    }

    private static func overlapBand(_ segment: Segment) -> [Point] {
        guard segment.polygon.count >= 3 else { return [] }
        let a=segment.polygon[0], b=segment.polygon[1], shift=segment.jointOverlapShift
        // The polygon's interior follows its top seam toward the distal paw.
        return [a,b,Point(b.x+shift.x,b.y+shift.y),Point(a.x+shift.x,a.y+shift.y)]
    }

    private static func contains(_ p: CGPoint, polygon: [Point]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            let crosses = ((a.y > p.y) != (b.y > p.y)) &&
                (p.x < (b.x-a.x) * (p.y-a.y) / ((b.y-a.y) == 0 ? .leastNonzeroMagnitude : (b.y-a.y)) + a.x)
            if crosses { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func rgbaTopLeft(_ image: CGImage) throws -> Data {
        let width=image.width, height=image.height, row=width*4
        var bytes=Data(count:row*height)
        let info=CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let ok=bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base=raw.baseAddress,
                  let ctx=CGContext(data:base,width:width,height:height,bitsPerComponent:8,bytesPerRow:row,
                                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            return true
        }
        guard ok else { throw BuildError.unsupportedPixelFormat }
        return bytes
    }

    private static func makeCGImage(bytes: Data, width: Int, height: Int) -> CGImage? {
        guard let provider=CGDataProvider(data:bytes as CFData) else { return nil }
        let info=CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue))
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
                       space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info,provider:provider,
                       decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
}

private extension SKNode {
    func positionFor(_ point: DragonDistalLegRigCandidateR007.Point) -> CGPoint {
        CGPoint(x:point.x-DragonDistalLegRigCandidateR007.nominalCanvas.width/2,
                y:DragonDistalLegRigCandidateR007.nominalCanvas.height/2-point.y)
    }
}
