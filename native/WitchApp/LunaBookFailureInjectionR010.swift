import Foundation

/// Deterministic, QA-only omission decision. It never edits bundle files or the normal texture cache.
@MainActor final class LunaBookFailureInjectionR010 {
    let missingWalkAssetID: String
    private(set) var successfulNonWalkPresentation = false
    private(set) var injectedFailureCount = 0
    private(set) var log: [[String: Any]] = []

    init(missingWalkAssetID: String) { self.missingWalkAssetID = missingWalkAssetID }

    func noteResult(state: String, loaded: Bool) {
        if loaded && state != "walk" { successfulNonWalkPresentation = true }
        log.append(["event": loaded ? "renderer_success" : "renderer_failure",
                    "state": state, "loaded": loaded,
                    "successSeen": successfulNonWalkPresentation])
    }

    /// Call before invoking the ordinary resolver, even if the asset may already be cached.
    func shouldReject(state: String, assetID: String) -> Bool {
        guard state == "walk", assetID == missingWalkAssetID else { return false }
        guard successfulNonWalkPresentation else {
            log.append(["event":"target_resolved_before_success", "state":state, "assetID":assetID])
            return false
        }
        injectedFailureCount += 1
        log.append(["event":"resolver_injected_missing", "state":state, "assetID":assetID,
                    "normalResolverCalled":false, "reason":"R010_QA_LOGICAL_OMISSION"])
        return true
    }

    func receipt() -> [String: Any] {
        ["mode":"after_success_missing_one_walk_body", "missingWalkAssetID":missingWalkAssetID,
         "successfulNonWalkPresentation":successfulNonWalkPresentation,
         "injectedFailureCount":injectedFailureCount, "events":log]
    }
}
