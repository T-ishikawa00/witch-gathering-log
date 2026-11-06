import SpriteKit
import UIKit

/// Candidate body, book and foreground palm share one SpriteKit action clock.
/// The renderer consumes equipped gear only; it cannot grant or mutate ownership.
@MainActor enum LunaBookSpriteMotion {
    private static var textures: [String: SKTexture] = [:]
    private static let bounds: [String: CGRect] = [
        "EQ_A_01": CGRect(x:111,y:137,width:50,height:43),
        "EQ_A_02": CGRect(x:116,y:136,width:41,height:44),
        "EQ_A_03": CGRect(x:113,y:136,width:46,height:44)
    ]
    private static func texture(_ id:String)->SKTexture? {
        if let cached=textures[id] {return cached}
        guard let image=ArtLibrary.image(id) else{return nil}
        let texture=SKTexture(image:image);texture.filteringMode = .linear;textures[id]=texture
        return texture
    }
    /// Exposes the unchanged cache-backed resolver only inside an isolated R010 run.
    static func qaDefaultTextureR010(_ id:String)->SKTexture? {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-luna-book-native-trace-r010") else { return nil }
        return texture(id)
    }
    static func play(state:String,gearID:String,on node:SKSpriteNode,attach:@escaping(CGPoint)->Void)->Bool {
        playResolvedInternalR010(state:state,gearID:gearID,on:node,resolveTexture:texture,attach:attach)
    }

    /// QA-only injection seam. The caller must have --qa-isolated and the
    /// dedicated R010 observer flag; normal play() keeps the original resolver.
    static func playResolvedR010(state:String,gearID:String,on node:SKSpriteNode,
                                 resolveTexture:(String)->SKTexture?,
                                 attach:@escaping(CGPoint)->Void)->Bool {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-luna-book-native-trace-r010") else { return false }
        return playResolvedInternalR010(state:state,gearID:gearID,on:node,resolveTexture:resolveTexture,attach:attach)
    }

    private static func playResolvedInternalR010(state:String,gearID:String,on node:SKSpriteNode,
                                                  resolveTexture:(String)->SKTexture?,
                                                  attach:@escaping(CGPoint)->Void)->Bool {
        let args=ProcessInfo.processInfo.arguments
        let qaTelemetryEnabled=args.contains("--qa-isolated") && args.contains("--qa-luna-book-native-trace-r010")
        let r050Enabled=args.contains("--qa-isolated") && args.contains("--qa-luna-execute-recover-midpoint-r050")
        let r088BridgeEnabled=args.contains("--qa-isolated") && args.contains("--qa-luna-pose-bridge-r088")
        guard let frames=LunaBookMotion.frames(state:state,gearID:gearID,
              includeR050ExecuteRecoverMidpoint:r050Enabled,
              includeR088BridgeAfterMidpoint:r088BridgeEnabled),
              let box=bounds[gearID],let first=frames.first else {
            LunaBookPresentationCleanupR004.clearOwnedPresentation(on: node)
            return false
        }
        guard let bookTexture=resolveTexture(first.attachment.layerAssetID) else {
            LunaBookPresentationCleanupR004.clearOwnedPresentation(on: node)
            return false
        }
        var bodies:[SKTexture]=[]
        for frame in frames {
            guard let body=resolveTexture(frame.bodyAssetID) else {
                LunaBookPresentationCleanupR004.clearOwnedPresentation(on: node)
                return false
            }
            bodies.append(body)
        }
        let cropped=SKTexture(rect:CGRect(x:box.minX/256,y:1-box.maxY/256,width:box.width/256,height:box.height/256),in:bookTexture)
        cropped.filteringMode = .linear
        for key in ["party_walk_clip","party_rest_clip","party_cast_clip"] {node.removeAction(forKey:key)}
        node.size.width=node.size.height;node.anchorPoint=CGPoint(x:0.5,y:12.0/256);node.warpGeometry=nil
        let displaySize=node.size
        let book=(node.childNode(withName:"luna_book") as? SKSpriteNode) ?? SKSpriteNode()
        book.name="luna_book";book.zPosition=1;book.texture=cropped
        if book.parent == nil {node.addChild(book)}
        let palm=(node.childNode(withName:"luna_book_palm") as? SKCropNode) ?? SKCropNode()
        palm.name="luna_book_palm";palm.zPosition=2
        if palm.parent == nil {node.addChild(palm)}
        let foreground=(palm.children.first as? SKSpriteNode) ?? SKSpriteNode()
        if foreground.parent == nil {palm.addChild(foreground)}
        func apply(_ index:Int,to body:SKSpriteNode) {
            let frame=frames[index], transform=frame.attachment.transform, mask=frame.attachment.palmOcclusionMask
            body.texture=bodies[index];body.size=displaySize;body.anchorPoint=CGPoint(x:0.5,y:frame.bodyAnchorY)
            if qaTelemetryEnabled {
                if body.userData == nil { body.userData = NSMutableDictionary() }
                body.userData?["lunaBookR010"] = ["requestedState": frame.requestedState,
                    "poseState": frame.poseState, "frameIndex": frame.frameIndex,
                    "sequenceIndex": frame.sequenceIndex, "durationMilliseconds": frame.durationMilliseconds,
                    "bodyAssetID": frame.bodyAssetID, "bookAssetID": frame.attachment.layerAssetID]
            }
            book.size=CGSize(width:displaySize.width*box.width/256*transform.scale,height:displaySize.height*box.height/256*transform.scale)
            book.position=CGPoint(x:(transform.centerX-body.anchorPoint.x)*displaySize.width,y:(1-transform.centerY-body.anchorPoint.y)*displaySize.height)
            book.zRotation=transform.rotationDegrees * .pi/180
            foreground.texture=bodies[index];foreground.size=displaySize;foreground.anchorPoint=body.anchorPoint
            if qaTelemetryEnabled {
                if book.userData == nil { book.userData = NSMutableDictionary() }
                book.userData?["lunaBookR010"] = ["assetID": frame.attachment.layerAssetID,
                    "frameIndex": frame.frameIndex, "sequenceIndex": frame.sequenceIndex]
                if foreground.userData == nil { foreground.userData = NSMutableDictionary() }
                foreground.userData?["lunaBookR010"] = ["bodyAssetID": frame.bodyAssetID,
                    "frameIndex": frame.frameIndex, "sequenceIndex": frame.sequenceIndex]
            }
            let ellipse=SKShapeNode(ellipseOf:CGSize(width:displaySize.width*mask.radiusX*2,height:displaySize.height*mask.radiusY*2))
            ellipse.fillColor = .white;ellipse.strokeColor = .clear
            let hand=CGPoint(x:mask.centerX,y:1-mask.centerY)
            ellipse.position=CGPoint(x:(hand.x-body.anchorPoint.x)*displaySize.width,y:(hand.y-body.anchorPoint.y)*displaySize.height)
            let maskLayer=SKNode();maskLayer.addChild(ellipse)
            // Keep the book in front of the torso but behind the face and casting
            // forearm. Putting the whole body above it hid the book during casts.
            func addForegroundEllipse(x:Double,y:Double,rx:Double,ry:Double,name:String) {
                let shape=SKShapeNode(ellipseOf:CGSize(width:displaySize.width*rx*2/256,height:displaySize.height*ry*2/256))
                shape.name=name
                shape.fillColor = .white;shape.strokeColor = .clear
                shape.position=CGPoint(x:(x/256-body.anchorPoint.x)*displaySize.width,y:(1-y/256-body.anchorPoint.y)*displaySize.height)
                maskLayer.addChild(shape)
            }
            addForegroundEllipse(x:143,y:112,rx:33,ry:35,name:"face")
            func addForegroundPolygon(_ points:[CGPoint], name:String) {
                guard let first=points.first else { return }
                func convert(_ point:CGPoint)->CGPoint {
                    CGPoint(x:(point.x/256-body.anchorPoint.x)*displaySize.width,
                            y:(1-point.y/256-body.anchorPoint.y)*displaySize.height)
                }
                let path=CGMutablePath()
                path.move(to:convert(first))
                for point in points.dropFirst() { path.addLine(to:convert(point)) }
                path.closeSubpath()
                let shape=SKShapeNode(path:path)
                shape.name=name;shape.fillColor = .white;shape.strokeColor = .clear
                maskLayer.addChild(shape)
            }
            if frame.bodyAssetID == "LUNA_EXEC_RECOVER_BRIDGE_R088_SOURCE" {
                addForegroundPolygon([
                    CGPoint(x:137,y:158),CGPoint(x:139,y:155),CGPoint(x:142,y:154),CGPoint(x:146,y:155),
                    CGPoint(x:150,y:158),CGPoint(x:155,y:159),CGPoint(x:160,y:161),CGPoint(x:164,y:163),
                    CGPoint(x:165,y:166),CGPoint(x:162,y:169),CGPoint(x:156,y:171),CGPoint(x:149,y:171),
                    CGPoint(x:143,y:169),CGPoint(x:138,y:166)
                ], name:"r088_near_palm_finger_contour")
                addForegroundPolygon([
                    CGPoint(x:169,y:153),CGPoint(x:171,y:149),CGPoint(x:174,y:146),CGPoint(x:177,y:143),
                    CGPoint(x:179,y:139),CGPoint(x:182,y:137),CGPoint(x:185,y:139),CGPoint(x:188,y:138),
                    CGPoint(x:191,y:139),CGPoint(x:194,y:142),CGPoint(x:193,y:145),CGPoint(x:197,y:147),
                    CGPoint(x:198,y:150),CGPoint(x:195,y:153),CGPoint(x:191,y:155),CGPoint(x:185,y:156),
                    CGPoint(x:180,y:156),CGPoint(x:175,y:155)
                ], name:"r088_far_curled_finger_contour")
            } else if frame.poseState=="execute" {
                let arms:[(Double,Double,Double,Double)]=[(154,145,37,11),(158,142,38,11),(166,146,36,10)]
                if frame.bodyAssetID == LunaBookMotionDataR050Candidate.bodyAssetID && frame.frameIndex == 3 {
                    // Midpoint-only mask revision: narrower forearm and authored fingers in front of the book.
                    addForegroundEllipse(x:170,y:148,rx:20,ry:7.5,name:"r050_execute_forearm_candidate")
                    addForegroundPolygon([
                        CGPoint(x:177,y:151), CGPoint(x:180,y:147), CGPoint(x:181,y:142),
                        CGPoint(x:183,y:139), CGPoint(x:186,y:143), CGPoint(x:188,y:136),
                        CGPoint(x:191,y:134), CGPoint(x:193,y:142), CGPoint(x:196,y:137),
                        CGPoint(x:199,y:139), CGPoint(x:198,y:146), CGPoint(x:202,y:145),
                        CGPoint(x:204,y:148), CGPoint(x:203,y:152), CGPoint(x:200,y:155),
                        CGPoint(x:196,y:158), CGPoint(x:191,y:160), CGPoint(x:186,y:159),
                        CGPoint(x:181,y:156)
                    ], name:"r050_outstretched_hand_candidate")
                } else {
                    let a=arms[min(2,frame.frameIndex)];addForegroundEllipse(x:a.0,y:a.1,rx:a.2,ry:a.3,name:"execute_forearm")
                }
            }
            palm.maskNode=maskLayer
            attach(hand)
            ActorBodyFrame.record(frame.bodyAssetID,index:frame.frameIndex,on:body)
        }
        apply(0,to:node)
        let sequence=SKAction.sequence(frames.enumerated().flatMap { index,frame in
            [SKAction.run{[weak node] in guard let node else{return};apply(index,to:node)},.wait(forDuration:Double(frame.durationMilliseconds)/1000)]
        })
        node.run(["idle","walk"].contains(state) ? .repeatForever(sequence):sequence,withKey:state=="walk" ? "party_walk_clip":"party_cast_clip")
        return true
    }
}
