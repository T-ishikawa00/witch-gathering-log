import SwiftUI

struct ResearchGatherPreviewR310: View {
    @ObservedObject var model: GameModel
    let route: ResearchGatherHandoffR310
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let preview = ResearchGatherRouteR310.resolve(route, catalog: model.catalog, state: model.state) {
                Text(preview.researchName).font(.headline)
                HStack(spacing: 12) {
                    AssetIcon(id: "ICO_" + route.materialID, size: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(GameText.name(route.materialID)).font(.title3)
                        Text("\(preview.regionName) · あと\(preview.missing)個")
                            .accessibilityIdentifier("research_gather_summary_r310")
                    }
                }
                if model.researchGatherTargetIsSelectedR310(route) {
                    Text("この素材を採集中です。受け取る前の成果は不足数に含まれていません。")
                        .accessibilityIdentifier("research_gather_already_selected_r310")
                } else {
                    Text("採集を始めると、それまでの作業で得た成果を受け取り、採集先を切り替えます。端数の時間は引き継がれません。")
                }
                Text("この画面を閉じても、現在の作業は変わりません。")
                    .font(.caption).foregroundStyle(Palette.gold)
                Button(action: onApply) {
                    Label(model.researchGatherTargetIsSelectedR310(route) ? "採集を続ける" : "この素材を採集する", systemImage: "leaf")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                .disabled(model.busy || model.fighting)
                .accessibilityIdentifier("research_gather_apply_r310")
            } else {
                Text("素材の不足数や採集条件が変わりました。閉じて研究を確認してください。")
                    .accessibilityIdentifier("research_gather_stale_r310")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

extension GameModel {
    func researchGatherTargetIsSelectedR310(_ route: ResearchGatherHandoffR310) -> Bool {
        state.activeRegionID == route.regionID && RecipeGatherHandoffTargetR157.isCommitted(
            sharedWorkEnabled: sharedPartyWorkR146Enabled,
            typedTarget: state.partyWorkTargetR144,
            legacyGatherTargetID: state.gatherTargetMaterialID,
            requestedMaterialID: route.materialID)
    }

    func applyResearchGatherHandoffR310(_ route: ResearchGatherHandoffR310) async throws {
        guard !busy, !fighting, let engine, let catalog else {
            throw CoreError.invalidCommand("今は採集先を切り替えられません。")
        }
        busy = true
        defer { busy = false }
        await refresh()
        guard ResearchGatherRouteR310.resolve(route, catalog: catalog, state: state) != nil else {
            throw CoreError.invalidCommand("素材の不足数や採集条件が変わりました。研究を開き直してください。")
        }
        // Reopening the current source is navigation, never an implicit claim.
        if researchGatherTargetIsSelectedR310(route) {
            notice = "\(GameText.name(route.materialID))の採集を続けています。成果は受け取る操作で確認できます。"
            return
        }
        if sharedPartyWorkR146Enabled { clearPendingGatherVisualForSharedWorkR146() }
        let commandTime = Date()
        var regionCommitted = false
        do {
            if state.activeRegionID != route.regionID {
                _ = try await engine.dispatch(.startExpeditionAt(regionID: route.regionID, now: commandTime),
                    operationID: UUID(), expectedRevision: state.revision)
                await refresh()
                regionCommitted = state.activeRegionID == route.regionID
            }
            guard state.activeRegionID == route.regionID,
                  ResearchGatherRouteR310.resolve(route, catalog: catalog, state: state) != nil else {
                throw CoreError.invalidCommand("採集条件が変わったため、素材の目標は設定していません。研究を確認してください。")
            }
            if !researchGatherTargetIsSelectedR310(route) {
                if sharedPartyWorkR146Enabled {
                    _ = try await engine.setPartyWorkTargetR144(.gather(route.materialID), now: commandTime,
                        operationID: UUID(), expectedRevision: state.revision)
                } else {
                    _ = try await engine.dispatch(.setGatherTargetAt(resourceID: route.materialID, now: commandTime),
                        operationID: UUID(), expectedRevision: state.revision)
                }
                await refresh()
            }
            guard researchGatherTargetIsSelectedR310(route) else {
                throw CoreError.invalidCommand("指定した素材を採集目標に設定できませんでした。")
            }
            let missing = ResearchGatherRouteR310.resolve(route, catalog: catalog, state: state)?.missing
            let remaining = missing.map { "研究まであと\($0)個です。" } ?? "所持数は研究の画面で確認できます。"
            notice = "\(GameText.name(route.materialID))の採集を始めました。" + remaining
        } catch {
            await refresh()
            if regionCommitted {
                chosenRegion = state.activeRegionID ?? chosenRegion
                notice = "地域の移動と、それまでの作業の受け取りは保存されています。素材の目標を確認してください。"
                throw CoreError.invalidCommand(notice + " " + GameText.error(error))
            }
            throw error
        }
    }
}
