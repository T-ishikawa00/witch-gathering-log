import SpriteKit

/// Candidate registration for the two authored ally-transfer paths. Original
/// textures stay intact. Pixel coordinates use the 128px image's top-left origin.
@MainActor enum TransferPathGeometry {
    static let startNodeName = "transfer_path_start"
    static let endNodeName = "transfer_path_end"
    static let arrivalNodeName = "transfer_path_arrival"
    static let noticeAnchorNodeName = "transfer_path_notice_anchor"
    static let noticeNodeName = "transfer_path_notice"
    static let noticeLifetime: TimeInterval = 0.45
    static let noticeWidth: CGFloat = 34
    static let noticeHeight: CGFloat = 20

    static func pixelAnchors(id: String) -> (start: CGPoint, end: CGPoint)? {
        switch id {
        // Both authored highlights move right to left. The highlight fades
        // before reaching the far endpoint; impact adds a local arrival accent.
        case "ACT_E_R02_04_support_arc":
            return (CGPoint(x: 94, y: 59), CGPoint(x: 31, y: 58))
        case "ACT_E_R05_03_light_transfer":
            return (CGPoint(x: 102, y: 52), CGPoint(x: 28, y: 68))
        default: return nil
        }
    }

    static func parentPoint(_ local: CGPoint, on node: SKNode) -> CGPoint {
        let x = local.x * node.xScale, y = local.y * node.yScale
        let c = cos(node.zRotation), s = sin(node.zRotation)
        return CGPoint(x: node.position.x + x*c - y*s,
                       y: node.position.y + x*s + y*c)
    }

    static func apply(to node: SKSpriteNode, id: String, origin: CGPoint,
                      destination: CGPoint) -> [String: Any]? {
        guard let pixels = pixelAnchors(id: id),
              [origin.x,origin.y,destination.x,destination.y,node.size.width,node.size.height].allSatisfy({$0.isFinite}),
              node.size.width > 0, node.size.height > 0 else { return nil }
        func local(_ pixel: CGPoint) -> CGPoint {
            CGPoint(x:(pixel.x/128-node.anchorPoint.x)*node.size.width,
                    y:(1-pixel.y/128-node.anchorPoint.y)*node.size.height)
        }
        let start = local(pixels.start), end = local(pixels.end)
        let ax = end.x-start.x, ay = end.y-start.y
        let dx = destination.x-origin.x, dy = destination.y-origin.y
        let authoredDistance = hypot(ax,ay), distance = hypot(dx,dy)
        guard authoredDistance > 0.001, distance > 1 else { return nil }
        let scale = distance/authoredDistance
        guard scale.isFinite else { return nil }
        node.zRotation = atan2(dy,dx)-atan2(ay,ax)
        node.setScale(scale)
        node.position = .zero
        let offset = parentPoint(start,on:node)
        node.position = CGPoint(x:origin.x-offset.x,y:origin.y-offset.y)
        for name in [startNodeName,endNodeName,arrivalNodeName,noticeAnchorNodeName,noticeNodeName] {
            node.childNode(withName:name)?.removeFromParent()
        }
        for (name,point) in [(startNodeName,start),(endNodeName,end)] {
            let marker=SKNode();marker.name=name;marker.position=point;node.addChild(marker)
        }
        let actualStart=parentPoint(start,on:node),actualEnd=parentPoint(end,on:node)
        return ["transferPathRegistered":true,"transferPathCandidate":"measured_endpoints_r001",
                "pathSourcePixelX":pixels.start.x,"pathSourcePixelY":pixels.start.y,
                "pathTargetPixelX":pixels.end.x,"pathTargetPixelY":pixels.end.y,
                "pathStartX":actualStart.x,"pathStartY":actualStart.y,
                "pathEndX":actualEnd.x,"pathEndY":actualEnd.y,
                "pathExpectedStartX":origin.x,"pathExpectedStartY":origin.y,
                "pathExpectedEndX":destination.x,"pathExpectedEndY":destination.y,
                "pathScale":scale,"rotation":node.zRotation,"scaleX":node.xScale]
    }

    /// The effect is not attached to the scene yet during placement. Convert
    /// its future parent coordinates explicitly instead of converting across
    /// two unrelated SpriteKit trees.
    static func registerNoticeAnchor(on node: SKSpriteNode, point: CGPoint) -> [String: Any] {
        guard [point.x,point.y,node.xScale,node.yScale,node.zRotation].allSatisfy({$0.isFinite}),
              abs(node.xScale)>0.001,abs(node.yScale)>0.001 else{return [:]}
        let dx=point.x-node.position.x,dy=point.y-node.position.y
        let c=cos(node.zRotation),s=sin(node.zRotation)
        let anchor=SKNode();anchor.name=noticeAnchorNodeName
        anchor.position=CGPoint(x:(dx*c+dy*s)/node.xScale,y:(-dx*s+dy*c)/node.yScale)
        node.childNode(withName:noticeAnchorNodeName)?.removeFromParent()
        node.addChild(anchor)
        let actual=parentPoint(anchor.position,on:node)
        return ["pathNoticeX":actual.x,"pathNoticeY":actual.y]
    }

    static func presentationDuration(id: String, on node: SKSpriteNode,
                                     clipDuration: TimeInterval) -> TimeInterval {
        pixelAnchors(id:id) != nil && node.childNode(withName:noticeAnchorNodeName) != nil
            ? max(clipDuration,noticeLifetime) : clipDuration
    }

    /// Child of the existing budgeted effect, so it follows cancellation,
    /// scene pause and parent cleanup without adding a third combat effect.
    static func showArrival(on node: SKSpriteNode, id: String, duration: TimeInterval) {
        guard pixelAnchors(id:id) != nil,
              let endpoint=node.childNode(withName:endNodeName),
              node.xScale.isFinite,abs(node.xScale)>0.001,duration>0 else{return}
        node.childNode(withName:arrivalNodeName)?.removeFromParent()
        let group=SKNode();group.name=arrivalNodeName;group.position=endpoint.position
        // Compensate for the registered path's scale to keep this accent 7pt
        // at every source/recipient distance.
        group.setScale(1/abs(node.xScale))
        let backing=SKShapeNode(circleOfRadius:7)
        backing.strokeColor=SKColor(red:0.12,green:0.17,blue:0.20,alpha:0.9)
        backing.lineWidth=3.5;backing.fillColor = .clear
        let rim=SKShapeNode(circleOfRadius:7)
        rim.strokeColor=SKColor(red:1.0,green:0.88,blue:0.56,alpha:1)
        rim.lineWidth=1.5;rim.fillColor = .clear
        group.addChild(backing);group.addChild(rim);node.addChild(group)
        let life=min(0.3,duration)
        group.run(.sequence([.wait(forDuration:life*0.55),
                             .fadeOut(withDuration:life*0.45),.removeFromParent()]))
        guard let anchor=node.childNode(withName:noticeAnchorNodeName) else{return}
        node.childNode(withName:noticeNodeName)?.removeFromParent()
        let notice=SKNode();notice.name=noticeNodeName;notice.position=anchor.position
        notice.zRotation = -node.zRotation
        notice.setScale(1/abs(node.xScale));notice.zPosition=2
        let noticeBacking=SKShapeNode(rectOf:CGSize(width:noticeWidth,height:noticeHeight),cornerRadius:6)
        noticeBacking.fillColor=SKColor(red:0.06,green:0.13,blue:0.16,alpha:0.98)
        noticeBacking.strokeColor=SKColor(red:0.58,green:0.91,blue:0.88,alpha:1)
        noticeBacking.lineWidth=1.2;notice.addChild(noticeBacking)
        let label=SKLabelNode(fontNamed:"HiraginoSans-W6")
        label.text="支援";label.fontSize=11;label.fontColor = .white
        label.verticalAlignmentMode = .center;label.horizontalAlignmentMode = .center
        label.zPosition=1;notice.addChild(label);node.addChild(notice)
        notice.run(.sequence([.wait(forDuration:noticeLifetime*2/3),
                              .fadeOut(withDuration:noticeLifetime/3),.removeFromParent()]))
    }
}
