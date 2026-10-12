import Foundation
import SpriteKit

/// R016 presentation-only projection. It resolves existing cataloged material props;
/// it does not own gathering availability, timing, rewards, or respawn mechanics.
@MainActor enum R016GatherNodePresentation {
    enum State: String { case present, collected }

    struct Projection: Equatable {
        let materialID: String
        let nodeID: String
        let regionID: String
        let state: State
    }

    static let normalizedGroundPoint = CGPoint(x: 0.68, y: 0.27)
    static let displayHeightMultiplier: CGFloat = 0.17
    static let collectedHold: TimeInterval = 0.65
    static let visualRespawnPause: TimeInterval = 0.75

    static func nodeID(for materialID: String) -> String? {
        guard materialID.range(of: #"^M_R0[1-5]_G[1-4]$"#, options: .regularExpression) != nil else { return nil }
        return "NODE_" + materialID
    }

    static func projection(materialID: String?, regionID: String,
                           resolution: R015AreaSceneResolution?, state: State = .present) -> Projection? {
        guard let materialID,
              let nodeID = nodeID(for: materialID),
              let resolution,
              resolution.selectionBasis == .selectedGatherMaterial,
              resolution.route.regionID == regionID,
              resolution.route.gatherableMaterialIDs.contains(materialID),
              let entry = ArtLibrary.index[nodeID],
              entry["kind"] as? String == "gather_prop",
              let states = entry["selectedPNG"] as? [String: String],
              states[state.rawValue] != nil else { return nil }
        return Projection(materialID: materialID, nodeID: nodeID,
                          regionID: regionID, state: state)
    }

    static func imageID(for projection: Projection) -> String {
        projection.nodeID + "__" + projection.state.rawValue
    }

    /// Explicitly presentation-only: successful claim briefly shows the authored
    /// collected sprite, a short visual pause, then returns to present. No timer or
    /// resource is scheduled in gameplay state.
    static func successfulClaimActions(collected: SKTexture, present: SKTexture) -> [SKAction] {
        [.setTexture(collected), .wait(forDuration: collectedHold), .fadeOut(withDuration: 0.12),
         .wait(forDuration: visualRespawnPause), .setTexture(present), .fadeIn(withDuration: 0.18)]
    }
}
