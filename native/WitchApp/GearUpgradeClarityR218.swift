import SwiftUI

/// Read-only, actor-specific projection for the next existing Core gear action.
/// It reads current catalog prices and never dispatches until the player applies.
enum GearUpgradeActionR218: String, Identifiable {
    case enhance
    case refine
    case promoteQuality

    var id: String { rawValue }
    var title: String {
        switch self {
        case .enhance: return "強化"
        case .refine: return "研成"
        case .promoteQuality: return "品質昇格"
        }
    }

    func command(gearID: UUID) -> GameCommand {
        switch self {
        case .enhance: return .enhance(gearID: gearID)
        case .refine: return .refine(gearID: gearID)
        case .promoteQuality: return .promoteQuality(gearID: gearID)
        }
    }
}

struct GearUpgradeRequestR218: Identifiable {
    let gearID: UUID
    let action: GearUpgradeActionR218
    var id: String { "\(action.id):\(gearID.uuidString)" }
}

@MainActor
struct GearUpgradeConfirmationR218: View {
    @ObservedObject var model: GameModel
    let request: GearUpgradeRequestR218
    @Environment(\.dismiss) private var dismiss
    @State private var openedRevision: Int64
    @State private var openedActorID: String

    private struct Projection {
        let current: GearInstance
        let next: GearInstance
        let action: GearUpgradeActionR218
        let dustCost: Int
        let dustOwned: Int
        let gateID: String?
        let before: GearStatsPresentation
        let after: GearStatsPresentation
        let catalogStatus: String?
    }

    private enum Evaluation {
        case ready(Projection)
        case blocked(String)
    }

    init(model: GameModel, request: GearUpgradeRequestR218) {
        self.model = model
        self.request = request
        _openedRevision = State(initialValue: model.state.revision)
        _openedActorID = State(initialValue: model.selectedActor)
    }

    private var revisionIsCurrent: Bool {
        model.state.revision == openedRevision && model.selectedActor == openedActorID
    }

    private var itemName: String {
        guard let item = model.state.gear.first(where: { $0.id == request.gearID }) else { return "装備" }
        return model.catalog?.gear.first(where: { $0.id == item.definitionID })?.name ?? item.definitionID
    }

    private func nextInvestment(_ current: Int, cost: Int) -> Int? {
        guard cost >= 0 else { return nil }
        let (value, overflow) = current.addingReportingOverflow(cost)
        return overflow ? nil : value
    }

    /// Mirrors the applicable recipe/gate/cost shape; GameEngine remains authoritative on apply.
    private func evaluate() -> Evaluation {
        guard revisionIsCurrent else { return .blocked("所持品か選択中の仲間が更新されました。閉じて最新の状態から開き直してください。") }
        guard let catalog = model.catalog,
              let current = model.state.gear.first(where: { $0.id == request.gearID }),
              let definition = catalog.gear.first(where: { $0.id == current.definitionID }) else {
            return .blocked("装備の最新情報を読み込めません。")
        }
        guard model.state.partyActorIDs.contains(openedActorID),
              definition.actorIDs.isEmpty || definition.actorIDs.contains(openedActorID) else {
            return .blocked("\(GameModel.actorNames[openedActorID] ?? "選んだ仲間")はこの装備を使えません。別の仲間を選んでください。")
        }
        guard model.canEquip(current) else {
            return .blocked("この仲間には装備できないか、効果の互換性を確認できません。")
        }

        let cost: Int
        let gateID: String?
        let catalogStatus: String?
        var next = current
        switch request.action {
        case .enhance:
            if NaturalGearRefinementBuildPolicyR352.enabled && model.naturalGearRefinementPolicyR352 == nil {
                return .blocked("強化条件を安全に読み込めません。操作は保存していません。")
            }
            let nextLevel = current.enhancement.addingReportingOverflow(1)
            guard !nextLevel.overflow,
                  let recipe = catalog.recipes.first(where: { $0.id == "ENHANCE_\(nextLevel.partialValue)" }),
                  recipe.kind == "enhance" else {
                return .blocked("この装備は現在の強化上限か、条件を読み込めません。")
            }
            if let policy = model.naturalGearRefinementPolicyR352 {
                let rank = model.state.naturalGearRefinementR352?.rank(for: current.id) ?? 1
                guard let cap = policy.maximumEnhancement(forRank: rank) else {
                    return .blocked("現在の研成段階の強化上限を確認できません。")
                }
                guard nextLevel.partialValue <= cap else {
                    if let transition = policy.transition(from: rank) {
                        let nextCap = policy.maximumEnhancement(forRank: transition.toRank)
                        return .blocked("現在の研成段階では強化は +\(cap) までです。研成段階 \(GearRefinementPresentationR352.rankName(transition.toRank)) に進むと +\(nextCap ?? cap) まで強化できます。")
                    }
                    return .blocked("最終研成段階の強化上限は +\(cap) です。")
                }
            }
            cost = recipe.dustCost
            gateID = recipe.gateID
            catalogStatus = recipe.status
            next.enhancement = nextLevel.partialValue
        case .refine:
            guard !NaturalGearRefinementBuildPolicyR352.enabled else {
                return .blocked("研成の条件を安全に読み込めません。操作は保存していません。")
            }
            guard current.refinement < Int.max else { return .blocked("この装備はこれ以上研成できません。") }
            cost = 5 // Exact current Core rule for .refine.
            gateID = nil
            catalogStatus = nil
            next.refinement = current.refinement + 1
        case .promoteQuality:
            let order = ["Q0", "Q1", "Q2", "Q3", "Q4"]
            guard let index = order.firstIndex(of: current.qualityID), index < order.count - 1 else {
                return .blocked("品質は現在の上限です。")
            }
            let ids = ["QUALITY_Q0_Q1", "QUALITY_Q1_Q2", "QUALITY_Q2_Q3", "QUALITY_Q3_Q4"]
            guard let recipe = catalog.recipes.first(where: { $0.id == ids[index] }), recipe.kind == "quality" else {
                return .blocked("次の品質昇格条件を読み込めません。")
            }
            cost = recipe.dustCost
            gateID = recipe.gateID
            catalogStatus = recipe.status
            next.qualityID = order[index + 1]
            if index == 3 {
                next.protected = true
                if model.candidateLatentPolicy == nil && next.latentEffectID == nil {
                    next.latentEffectID = "LATENT_POWER_TEST"
                }
            }
        }
        guard cost >= 0, let investment = nextInvestment(current.investmentDust, cost: cost) else {
            return .blocked("必要量を安全に計算できません。操作は保存していません。")
        }
        next.investmentDust = investment
        if let gateID, gateID != "G_START" {
            let parts = gateID.split(separator: "_")
            guard parts.count == 3, parts[0] == "G" else {
                return .blocked("解放条件を読み取れません。操作はできません。")
            }
            let encounterID = "B_\(parts[1])_\(parts[2])"
            guard model.state.completedEncounterIDs.contains(encounterID) else {
                let encounterName = catalog.enemies.first(where: { $0.id == encounterID })?.name ?? "必要なボス"
                return .blocked("先に「\(encounterName)」を達成してください。")
            }
        }
        let owned = model.state.materials["refine_dust", default: 0]
        guard owned >= cost else {
            return .blocked("研成の粉が足りません。必要 \(cost) 個、所持 \(owned) 個です（あと \(cost - owned) 個）。")
        }
        guard model.canEquip(next) else {
            return .blocked("変更後の装備効果をこの仲間に適用できないため、内容を確認できません。")
        }
        do {
            let before = try model.comparisonStats(current)
            let after = try model.comparisonStats(next)
            return .ready(Projection(current: current, next: next, action: request.action,
                                      dustCost: cost, dustOwned: owned, gateID: gateID,
                                      before: before, after: after, catalogStatus: catalogStatus))
        } catch {
            return .blocked("変更後の仲間の性能を確認できません。操作は保存していません。")
        }
    }

    private func delta(_ before: Int, _ after: Int) -> String {
        let difference = after - before
        let sign = difference > 0 ? "+" : ""
        return "\(before) → \(after)（\(sign)\(difference)）"
    }

    private enum FutureEnhancementHint {
        case found(level: Int, totalDust: Int)
        case cappedWithoutVisibleStatChange
        case unavailable
    }

    /// Uses the same actor-specific Core-backed projection and catalog recipes as the immediate preview.
    /// This is explanatory only: it does not dispatch, mutate the snapshot, or promise a combat outcome.
    private func futureEnhancementHint(from current: GearInstance,
                                       baseline: GearStatsPresentation) -> FutureEnhancementHint {
        guard request.action == .enhance,
              current.enhancement >= 0, current.enhancement < 10,
              let catalog = model.catalog else { return .unavailable }
        let maximumLevel: Int
        if let policy = model.naturalGearRefinementPolicyR352 {
            let rank = model.state.naturalGearRefinementR352?.rank(for: current.id) ?? 1
            guard let cap = policy.maximumEnhancement(forRank: rank) else { return .unavailable }
            maximumLevel = cap
        } else {
            maximumLevel = 10
        }
        guard current.enhancement < maximumLevel else { return .unavailable }

        var projected = current
        var totalDust = 0
        for level in (current.enhancement + 1)...maximumLevel {
            guard let recipe = catalog.recipes.first(where: { $0.id == "ENHANCE_\(level)" && $0.kind == "enhance" }),
                  recipe.dustCost >= 0 else { return .unavailable }
            if let gateID = recipe.gateID, gateID != "G_START" {
                let parts = gateID.split(separator: "_")
                guard parts.count == 3, parts[0] == "G" else { return .unavailable }
                let encounterID = "B_\(parts[1])_\(parts[2])"
                guard model.state.completedEncounterIDs.contains(encounterID) else { return .unavailable }
            }
            let (nextTotal, totalOverflow) = totalDust.addingReportingOverflow(recipe.dustCost)
            let (nextInvestment, investmentOverflow) = projected.investmentDust.addingReportingOverflow(recipe.dustCost)
            guard !totalOverflow, !investmentOverflow else { return .unavailable }
            totalDust = nextTotal
            projected.investmentDust = nextInvestment
            projected.enhancement = level
            guard model.canEquip(projected), let future = try? model.comparisonStats(projected) else {
                return .unavailable
            }
            let before = baseline.combatant
            let after = future.combatant
            if before.attack != after.attack || before.maxHP != after.maxHP || before.defense != after.defense {
                return .found(level: level, totalDust: totalDust)
            }
        }
        return .cappedWithoutVisibleStatChange
    }

    private func immediateCombatStatsUnchanged(_ value: Projection) -> Bool {
        value.before.combatant.attack == value.after.combatant.attack &&
        value.before.combatant.maxHP == value.after.combatant.maxHP &&
        value.before.combatant.defense == value.after.combatant.defense
    }

    private func effectSummary(before: Set<String>, after: Set<String>) -> String {
        let added = after.subtracting(before).sorted().map(GameText.effect)
        let removed = before.subtracting(after).sorted().map(GameText.effect)
        var parts: [String] = []
        if !added.isEmpty { parts.append("追加：" + added.joined(separator: "、")) }
        if !removed.isEmpty { parts.append("終了：" + removed.joined(separator: "、")) }
        return parts.isEmpty ? "効果の表示に変化はありません。" : parts.joined(separator: "\n")
    }

    /// Shows the actor projection after quality/slot activation and aggregate caps.
    /// This is deliberately separate from effectSummary, which only describes the
    /// item's ordinary combatant effect IDs.
    private func latentSummary(before: GearStatsPresentation, after: GearStatsPresentation) -> String {
        guard let old = before.latent, let new = after.latent else {
            if before.latent == nil && after.latent == nil {
                return "潜在補正の比較対象はありません。"
            }
            return "潜在補正の比較情報が揃わないため、差を表示できません。"
        }

        var lines: [String] = []
        let keys = Set(old.cappedValuesBP.keys).union(new.cappedValuesBP.keys).sorted()
        let changedStats = keys.compactMap { key -> String? in
            let oldValue = old.cappedValuesBP[key, default: 0]
            let newValue = new.cappedValuesBP[key, default: 0]
            guard oldValue != newValue else { return nil }
            return "\(GearLatentText.statName(key))：\(GearLatentText.percent(oldValue)) → \(GearLatentText.percent(newValue))"
        }
        if changedStats.isEmpty {
            lines.append("適用値に変化はありません。")
        } else {
            lines.append(contentsOf: changedStats)
        }

        // Slot status is tied to the exact gear UUID used by comparisonStats,
        // preventing another equipped item or another actor's slots from leaking in.
        if let oldItem = old.itemDisplays[request.gearID],
           let newItem = new.itemDisplays[request.gearID],
           oldItem.slots.count == newItem.slots.count {
            let slotChanges = zip(oldItem.slots, newItem.slots).compactMap { pair -> String? in
                let prior = pair.0
                let next = pair.1
                guard prior.id == next.id else { return nil }
                let priorActive = prior.isActive
                let nextActive = next.isActive
                guard priorActive != nextActive else { return nil }
                let title = GameText.effect(next.affixID)
                return "\(title)：\(priorActive ? "有効" : "未発動") → \(nextActive ? "有効" : "未発動")"
            }
            if !slotChanges.isEmpty {
                lines.append("枠の状態：" + slotChanges.joined(separator: "、"))
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(itemName).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("次の\(request.action.title)を適用する前に、必要な粉と仲間の性能を確認できます。")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    switch evaluate() {
                    case .blocked(let reason):
                        Text(reason).foregroundStyle(Palette.gold).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("r218_upgrade_blocked")
                    case .ready(let projection):
                        readyContent(projection)
                    }
                    Button("適用する") { apply() }
                        .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .disabled(model.busy || !revisionIsCurrent || isBlocked)
                        .accessibilityIdentifier("r218_upgrade_apply_\(request.id)")
                    Button("キャンセル", role: .cancel) { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("r218_upgrade_cancel_\(request.id)")
                }.padding(20)
            }
            .navigationTitle("育成前の確認")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    private var isBlocked: Bool {
        if case .blocked = evaluate() { return true }
        return false
    }

    @ViewBuilder private func readyContent(_ value: Projection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                LabeledContent("現在", value: stage(value.current))
                LabeledContent("適用後", value: stage(value.next))
                LabeledContent("必要な研成の粉", value: "\(value.dustCost) 個")
                LabeledContent("現在の所持", value: "\(value.dustOwned) 個")
                LabeledContent("適用後の所持", value: "\(value.dustOwned - value.dustCost) 個")
                if let gateID = value.gateID, gateID != "G_START" {
                    let encounterID = "B_" + gateID.dropFirst(2)
                    let name = model.catalog?.enemies.first(where: { $0.id == encounterID })?.name ?? "必要なボス"
                    Text("「\(name)」を攻略済み").font(.caption)
                }
            }
            Divider()
            Text("\(GameModel.actorNames[openedActorID] ?? "選んだ仲間")に装備した場合")
                .font(.subheadline).foregroundStyle(Palette.gold)
            statLine("攻撃", value.before.combatant.attack, value.after.combatant.attack)
            statLine("体力", value.before.combatant.maxHP, value.after.combatant.maxHP)
            statLine("防御", value.before.combatant.defense, value.after.combatant.defense)
            if value.action == .enhance && immediateCombatStatsUnchanged(value) {
                switch futureEnhancementHint(from: value.current, baseline: value.before) {
                case .found(let level, let totalDust):
                    Text("今回の強化では攻撃・体力・防御に変化はありません。現在から累計\(totalDust)個の研成の粉を使うと、+\(level)で初めて表示値が変わります。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("r235_next_visible_enhancement")
                case .cappedWithoutVisibleStatChange:
                    Text("強化上限まで、攻撃・体力・防御の表示値に変化はありません。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("r235_next_visible_enhancement")
                case .unavailable:
                    Text("次に表示値が変わる強化段階と累計費用を確認できません。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("r235_next_visible_enhancement_unavailable")
                }
            }
            Text("装備効果（基本）")
                .font(.caption.weight(.semibold))
            Text(effectSummary(before: Set(value.before.combatant.effectIDs), after: Set(value.after.combatant.effectIDs)))
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("r218_upgrade_effect_delta")
            Text("潜在補正")
                .font(.caption.weight(.semibold))
            Text(latentSummary(before: value.before, after: value.after))
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("r218_upgrade_latent_delta")
        }
    }

    private func stage(_ value: GearInstance) -> String {
        let base = "\(GameText.quality(value.qualityID))・+\(value.enhancement)"
        guard model.naturalGearRefinementPolicyR352 != nil else { return base + "・研成\(value.refinement)" }
        let rank = model.state.naturalGearRefinementR352?.rank(for: value.id) ?? 1
        let legacy = value.refinement <= 0 ? "" : "・従来の研成補正 +\(value.refinement)（保持）"
        return base + "・研成段階 " + GearRefinementPresentationR352.rankName(rank) + legacy
    }

    private func statLine(_ title: String, _ before: Int, _ after: Int) -> some View {
        LabeledContent(title, value: delta(before, after))
    }

    private func apply() {
        guard revisionIsCurrent, !model.busy,
              case .ready = evaluate() else { return }
        model.act(request.action.command(gearID: request.gearID), "\(request.action.title)しました。")
        dismiss()
    }
}
