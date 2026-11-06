import SpriteKit

/// Authored rest/attack/recoil/celebration frames retain costume and pivot.
/// Technical playback does not imply Human acceptance of generated animation.
@MainActor enum PartyAuthoredMotion {
    private struct Clip {
        let frames:[String],times:[Double],canvas:[Double],anchor:[Double]
        let loop:Bool
    }
    private static let entries:[String:[String:Clip]] = {
        var result:[String:[String:Clip]]=[:]
        for directory in ["PartyRest","PartyAttack"] {
            let prefix="GeneratedArt/"+directory+"/"
            let url=Bundle.main.bundleURL.appendingPathComponent(prefix+"MANIFEST.json")
            guard let data=try? Data(contentsOf:url),let actors=try? JSONSerialization.jsonObject(with:data) as? [String:[String:Any]] else{continue}
            for (actor,entry) in actors {
                guard let clips=entry["clips"] as? [String:[String:Any]],let canvas=entry["canvas"] as? [Double],canvas.count==2,canvas.allSatisfy({$0.isFinite && $0>0}),let anchor=entry["anchor"] as? [Double],anchor.count==2,anchor.allSatisfy({$0.isFinite}) else{continue}
                for (state,clip) in clips {
                    guard let frames=clip["frames"] as? [String],let times=clip["durations"] as? [Double],!frames.isEmpty,frames.count==times.count,times.allSatisfy({$0.isFinite && $0>0}) else{continue}
                    result[actor,default:[:]][state]=Clip(frames:frames.map{prefix+$0},times:times,canvas:canvas,anchor:anchor,loop:clip["loop"] as? Bool == true)
                }
            }
        }
        return result
    }()
    private static var textures:[String:SKTexture]=[:]
    static func play(actor:String,state:String,on node:SKSpriteNode)->Bool {
        guard let clip=entries[actor]?[state] else{return false}
        let frames=clip.frames,times=clip.times,canvas=clip.canvas,anchor=clip.anchor
        let displaySize=CGSize(width:node.size.height*canvas[0]/canvas[1],height:node.size.height)
        var sequence:[SKAction]=[]
        for (index,path) in frames.enumerated() {
            let texture:SKTexture
            if let cached=textures[path]{texture=cached}else{
                let url=Bundle.main.bundleURL.appendingPathComponent(path)
                guard let image=UIImage(contentsOfFile:url.path) else{return false}
                texture=SKTexture(image:image);texture.filteringMode = .linear;textures[path]=texture
            }
            // The Simulator setTexture action reset every actor to 256px even
            // with resize:false (R032 geometry receipt). Retain explicit size.
            sequence.append(.sequence([.run{[weak node] in
                guard let node else{return};node.texture=texture;node.size=displaySize
                ActorBodyFrame.record(path,index:index,on:node)
            },.wait(forDuration:times[index])]))
        }
        node.removeAction(forKey:"party_cast_clip")
        node.size=displaySize
        node.anchorPoint=CGPoint(x:anchor[0]/canvas[0],y:1-anchor[1]/canvas[1])
        let action=SKAction.sequence(sequence)
        node.run(clip.loop ? .repeatForever(action):action,withKey:"party_rest_clip")
        return true
    }
}
