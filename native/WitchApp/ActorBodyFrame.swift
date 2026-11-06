import SpriteKit

/// The identity of the texture actually assigned to an actor, not a prediction
/// from elapsed wall time. State belongs to its node and has no global retention.
@MainActor enum ActorBodyFrame {
    struct Sample {
        let assetID:String
        let frameIndex:Int
        let canvasSize:CGSize
    }
    private final class Observation:NSObject {
        var sample:Sample?
        var didSet:((Sample)->Void)?
    }
    private static let key="witch_actor_body_frame"
    private static func observation(on node:SKSpriteNode)->Observation {
        if let existing=node.userData?[key] as? Observation {return existing}
        if node.userData == nil {node.userData=NSMutableDictionary()}
        let value=Observation();node.userData?[key]=value;return value
    }
    static func current(on node:SKSpriteNode)->Sample? {
        (node.userData?[key] as? Observation)?.sample
    }
    static func bind(on node:SKSpriteNode,didSet:@escaping(Sample)->Void) {
        observation(on:node).didSet=didSet
    }
    /// Call inside the same action block, after texture, size and anchor changes.
    static func record(_ assetID:String,index:Int=0,on node:SKSpriteNode) {
        let observer=observation(on:node)
        let sample=Sample(assetID:assetID,frameIndex:index,canvasSize:node.texture?.size() ?? .zero)
        observer.sample=sample
        observer.didSet?(sample)
    }
}
