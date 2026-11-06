import SpriteKit

/// Generated in-betweens are an unapproved animation candidate. The original
/// six poses remain the idle/hit/recover/resolve fallback and are not overwritten.
@MainActor enum CharacterClips {
    static let entries:[String:[String:Any]]={
        let file=Bundle.main.bundleURL.appendingPathComponent("GeneratedArt/PartyMotion/MANIFEST.json")
        guard let data=try? Data(contentsOf:file),let entries=try? JSONSerialization.jsonObject(with:data) as? [String:[String:Any]] else{return [:]}
        return entries
    }()
    static var textures:[String:SKTexture]=[:]
    static func play(actor:String,state:String,on node:SKSpriteNode)->Bool {
        node.removeAction(forKey:"party_cast_clip")
        guard state=="anticipate" || state=="execute",let entry=entries[actor] else{return false}
        let names=(entry["exported_frames"] as? [String] ?? []).map{String($0.dropLast(4))}
        let selected=names.filter{name in
            let index=Int(name.components(separatedBy:"_").last ?? "") ?? 0
            return state=="anticipate" ? index<3:index>=3
        }
        let sequence=selected.compactMap{name->SKTexture? in
            if let texture=textures[name]{return texture}
            guard let image=ArtLibrary.image(name) else{return nil}
            let texture=SKTexture(image:image);texture.filteringMode = .linear;textures[name]=texture;return texture
        }
        guard !sequence.isEmpty else{return false}
        if let canvas=entry["canvas"] as? [Double],canvas.count==2 {node.size.width=node.size.height*canvas[0]/canvas[1]}
        if let anchor=entry["foot_anchor"] as? [Double],let canvas=entry["canvas"] as? [Double],anchor.count==2,canvas.count==2 {node.anchorPoint=CGPoint(x:anchor[0]/canvas[0],y:1-anchor[1]/canvas[1])}
        guard sequence.count==selected.count else{return false}
        node.texture=sequence[0]
        ActorBodyFrame.record(selected[0],on:node)
        let displaySize=node.size
        let actions=SKAction.sequence(sequence.enumerated().flatMap { index,texture in
            [SKAction.run { [weak node] in
                guard let node else{return};node.texture=texture;node.size=displaySize
                ActorBodyFrame.record(selected[index],index:index,on:node)
            },.wait(forDuration:0.28/Double(sequence.count))]
        })
        node.run(actions,withKey:"party_cast_clip")
        return true
    }
}
