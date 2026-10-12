import UIKit

@MainActor enum ArtLibrary {
    static let cache = NSCache<NSString,UIImage>()
    static let root = Bundle.main.bundleURL.appendingPathComponent("Art")
    static let index: [String:[String:Any]] = {
        guard let d=try? Data(contentsOf:root.appendingPathComponent("runtime_index.json")),let j=try? JSONSerialization.jsonObject(with:d) as? [String:Any] else{return [:]};return j["entries"] as? [String:[String:Any]] ?? [:]
    }()
    static func image(_ id:String)->UIImage? {
        if let i=cache.object(forKey:id as NSString){return i}
        var paths=["Art/\(id).png","GeneratedArt/\(id).png","GeneratedArt/PartyMotion/\(id).png","GeneratedArt/WeaponLayers/\(id).png"]
        if id=="STAFF_MOON" || id=="STAFF_BRANCH" {paths.insert("GeneratedArt/WeaponLayers/\(id)_ALPHA_R002.png",at:0)}
        if let entry=index[id] {if let p=entry["selectedPNG"] as? String{paths.append("Art/"+p)}else if let layers=entry["layers"] as? [String],let p=layers.first{paths.append("Art/"+p)}else if let clips=entry["clips"] as? [String:[String:Any]],let p=(clips["idle"]?["frames"] as? [String])?.first{paths.append("Art/"+p)}}
        let parts=id.components(separatedBy:"__")
        if parts.count==2,let poses=index[parts[0]]?["selectedPNG"] as? [String:String],let p=poses[parts[1]] {paths.append("Art/"+p)}
        for p in paths{if let img=UIImage(contentsOfFile:Bundle.main.bundleURL.appendingPathComponent(p).path){cache.setObject(img,forKey:id as NSString,cost:Int(img.size.width*img.size.height*4));cache.totalCostLimit=48*1024*1024;return img}}
        return nil
    }
}
