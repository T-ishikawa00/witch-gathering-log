import SpriteKit

/// Body frames and hand registration advance together; staff ownership stays separate.
@MainActor enum LayeredWitchMotion {
    static let entries:[String:[String:Any]] = {
        let file=Bundle.main.bundleURL.appendingPathComponent("GeneratedArt/LayeredMotion/MANIFEST.json")
        guard let data=try? Data(contentsOf:file),let value=try? JSONSerialization.jsonObject(with:data) as? [String:[String:Any]] else{return [:]};return value
    }()
    private static var textures:[String:SKTexture]=[:]
    static func play(costume:String,state:String,on node:SKSpriteNode,attach:@escaping (SKSpriteNode,CGPoint,CGFloat)->Void)->Bool {
        guard let entry=entries[costume],let clip=entry[state] as? [String:Any],let frames=clip["frames"] as? [[String:Any]],!frames.isEmpty else{return false}
        var poses:[(SKTexture,CGPoint,CGFloat)]=[]
        for frame in frames {
            guard let path=frame["path"] as? String,let hand=frame["hand_top_left_px"] as? [Double],hand.count==2 else{return false}
            let tex:SKTexture
            if let cached=textures[path]{tex=cached}else{
                let url=Bundle.main.bundleURL.appendingPathComponent("GeneratedArt/LayeredMotion/"+path)
                guard let image=UIImage(contentsOfFile:url.path) else{return false};tex=SKTexture(image:image);tex.filteringMode = .linear;textures[path]=tex
            }
            poses.append((tex,CGPoint(x:hand[0]/256,y:1-hand[1]/256),CGFloat((frame["angle"] as? Double) ?? 0)))
        }
        node.removeAction(forKey:"party_cast_clip");node.removeAction(forKey:"party_walk_clip")
        node.size.width=node.size.height;node.anchorPoint=CGPoint(x:0.5,y:12.0/256);node.warpGeometry=nil
        let fps=max(1,(clip["fps"] as? Double) ?? 12)
        let durations=clip["durations"] as? [Double]
        let displaySize=node.size
        let actions=poses.enumerated().map{index,pose in
            let (tex,hand,angle)=pose
            let duration=(durations?.count==poses.count ? durations?[index]:nil) ?? 1/fps
            return SKAction.sequence([.run{[weak node] in guard let node else{return};node.texture=tex;node.size=displaySize;attach(node,hand,angle)
                ActorBodyFrame.record("GeneratedArt/LayeredMotion/"+(frames[index]["path"] as? String ?? ""),index:index,on:node)},.wait(forDuration:duration.isFinite && duration>0 ? duration:1/fps)])
        }
        let sequence=SKAction.sequence(actions)
        node.run((clip["loop"] as? Bool)==true ? .repeatForever(sequence):sequence,withKey:state=="walk" ? "party_walk_clip":"party_cast_clip")
        return true
    }
}
