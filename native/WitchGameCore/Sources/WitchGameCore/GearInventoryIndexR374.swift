import Foundation

/// Candidate read-only index for the gear inventory UI. Preserves first-match behavior
/// for duplicate UUID input instead of trapping; countByDefinition counts every row.
public struct GearInventoryIndexR374 {
    public struct RefundSummary: Equatable {
        public let itemCount: Int
        public let baseSalvageDust: Int
        public let investmentRefundDust: Int
        public let totalDust: Int
    }

    private var firstGearByID: [UUID: GearInstance] = [:]
    private var countByDefinition: [String: Int] = [:]

    public init(_ inventory: [GearInstance]) {
        firstGearByID.reserveCapacity(inventory.count)
        countByDefinition.reserveCapacity(min(inventory.count, 64))
        for gear in inventory {
            if firstGearByID[gear.id] == nil { firstGearByID[gear.id] = gear }
            countByDefinition[gear.definitionID, default: 0] += 1
        }
    }

    public func firstGear(id: UUID) -> GearInstance? { firstGearByID[id] }
    public func count(definitionID: String) -> Int { countByDefinition[definitionID, default: 0] }
    public func isLastCopy(_ gear: GearInstance) -> Bool { count(definitionID: gear.definitionID) <= 1 }

    public func recyclableIDs(in inventory: [GearInstance], equippedIDs: Set<UUID>,
                              savedLoadoutIDs: Set<UUID> = []) -> [UUID] {
        var remaining = countByDefinition.mapValues { $0 - 1 }
        return inventory.reversed().compactMap { gear in
            guard gear.qualityID == "Q0", !gear.protected,
                  !equippedIDs.contains(gear.id), !savedLoadoutIDs.contains(gear.id),
                  remaining[gear.definitionID, default: 0] > 0 else { return nil }
            remaining[gear.definitionID, default: 0] -= 1
            return gear.id
        }
    }

    public func refundSummary(ids: [UUID], policy: GearDismantleRefundPolicyR353) -> RefundSummary? {
        guard !ids.isEmpty, Set(ids).count == ids.count else { return nil }
        var base = 0, investment = 0, total = 0
        for id in ids {
            guard let gear = firstGearByID[id],
                  let refund = try? policy.refundBreakdown(gearID: gear.id,
                                                           qualityID: gear.qualityID,
                                                           investmentDust: gear.investmentDust) else { return nil }
            let (nextBase, baseOverflow) = base.addingReportingOverflow(refund.baseSalvageDust)
            let (nextInvestment, investmentOverflow) = investment.addingReportingOverflow(refund.investmentRefundDust)
            let (nextTotal, totalOverflow) = total.addingReportingOverflow(refund.totalDust)
            guard !baseOverflow, !investmentOverflow, !totalOverflow else { return nil }
            base = nextBase; investment = nextInvestment; total = nextTotal
        }
        return RefundSummary(itemCount: ids.count, baseSalvageDust: base,
                             investmentRefundDust: investment, totalDust: total)
    }
}
