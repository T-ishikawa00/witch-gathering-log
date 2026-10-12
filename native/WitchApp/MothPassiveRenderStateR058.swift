import Foundation

/// Pure state-transition contract shared by the passive R058 observer and
/// host tests. A stale cleanup reason on the first sampled non-idle frame is
/// not evidence that an idle registration was ever rendered.
enum MothPassiveRenderStateR058 {
    static func isObservedIdleExitCleanup(
        idleAppliedFrameSeen: Bool,
        state: String,
        applied: Bool,
        reason: String
    ) -> Bool {
        let knownExitStates: Set<String> = ["walk", "flight", "anticipate", "execute", "recover", "hit", "resolve"]
        return idleAppliedFrameSeen && knownExitStates.contains(state) && !applied && reason == "cleared_on_state_exit"
    }
}
