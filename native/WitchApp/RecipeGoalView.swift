import SwiftUI

struct RecipeGatherHandoffR039: Equatable {
    let recipeID: String
    let materialID: String
    let regionID: String
    let missing: Int
}

extension GameModel {
    func applyRecipeGatherHandoffR039(_ route: RecipeGatherHandoffR039) async throws {
        guard !busy, !fighting, let engine, let catalog else {
            throw CoreError.invalidCommand("採集先を切り替えられません。")
        }
        var projectedState = state
        projectedState.trackedRecipeID = route.recipeID
        guard let goal = RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: projectedState),
              let requirement = goal.requirements.first(where: { $0.materialID == route.materialID }),
              requirement.missing > 0,
              requirement.availableGatherRegions.contains(route.regionID) else {
            throw CoreError.invalidCommand("目標の不足数または採集先が変わりました。目標を開き直してください。")
        }
        busy = true
        defer { busy = false }
        let commandTime = Date()
        var regionDispatchCommitted = false
        do {
            if state.activeRegionID != route.regionID {
                _ = try await engine.dispatch(.startExpeditionAt(regionID: route.regionID, now: commandTime),
                                              operationID: UUID(), expectedRevision: state.revision)
                await refresh()
                regionDispatchCommitted = state.activeRegionID == route.regionID
            }
            guard state.activeRegionID == route.regionID else {
                throw CoreError.invalidCommand("指定した地域へ移動できませんでした。")
            }
            if state.gatherTargetMaterialID != route.materialID {
                _ = try await engine.dispatch(.setGatherTargetAt(resourceID: route.materialID, now: commandTime),
                                              operationID: UUID(), expectedRevision: state.revision)
                await refresh()
            }
            guard state.gatherTargetMaterialID == route.materialID else {
                throw CoreError.invalidCommand("指定した素材を採集目標に設定できませんでした。")
            }
            // Switching a region or target settles elapsed work. Re-project the
            // shortage from the committed state instead of the old preview.
            var settledState = state
            settledState.trackedRecipeID = route.recipeID
            let remaining = RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: settledState)?
                .requirements.first(where: { $0.materialID == route.materialID })?.missing
            let progress = remaining.map { $0 == 0 ? "この材料は必要数が揃いました。" : "目標まであと\($0)個です。" } ?? "制作目標で所持数を確認できます。"
            notice = "\(GameText.name(route.materialID))を採集します。" + progress + "成果は『成果を受け取る』から受け取れます。"
        } catch {
            // Region selection may have committed before target selection failed.
            await refresh()
            if regionDispatchCommitted && state.activeRegionID == route.regionID && state.gatherTargetMaterialID != route.materialID {
                notice = "地域は切り替わりましたが、素材目標は未設定です。採集・魔物から選び直してください。"
            }
            throw error
        }
    }
    var recipeGoals: [RecipeGoalProjectionR035.Goal] {
        guard let catalog else { return [] }
        return RecipeGoalProjectionR035.goals(catalog: catalog, state: state)
    }

    var trackedRecipeGoal: RecipeGoalProjectionR035.Goal? {
        guard let catalog else { return nil }
        return RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: state)
    }

    var previewRecipeGoal: RecipeGoalProjectionR035.Goal? {
        let target = previewRecipeID ?? state.trackedRecipeID
        guard let target, let catalog else { return nil }
        // This value copy is display context only. It is never dispatched or saved.
        // Direct resolution keeps the preview visible after its parent evolves.
        var displayState = state
        displayState.trackedRecipeID = target
        return RecipeGoalProjectionR035.trackedGoal(catalog: catalog, state: displayState)
    }

    func showRecipeGoal(_ recipeID: String, gearID: UUID? = nil) {
        previewRecipeID = recipeID
        previewRecipeGearID = gearID
        sheet = "制作目標"
    }

    func recipeGearName(_ id: String) -> String {
        catalog?.gear.first { $0.id == id }?.name ?? "装備情報を確認できません"
    }

    func recipeRegionNames(_ ids: [String]) -> String {
        ids.map { id in catalog?.regions.first { $0.id == id }?.name ?? "地域情報を確認できません" }
            .joined(separator: "、")
    }

    func recipeDropSourceLines(_ materialID: String) -> [String] {
        guard let catalog else { return [] }
        return catalog.enemies.filter { $0.dropMaterialID == materialID }.map { enemy in
            let available = state.unlockedRegionIDs.contains(enemy.regionID)
                && (enemy.prerequisiteEncounterID.map(state.completedEncounterIDs.contains) ?? true)
            return (available ? "討伐: " : "討伐の解放待ち: ") + enemy.name
                + "（" + recipeRegionNames([enemy.regionID]) + "）"
        }
    }

    func recipeGateText(_ goal: RecipeGoalProjectionR035.Goal) -> String? {
        guard !goal.gateCleared else { return nil }
        let parts = (goal.gateID ?? "").split(separator: "_")
        guard parts.count == 3, parts[0] == "G",
              let enemy = catalog?.enemies.first(where: { $0.id == "B_\(parts[1])_\(parts[2])" }) else {
            return "解放条件を確認できません。"
        }
        return enemy.name + "の討伐で解放されます。"
    }
}

struct RecipeGoalSummaryView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        if let goal = model.trackedRecipeGoal {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    AssetIcon(id: "ICO_" + goal.outputGearID, size: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("次の制作目標").font(.caption).foregroundStyle(Palette.gold)
                        Text(model.recipeGearName(goal.outputGearID)).font(.headline)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                Text(goal.outputOwned ? "目標の型の装備を所持しています" : goal.parentOwned == false ? "元の装備を確認しよう" : goal.ready ? "必要な材料が揃いました" : "材料と入手先を確認する")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button { model.showRecipeGoal(goal.recipeID) } label: {
                    Text("材料を確認").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.bordered).accessibilityIdentifier("tracked_recipe_summary")
                    .disabled(model.busy)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Palette.text)
        }
    }
}

struct RecipeGoalView: View {
    @ObservedObject var model: GameModel
    var onGatherSource: ((String, String, String, Int) -> Void)? = nil

    var body: some View {
        if let goal = model.previewRecipeGoal {
            VStack(alignment: .leading, spacing: 16) {
                Text(goal.kind == "evolve_in_place" ? "装備を育てる準備" : "制作の準備")
                    .font(.system(.title, design: .serif))
                HStack(alignment: .top, spacing: 12) {
                    AssetIcon(id: "ICO_" + goal.outputGearID, size: 72).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.recipeGearName(goal.outputGearID)).font(.headline)
                        if let parent = goal.parentTemplateID {
                            Text(model.recipeGearName(parent) + "から進化").font(.caption)
                        }
                        if goal.outputOwned { Text("この型の装備を所持しています").font(.caption) }
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if let lock = model.recipeGateText(goal) { Text(lock).foregroundStyle(Palette.gold) }
                if goal.parentOwned == false {
                    Text(goal.outputOwned
                         ? "目標の型の装備を所持しています。目標は保存したままなので、解除するか別の目標を選べます。"
                         : "進化の元になる装備を所持していません。目標はそのまま残しています。")
                        .foregroundStyle(Palette.gold).accessibilityIdentifier("recipe_goal_parent_status")
                }
                Text("必要な材料").font(.headline)
                ForEach(goal.requirements, id: \.materialID) { requirement in
                    requirementCard(requirement, recipeID: goal.recipeID)
                }
                if goal.dustRequired > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("研成の粉  \(goal.dustOwned) / \(goal.dustRequired)")
                        Text(goal.dustMissing == 0 ? "必要数を所持しています" : "あと\(goal.dustMissing)個。同じ型を2個以上持つ、未保護・未使用の装備を分解すると手に入ります。")
                            .font(.caption).foregroundStyle(Palette.gold)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if model.state.trackedRecipeID == goal.recipeID {
                    Label("この装備を目標にしています", systemImage: "bookmark.fill")
                        .foregroundStyle(Palette.gold).accessibilityIdentifier("recipe_goal_selected")
                    Button { model.act(.setTrackedRecipe(nil), "制作目標を解除しました。") } label: {
                        actionLabel("目標を解除する")
                    }.buttonStyle(.bordered).accessibilityIdentifier("clear_recipe_goal")
                } else {
                    Button { model.act(.setTrackedRecipe(goal.recipeID), "制作目標を保存しました。") } label: {
                        actionLabel("この装備を目標にする")
                    }.buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("track_recipe_goal")
                }
                if goal.kind == "craft_new" {
                    Button { model.act(.craftRecipe(goal.recipeID), "装備を制作しました。") } label: {
                        actionLabel("制作する")
                    }.buttonStyle(.bordered).disabled(!goal.ready)
                        .accessibilityIdentifier("goal_craft")
                } else if let itemID = model.previewRecipeGearID,
                          let item = model.state.gear.first(where: { $0.id == itemID }),
                          item.definitionID == goal.parentTemplateID {
                    Text("育てる装備: " + parentDescription(item))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recipe_selected_parent")
                    GearLatentDetailsView(model: model, item: item)
                    Button { model.previewRecipeGearID = nil } label: { actionLabel("育てる装備を選び直す") }
                        .buttonStyle(.bordered).accessibilityIdentifier("recipe_reselect_parent")
                    Button { model.act(.evolveGear(gearID: itemID, recipeID: goal.recipeID), "装備が進化しました。") } label: {
                        actionLabel("この装備を進化させる")
                    }.buttonStyle(.bordered).disabled(!goal.ready || goal.parentOwned != true)
                        .accessibilityIdentifier("goal_evolve")
                } else if goal.parentOwned == true {
                    Text("育てる装備を選ぶ").font(.headline)
                    ForEach(model.state.gear.filter { $0.definitionID == goal.parentTemplateID }) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(parentDescription(item)).font(.caption).fixedSize(horizontal: false, vertical: true)
                            GearLatentDetailsView(model: model, item: item)
                            Button { model.previewRecipeGearID = item.id } label: { actionLabel("この装備を育てる") }
                                .buttonStyle(.bordered).accessibilityIdentifier("recipe_parent_" + item.id.uuidString)
                        }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else if !goal.outputOwned {
                    Button { model.sheet = "装備" } label: { actionLabel("持ちものを確認する") }
                        .buttonStyle(.bordered).accessibilityIdentifier("goal_open_inventory")
                }
                Text("目標の設定だけでは、材料を使ったり装備を変更したりしません。")
                    .font(.caption).foregroundStyle(Palette.gold)
            }.fixedSize(horizontal: false, vertical: true).disabled(model.busy)
        } else {
            Text("制作目標の情報を確認できません。工房か持ちものから選び直してください。")
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recipe_goal_unavailable")
        }
    }

    private func requirementCard(_ r: RecipeGoalProjectionR035.Requirement, recipeID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameText.name(r.materialID)).font(.headline)
            Text("所持 \(r.owned) / 必要 \(r.required)")
            Text(r.missing == 0 ? "必要数を所持しています" : "あと\(r.missing)個")
                .foregroundStyle(Palette.gold)
            if !r.availableGatherRegions.isEmpty { Text("採集: " + model.recipeRegionNames(r.availableGatherRegions)) }
            if r.missing > 0 {
                ForEach(r.availableGatherRegions, id: \.self) { regionID in
                    if let onGatherSource {
                        Button {
                            onGatherSource(recipeID, r.materialID, regionID, r.missing)
                        } label: {
                            Label(model.recipeRegionNames([regionID]) + "で採集場所を確認", systemImage: "map")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("goal_gather_source_\(r.materialID)_\(regionID)")
                    }
                }
            }
            ForEach(Array(model.recipeDropSourceLines(r.materialID).enumerated()), id: \.offset) { _, line in Text(line) }
            if !r.lockedGatherRegions.isEmpty { Text("採集の解放待ち: " + model.recipeRegionNames(r.lockedGatherRegions)).foregroundStyle(Palette.gold) }
            if r.availableGatherRegions.isEmpty && r.availableEnemyDropRegions.isEmpty && r.lockedGatherRegions.isEmpty && r.lockedEnemyDropRegions.isEmpty {
                Text("入手先の情報を確認できません。").foregroundStyle(Palette.gold)
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(requirementAccessibilitySummary(r))
            .accessibilityIdentifier("goal_material_" + r.materialID)
    }

    private func requirementAccessibilitySummary(_ r: RecipeGoalProjectionR035.Requirement) -> String {
        var lines = [GameText.name(r.materialID), "所持 \(r.owned) / 必要 \(r.required)",
                     r.missing == 0 ? "必要数を所持しています" : "あと\(r.missing)個"]
        if !r.availableGatherRegions.isEmpty { lines.append("採集: " + model.recipeRegionNames(r.availableGatherRegions)) }
        lines += model.recipeDropSourceLines(r.materialID)
        if !r.lockedGatherRegions.isEmpty { lines.append("採集の解放待ち: " + model.recipeRegionNames(r.lockedGatherRegions)) }
        if r.availableGatherRegions.isEmpty && r.availableEnemyDropRegions.isEmpty && r.lockedGatherRegions.isEmpty && r.lockedEnemyDropRegions.isEmpty {
            lines.append("入手先の情報を確認できません。")
        }
        return lines.joined(separator: "、")
    }

    private func parentDescription(_ item: GearInstance) -> String {
        var parts = [model.recipeGearName(item.definitionID), GameText.quality(item.qualityID),
                     "+\(item.enhancement)", "研成\(item.refinement)"]
        if let owner = item.ownerID { parts.append((GameModel.actorNames[owner] ?? "仲間") + "が使用中") }
        return parts.joined(separator: " · ")
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
    }
}
