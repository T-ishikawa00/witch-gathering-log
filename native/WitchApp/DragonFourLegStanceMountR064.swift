import Foundation
import SpriteKit
import UIKit
import ImageIO
import CryptoKit


/// iOS SpriteKit adapter candidate for the R064 canonical-pixel four-leg schedule.
/// No viewport padding is applied here: source points map through the manifest
/// part pivot and body size. The host preview's 8 px capture border is not rig geometry.
/// R068 selects this as a local Simulator candidate after canonical-source checks.
/// Non-Simulator builds retain the existing backend pending native quality acceptance.
@MainActor
final class DragonFourLegStanceMountR064 {
    static let candidateID = "dragon_four_leg_stance_r064"
    static let sourceRelativePath = "GeneratedCandidates/ACT_B_R04_B/rig_candidate_r001/parts/body4legs_tail_part_r001.png"
    static let actionKey = "witch.enemy.part-rig.walk-four-leg-r064"
    static let sourceSHA256 = "66cb4bc19239fb91808e163a0bceb88cf2016bc52dbfcb3dd45045f28af83065"
    static let width = 455
    static let height = 157

    private struct Leg {
        let id: String
        let polygon: [(CGFloat, CGFloat)]
        let topEdge: [(CGFloat, CGFloat)]
        let hip: CGPoint
        let knee: CGPoint
        let ankle: CGPoint
        let toe: CGPoint
        let schedule: GaitContactScheduleR064.LegID
        let z: CGFloat
    }
    private struct RigNodes {
        let upperPivot: SKNode
        let lowerPivot: SKNode
        let wristPivot: SKNode
        let homeWrist: CGPoint
        let toeLocal: CGPoint
    }
    private static let legs: [Leg] = [
        Leg(id:"fore_far",polygon:[(0,106),(10,82),(24,69),(49,67),(64,78),(61,101),(57,116),(78,132),(82,146),(72,155),(8,155),(0,147)],topEdge:[(0,106),(10,89),(22,82),(38,81),(52,85),(64,96),(72,113),(82,132)],hip:CGPoint(x:52,y:85),knee:CGPoint(x:37,y:116),ankle:CGPoint(x:28,y:136),toe:CGPoint(x:5,y:147),schedule:.foreFar,z:0.2),
        Leg(id:"fore_near",polygon:[(70,107),(76,79),(95,58),(121,55),(143,69),(150,92),(141,111),(154,127),(164,140),(161,155),(84,156),(74,147),(92,127),(81,116)],topEdge:[(70,108),(76,93),(84,80),(95,73),(108,72),(124,76),(139,86),(151,105),(164,140)],hip:CGPoint(x:111,y:79),knee:CGPoint(x:112,y:111),ankle:CGPoint(x:119,y:138),toe:CGPoint(x:90,y:150),schedule:.foreNear,z:0.4),
        Leg(id:"hind_far",polygon:[(143,115),(149,86),(166,68),(194,67),(211,82),(215,103),(209,121),(225,134),(228,148),(214,156),(148,156),(139,145),(162,115)],topEdge:[(139,133),(148,111),(160,96),(174,88),(190,87),(202,93),(214,107),(228,134)],hip:CGPoint(x:190,y:88),knee:CGPoint(x:174,y:111),ankle:CGPoint(x:177,y:130),toe:CGPoint(x:153,y:139),schedule:.hindFar,z:0.1),
        Leg(id:"hind_near",polygon:[(203,118),(205,90),(221,71),(248,70),(265,85),(270,106),(282,122),(290,140),(284,154),(210,155),(199,145),(216,125)],topEdge:[(199,137),(208,117),(218,99),(232,91),(247,91),(262,100),(274,114),(290,140)],hip:CGPoint(x:247,y:91),knee:CGPoint(x:241,y:114),ankle:CGPoint(x:241,y:138),toe:CGPoint(x:216,y:150),schedule:.hindNear,z:0.3)
    ]

    let bodyPart: SKSpriteNode
    let originalTexture: SKTexture
    let staticCoreTexture: SKTexture
    let sourceSHA256Readback: String
    let anchorCanvas: CGPoint
    let displayScale: CGPoint
    let recompositionByteMismatchCount: Int
    private let nodes: [String: RigNodes]
    private(set) var isMounted = false
    private(set) var isAnimating = false
    private var currentElapsed: TimeInterval = 0

    var originalTextureRestored: Bool { bodyPart.texture === originalTexture }
    var staticCoreInstalled: Bool { bodyPart.texture === staticCoreTexture }

    init?(bodyPart: SKSpriteNode, artRoot: URL, anchorCanvas: CGPoint) {
        let sourceURL = artRoot.appendingPathComponent(Self.sourceRelativePath)
        guard let data = try? Data(contentsOf: sourceURL),
              Self.sha256(data) == Self.sourceSHA256,
              let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let source = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              source.width == Self.width, source.height == Self.height,
              let existing = bodyPart.texture,
              abs(anchorCanvas.x - 178) < 0.01, abs(anchorCanvas.y - 56) < 0.01,
              bodyPart.size.width.isFinite, bodyPart.size.height.isFinite,
              bodyPart.size.width > 0, bodyPart.size.height > 0,
              abs(bodyPart.size.width / bodyPart.size.height - CGFloat(Self.width)/CGFloat(Self.height)) < 0.01,
              let partition = try? Self.partition(source: source),
              partition.mismatch == 0 else { return nil }
        self.bodyPart = bodyPart
        self.originalTexture = existing
        self.staticCoreTexture = SKTexture(cgImage: partition.core)
        self.staticCoreTexture.filteringMode = .linear
        self.sourceSHA256Readback = Self.sourceSHA256
        self.anchorCanvas = anchorCanvas
        self.displayScale = CGPoint(x: bodyPart.size.width / CGFloat(Self.width), y: bodyPart.size.height / CGFloat(Self.height))
        self.recompositionByteMismatchCount = partition.mismatch

        var built: [String: RigNodes] = [:]
        for leg in Self.legs {
            guard let slices = partition.slices[leg.id], slices.count == 3 else { return nil }
            let upper = Self.partNode(mask: slices[0], body: bodyPart,
                                      pivot: leg.hip, name: "r064_\(leg.id)_upper", z: leg.z)
            upper.position = Self.localPoint(leg.hip, anchor: anchorCanvas, scale: displayScale)
            let lower = SKNode()
            lower.name = "r064_\(leg.id)_knee"
            lower.zPosition = leg.z + 0.01
            lower.position = Self.localPoint(leg.knee, anchor: anchorCanvas, scale: displayScale)
            let lowerSlice = Self.partNode(mask: slices[1], body: bodyPart,
                                           pivot: leg.knee, name: "r064_\(leg.id)_lower", z: 0)
            lower.addChild(lowerSlice)
            let wrist = SKNode()
            wrist.name = "r064_\(leg.id)_wrist"
            let wristHome = CGPoint(x: (leg.ankle.x - leg.knee.x) * displayScale.x,
                                    y: -(leg.ankle.y - leg.knee.y) * displayScale.y)
            wrist.position = wristHome
            let foot = Self.partNode(mask: slices[2], body: bodyPart,
                                     pivot: leg.ankle, name: "r064_\(leg.id)_foot", z: 0.02)
            wrist.addChild(foot)
            lower.addChild(wrist)
            built[leg.id] = RigNodes(upperPivot: upper, lowerPivot: lower,
                                     wristPivot: wrist, homeWrist: wristHome,
                                     toeLocal: CGPoint(x: (leg.toe.x-leg.ankle.x)*displayScale.x,
                                                       y: -(leg.toe.y-leg.ankle.y)*displayScale.y))
        }
        self.nodes = built
    }

    func mount() -> Bool {
        guard !isMounted, bodyPart.texture === originalTexture,
              nodes.count == Self.legs.count else { return false }
        bodyPart.texture = staticCoreTexture
        for leg in Self.legs.sorted(by: { $0.z < $1.z }) {
            guard let rig = nodes[leg.id] else { unmount(); return false }
            bodyPart.addChild(rig.upperPivot)
            bodyPart.addChild(rig.lowerPivot)
        }
        isMounted = Self.legs.allSatisfy { nodes[$0.id]?.upperPivot.parent === bodyPart && nodes[$0.id]?.lowerPivot.parent === bodyPart }
        if !isMounted { unmount() }
        return isMounted
    }

    func applyPose(elapsed: TimeInterval) {
        guard isMounted, elapsed.isFinite else { return }
        isAnimating = true
        currentElapsed = elapsed
        for leg in Self.legs {
            guard let rig = nodes[leg.id],
                  let pose = GaitContactScheduleR064.sample(at: elapsed, leg: leg.schedule) else { continue }
            rig.lowerPivot.zRotation = CGFloat(pose.lowerAngleRadians)
            rig.wristPivot.zRotation = CGFloat(pose.wristAngleRadians)
            rig.wristPivot.position = CGPoint(
                x: rig.homeWrist.x + CGFloat(pose.wristOffset.x + pose.toeOffset.x) * displayScale.x,
                y: rig.homeWrist.y + CGFloat(pose.wristOffset.y + pose.toeOffset.y) * displayScale.y)
        }
    }

    func unmount() {
        bodyPart.removeAction(forKey: Self.actionKey)
        for rig in nodes.values {
            rig.upperPivot.removeAllActions(); rig.lowerPivot.removeAllActions(); rig.wristPivot.removeAllActions()
            rig.upperPivot.removeFromParent(); rig.lowerPivot.removeFromParent()
            rig.lowerPivot.zRotation = 0; rig.wristPivot.zRotation = 0; rig.wristPivot.position = rig.homeWrist
        }
        if bodyPart.texture === staticCoreTexture { bodyPart.texture = originalTexture }
        isMounted = false
        isAnimating = false
        currentElapsed = 0
    }

    func startLoop() -> Bool {
        guard isMounted else { return false }
        bodyPart.removeAction(forKey: Self.actionKey)
        let action = SKAction.customAction(withDuration: GaitContactScheduleR064.periodSeconds) { [weak self] _, elapsed in
            self?.applyPose(elapsed: Double(elapsed))
        }
        bodyPart.run(.repeatForever(action), withKey: Self.actionKey)
        return bodyPart.action(forKey: Self.actionKey) != nil
    }

    var pivotReadback: [[String: Any]] {
        Self.legs.map { leg in
            let rig = nodes[leg.id]
            let upperParented = rig?.upperPivot.parent === bodyPart
            let lowerParented = rig?.lowerPivot.parent === bodyPart
            let wristParented = rig?.wristPivot.parent === rig?.lowerPivot
            let fullyMounted = upperParented && lowerParented && wristParented
            let measuredToe = fullyMounted
                ? rig?.wristPivot.convert(rig?.toeLocal ?? .zero, to: bodyPart)
                : Self.localPoint(leg.toe, anchor: anchorCanvas, scale: displayScale)
            let toeFinite = measuredToe.map { $0.x.isFinite && $0.y.isFinite } ?? false
            let toeValue: Any = toeFinite
                ? [Double(measuredToe!.x), Double(measuredToe!.y)]
                : NSNull()
            return ["legID": leg.id,
                    "upperAttached": upperParented,
                    "lowerAttached": lowerParented,
                    "wristAttached": wristParented,
                    "readbackSpace": fullyMounted ? "mounted_body_local" : "neutral_source_projection",
                    "hipSourcePx": [Double(leg.hip.x), Double(leg.hip.y)],
                    "kneeSourcePx": [Double(leg.knee.x), Double(leg.knee.y)],
                    "ankleSourcePx": [Double(leg.ankle.x), Double(leg.ankle.y)],
                    "toeSourcePx": [Double(leg.toe.x), Double(leg.toe.y)],
                    "lowerAngleRadians": Double(rig?.lowerPivot.zRotation ?? 0),
                    "wristAngleRadians": Double(rig?.wristPivot.zRotation ?? 0),
                    "toeBodyLocal": toeValue,
                    "toeReadbackFinite": toeFinite,
                    "stance": GaitContactScheduleR064.sample(at: currentElapsed, leg: leg.schedule)?.isStance ?? false]
        }
    }

    /// Same-render callback readback. `scenePoint` includes the root's current
    /// battle-entry translation and the body/leg transforms; it is a SpriteKit
    /// scene coordinate, not a physical ground-contact assertion.
    func entryToeSnapshot(in scene: SKScene) -> [String: Any] {
        let rows = pivotReadback.map { row -> [String: Any] in
            var output = row
            if let local = row["toeBodyLocal"] as? [Double], local.count == 2,
               local.allSatisfy({ $0.isFinite }) {
                let point = bodyPart.convert(CGPoint(x: local[0], y: local[1]), to: scene)
                let viewPoint = scene.convertPoint(toView: point)
                output["scenePoint"] = [Double(point.x), Double(point.y)]
                output["viewPoint"] = [Double(viewPoint.x), Double(viewPoint.y)]
                output["scenePointFinite"] = point.x.isFinite && point.y.isFinite
            } else {
                output["scenePoint"] = NSNull()
                output["viewPoint"] = NSNull()
                output["scenePointFinite"] = false
            }
            output["stanceKnown"] = isMounted && isAnimating
            return output
        }
        return ["schema": "dragon-normal-entry-world-toe-r068-r001",
                "sourceSHA256": sourceSHA256Readback,
                "sourceRelativePath": Self.sourceRelativePath,
                "canvas": [Self.width, Self.height],
                "coordinateSpace": "SpriteKit scene coordinates after actions and root compensation",
                "pointSemantics": "candidate source-pixel toe proxies; not physical ground truth",
                "mounted": isMounted, "animating": isAnimating,
                "periodSeconds": GaitContactScheduleR064.periodSeconds,
                "elapsedSeconds": currentElapsed,
                "cycleElapsedSeconds": currentElapsed.truncatingRemainder(dividingBy: GaitContactScheduleR064.periodSeconds),
                "cyclePhase": currentElapsed.truncatingRemainder(dividingBy: GaitContactScheduleR064.periodSeconds) / GaitContactScheduleR064.periodSeconds,
                "legs": rows]
    }

    /// Comparison-only legacy readback uses the same four canonical toe proxy
    /// pixels through the existing body transform, with no candidate leg motion.
    static func sourceToeSnapshot(bodyPart: SKSpriteNode, anchorCanvas: CGPoint,
                                  scene: SKScene) -> [String: Any] {
        let scale = CGPoint(x: bodyPart.size.width / CGFloat(width),
                            y: bodyPart.size.height / CGFloat(height))
        let rows: [[String: Any]] = legs.map { leg in
            let local = localPoint(leg.toe, anchor: anchorCanvas, scale: scale)
            let point = bodyPart.convert(local, to: scene)
            let viewPoint = scene.convertPoint(toView: point)
            return ["legID": leg.id, "toeSourcePx": [Double(leg.toe.x), Double(leg.toe.y)],
                    "toeBodyLocal": [Double(local.x), Double(local.y)],
                    "scenePoint": [Double(point.x), Double(point.y)],
                    "viewPoint": [Double(viewPoint.x), Double(viewPoint.y)],
                    "stanceKnown": false, "readbackSpace": "legacy_source_projection"]
        }
        return ["schema": "dragon-normal-entry-world-toe-r068-r001",
                "sourceSHA256": sourceSHA256, "sourceRelativePath": Self.sourceRelativePath,
                "canvas": [width, height], "coordinateSpace": "SpriteKit scene coordinates after actions",
                "pointSemantics": "same candidate source-pixel toe proxies projected through legacy body transform; not physical ground truth",
                "mounted": false, "animating": false, "stanceKnown": false, "legs": rows]
    }

    /// Exposes only validated pivot sprites/nodes for the off-live R068 entry
    /// footpath adapter. No node is created, reparented, or mutated here.
    func entryLegBindingsR068R002() -> [String: DragonEntryFootpathSpriteKitAdapterR068R002.LegNodes]? {
        guard isMounted, bodyPart.texture === staticCoreTexture,
              sourceSHA256Readback == DragonEntryFootpathSpriteKitAdapterR068R002.sourceSHA256,
              nodes.count == Self.legs.count else { return nil }
        var result: [String: DragonEntryFootpathSpriteKitAdapterR068R002.LegNodes] = [:]
        for leg in Self.legs {
            guard let rig = nodes[leg.id],
                  let upperSprite = rig.upperPivot as? SKSpriteNode,
                  upperSprite.parent === bodyPart,
                  rig.lowerPivot.parent === bodyPart,
                  rig.wristPivot.parent === rig.lowerPivot else { return nil }
            result[leg.id] = .init(upperPivot: upperSprite, lowerPivot: rig.lowerPivot,
                wristPivot: rig.wristPivot, hip: leg.hip, knee: leg.knee,
                ankle: leg.ankle, toe: leg.toe)
        }
        return result.count == 4 ? result : nil
    }

    private static func partNode(mask: CGImage, body: SKSpriteNode,
                                 pivot: CGPoint, name: String, z: CGFloat) -> SKNode {
        // `mask` is already a disjoint, alpha-bearing RGBA partition of the
        // canonical source. Applying it again as an SKCropNode mask would
        // multiply edge alpha (a*a/255) and create dark/semitransparent seams.
        // Render this partition directly as a sprite instead.
        let a = CGPoint(x: pivot.x / CGFloat(width), y: 1 - pivot.y / CGFloat(height))
        let partitionSprite = SKSpriteNode(texture: SKTexture(cgImage: mask), size: body.size)
        partitionSprite.name = name
        partitionSprite.zPosition = z
        partitionSprite.anchorPoint = a
        partitionSprite.position = .zero
        return partitionSprite
    }

    private static func localPoint(_ p: CGPoint, anchor: CGPoint, scale: CGPoint) -> CGPoint {
        DragonFourLegCoordinateContractR064.bodyLocal(
            p, anchor: anchor,
            size: CGSize(width: scale.x*CGFloat(width), height: scale.y*CGFloat(height)))
    }

    private struct Partition { let core: CGImage; let slices: [String: [CGImage]]; let mismatch: Int }

    private static func partition(source: CGImage) throws -> Partition {
        let w = source.width, h = source.height
        guard w == width, h == height,
              let color = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                  bytesPerRow: w*4, space: color,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NSError(domain:"R064",code:1) }
        // Keep CGImage's pixel row order. The UIImage-backed source and the
        // SKTexture(cgImage:) outputs use the same orientation; flipping this
        // context here inverts every partition relative to the canonical body.
        context.draw(source, in: CGRect(x:0,y:0,width:w,height:h))
        guard let ptr = context.data else { throw NSError(domain:"R064",code:2) }
        let original = Data(bytes: ptr, count: w*h*4)
        let rgba = [UInt8](original)
        var owner = Array(repeating: -1, count: w*h)
        for (i, leg) in legs.enumerated() {
            for y in 0..<h { for x in 0..<w {
                let p = CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)
                guard polygonContains(p, leg.polygon), p.y >= edgeY(p.x, leg.topEdge) else { continue }
                let idx=y*w+x
                if owner[idx] < 0 || distanceToAxis(p, leg) < distanceToAxis(p, legs[owner[idx]]) { owner[idx]=i }
            }}
        }
        var classes = [[[Bool]]](); classes.reserveCapacity(legs.count)
        for (legIndex, leg) in legs.enumerated() {
            let kneeT = projection(leg.knee, leg), ankleT = projection(leg.ankle, leg)
            let ranges: [ClosedRange<CGFloat>] = [
                0...min(1,kneeT+0.10), max(0,kneeT-0.07)...min(1,ankleT+0.10), max(0,ankleT-0.07)...CGFloat.infinity
            ]
            var three = ranges.map { _ in Array(repeating:false,count:w*h) }
            for y in 0..<h { for x in 0..<w {
                let idx=y*w+x
                guard owner[idx] == legIndex else { continue }
                let t=projection(CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5),leg)
                for slice in ranges.indices where ranges[slice].contains(t) { three[slice][idx]=true }
            }}
            classes.append(three)
        }
        var core = Array(repeating: UInt8(0), count: w*h*4)
        var sliceData = legs.map { _ in (0..<3).map { _ in Array(repeating:UInt8(0),count:w*h*4) } }
        for pixel in 0..<(w*h) {
            let ownerID=owner[pixel]
            var sliceID:Int? = nil
            if ownerID >= 0 {
                for candidate in 0..<3 where classes[ownerID][candidate][pixel] { sliceID=candidate; break }
            }
            let offset=pixel*4
            if sliceID == nil { core.replaceSubrange(offset..<offset+4,with:rgba[offset..<offset+4]) }
            else { sliceData[ownerID][sliceID!].replaceSubrange(offset..<offset+4,with:rgba[offset..<offset+4]) }
        }
        var recomposed=core
        for leg in sliceData { for bytes in leg { for pixel in 0..<(w*h) where bytes[pixel*4+3] > 0 {
            let o=pixel*4;recomposed.replaceSubrange(o..<o+4,with:bytes[o..<o+4])
        }}}
        let mismatch=zip(rgba,recomposed).reduce(0){$0 + ($1.0 == $1.1 ? 0:1)}
        func image(_ bytes:[UInt8])->CGImage? {
            let d=Data(bytes)
            guard let provider=CGDataProvider(data:d as CFData) else{return nil}
            return CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:color,
                           bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,
                           decode:nil,shouldInterpolate:false,intent:.defaultIntent)
        }
        guard let coreImage=image(core) else{throw NSError(domain:"R064",code:3)}
        var result:[String:[CGImage]]=[:]
        for i in legs.indices {
            let rendered=try sliceData[i].map { bytes -> CGImage in guard let i=image(bytes) else{throw NSError(domain:"R064",code:4)};return i }
            result[legs[i].id]=rendered
        }
        return Partition(core:coreImage,slices:result,mismatch:mismatch)
    }

    private static func polygonContains(_ p:CGPoint,_ poly:[(CGFloat,CGFloat)])->Bool {
        var inside=false,j=poly.count-1
        for i in poly.indices { let a=poly[i],b=poly[j]
            if (a.1>p.y) != (b.1>p.y), p.x < (b.0-a.0)*(p.y-a.1)/(b.1-a.1)+a.0 { inside.toggle() };j=i
        };return inside
    }
    private static func edgeY(_ x:CGFloat,_ points:[(CGFloat,CGFloat)])->CGFloat {
        guard let f=points.first,let l=points.last else{return .infinity};if x<=f.0{return f.1};if x>=l.0{return l.1}
        for i in 0..<(points.count-1){let a=points[i],b=points[i+1];if x>=a.0 && x<=b.0{let t=(x-a.0)/(b.0-a.0);return a.1+(b.1-a.1)*t}};return l.1
    }
    private static func projection(_ p:CGPoint,_ leg:Leg)->CGFloat {
        let dx=leg.toe.x-leg.hip.x,dy=leg.toe.y-leg.hip.y,d=dx*dx+dy*dy
        guard d>0 else{return 0};return ((p.x-leg.hip.x)*dx+(p.y-leg.hip.y)*dy)/d
    }
    private static func distanceToAxis(_ p:CGPoint,_ leg:Leg)->CGFloat {
        let dx=leg.toe.x-leg.hip.x,dy=leg.toe.y-leg.hip.y,d=dx*dx+dy*dy
        guard d>0 else{return .infinity};let t=max(0,min(1,((p.x-leg.hip.x)*dx+(p.y-leg.hip.y)*dy)/d))
        let x=p.x-(leg.hip.x+t*dx),y=p.y-(leg.hip.y+t*dy);return x*x+y*y
    }
    private static func sha256(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
}

/// Simulator-only exact QA gate. Any conflicting art-audit mode is rejected.
enum DragonFourLegStanceR064QA {
    static let flag = "--qa-dragon-fourleg-r064"
    static func isEnabled(arguments:[String]=ProcessInfo.processInfo.arguments, actorID:String="ACT_B_R04_B")->Bool {
        #if targetEnvironment(simulator)
        let keys=arguments.filter{$0.hasPrefix("--qa-save-key=")}
        let key=keys.first.flatMap{$0.split(separator:"=",maxSplits:1).last.map(String.init)} ?? ""
        let forbidden=["--qa-dragon-distal-leg-r007","--qa-dragon-gait-r038","--qa-dragon-mesh-r004","--qa-dragon-mesh-pause-probe","--qa-loop-boundary-trace"]
        let allowedQA:Set<String>=["--qa-isolated",flag,"--qa-dragon-gait-r038-sequence-probe"]
        let unexpectedQA=arguments.filter{$0.hasPrefix("--qa-") && !allowedQA.contains($0) && !$0.hasPrefix("--qa-save-key=")}
        return actorID == "ACT_B_R04_B" && arguments.contains("--qa-isolated") && arguments.contains(flag) &&
            arguments.contains("--art-audit=ACT_B_R04_B") && keys.count == 1 &&
            arguments.filter({$0 == "--qa-isolated"}).count == 1 && arguments.filter({$0 == flag}).count == 1 &&
            arguments.filter({$0 == "--art-audit=ACT_B_R04_B"}).count == 1 && unexpectedQA.isEmpty &&
            key.count >= 12 && key.count <= 64 && key.unicodeScalars.allSatisfy{CharacterSet.alphanumerics.contains($0) || $0 == "-"} &&
            !forbidden.contains(where:arguments.contains)
        #else
        return false
        #endif
    }
}
