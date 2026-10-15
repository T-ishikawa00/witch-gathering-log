import CryptoKit
import SwiftUI

/// Same-snapshot, no-reward trials for available campaign enemies and unlocked research.
struct GearComparisonR136Section: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: GameModel
    let items: [GearInstance]
    @State private var targetKey = ""
    @State private var results: [UUID: TrialCard] = [:]
    @State private var runError: String?
    @State private var activeRun: UUID?
    @State private var previewTask: Task<Void, Never>?

    private var campaignEnemies: [EnemyDefinition] {
        model.engine?.availableCampaignGearTrialEnemiesR136(snapshot: model.state) ?? []
    }
    private var availableChallenges: [ChallengeDefinition] {
        guard let catalog = model.catalog else { return [] }
        let progress = PostClearGoalProjectionR122.project(catalog: catalog, state: model.state)
        let ids = Set(progress.challenges.filter { $0.availability != .locked }.map(\.id))
        return catalog.challenges.filter { ids.contains($0.id) }
    }
    private var availableTargets: [TrialTargetChoiceR136] {
        campaignEnemies.map { .init(target: .campaign($0.id), name: "探索：" + $0.name) }
        + availableChallenges.map { .init(target: .challenge($0.id), name: "研究：" + $0.name) }
    }
    private var defaultTargetKey: String {
        let campaign = campaignEnemies.first { !model.state.completedEncounterIDs.contains($0.id) }
            ?? campaignEnemies.last
        if let campaign { return GearTrialTargetR136.campaign(campaign.id).key }
        return availableTargets.first?.id ?? ""
    }
    private var selectedTarget: GearTrialTargetR136? {
        availableTargets.first { $0.id == targetKey }?.target
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("この相手で試す").font(.headline)
            Text("同じ敵・仲間で、2つの装備を一つずつ試します。装備や進行、報酬は変わりません。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            Text("比べる仲間：" + (GameModel.actorNames[model.selectedActor] ?? "仲間"))
                .font(.subheadline).foregroundStyle(Palette.gold)
                .accessibilityIdentifier("gear_trial_actor")
            if availableChallenges.isEmpty {
                Text(nextUnlockGuidance).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gear_trial_no_unlocked_challenge")
            }
            if availableTargets.isEmpty {
                Text("探索先を選ぶと、そこで戦える相手の装備比較を試せます。")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gear_trial_no_available_target")
            } else {
                Picker("試す相手", selection: $targetKey) {
                    ForEach(availableTargets) { choice in
                        Text(choice.name).tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("gear_trial_target_picker")
                Button(action: runPair) {
                    Text(activeRun == nil ? "条件をそろえて試す" : "計算中…")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                .disabled(activeRun != nil || model.busy || model.fighting || items.count != 2 ||
                          model.engine == nil || selectedTarget == nil)
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
        .onAppear { if targetKey.isEmpty { targetKey = defaultTargetKey } }
        .onDisappear { invalidate() }
        .onChange(of: targetKey) { _, _ in invalidate() }
        .onChange(of: model.selectedActor) { _, _ in invalidate() }
        .onChange(of: model.comparison) { _, _ in invalidate() }
        .onChange(of: model.busy) { _, busy in if busy { invalidate() } }
        .onChange(of: model.state.revision) { _, _ in
            invalidate()
            if selectedTarget == nil { targetKey = defaultTargetKey }
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
              let target = selectedTarget else { return }
        let actorID = model.selectedActor
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
                      selectedTarget == target, !model.busy, !model.fighting else { return }
                let seed = UInt64(bitPattern: baseline.revision) &+ 0x5231
                let qaArguments = ProcessInfo.processInfo.arguments
                let captureEarnedSave = qaArguments.contains("--qa-isolated") &&
                    qaArguments.filter { $0 == "--qa-gear-trial-readback-r140" }.count == 1
                let baselineSaveSHA256 = captureEarnedSave ? model.saveURL.flatMap { try? Data(contentsOf: $0) }.map {
                    SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
                } : nil
                let calculation = Task.detached(priority: .userInitiated) {
                    try await GearTrialWorkerR136.shared.run(engine: engine, ids: selectedIDs,
                        actorID: actorID, target: target, seed: seed, baseline: baseline)
                }
                let previews = try await withTaskCancellationHandler {
                    try await calculation.value
                } onCancel: { calculation.cancel() }
                let after = await engine.snapshot()
                guard !Task.isCancelled, activeRun == token else { return }
                guard after == baseline, model.state == baseline, !model.busy, !model.fighting,
                      model.selectedActor == actorID, model.comparison == selectedIDs,
                      selectedTarget == target else {
                    runError = "装備や探索先が変わりました。最新の状態でもう一度試してください。"
                    return
                }
                var completed: [UUID: TrialCard] = [:]
                for preview in previews {
                    guard selectedIDs.contains(preview.selectedGearID), preview.actorID == actorID,
                          preview.target == target, preview.seed == seed, preview.slot == slot,
                          preview.currentGearID == baseline.equippedGearIDs[actorID + "|" + slot] else {
                        throw GearSwapCombatPreviewErrorR131.wrongGearSlot
                    }
                    let currentName: String
                    if let id = preview.currentGearID,
                       let gear = baseline.gear.first(where: { $0.id == id }),
                       let definition = catalog.gear.first(where: { $0.id == gear.definitionID }) {
                        currentName = definition.name
                    } else { currentName = "この部位の装備なし" }
                    completed[preview.selectedGearID] = TrialCard(summary: preview.summary, currentName: currentName)
                }
                guard completed.count == 2 else { throw GearSwapCombatPreviewErrorR131.wrongGearSlot }
                results = completed
                writeQAReceipt(previews: previews, baseline: baseline, seed: seed, baselineSaveSHA256: baselineSaveSHA256)
            } catch is CancellationError {
                // A closed sheet or changed selection must never publish old results.
            } catch let error as GearSwapCombatPreviewErrorR131 {
                if activeRun == token { runError = localized(error); results = [:] }
            } catch is CampaignGearTrialErrorR136 {
                if activeRun == token {
                    runError = "この相手とはまだ戦えません。探索先と解放状況を確認してください。"
                    results = [:]
                }
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
                return "「\(enemy.name)」を倒すと研究課題が解放されます。"
            }
        }
        return "研究課題は、各課題の解放条件を満たすと選べます。"
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

    private func writeQAReceipt(previews: [TrialPreviewR136], baseline: GameSnapshot, seed: UInt64, baselineSaveSHA256: String?) {
        let args = ProcessInfo.processInfo.arguments
        let r131FixtureReceipt = args.contains("--qa-r131-gear-comparison")
        let r140EarnedReceipt = args.filter { $0 == "--qa-gear-trial-readback-r140" }.count == 1
        guard args.contains("--qa-isolated"), r131FixtureReceipt != r140EarnedReceipt,
              let saveURL = model.saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else { return }
        if r140EarnedReceipt {
            let keys = args.filter { $0.hasPrefix("--qa-save-key=") }
            guard keys.count == 1,
                  let key = keys.first?.split(separator: "=", maxSplits: 1).last.map(String.init),
                  UUID(uuidString: key) != nil,
                  saveURL.lastPathComponent == "qa-\(key)-save.json",
                  !args.contains("--qa-r131-gear-comparison"),
                  !args.contains(where: { $0.hasPrefix("--qa-fixture=") || $0 == "--qa-persist-fixture" ||
                      $0 == "--qa-readback-save" || $0.contains("grant") || $0.contains("time-override") || $0.contains("fast-battle") }) else { return }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let rows: [[String: Any]] = previews.compactMap { preview in
            guard let raw = try? encoder.encode(preview.summary),
                  let summary = try? JSONSerialization.jsonObject(with: raw) else { return nil }
            var row: [String: Any] = ["selectedGearID": preview.selectedGearID.uuidString,
                "currentGearID": preview.currentGearID?.uuidString ?? "", "actorID": preview.actorID,
                "targetKind": preview.target.kind, "targetID": preview.target.value,
                "slot": preview.slot, "seed": String(seed), "summary": summary]
            switch preview.target {
            case .campaign(let id): row["enemyID"] = id
            case .challenge(let id): row["challengeID"] = id
            }
            return row
        }
        var metadata: [String: Any] = [
            "saveFilename": saveURL.lastPathComponent, "baselineRevision": baseline.revision,
            "processID": ProcessInfo.processInfo.processIdentifier,
            "orderedGearIDs": previews.map(\.selectedGearID.uuidString), "results": rows,
            "simulationOnly": true, "rewardsCommitted": false]
        if r140EarnedReceipt {
            let after = try? Data(contentsOf: saveURL)
            let afterSHA = after.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
            metadata["r140BaselineSaveSHA256"] = baselineSaveSHA256 ?? "UNAVAILABLE"
            metadata["r140SaveSHA256AtReceipt"] = afterSHA ?? "UNAVAILABLE"
            metadata["r140SaveBytesUnchanged"] = baselineSaveSHA256 != nil && afterSHA == baselineSaveSHA256
        }
        model.writeReceipt("gear_trial_r136", "READ_ONLY_PAIR", metadata: metadata)
    }

    private struct TrialCard {
        let summary: GearSwapCombatSummaryR131
        let currentName: String
    }
}

private enum GearTrialTargetR136: Equatable, Sendable {
    case campaign(String)
    case challenge(String)
    var value: String { switch self { case .campaign(let id), .challenge(let id): return id } }
    var kind: String { switch self { case .campaign: return "campaign"; case .challenge: return "challenge" } }
    var key: String { kind + ":" + value }
}
private struct TrialTargetChoiceR136: Identifiable {
    let target: GearTrialTargetR136
    let name: String
    var id: String { target.key }
}
private enum TrialPreviewR136: Sendable {
    case campaign(CampaignGearSwapPreviewR136)
    case challenge(GearSwapCombatPreviewR131)
    var target: GearTrialTargetR136 { switch self {
        case .campaign(let p): return .campaign(p.enemyID)
        case .challenge(let p): return .challenge(p.challengeID)
    } }
    var actorID: String { switch self { case .campaign(let p): return p.actorID; case .challenge(let p): return p.actorID } }
    var currentGearID: UUID? { switch self { case .campaign(let p): return p.currentGearID; case .challenge(let p): return p.currentGearID } }
    var selectedGearID: UUID { switch self { case .campaign(let p): return p.selectedGearID; case .challenge(let p): return p.selectedGearID } }
    var slot: String { switch self { case .campaign(let p): return p.slot; case .challenge(let p): return p.slot } }
    var seed: UInt64 { switch self { case .campaign(let p): return p.seed; case .challenge(let p): return p.seed } }
    var summary: GearSwapCombatSummaryR131 { switch self {
        case .campaign(let p): return .make(from: p)
        case .challenge(let p): return .make(from: p)
    } }
}

/// Serial across sheet instances. Cancelling checks between bounded battles.
private actor GearTrialWorkerR136 {
    static let shared = GearTrialWorkerR136()
    func run(engine: GameEngine, ids: [UUID], actorID: String, target: GearTrialTargetR136,
             seed: UInt64, baseline: GameSnapshot) throws -> [TrialPreviewR136] {
        try ids.map { id in
            try Task.checkCancellation()
            switch target {
            case .campaign(let enemyID):
                return .campaign(try engine.previewCampaignGearSwapR136(enemyID: enemyID,
                    actorID: actorID, selectedGearID: id, seed: seed, snapshot: baseline))
            case .challenge(let challengeID):
                return .challenge(try engine.previewChallengeGearSwapR131(challengeID: challengeID,
                    actorID: actorID, selectedGearID: id, seed: seed, snapshot: baseline))
            }
        }
    }
}
