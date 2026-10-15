import Foundation

/// Selection contract for the recipe-to-gather handoff. In R144 mode the typed
/// selector is authoritative; a legacy gather ID is not evidence that an
/// investigation target has been switched back to gathering.
public enum RecipeGatherHandoffTargetR157 {
    public enum FailureContext: Equatable {
        case noPartialRegionChange
        case regionChangedTargetPending
        case targetUnchangedInSelectedRegion
    }

    public static func failureContext(regionDispatchCommitted: Bool,
                                      activeRegionID: String?,
                                      requestedRegionID: String,
                                      targetCommitted: Bool) -> FailureContext {
        guard activeRegionID == requestedRegionID, !targetCommitted else { return .noPartialRegionChange }
        return regionDispatchCommitted ? .regionChangedTargetPending : .targetUnchangedInSelectedRegion
    }

    public static func isCommitted(sharedWorkEnabled: Bool,
                                   typedTarget: PartyWorkTargetR144?,
                                   legacyGatherTargetID: String?,
                                   requestedMaterialID: String) -> Bool {
        if sharedWorkEnabled {
            return typedTarget == .gather(requestedMaterialID)
        }
        return legacyGatherTargetID == requestedMaterialID
    }

    public static func needsDispatch(sharedWorkEnabled: Bool,
                                     typedTarget: PartyWorkTargetR144?,
                                     legacyGatherTargetID: String?,
                                     requestedMaterialID: String) -> Bool {
        !isCommitted(sharedWorkEnabled: sharedWorkEnabled,
                     typedTarget: typedTarget,
                     legacyGatherTargetID: legacyGatherTargetID,
                     requestedMaterialID: requestedMaterialID)
    }
}
