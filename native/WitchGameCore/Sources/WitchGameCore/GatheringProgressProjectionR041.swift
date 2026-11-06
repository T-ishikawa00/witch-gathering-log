import Foundation

/// Read-only presentation of the default catalog-based claimOffline contract.
/// This never settles work or changes a save; the command remains authoritative.
public enum GatheringProgressProjectionR041 {
    public struct Reading: Equatable, Sendable {
        public let materialID: String
        public let readyUnits: Int
        public let secondsUntilNextUnit: Int
        public let reachedCap: Bool
    }

    public enum State: Equatable, Sendable {
        case inactive
        case unavailable
        case clockBehind
        case collecting(Reading)
    }

    public static func read(catalog: GameCatalog, state: GameSnapshot, now: Date) -> State {
        guard let regionID = state.activeRegionID else { return .inactive }
        guard let region = catalog.regions.first(where: { $0.id == regionID }),
              now.timeIntervalSince1970.isFinite else { return .unavailable }
        let interval = TimeInterval(max(1, region.workSeconds))
        let remainder = state.offlineRemainderSeconds
        guard remainder.isFinite, remainder >= 0, remainder <= interval else { return .unavailable }
        let elapsed = state.lastClaimAt.map { now.timeIntervalSince($0) } ?? 0
        guard elapsed.isFinite else { return .unavailable }
        guard elapsed >= 0 else { return .clockBehind }
        let available = catalog.materialAvailabilityGates.isEmpty
            ? region.gatherMaterialIDs
            : catalog.availableGatherMaterialIDs(in: regionID,
                unlockedRegionIDs: state.unlockedRegionIDs,
                completedEncounterIDs: state.completedEncounterIDs)
        guard let materialID = available.contains(state.gatherTargetMaterialID ?? "")
                ? state.gatherTargetMaterialID : available.first else { return .unavailable }
        let cap: TimeInterval = 48 * 3600
        let accrued = min(cap, min(cap, elapsed) + remainder)
        let units = Int(accrued / interval)
        let capped = accrued >= cap
        guard let next = Int(exactly: capped ? 0 : ceil(interval - accrued.truncatingRemainder(dividingBy: interval))) else {
            return .unavailable
        }
        return .collecting(Reading(materialID: materialID, readyUnits: units,
                                   secondsUntilNextUnit: next, reachedCap: capped))
    }
}
