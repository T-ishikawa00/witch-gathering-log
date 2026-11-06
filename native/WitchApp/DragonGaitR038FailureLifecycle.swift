import Foundation

/// Pure bounded failure/cleanup state used by the R038 QA observer.
/// It intentionally contains no SpriteKit, game, or persistence operations.
struct DragonGaitR038FailureLifecycle {
    enum CleanupDecision: Equatable {
        case waiting
        case completed(String)
    }

    private(set) var failureReason: String?
    private(set) var cleanupDeadline: Double?
    private(set) var completedStatus: String?

    @discardableResult
    mutating func beginFailure(_ reason: String, now: Double, cleanupWindow: Double = 2.0) -> Bool {
        guard failureReason == nil, completedStatus == nil,
              now.isFinite, cleanupWindow.isFinite, cleanupWindow >= 0 else { return false }
        failureReason = reason
        cleanupDeadline = now + cleanupWindow
        return true
    }

    mutating func evaluateCleanup(now: Double, actualStateIsIdle: Bool, warpClean: Bool) -> CleanupDecision {
        guard completedStatus == nil, let reason = failureReason, let deadline = cleanupDeadline else {
            return .waiting
        }
        if actualStateIsIdle && warpClean {
            let status = "INCOMPLETE_\(reason)_CLEANUP_OBSERVED"
            return .completed(status)
        }
        if now.isFinite && now >= deadline {
            let status = "INCOMPLETE_\(reason)_CLEANUP_UNCONFIRMED"
            return .completed(status)
        }
        return .waiting
    }

    @discardableResult
    mutating func complete(_ status: String) -> CleanupDecision? {
        guard completedStatus == nil else { return nil }
        completedStatus = status
        return .completed(status)
    }
}
