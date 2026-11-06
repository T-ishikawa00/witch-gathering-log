import Foundation

/// The refund display is available only in the explicit local R169 build profile.
enum GearDismantleBuildPolicyR353 {
    static var enabled: Bool {
        #if STANDARD_PLAY_R169 && GEAR_DISMANTLE_REFUND_R353
        true
        #else
        false
        #endif
    }
}

struct GearDismantleRefundSummaryR353: Equatable {
    let itemCount: Int
    let baseSalvageDust: Int
    let investmentRefundDust: Int
    let totalDust: Int
}

@MainActor extension GameModel {
    func isLastDismantleCopyR353(_ gearID: UUID) -> Bool {
        guard let item = state.gear.first(where: { $0.id == gearID }) else { return false }
        return state.gear.filter { $0.definitionID == item.definitionID }.count <= 1
    }

    func dismantleBlockReasonR353(for gearID: UUID) -> String? {
        guard let item = state.gear.first(where: { $0.id == gearID }) else { return "装備を確認できません。" }
        if item.protected { return "保護中の装備は分解できません。" }
        if state.equippedGearIDs.values.contains(gearID) { return "使用中の装備は分解できません。" }
        if state.gearLoadoutsR342?.referencedGearIDs.contains(gearID) ?? false {
            return "保存セットに登録中の装備は分解できません。先にセット登録を解除してください。"
        }
        if GearDismantleBuildPolicyR353.enabled {
            if state.gear.filter({ $0.definitionID == item.definitionID }).count <= 1 {
                return "各種類の最後の1個は残ります。"
            }
            guard dismantleRefundBreakdownR353(for: gearID) != nil else {
                return "返却量を安全に確認できないため、分解できません。"
            }
        }
        return nil
    }

    func dismantleRefundBreakdownR353(for gearID: UUID) -> GearDismantleRefundPolicyR353.RefundBreakdown? {
        guard GearDismantleBuildPolicyR353.enabled,
              let policy = engine?.gearDismantleRefundPolicyR353,
              let gear = state.gear.first(where: { $0.id == gearID }) else { return nil }
        return try? policy.refundBreakdown(gearID: gear.id, qualityID: gear.qualityID,
                                           investmentDust: gear.investmentDust)
    }

    /// Requires every exact UUID to resolve before presenting or dispatching a batch.
    func dismantleRefundSummaryR353(for gearIDs: [UUID], gearInventory: [GearInstance]? = nil) -> GearDismantleRefundSummaryR353? {
        guard GearDismantleBuildPolicyR353.enabled,
              let policy = engine?.gearDismantleRefundPolicyR353,
              !gearIDs.isEmpty, Set(gearIDs).count == gearIDs.count else { return nil }
        let inventory = gearInventory ?? state.gear
        var base = 0
        var investment = 0
        var total = 0
        for id in gearIDs {
            guard let gear = inventory.first(where: { $0.id == id }),
                  let amount = try? policy.refundBreakdown(gearID: gear.id, qualityID: gear.qualityID,
                                                           investmentDust: gear.investmentDust) else { return nil }
            let (nextBase, baseOverflow) = base.addingReportingOverflow(amount.baseSalvageDust)
            let (nextInvestment, investmentOverflow) = investment.addingReportingOverflow(amount.investmentRefundDust)
            let (nextTotal, totalOverflow) = total.addingReportingOverflow(amount.totalDust)
            guard !baseOverflow, !investmentOverflow, !totalOverflow else { return nil }
            base = nextBase
            investment = nextInvestment
            total = nextTotal
        }
        return GearDismantleRefundSummaryR353(itemCount: gearIDs.count,
            baseSalvageDust: base, investmentRefundDust: investment, totalDust: total)
    }
}
