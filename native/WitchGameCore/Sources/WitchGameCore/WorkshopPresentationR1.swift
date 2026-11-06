import Foundation

/// Presentation state only. Selecting or previewing a recipe never dispatches a command.
/// The accepted cost projection is held while the durable operation is in progress.
public struct WorkshopPresentationR1: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case selected, missingRequirements, ready, awaitingConfirmation, processing, completed, failed
    }
    public let phase: Phase
    public let goal: RecipeGoalProjectionR035.Goal?

    public init(liveGoal: RecipeGoalProjectionR035.Goal?, confirmation: Bool,
                operationPhase: Phase? = nil, acceptedGoal: RecipeGoalProjectionR035.Goal? = nil) {
        if operationPhase == .processing {
            phase = .processing
            goal = acceptedGoal
        } else {
            goal = liveGoal
            if operationPhase == .completed || operationPhase == .failed {
                phase = operationPhase!
            } else if let liveGoal {
                phase = liveGoal.ready && liveGoal.dispatchCompatible
                    ? (confirmation ? .awaitingConfirmation : .ready) : .missingRequirements
            } else {
                phase = .selected
            }
        }
    }

    public var statusText: String {
        switch phase {
        case .selected: return "制作の目標"
        case .missingRequirements: return "制作の準備中"
        case .ready: return "制作できます"
        case .awaitingConfirmation: return "材料が揃いました。内容を確認してください"
        case .processing: return "制作結果を保存しています"
        case .completed: return "制作して保存しました"
        case .failed: return "制作できませんでした"
        }
    }
}

extension GameEngine {
    public func claimOfflineConfirmingSavedReceipt(now: Date, secondsPerUnit: TimeInterval? = nil,
                                                   cap: TimeInterval = 48 * 3600,
                                                   operationID: UUID, expectedRevision: Int64) async throws -> CommandReceipt {
        do {
            return try await claimOffline(now:now,secondsPerUnit:secondsPerUnit,cap:cap,
                operationID:operationID,expectedRevision:expectedRevision)
        } catch SaveRepositoryError.commitMayHaveSucceeded(let committedID, let revision) {
            guard committedID == operationID,
                  let receipt=await saves.receipt(for:operationID),receipt.revision == revision else {
                throw SaveRepositoryError.commitMayHaveSucceeded(operationID:committedID,revision:revision)
            }
            return try await saves.confirmCommittedReceipt(operationID:operationID,revision:receipt.revision)
        }
    }

    /// A write can report an error after atomic replacement. Resolve the SAME operation
    /// using the repository's verified primary readback; never turn a committed game operation into
    /// a new attempt. Other failures remain failures and leave the previous save intact.
    public func dispatchConfirmingSavedReceipt(_ command: GameCommand, operationID: UUID,
                                              expectedRevision: Int64,
                                              transactionDate: Date? = nil) async throws -> CommandReceipt {
        do {
            return try await dispatch(command, operationID: operationID,
                                      expectedRevision: expectedRevision, transactionDate: transactionDate)
        } catch SaveRepositoryError.commitMayHaveSucceeded(let committedID, let revision) {
            guard committedID == operationID,
                  let receipt = await saves.receipt(for: operationID), receipt.revision == revision else {
                throw SaveRepositoryError.commitMayHaveSucceeded(operationID: committedID, revision: revision)
            }
            return try await saves.confirmCommittedReceipt(operationID:operationID,revision:receipt.revision)
        }
    }
}
