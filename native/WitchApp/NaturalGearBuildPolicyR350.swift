import Foundation

/// Explicit local-development capability. Candidate production does not adopt its rules.
enum NaturalGearBuildPolicyR350 {
    static var enabled: Bool {
        #if STANDARD_PLAY_R169 && NATURAL_GEAR_R350
        true
        #else
        false
        #endif
    }
}

@MainActor extension GameModel {
    /// Join the transaction's real inventory delta to bounded natural-acquisition provenance.
    /// Crafted and summoned instances are never relabeled as exploration drops.
    func naturalGearArrivalsR350(since before: GameSnapshot) -> [GearInstance] {
        let old = Set(before.gear.map(\.id))
        let natural = Set(state.naturalGearDiscoveryR350?.acquisitionRecords.map(\.gearInstanceID) ?? [])
        return state.gear.filter { !old.contains($0.id) && natural.contains($0.id) }
    }

    func appendNaturalGearNoticeR350(since before: GameSnapshot) {
        let count = naturalGearArrivalsR350(since: before).count
        if count > 0 { notice += " 探索から装備が\(count)点届きました。" }
    }
}
