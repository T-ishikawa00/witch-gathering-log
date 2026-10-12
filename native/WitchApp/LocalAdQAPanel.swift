import SwiftUI

extension GameModel {
    var localAdRewardQAEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--qa-isolated")
        #else
        return false
        #endif
    }

    func qaSetAdSkipEntitlement(_ enabled: Bool) {
        guard localAdRewardQAEnabled else { return }
        act(.setLocalAdSkipEntitlementForQA(enabled: enabled))
    }

    func qaRewardedAdAttempt(opportunityID: String, outcome: LocalAdAttemptOutcome) {
        guard localAdRewardQAEnabled, !busy, let engine else { return }
        busy = true
        let result = LocalRewardedAdQAResult.simulate(sessionID: "qa-ad-\(UUID().uuidString)", outcome: outcome)
        Task {
            do {
                let receipt = try await engine.dispatch(.recordMockRewardedAdAttempt(opportunityID: opportunityID, result: result), operationID: UUID(), expectedRevision: state.revision)
                await refresh()
                notice = receipt.result
            } catch {
                self.error = GameText.error(error)
                await refresh()
            }
            busy = false
        }
    }

    func qaClaimAdSkip(opportunityID: String) {
        guard localAdRewardQAEnabled else { return }
        act(.claimMockAdSkip(opportunityID: opportunityID))
    }

    func qaAccrueOneEightHourBlock() {
        guard localAdRewardQAEnabled, !busy, let engine else { return }
        busy = true
        Task {
            do {
                let start = state.lastClaimAt ?? Date()
                let receipt = try await engine.claimOffline(now: start.addingTimeInterval(8 * 3600), operationID: UUID(), expectedRevision: state.revision)
                await refresh()
                notice = "QA専用: 8時間相当の基礎作業を精算しました。\n" + receipt.result
            } catch {
                self.error = GameText.error(error)
                await refresh()
            }
            busy = false
        }
    }

    func qaAdXPPreview(_ opportunity: LocalAdRewardOpportunity) -> [(String, Int)] {
        opportunity.baseXPByActor.keys.sorted().map { actorID in
            let base = opportunity.baseXPByActor[actorID, default: 0]
            let carry = state.localAdXPFractionalCarry[actorID, default: 0]
            return (actorID, (base + carry) / 16)
        }
    }

    func qaAdDustPreview(_ opportunity: LocalAdRewardOpportunity) -> Int {
        (opportunity.baseDust + state.localAdDustFractionalCarry) / 16
    }
}

struct LocalAdQAPanel: View {
    @ObservedObject var model: GameModel

    private var opportunities: [LocalAdRewardOpportunity] {
        model.state.localAdRewardOpportunities.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        Group {
            if model.localAdRewardQAEnabled {
                qaContent
            } else {
                Text("この画面は独立QAセーブのシミュレーターでのみ使用できます。")
                    .padding()
            }
        }
    }

    private var qaContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("任意報酬 QA").font(.title2.bold())
                Text("ローカルQA専用。広告SDK・通信・購入は使用しません。実報酬や販売権を付与しません。")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("QA広告省略 entitlement", isOn: Binding(
                    get: { model.state.localAdSkipEntitledForQA },
                    set: { model.qaSetAdSkipEntitlement($0) }
                ))
                .accessibilityIdentifier("qa_ad_skip_entitlement")
                HStack {
                    Text("未受取: \(opportunities.count) / 6")
                    Spacer()
                    Text("次の8時間区切り: \(model.state.localAdWorkBlockSeconds / 60)分")
                }.font(.caption)
                Button("QA用に8時間相当を精算") { model.qaAccrueOneEightHourBlock() }
                    .accessibilityIdentifier("qa_ad_accrue_eight_hours")

                if opportunities.isEmpty {
                    Text("受取機会はありません。上のQA精算で実際の基礎採集を進めてください。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(opportunities) { opportunity in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(opportunity.id).font(.headline)
                        Text("基礎報酬の1/16候補。素材・装備・券・天井進行はありません。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.qaAdXPPreview(opportunity).map(\.0), id: \.self) { actorID in
                            let amount = model.qaAdXPPreview(opportunity).first(where: { $0.0 == actorID })?.1 ?? 0
                            Text("\(GameModel.actorNames[actorID] ?? actorID) EXP +\(amount)")
                                .font(.caption)
                        }
                        Text("研磨粉 +\(model.qaAdDustPreview(opportunity))")
                            .font(.caption)
                        HStack {
                            Button("完了を模擬") { model.qaRewardedAdAttempt(opportunityID: opportunity.id, outcome: .completed) }
                                .accessibilityIdentifier("qa_ad_complete_\(opportunity.id)")
                            Button("キャンセル") { model.qaRewardedAdAttempt(opportunityID: opportunity.id, outcome: .cancelled) }
                                .accessibilityIdentifier("qa_ad_cancel_\(opportunity.id)")
                            Button("失敗") { model.qaRewardedAdAttempt(opportunityID: opportunity.id, outcome: .failed) }
                                .accessibilityIdentifier("qa_ad_fail_\(opportunity.id)")
                            if model.state.localAdSkipEntitledForQA {
                                Button("省略して受取") { model.qaClaimAdSkip(opportunityID: opportunity.id) }
                                    .accessibilityIdentifier("qa_ad_skip_\(opportunity.id)")
                            }
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                }

                Text("実広告完了の検証、広告省略商品のStoreKit entitlement、サーバー検証、返金・復元は未実装です。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("qa_ad_production_boundary")
            }
            .padding()
        }
        .buttonStyle(.bordered)
        .disabled(model.busy)
    }
}
