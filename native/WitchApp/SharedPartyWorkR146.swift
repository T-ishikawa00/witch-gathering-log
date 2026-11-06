import Foundation
import SwiftUI

/// Narrow app-side opt-in gate. Ordinary app launches return false without changing
/// runtime selection. A partial/malformed R146 invocation fails before save loading.
enum SharedPartyWorkLaunchGateR146 {
    static let flag = "--qa-shared-party-work-r146"
    // Kept local to this nonisolated argument parser: EnemyEventRenderRequestR145
    // is MainActor-isolated, so querying its map here would require actor hopping.
    private static let r145EncounterIDs: Set<String> = [
        "E_R01_01", "E_R01_02", "E_R01_03", "E_R01_04", "B_R01_A", "B_R01_B",
        "E_R02_01", "E_R02_02", "E_R02_03", "E_R02_04", "B_R02_A", "B_R02_B",
        "E_R03_01", "E_R03_02", "E_R03_03", "E_R03_04", "B_R03_A", "B_R03_B",
        "E_R04_01", "E_R04_02", "E_R04_03", "E_R04_04", "B_R04_A", "B_R04_B",
        "E_R05_01", "E_R05_02", "E_R05_03", "E_R05_04", "B_R05_A", "B_R05_B"
    ]
    enum GateError: Error {
        case simulatorOnly
        case duplicateOrMissingFlag
        case isolatedAndCanonicalSaveKeyRequired
        case unsupportedDoubleDashArgument(String)
    }

    #if targetEnvironment(simulator)
    private static let simulatorBuild = true
    #else
    private static let simulatorBuild = false
    #endif

    static func parse(arguments: [String], environment: [String: String]) throws -> Bool {
        let featureArgs = arguments.filter { $0.hasPrefix("--qa-shared-party-work") }
        if featureArgs.isEmpty {
            guard !arguments.contains(where: { $0.hasPrefix("--qa-shared-party") }) else {
                throw GateError.duplicateOrMissingFlag
            }
            return false
        }
        guard featureArgs == [flag] else { throw GateError.duplicateOrMissingFlag }
        guard simulatorBuild,
              environment["SIMULATOR_UDID"]?.isEmpty == false,
              environment["SIMULATOR_DEVICE_NAME"]?.isEmpty == false else {
            throw GateError.simulatorOnly
        }
        guard arguments.filter({ $0 == "--qa-isolated" }).count == 1 else {
            throw GateError.isolatedAndCanonicalSaveKeyRequired
        }
        let keys = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        guard keys.count == 1,
              let raw = keys.first?.split(separator: "=", maxSplits: 1).last.map(String.init),
              let uuid = UUID(uuidString: raw), uuid.uuidString.lowercased() == raw else {
            throw GateError.isolatedAndCanonicalSaveKeyRequired
        }
        let screens = arguments.filter { $0.hasPrefix("--screen=") }
        guard screens.count <= 1, screens.allSatisfy({ $0 == "--screen=探索" }) else {
            throw GateError.unsupportedDoubleDashArgument(screens.first ?? "--screen")
        }
        // The art batch is a separate simulator-only diagnostic route. It is
        // accepted only as the complete R145 + challenge-fixture command set;
        // ordinary R146 invocations keep the original exact allowlist.
        let traceFlags = arguments.filter { $0 == "--qa-enemy-event-render-trace-r145" }
        let fixtures = arguments.filter { $0.hasPrefix("--qa-fixture=") }
        let persistFixtures = arguments.filter { $0 == "--qa-persist-fixture" }
        let encounters = arguments.filter { $0.hasPrefix("--qa-encounter=") }
        let artCapture = !traceFlags.isEmpty || !fixtures.isEmpty || !persistFixtures.isEmpty || !encounters.isEmpty
        var allowed = Set(["--qa-isolated", flag, keys[0], "--screen=探索"])
        if artCapture {
            guard traceFlags == ["--qa-enemy-event-render-trace-r145"],
                  fixtures == ["--qa-fixture=challenge"],
                  persistFixtures == ["--qa-persist-fixture"],
                  encounters.count == 1,
                  let encounterID = encounters.first?.split(separator: "=", maxSplits: 1).last.map(String.init),
                  r145EncounterIDs.contains(encounterID) else {
                throw GateError.unsupportedDoubleDashArgument("incomplete R145 challenge-capture request")
            }
            allowed.formUnion(["--qa-enemy-event-render-trace-r145", fixtures[0], persistFixtures[0], encounters[0]])
        }
        if let unexpected = arguments.first(where: { $0.hasPrefix("--") && !allowed.contains($0) }) {
            throw GateError.unsupportedDoubleDashArgument(unexpected)
        }
        return true
    }
}

struct SharedPartyWorkOptionR146: Identifiable {
    let target: PartyWorkTargetR144
    let title: String
    let detail: String
    let enabled: Bool
    var id: String { "\(target.kind.rawValue):\(target.targetID)" }
}

/// UI-only estimate mirrors the candidate engine's region interval and capped
/// shared clock. It never dispatches or writes. Native behavior remains unverified.
struct SharedPartyWorkProgressR146: View {
    let state: GameSnapshot
    let catalog: GameCatalog

    static func project(state: GameSnapshot, catalog: GameCatalog, now: Date) -> (target: String, materialID: String, ready: Int, secondsToNext: Int, interval: Int, capped: Bool)? {
        guard let regionID = state.activeRegionID,
              let region = catalog.regions.first(where: { $0.id == regionID }),
              region.workSeconds > 0,
              state.offlineRemainderSeconds.isFinite,
              state.offlineRemainderSeconds >= 0,
              state.offlineRemainderSeconds <= Double(region.workSeconds) else { return nil }
        guard let selected = state.partyWorkTargetR144,
              let materialID = sharedPartyWorkMaterialR146(target: selected, state: state, catalog: catalog) else { return nil }
        let targetName: String
        switch selected.kind {
        case .gather:
            targetName = "採集 · \(GameText.name(materialID))"
        case .investigate:
            let enemy = catalog.enemies.first { $0.id == selected.targetID }
            targetName = "再調査 · \(enemy?.name ?? "対象") → \(GameText.name(materialID))"
        }
        let interval = region.workSeconds
        let rawElapsed = state.lastClaimAt.map { now.timeIntervalSince($0) } ?? 0
        guard rawElapsed.isFinite, rawElapsed >= 0 else { return nil }
        let cap: TimeInterval = PartyWorkPolicyR144.offlineCapSeconds
        let capped = rawElapsed >= cap - state.offlineRemainderSeconds
        let accrued = min(cap, rawElapsed + state.offlineRemainderSeconds)
        guard accrued.isFinite, accrued >= 0 else { return nil }
        let readyDouble = accrued / Double(interval)
        guard readyDouble < Double(Int.max) else { return nil }
        let ready = Int(readyDouble)
        let remainder = accrued.truncatingRemainder(dividingBy: Double(interval))
        let remaining = remainder == 0 ? interval : max(1, interval - Int(remainder))
        return (targetName, materialID, ready, remaining, interval, capped)
    }

    /// True only when the saved target and active-region work configuration are valid,
    /// but the wall clock is earlier than the persisted settlement anchor. This distinguishes
    /// a recoverable clock rollback from an unconfigured or invalid target.
    static func hasRecoverableClockRollback(state: GameSnapshot, catalog: GameCatalog, now: Date) -> Bool {
        guard let anchor = state.lastClaimAt, now < anchor,
              let regionID = state.activeRegionID,
              let region = catalog.regions.first(where: { $0.id == regionID }),
              region.workSeconds > 0,
              state.offlineRemainderSeconds.isFinite,
              state.offlineRemainderSeconds >= 0,
              state.offlineRemainderSeconds <= Double(region.workSeconds),
              let target = state.partyWorkTargetR144,
              sharedPartyWorkMaterialR146(target: target, state: state, catalog: catalog) != nil else {
            return false
        }
        return true
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if let values = Self.project(state: state, catalog: catalog, now: context.date) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(values.target).font(.caption.weight(.semibold))
                            .accessibilityIdentifier("r146_shared_work_target")
                        if NaturalGearBuildPolicyR350.enabled {
                            if let ledger = state.naturalGearDiscoveryR350 {
                                let totalUnits = ledger.workUnitsIntoDrop + max(0, values.ready - (ledger.skipLegacyPartialUnit ? 1 : 0))
                                let gearReady = totalUnits / NaturalGearDiscoveryPolicyR350.workUnitsPerDrop
                                if gearReady > 0 {
                                    Text("装備の発見 \(gearReady)点 · 成果と一緒に受け取れます")
                                        .font(.caption).foregroundStyle(Palette.gold)
                                        .accessibilityIdentifier("natural_gear_ready_r350")
                                } else {
                                    let remainingUnits = NaturalGearDiscoveryPolicyR350.workUnitsPerDrop - ledger.workUnitsIntoDrop
                                        + (ledger.skipLegacyPartialUnit ? 1 : 0) - values.ready
                                    let remainingSeconds = max(1, (remainingUnits - 1) * values.interval + values.secondsToNext)
                                    Text("装備も探索中 · 次の発見まで約\((remainingSeconds + 59) / 60)分")
                                        .font(.caption2).accessibilityIdentifier("natural_gear_progress_r350")
                                }
                            } else {
                                Text("次の成果の受取から、装備も探し始めます。")
                                    .font(.caption2).accessibilityIdentifier("natural_gear_prospective_r350")
                            }
                        }
                        Text(values.capped
                             ? "蓄積上限（48時間分）に達しています · 受取可能 \(values.ready)単位"
                             : "次の成果まで \(values.secondsToNext)秒 · 完了 \(values.ready)単位 · 蓄積上限48時間")
                            .font(.caption2).monospacedDigit()
                            .accessibilityIdentifier("r146_shared_work_clock")
                    }
                } else if Self.hasRecoverableClockRollback(state: state, catalog: catalog, now: context.date) {
                    Text("保存日時より端末の日時が前になっています。日時が追いつくまで共同作業の進行と受取は一時停止します。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("r146_shared_work_clock_rollback")
                } else {
                    Text("共同作業の対象を選んでください。")
                        .font(.caption).accessibilityIdentifier("r146_shared_work_unconfigured")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}

struct SharedPartyWorkSummaryViewR146: View {
    let targetLabel: String?
    let summary: GatheringSummary
    var onInspectAllNewGear: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("共同作業の成果").font(.system(size: 25, design: .serif))
            if let targetLabel { Text(targetLabel).font(.callout).foregroundStyle(Palette.gold) }
            if summary.isEmpty {
                Text("完了した作業単位はありません。対象の成果時間がたまってから受け取れます。")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(summary.materials.map(\.0), id: \.self) { id in
                HStack {
                    AssetIcon(id: "ICO_" + id, size: 40).accessibilityHidden(true)
                    Text(GameText.name(id)); Spacer()
                    Text("+\(summary.materials.first { $0.0 == id }?.1 ?? 0)").monospacedDigit()
                }
            }
            ForEach(summary.currency.map(\.0), id: \.self) { id in
                HStack { Text(GameText.name(id)); Spacer(); Text("+\(summary.currency.first { $0.0 == id }?.1 ?? 0)").monospacedDigit() }
            }
            if !summary.gainedGear.isEmpty {
                GainedGearSummaryR350(summary: summary, onInspectAll: onInspectAllNewGear)
            }
            if !summary.experience.isEmpty {
                Divider()
                ForEach(summary.experience.map(\.0), id: \.self) { id in
                    HStack { Text(GameModel.actorNames[id] ?? id); Spacer(); Text("EXP +\(summary.experience.first { $0.0 == id }?.1 ?? 0)").monospacedDigit() }
                        .font(.caption)
                }
            }
            Text("この結果は保存済みです。").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("r146_shared_work_summary")
    }
}

struct SharedPartyWorkPanelR146: View {
    @ObservedObject var model: GameModel

    private var options: [SharedPartyWorkOptionR146] {
        guard let catalog = model.catalog,
              let regionID = model.state.activeRegionID,
              let region = catalog.regions.first(where: { $0.id == regionID }) else { return [] }
        let available = model.availableMaterials[regionID] ?? []
        var result = region.gatherMaterialIDs.map { materialID in
            SharedPartyWorkOptionR146(
                target: .gather(materialID), title: "採集 · \(GameText.name(materialID))",
                detail: available.contains(materialID) ? "地域の通常採集素材" : "まだ解放されていません",
                enabled: available.contains(materialID))
        }
        for enemyID in region.enemyIDs {
            guard let enemy = catalog.enemies.first(where: { $0.id == enemyID }) else { continue }
            let cleared = model.state.completedEncounterIDs.contains(enemy.id)
            let prerequisiteCleared = enemy.prerequisiteEncounterID.map(model.state.completedEncounterIDs.contains) ?? true
            let hasCatalogDrop = enemy.dropMaterialID.map(catalog.materialIDs.contains) ?? false
            let canInvestigate = cleared && prerequisiteCleared && hasCatalogDrop
            let detail: String
            if canInvestigate {
                detail = "初回討伐報酬は取得済み · 再調査では即時報酬なし"
            } else if !prerequisiteCleared {
                detail = "前の魔物を討伐すると解放 · 解放後に初回討伐できます"
            } else if !cleared {
                detail = "初回討伐で通常報酬 · 討伐後に再調査できます"
            } else {
                detail = "この魔物は現在再調査できません"
            }
            result.append(SharedPartyWorkOptionR146(
                target: .investigate(enemy.id), title: "再調査 · \(enemy.name)",
                detail: detail, enabled: canInvestigate))
        }
        return result
    }

    private var selectedWorkGuidance: String {
        guard let target = model.state.partyWorkTargetR144 else {
            return "作業対象を選ぶと、時間に応じて成果が蓄積されます。"
        }
        switch target.kind {
        case .gather:
            return "\(GameText.name(target.targetID))を仲間が採集します。成果は時間に応じて蓄積され、ここで受け取れます。"
        case .investigate:
            let enemyName = model.catalog?.enemies.first(where: { $0.id == target.targetID })?.name ?? "討伐済みの魔物"
            return "\(enemyName)を再調査し、時間に応じて素材を集めます。再調査中に即時報酬はありません。"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            panel(now: context.date)
        }
    }

    private func panel(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("共同作業").font(.headline)
            Text(selectedWorkGuidance)
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("r146_shared_work_guidance")
            ForEach(options) { option in
                Button {
                    model.selectSharedPartyWorkTargetR146(option.target)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(option.title).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            if model.state.partyWorkTargetR144 == option.target {
                                Text("選択中").font(.caption).foregroundStyle(Palette.gold)
                            }
                        }
                        Text(option.detail).font(.caption2).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(model.busy || model.fighting || !option.enabled)
                .accessibilityIdentifier("r146_work_" + option.id.replacingOccurrences(of: ":", with: "_"))
                .accessibilityValue(model.state.partyWorkTargetR144 == option.target ? "選択中" : option.enabled ? "選択できます" : "未解放")
            }
            Button { model.collect() } label: {
                Label("共同作業の成果を受け取る", systemImage: "basket")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || model.fighting || (model.catalog.flatMap { SharedPartyWorkProgressR146.project(state: model.state, catalog: $0, now: now)?.ready } ?? 0) == 0)
            .accessibilityIdentifier("r146_shared_work_collect")
        }
        .padding(12)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("r146_shared_party_work_panel")
    }
}

@MainActor extension GameModel {
    func prepareFreshSharedPartyWorkR146(
        existingSaveLoaded: Bool = false,
        freshSaveReceiptMode: String? = "UNAPPROVED_SIMULATOR_QA_CANDIDATE") async throws {
        guard sharedPartyWorkR146Enabled, let engine else { return }
        if qaLoadedExistingSave || existingSaveLoaded {
            guard let target = state.partyWorkTargetR144, target.futureVersion == 2,
                  let catalog,
                  sharedPartyWorkMaterialR146(target: target, state: state, catalog: catalog) != nil else {
                throw CoreError.invalidCommand("R146 existing save lacks a valid R144 policy marker or active target")
            }
            return
        }
        guard state.partyWorkTargetR144 == nil,
              let catalog,
              let regionID = state.activeRegionID,
              let region = catalog.regions.first(where: { $0.id == regionID }) else {
            throw CoreError.invalidCommand("R146 fresh save has no valid active region")
        }
        let available = await engine.availableGatherMaterials(in: regionID)
        let target = state.gatherTargetMaterialID.flatMap { available.contains($0) ? $0 : nil } ?? available.first
        guard let target else { throw CoreError.invalidCommand("R146 fresh save has no unlocked initial work target") }
        _ = try await engine.setPartyWorkTargetR144(.gather(target), now: Date(),
                                                    operationID: UUID(), expectedRevision: state.revision)
        await refresh()
        if let freshSaveReceiptMode {
            writeReceipt("shared_party_work_r146", "ENABLED_FRESH_SAVE", metadata: [
                "policyID": PartyWorkPolicyR144.policyID,
                "targetKind": "gather", "targetID": target,
                "mode": freshSaveReceiptMode
            ])
        }
    }

    /// Publish the visible region only after the atomic Core selection commits.
    func selectSharedPartyWorkRegionR146(_ regionID: String) {
        guard sharedPartyWorkR146Enabled, !busy, !fighting, let engine else { return }
        clearPendingGatherVisualForSharedWorkR146()
        busy = true
        let before = state
        Task { @MainActor in
            do {
                _ = try await engine.dispatchConfirmingSavedReceipt(.startExpeditionAt(regionID: regionID, now: Date()),
                                              operationID: UUID(), expectedRevision: before.revision)
                chosenRegion = regionID
                await refresh()
                notice = (catalog?.regions.first { $0.id == regionID }?.name ?? regionID) + "へ出発しました。"
                appendNaturalGearNoticeR350(since: before)
                writeReceipt("shared_party_work_r146", "REGION_SELECTED", metadata: [
                    "regionID": regionID, "targetKind": state.partyWorkTargetR144?.kind.rawValue ?? "none",
                    "targetID": state.partyWorkTargetR144?.targetID ?? "none",
                    "policyID": PartyWorkPolicyR144.policyID])
            } catch {
                self.error = commandErrorText(error)
                await refresh()
                chosenRegion = state.activeRegionID ?? chosenRegion
                syncScene()
            }
            busy = false
        }
    }

    func selectSharedPartyWorkTargetR146(_ target: PartyWorkTargetR144) {
        guard sharedPartyWorkR146Enabled, !busy, !fighting, let engine else { return }
        clearPendingGatherVisualForSharedWorkR146()
        busy = true
        let before = state
        Task { @MainActor in
            do {
                let receipt = try await engine.setPartyWorkTargetR144(target, now: Date(),
                                                                      operationID: UUID(), expectedRevision: before.revision)
                await refresh()
                collectionSummary = GatheringSummary(before: before, after: state, catalog: catalog)
                let settledTarget = before.partyWorkTargetR144 ?? before.gatherTargetMaterialID.map(PartyWorkTargetR144.gather)
                sharedPartyWorkSummaryTargetR146 = sharedPartyWorkLabelR146(target: settledTarget, state: before, catalog: catalog)
                let settledMaterialID = settledTarget.flatMap { sharedPartyWorkMaterialR146(target: $0, state: before, catalog: catalog) }
                let amount = settledMaterialID.map { state.materials[$0, default: 0] - before.materials[$0, default: 0] } ?? 0
                let targetName = target.kind == .investigate
                    ? (catalog?.enemies.first(where: { $0.id == target.targetID })?.name ?? "対象")
                    : "採集"
                if amount > 0, let settledMaterialID {
                    notice = "切替前の共同作業から\(GameText.name(settledMaterialID))を\(amount)個受け取り、\(targetName)へ切り替えました。"
                } else if target.kind == .investigate {
                    notice = "\(targetName)の再調査を始めました。即時報酬はありません。"
                } else {
                    notice = "採集を始めました。"
                }
                if collectionSummary?.isEmpty == false { sheet = "共同作業の成果" }
                writeReceipt("shared_party_work_r146", "TARGET_SELECTED", metadata: [
                    "targetKind": target.kind.rawValue, "targetID": target.targetID,
                    "settledTargetKind": settledTarget?.kind.rawValue ?? "none",
                    "settledTargetID": settledTarget?.targetID ?? "none",
                    "materialID": settledMaterialID.map { $0 as Any } ?? NSNull(), "materialDelta": amount,
                    "result": receipt.result,
                    "policyID": PartyWorkPolicyR144.policyID
                ])
            } catch {
                self.error = commandErrorText(error)
                await refresh()
            }
            busy = false
        }
    }

    func collectSharedPartyWorkR146() {
        guard sharedPartyWorkR146Enabled, !busy, !fighting, let engine,
              let catalog,
              (SharedPartyWorkProgressR146.project(state: state, catalog: catalog, now: Date())?.ready ?? 0) > 0,
              let target = state.partyWorkTargetR144 else { return }
        busy = true
        clearPendingGatherVisualForSharedWorkR146()
        let before = state
        let now = Date()
        Task { @MainActor in
            do {
                let receipt = try await engine.claimOfflineConfirmingSavedReceipt(now: now, operationID: UUID(),
                                                            expectedRevision: before.revision)
                await refresh()
                collectionSummary = GatheringSummary(before: before, after: state, catalog: catalog)
                sharedPartyWorkSummaryTargetR146 = sharedPartyWorkLabelR146(target: target, state: before, catalog: catalog)
                let materialID = sharedPartyWorkMaterialR146(target: target, state: before, catalog: catalog)
                let amount = materialID.map { state.materials[$0, default: 0] - before.materials[$0, default: 0] } ?? 0
                if target.kind == .gather, amount > 0, let materialID {
                    setPendingGatherVisualForSharedWorkR146(materialID)
                    notice = "採集の成果として\(GameText.name(materialID))を\(amount)個受け取りました。"
                    WitchAudioCoordinator.shared.play(.gather)
                } else if target.kind == .investigate, amount > 0, let materialID {
                    notice = "再調査の成果として\(GameText.name(materialID))を\(amount)個受け取りました。"
                } else {
                    notice = "完了した作業はありません。"
                }
                sheet = "共同作業の成果"
                writeReceipt("shared_party_work_r146", "COLLECTED", metadata: [
                    "targetKind": target.kind.rawValue, "targetID": target.targetID,
                    "materialID": materialID.map { $0 as Any } ?? NSNull(), "materialDelta": amount,
                    "result": receipt.result, "policyID": PartyWorkPolicyR144.policyID
                ])
            } catch {
                self.error = commandErrorText(error)
                await refresh()
            }
            busy = false
        }
    }
}

private func sharedPartyWorkMaterialR146(target: PartyWorkTargetR144, state: GameSnapshot,
                                          catalog: GameCatalog?) -> String? {
    guard let catalog, let regionID = state.activeRegionID,
          state.unlockedRegionIDs.contains(regionID),
          let region = catalog.regions.first(where: { $0.id == regionID }) else { return nil }
    switch target.kind {
    case .gather:
        let available = catalog.availableGatherMaterialIDs(in: regionID,
            unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs)
        guard region.gatherMaterialIDs.contains(target.targetID), available.contains(target.targetID) else { return nil }
        return target.targetID
    case .investigate:
        guard let enemy = catalog.enemies.first(where: { $0.id == target.targetID }),
              region.enemyIDs.contains(enemy.id), enemy.regionID == regionID,
              state.completedEncounterIDs.contains(enemy.id),
              enemy.prerequisiteEncounterID.map(state.completedEncounterIDs.contains) ?? true,
              let materialID = enemy.dropMaterialID,
              catalog.materialIDs.contains(materialID) else { return nil }
        return materialID
    }
}

private func sharedPartyWorkLabelR146(target: PartyWorkTargetR144?, state: GameSnapshot,
                                       catalog: GameCatalog?) -> String? {
    guard let target else { return nil }
    switch target.kind {
    case .gather:
        return "採集 · \(GameText.name(target.targetID))"
    case .investigate:
        guard let catalog, let enemy = catalog.enemies.first(where: { $0.id == target.targetID }),
              let materialID = enemy.dropMaterialID else { return "再調査 · \(target.targetID)" }
        return "再調査 · \(enemy.name) → \(GameText.name(materialID))"
    }
}
