import Foundation

/// Runtime candidate keys for already-defined R4 equipment. Ownership and active
/// equipment pointers are checked before a renderer sees a candidate attachment.
/// This does not grant, equip, approve, or change any item or stat.
public struct EquippedVisualCandidate: Sendable, Equatable {
    public let gearID: String
    public let actorID: String
    public let slot: String
    public let sceneKey: String
    public let candidateAssetID: String
}

public extension GameCatalog {
    func equippedVisualCandidates(in snapshot: GameSnapshot) -> [EquippedVisualCandidate] {
        var result: [EquippedVisualCandidate] = []
        for actor in snapshot.partyActorIDs {
            for instance in snapshot.gear where instance.ownerID == actor {
                guard let projection = gearAppearanceProjection(for: instance, actorID: actor, in: snapshot),
                      projection.isEquipped else { continue }
                let gearID = projection.gearID
                if projection.visualScope == .iconAndSmallDetailOnly {
                    result.append(EquippedVisualCandidate(gearID: gearID, actorID: actor, slot: projection.slot,
                        sceneKey: "DETAIL|\(actor)|\(projection.slot)", candidateAssetID: "DETAIL_\(gearID)"))
                } else if actor == "C_APPRENTICE", ["EQ_A_01", "EQ_A_02", "EQ_A_03"].contains(gearID) {
                    result.append(EquippedVisualCandidate(gearID: gearID, actorID: actor, slot: projection.slot,
                        sceneKey: "APPRENTICE_BOOK_GEAR", candidateAssetID: "BOOK_\(gearID)"))
                } else if actor == "C_SMITH", ["EQ_S_02", "EQ_S_03"].contains(gearID) {
                    result.append(EquippedVisualCandidate(gearID: gearID, actorID: actor, slot: projection.slot,
                        sceneKey: "DETAIL|\(actor)|weapon", candidateAssetID: "DETAIL_\(gearID)"))
                } else if actor == "C_FAMILIAR", ["EQ_F_01", "EQ_F_02", "EQ_F_03"].contains(gearID) {
                    result.append(EquippedVisualCandidate(gearID: gearID, actorID: actor, slot: projection.slot,
                        sceneKey: "DETAIL|\(actor)|weapon", candidateAssetID: "DETAIL_\(gearID)"))
                }
            }
        }
        return result.sorted { $0.sceneKey < $1.sceneKey }
    }
}
