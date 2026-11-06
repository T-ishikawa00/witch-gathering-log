import SwiftUI

/// Each displayed item is tried from one unchanged, current engine snapshot.
struct GearComparisonR131Section: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: GameModel
    let items: [GearInstance]
    @State private var challengeID = ""
    @State private var results: [UUID: TrialCard] = [:]
    @State private var runError: String?
    @State private var activeRun: UUID?
    @State private var previewTask: Task<Void, Never>?

    private var availableChallenges: [ChallengeDefinition] {
        guard let catalog = model.catalog else { return [] }
        let progress = PostClearGoalProjectionR122.project(catalog: catalog, state: model.state)
        let ids = Set(progress.challenges.filter { $0.availability != .locked }.map(\.id))
        return catalog.challenges.filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("この課題で試す").font(.headline)
            Text("同じ敵・仲間で、2つの装備を一つずつ試します。装備や進行、報酬は変わりません。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Text("比べる仲間：" + (GameModel.actorNames[model.selectedActor] ?? "仲間"))
                .font(.subheadline).foregroundStyle(Palette.gold)
                .accessibilityIdentifier("gear_trial_actor")
            if availableChallenges.isEmpty {
                Text(nextUnlockGuidance).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gear_trial_no_unlocked_challenge")
            } else {
                Picker("試す研究課題", selection: $challengeID) {
                    ForEach(availableChallenges) { challenge in
                        Text(challenge.name).tag(challenge.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("gear_trial_challenge_picker")
                Button(action: runPair) {
                    Text(activeRun == nil ? "条件をそろえて試す" : "計算中…")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                .disabled(activeRun != nil || model.busy || model.fighting || items.count != 2 ||
                          model.engine == nil || !availableChallenges.contains(where: { $0.id == challengeID }))
                .accessibilityIdentifier("run_gear_trial")
            }
            if let runError {
                Text(runError).foregroundStyle(Palette.gold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gear_trial_error")
            }
            if !results.isEmpty {
                Text("1回ずつ試した結果です。敵や仲間の組み合わせによって変わります。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(items) { item in
                if let result = results[item.id] { resultCard(item: item, result: result) }
            }
        }
        .padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { if challengeID.isEmpty { challengeID = availableChallenges.first?.id ?? "" } }
        .onDisappear { invalidate() }
        .onChange(of: challengeID) { _, _ in invalidate() }
        .onChange(of: model.selectedActor) { _, _ in invalidate() }
        .onChange(of: model.comparison) { _, _ in invalidate() }
        .onChange(of: model.busy) { _, busy in if busy { invalidate() } }
        .onChange(of: model.state.revision) { _, _ in
            invalidate()
            if !availableChallenges.contains(where: { $0.id == challengeID }) {
                challengeID = availableChallenges.first?.id ?? ""
            }
        }
    }

    private func invalidate() {
        previewTask?.cancel()
        previewTask = nil
        activeRun = nil
        results = [:]
        runError = nil
    }

    private func runPair() {
        guard activeRun == nil, !model.busy, !model.fighting, items.count == 2,
              let engine = model.engine, let catalog = model.catalog,
              availableChallenges.contains(where: { $0.id == challengeID }) else { return }
        let actorID = model.selectedActor
        let selectedChallenge = challengeID
        let selectedIDs = items.map(\.id)
        let definitions = items.compactMap { item in catalog.gear.first { $0.id == item.definitionID } }
        guard model.comparison == selectedIDs, Set(selectedIDs).count == 2,
              definitions.count == 2, definitions[0].slot == definitions[1].slot else {
            runError = "同じ部位の装備を確認できません。比較を開き直してください。"
            return
        }
        let slot = definitions[0].slot
        let token = UUID()
        activeRun = token
        results = [:]
        runError = nil
        previewTask = Task { @MainActor in
            defer { if activeRun == token { activeRun = nil; previewTask = nil } }
            do {
                let baseline = await engine.snapshot()
                guard !Task.isCancelled, activeRun == token, model.state == baseline,
                      model.selectedActor == actorID, model.comparison == selectedIDs,
                      challengeID == selectedChallenge, !model.busy, !model.fighting else { return }
                let seed = UInt64(bitPattern: baseline.revision) &+ 0x5231
                // Keep simulation off the UI actor. It has no command, persistence or reward path.
                let calculation = Task.detached(priority: .userInitiated) {
                    try await GearTrialWorkerR131.shared.run(engine: engine, ids: selectedIDs,
                        actorID: actorID, challengeID: selectedChallenge, seed: seed, baseline: baseline)
                }
                let previews = try await withTaskCancellationHandler {
                    try await calculation.value
                } onCancel: { calculation.cancel() }
                let after = await engine.snapshot()
                guard !Task.isCancelled, activeRun == token else { return }
                guard after == baseline, model.state == baseline, !model.busy, !model.fighting,
                      model.selectedActor == actorID, model.comparison == selectedIDs,
                      challengeID == selectedChallenge else {
                    runError = "装備の状態が変わりました。最新の状態でもう一度試してください。"
                    return
                }
                var completed: [UUID: TrialCard] = [:]
                for preview in previews {
                    guard selectedIDs.contains(preview.selectedGearID), preview.actorID == actorID,
                          preview.challengeID == selectedChallenge, preview.seed == seed,
                          preview.slot == slot,
                          preview.currentGearID == baseline.equippedGearIDs[actorID + "|" + slot] else {
                        throw GearSwapCombatPreviewErrorR131.wrongGearSlot
                    }
                    let currentName: String
                    if let id = preview.currentGearID,
                       let gear = baseline.gear.first(where: { $0.id == id }),
                       let definition = catalog.gear.first(where: { $0.id == gear.definitionID }) {
                        currentName = definition.name
                    } else { currentName = "この部位の装備なし" }
                    completed[preview.selectedGearID] = TrialCard(
                        summary: GearSwapCombatSummaryR131.make(from: preview), currentName: currentName)
                }
                guard completed.count == 2 else { throw GearSwapCombatPreviewErrorR131.wrongGearSlot }
                results = completed
                writeQAReceipt(previews: previews, baseline: baseline, seed: seed)
            } catch is CancellationError {
                // Leaving the view or changing a comparison intentionally cancels display.
            } catch let error as GearSwapCombatPreviewErrorR131 {
                if activeRun == token { runError = localized(error); results = [:] }
            } catch {
                if activeRun == token {
                    runError = "試し戦闘を計算できませんでした。装備を確認して、もう一度試してください。"
                    results = [:]
                }
            }
        }
    }

    private func resultCard(item: GearInstance, result: TrialCard) -> some View {
        let summary = result.summary
        return VStack(alignment: .leading, spacing: 8) {
            Text(model.catalog?.gear.first { $0.id == item.definitionID }?.name ?? "装備")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gear_trial_result_" + item.id.uuidString)
            Text("\(GameText.quality(item.qualityID))　強化 +\(item.enhancement)　研成 \(item.refinement)")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            infoRow("いまの装備", value: result.currentName)
            Text("試し戦闘の結果：" + (summary.won ? "勝利" : "勝利できず"))
                .accessibilityIdentifier("gear_trial_outcome_" + item.id.uuidString)
            infoRow("戦闘時間の目安", value: "約\(summary.ticks)秒")
            Text("仲間の残り体力").foregroundStyle(Palette.gold)
                .accessibilityIdentifier("gear_trial_party_hp_" + item.id.uuidString)
            ForEach(summary.initialPartyHP.keys.sorted(), id: \.self) { actor in
                Text("\(GameModel.actorNames[actor] ?? "仲間")　\(summary.remainingPartyHP[actor, default: 0]) / \(summary.initialPartyHP[actor, default: 0])")
                    .fixedSize(horizontal: false, vertical: true)
            }
            let survivors = summary.remainingPartyHP.values.filter { $0 > 0 }.count
            Text("戦闘を終えた仲間　\(survivors) / \(summary.initialPartyHP.count)人")
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("敵の残り体力").foregroundStyle(Palette.gold)
                        .accessibilityIdentifier("gear_trial_enemy_hp_" + item.id.uuidString)
                    ForEach(summary.initialEnemyHP.keys.sorted(), id: \.self) { enemy in
                        Text("\(model.catalog?.enemies.first { $0.id == enemy }?.name ?? "敵")　\(summary.remainingEnemyHP[enemy, default: 0]) / \(summary.initialEnemyHP[enemy, default: 0])")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(observedEventRows(summary), id: \.label) { row in
                        Text("\(row.label)　\(row.count)回").fixedSize(horizontal: false, vertical: true)
                    }
                    Text("味方と敵の戦闘中の記録です。装備だけの効果を表す数値ではありません。")
                        .foregroundStyle(Palette.gold).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 6)
            } label: {
                Text("戦闘で起きたこと")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("gear_trial_details_" + item.id.uuidString)
            }
        }
        .font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).foregroundStyle(Palette.gold)
                Text(value)
            }.fixedSize(horizontal: false, vertical: true)
        } else {
            LabeledContent(label, value: value)
        }
    }

    private func observedEventRows(_ summary: GearSwapCombatSummaryR131) -> [(label: String, count: Int)] {
        let labels = [("poison_tick", "毒の継続"), ("barrier_absorb", "結界で受け止め"),
                      ("heal", "回復"), ("reflect", "反射"), ("counter", "反撃")]
        return labels.compactMap { id, label in
            let count = summary.eventKindCounts[id, default: 0]
            return count > 0 ? (label, count) : nil
        }
    }

    private var nextUnlockGuidance: String {
        guard let catalog = model.catalog else { return "課題情報を読み込めません。比較を開き直してください。" }
        let progress = PostClearGoalProjectionR122.project(catalog: catalog, state: model.state)
        if let row = progress.challenges.first(where: { $0.availability == .locked }),
           let challenge = catalog.challenges.first(where: { $0.id == row.id }) {
            let parts = challenge.unlockGate.split(separator: "_")
            if parts.count == 3, parts[0] == "G",
               let enemy = catalog.enemies.first(where: { $0.id == "B_\(parts[1])_\(parts[2])" }) {
                return "「\(enemy.name)」を倒すと研究課題と試し戦闘が解放されます。"
            }
        }
        return "研究課題を解放すると、この画面で装備を試せます。"
    }

    private func localized(_ error: GearSwapCombatPreviewErrorR131) -> String {
        switch error {
        case .unknownChallenge, .challengeLocked: return "この課題はまだ試せません。解放状況を確認してください。"
        case .actorNotInParty: return "仲間の編成が変わりました。仲間を選び直してください。"
        case .missingOrDuplicateGear: return "比較する装備を確認できません。比較を開き直してください。"
        case .wrongGearOwner: return "別の仲間が使用中の装備は、この試し戦闘では比べられません。"
        case .selectedGearEquippedElsewhere: return "装着先が重複しているため試せません。装備の状態を確認してください。"
        case .wrongGearSlot: return "同じ部位の装備を選んでください。"
        case .gearNotUsableByActor: return "この仲間が使えない装備を含んでいます。仲間を選び直してください。"
        }
    }

    private func writeQAReceipt(previews: [GearSwapCombatPreviewR131], baseline: GameSnapshot, seed: UInt64) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-r131-gear-comparison"),
              let saveURL = model.saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let rows: [[String: Any]] = previews.compactMap { preview in
            guard let raw = try? encoder.encode(GearSwapCombatSummaryR131.make(from: preview)),
                  let summary = try? JSONSerialization.jsonObject(with: raw) else { return nil }
            return ["selectedGearID": preview.selectedGearID.uuidString,
                    "currentGearID": preview.currentGearID?.uuidString ?? "",
                    "actorID": preview.actorID, "challengeID": preview.challengeID,
                    "slot": preview.slot, "seed": String(seed), "summary": summary]
        }
        model.writeReceipt("gear_trial_r131", "READ_ONLY_PAIR", metadata: [
            "saveFilename": saveURL.lastPathComponent, "baselineRevision": baseline.revision,
            "processID": ProcessInfo.processInfo.processIdentifier,
            "orderedGearIDs": previews.map { $0.selectedGearID.uuidString }, "results": rows,
            "simulationOnly": true, "rewardsCommitted": false])
    }

    private struct TrialCard {
        let summary: GearSwapCombatSummaryR131
        let currentName: String
    }
}

/// One executor across sheet instances prevents overlapping CPU work after a
/// rapid close/reopen. Cancellation is checked between the two bounded battles.
private actor GearTrialWorkerR131 {
    static let shared = GearTrialWorkerR131()

    func run(engine: GameEngine, ids: [UUID], actorID: String, challengeID: String,
             seed: UInt64, baseline: GameSnapshot) throws -> [GearSwapCombatPreviewR131] {
        try ids.map { id in
            try Task.checkCancellation()
            return try engine.previewChallengeGearSwapR131(challengeID: challengeID,
                actorID: actorID, selectedGearID: id, seed: seed, snapshot: baseline)
        }
    }
}
