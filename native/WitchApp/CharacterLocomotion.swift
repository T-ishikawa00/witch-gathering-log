import SpriteKit

/// Added candidate gait drawings, registered to the approved 256px foot canvas.
@MainActor enum CharacterLocomotion {
    static let entries:[String:[String:Any]] = {
        let file=Bundle.main.bundleURL.appendingPathComponent("GeneratedArt/PartyWalk/MANIFEST.json")
        guard let data=try? Data(contentsOf:file),let value=try? JSONSerialization.jsonObject(with:data) as? [String:[String:Any]] else{return [:]}
        return value
    }()
    private static var textures:[String:SKTexture]=[:]
    static func play(actor:String,on node:SKSpriteNode)->Bool {
        guard let entry=entries[actor],let paths=entry["frames"] as? [String],!paths.isEmpty else{return false}
        let frames=paths.compactMap{path->SKTexture? in
            if let texture=textures[path]{return texture}
            let file=Bundle.main.bundleURL.appendingPathComponent("GeneratedArt/PartyWalk/"+path)
            guard let image=UIImage(contentsOfFile:file.path) else{return nil}
            let texture=SKTexture(image:image);texture.filteringMode = .linear;textures[path]=texture;return texture
        }
        guard frames.count==paths.count else{return false}
        node.removeAction(forKey:"party_cast_clip")
        node.size.width=node.size.height;node.anchorPoint=CGPoint(x:0.5,y:12.0/256.0)
        node.texture=frames[0];node.warpGeometry=nil
        ActorBodyFrame.record("GeneratedArt/PartyWalk/"+paths[0],on:node)
        let fps=(entry["fps"] as? Double) ?? 12
        let displaySize=node.size
        let sequence=SKAction.sequence(frames.enumerated().flatMap { index,texture in
            [SKAction.run { [weak node] in
                guard let node else{return};node.texture=texture;node.size=displaySize
                ActorBodyFrame.record("GeneratedArt/PartyWalk/"+paths[index],index:index,on:node)
            },.wait(forDuration:1/max(1,fps))]
        })
        node.run(.repeatForever(sequence),withKey:"party_walk_clip")
        return true
    }
}
