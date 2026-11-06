import SwiftUI

/// Paper-ledger and moon-vault screens (S28–S39). All counts and availability
/// are projected from the active catalog and saved snapshot.
struct UI48JournalView: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    let screen: Int
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var confirmTarget = false
    @State private var selectedChallengeRegion = "R01"
    @State private var journalSection = 0
    @State private var selectedTargetCategory = "杖"
    @State private var selectedTargetGearSlot: String?
    @State private var selectedTargetAccessoryMode = false

    private var catalog: GameCatalog? { model.catalog }
    private var state: GameSnapshot { model.state }
    private var materialID: String? { flow.materialID ?? catalog?.materialIDs.first }
    private var research: ResearchDefinition? { catalog?.research.first { $0.id == flow.researchID } ?? catalog?.research.first }
    private var challenge: ChallengeDefinition? { catalog?.challenges.first { $0.id == flow.challengeID } ?? catalog?.challenges.first }
    private var target: GearDefinition? {
        let id = screen == 37 ? (flow.targetID ?? state.gachaPity.targetTemplateID) : state.gachaPity.targetTemplateID
        return catalog?.gear.first { $0.id == id }
    }
    private var targetConfirmationNeeded: Bool { state.gachaPity.guaranteeTargetOnNextTop }

    var body: some View {
        Group {
            switch screen {
            case 28: index
            case 29: materialRecord
            case 30: enemyRecord
            case 31: researchIndex
            case 32: researchDetail
            case 33: challengeIndex
            case 34: challengeDetail
            case 35: lrCollection
            case 36: vault
            case 37: targetPicker
            case 38: odds
            default: results
            }
        }
        .alert("目標を切り替えますか？", isPresented: $confirmTarget) {
            Button("切り替える", role: .destructive) { applyTarget() }
            Button("戻る", role: .cancel) { }
        } message: {
            Text("次の上位品質に対する目標保証が解除されます。鑑定は実行されません。")
        }
    }

    private var index: some View {
        UI48Page(paper: true) {
            journalHeading("採集帳", "見つけた素材、出会った魔物、深まる研究を記す")
            let discovered = state.completedEncounterIDs.intersection(Set(catalog?.enemies.map(\.id) ?? [])).count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: "book.closed.fill").font(.system(size: 46, weight: .light)).foregroundStyle(UI48Theme.ivory)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("あなたの採集帳").font(.system(.title3, design: .serif, weight: .semibold))
                        Text("魔物の記録 \(discovered) / \((catalog?.enemies.count ?? 0))")
                            .font(.caption).foregroundStyle(Color(hex48: 0xd6c59d).opacity(0.9)).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }.padding(16).frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
                    .foregroundStyle(UI48Theme.ivory).background(UI48Theme.enamel)
                    .clipShape(UI48Frame(radius: 18)).overlay(UI48Frame(radius: 18).stroke(UI48Theme.gold, lineWidth: 1.2))
            }
            journalSectionTabs
            if journalSection == 0 {
                UI48ResponsiveRow(spacing: 10) {
                    journalTile("ICO_\(catalog?.materialIDs.first ?? "")", title: "素材の記録", detail: "入手先と使いみち", screen: 29)
                    journalTile("ACT_\(catalog?.enemies.first?.id ?? "")", title: "魔物の記録", detail: "出会いと再調査", screen: 30)
                }
                UI48Goal(title: nextJournalGoal, detail: nextJournalDetail) { flow.go(nextJournalGoalScreen) }
                journalLink("暮らしと冒険の研究", detail: "素材と効果を確かめる", symbol: "books.vertical", screen: 31)
                journalLink("15の研究課題", detail: "地域ごとの課題と次の挑戦", symbol: "sparkles", screen: 33)
            } else if journalSection == 1 {
                journalLink("暮らしと冒険の研究", detail: "\(state.completedResearchIDs.count)件習得済み · 効果と必要素材を確認", symbol: "books.vertical", screen: 31)
                UI48Action(title: "研究一覧を開く", symbol: "books.vertical", id: "ui48_journal_open_research") { flow.go(31) }
            } else {
                let progress = catalog.map { PostClearGoalProjectionR122.project(catalog: $0, state: state).challenges } ?? []
                Text("達成 \(progress.filter { $0.availability == .cleared }.count) / \(catalog?.challenges.count ?? 0)")
                    .font(.subheadline).monospacedDigit()
                journalLink("15の研究課題", detail: "地域ごとの条件と達成状況を確認", symbol: "sparkles", screen: 33)
                UI48Action(title: "15の研究課題を見る", symbol: "sparkles", id: "ui48_journal_open_challenges") { flow.go(33) }
            }
            UI48Panel(title: "星灯りの頁", paper: true) {
                journalLink("LR装備の収集帳", detail: "手に入れた最高品質の装備", symbol: "star.square", screen: 35)
                journalLink("星灯りの魔導庫", detail: "無料券と鑑定の記録", symbol: "moon.stars", screen: 36)
            }
        }
    }

    private func journalTile(_ assetID: String, title: String, detail: String, screen: Int) -> some View {
        Button { flow.go(screen) } label: {
            VStack(spacing: 8) {
                AssetIcon(id: assetID, size: 76).frame(height: 82)
                Text(title).font(.headline).multilineTextAlignment(.center).foregroundStyle(UI48Theme.paperInk)
                Text(detail).font(.caption).foregroundStyle(Color(hex48: 0x53634f))
            }.frame(maxWidth: .infinity, minHeight: 174).padding(8)
                .background(Color.white.opacity(0.27)).clipShape(UI48Frame(radius: 14))
                .overlay(UI48Frame(radius: 14).stroke(UI48Theme.gold.opacity(0.65), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("ui48_journal_\(screen)")
    }

    private var journalSectionTabs: some View {
        UI48ResponsiveRow(spacing: 3) {
            ForEach(Array(["記録", "研究", "研究課題"].enumerated()), id: \.offset) { index, label in
                Button { journalSection = index } label: {
                    Text(label).font(.subheadline.weight(journalSection == index ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(journalSection == index ? UI48Theme.ink : UI48Theme.paperInk)
                        .background(journalSection == index ? UI48Theme.gold : Color.clear)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("ui48_journal_section_\(["record", "research", "challenges"][index])")
                    .accessibilityAddTraits(journalSection == index ? .isSelected : [])
            }
        }.padding(3).background(Color.white.opacity(0.3))
            .overlay(alignment: .bottom) { Rectangle().fill(UI48Theme.gold.opacity(0.65)).frame(height: 1) }
    }

    private var materialRecord: some View {
        let id = materialID ?? ""
        let sources = (catalog?.regions ?? []).filter { $0.gatherMaterialIDs.contains(id) }
        let availableSources = sources.filter { region in
            catalog?.availableGatherMaterialIDs(in: region.id, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs).contains(id) == true
        }
        let dropSources = (catalog?.enemies ?? []).filter { $0.dropMaterialID == id }
        return UI48Page(paper: true) {
            journalHeading("素材の記録", "採集帳のしおり")
            if !id.isEmpty {
                journalHero(assetID: "ICO_" + id, title: GameText.name(id), subtitle: "所持数　\(state.materials[id, default: 0])")
                UI48Panel(title: "採集できる場所", paper: true) {
                    if sources.isEmpty { UI48Note(text: "この素材に採集先は登録されていません。", warning: true) }
                    ForEach(sources) { region in
                        let canGather = catalog?.availableGatherMaterialIDs(in: region.id, unlockedRegionIDs: state.unlockedRegionIDs, completedEncounterIDs: state.completedEncounterIDs).contains(id) == true
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { VStack(alignment: .leading, spacing: 4) { Text(region.name).font(.headline); Text(canGather ? "採集できます" : (state.unlockedRegionIDs.contains(region.id) ? "採集条件未達" : "地域未解放")).font(.caption) }; Spacer() }
                            if !canGather {
                                Text(state.unlockedRegionIDs.contains(region.id) ? "討伐や採集記録の条件を満たすと選べます。" : "地域地図で解放条件を確認できます。")
                                    .font(.caption2).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(10).background(Color.white.opacity(0.32)).clipShape(UI48Frame(radius: 12))
                    }
                }
                UI48Panel(title: "魔物から見つかる素材", paper: true) {
                    if dropSources.isEmpty { Text("この素材を落とす魔物は登録されていません。").font(.caption) }
                    ForEach(dropSources) { enemy in
                        Button {
                            flow.enemyID = enemy.id
                            flow.go(30)
                        } label: {
                            HStack(spacing: 8) { AssetIcon(id: "ACT_" + enemy.id, size: 40); VStack(alignment: .leading) { Text(enemy.name).font(.subheadline); Text(catalog?.regions.first { $0.id == enemy.regionID }?.name ?? "森").font(.caption2) }; Spacer(); Image(systemName: "chevron.right") }
                                .contentShape(Rectangle()).padding(8).background(Color.white.opacity(0.32)).clipShape(UI48Frame(radius: 9))
                        }.buttonStyle(.plain)
                    }
                }
                UI48Panel(title: "この素材でできること", paper: true) {
                    let uses = (catalog?.recipes ?? []).filter {
                        ($0.kind == "craft_new" || $0.kind == "evolve_in_place") && $0.outputGearID != nil && $0.costs[id, default: 0] > 0
                    }
                    if uses.isEmpty {
                        Text("この素材を使う制作・進化レシピは、現在のカタログにありません。")
                            .font(.caption).foregroundStyle(Color(hex48: 0x53634f)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(uses) { recipe in
                            let goal = model.recipeGoals.first { $0.recipeID == recipe.id }
                            let outputID = recipe.outputGearID ?? ""
                            let definition = catalog?.gear.first { $0.id == outputID }
                            let parentGear = recipe.parentTemplateID.flatMap { parent in state.gear.first { $0.definitionID == parent } }
                            let requirement = goal?.requirements.first { $0.materialID == id }
                            let currentCost = requirement?.required ?? (goal == nil ? recipe.costs[id, default: 0] : 0)
                            let countText = currentCost == 0 && goal != nil
                                ? "今回の制作支援では不要"
                                : requirement.map { "\($0.owned) / \($0.required)" }
                                    ?? "\(state.materials[id, default: 0]) / \(currentCost)"
                            let row = HStack(spacing: 10) {
                                UI48Item(assetID: "ICO_\(outputID)", qualityID: "Q0", size: 54)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(definition?.name ?? outputID).font(.subheadline.weight(.semibold))
                                    Text("\(recipe.kind == "evolve_in_place" ? "進化" : "制作")素材 · \(countText)")
                                        .font(.caption).foregroundStyle(Color(hex48: 0x53634f)).monospacedDigit()
                                    if recipe.parentTemplateID != nil, parentGear == nil {
                                        Text("進化元の装備が必要です").font(.caption2).foregroundStyle(Color(hex48: 0x53634f))
                                    } else if goal?.ready == true {
                                        Text("必要素材がそろっています").font(.caption2).foregroundStyle(Color(hex48: 0x53634f))
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").foregroundStyle(Color(hex48: 0x806431))
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.25)).clipShape(UI48Frame(radius: 10))
                            if goal != nil || recipe.parentTemplateID == nil {
                                Button { flow.recipe(recipe.id, model: model, gearID: parentGear?.id) } label: { row }
                                    .buttonStyle(.plain).accessibilityIdentifier("ui48_material_recipe_\(recipe.id)")
                            } else {
                                Button { flow.go(14) } label: { row }
                                    .buttonStyle(.plain).accessibilityIdentifier("ui48_material_recipe_\(recipe.id)")
                            }
                        }
                    }
                }
                UI48Panel(title: "素材を選ぶ", paper: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 108), spacing: 8)], spacing: 8) {
                        ForEach(catalog?.materialIDs ?? [], id: \.self) { candidate in
                            Button { flow.materialID = candidate } label: {
                                VStack(spacing: 4) {
                                    AssetIcon(id: "ICO_" + candidate, size: 44)
                                    Text(GameText.name(candidate)).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                                    Text("×\(state.materials[candidate, default: 0])").font(.caption2).monospacedDigit()
                                }.frame(maxWidth: .infinity, minHeight: 88).padding(5)
                                    .background(candidate == id ? Color(hex48: 0xcbb782) : Color.white.opacity(0.35))
                                    .clipShape(UI48Frame(radius: 9))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else { UI48Note(text: "素材記録を読み込めません。", warning: true) }
            if let research, research.cost[id] != nil {
                UI48Action(title: "\(research.name)の不足分を確認", symbol: "books.vertical", secondary: true) { flow.go(32) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !availableSources.isEmpty {
                UI48ActionDock {
                    ForEach(availableSources) { region in
                        UI48Action(
                            title: availableSources.count == 1 ? "この素材を採集しに行く" : "\(region.name)でこの素材を採集",
                            symbol: "leaf",
                            disabled: model.busy || model.fighting,
                            id: "ui48_material_gather_\(region.id)"
                        ) {
                            flow.pendingRecipeGather = nil
                            flow.pendingInvestigation = nil
                            flow.pendingResearchGather = nil
                            flow.materialID = id
                            flow.regionID = region.id
                            flow.workTarget = .gather(id)
                            flow.go(12)
                        }
                    }
                }
            }
        }
    }

    private var enemyRecord: some View {
        let enemies = catalog?.enemies ?? []
        let selectedID = flow.enemyID ?? enemies.first(where: { state.completedEncounterIDs.contains($0.id) })?.id ?? enemies.first?.id
        let selected = enemies.first { $0.id == selectedID }
        return UI48Page(paper: true) {
            journalHeading("魔物の記録", "森で出会った相手と、その素材の手がかり")
            if let enemy = selected {
                let known = state.completedEncounterIDs.contains(enemy.id)
                journalHero(assetID: "ACT_" + enemy.id, title: known ? enemy.name : "まだ出会っていない魔物", subtitle: (catalog?.regions.first { $0.id == enemy.regionID }?.name ?? "森") + (known ? " · 討伐記録あり" : " · 記録なし"))
                let prerequisiteMissing = enemy.prerequisiteEncounterID.flatMap { prerequisite in
                    state.completedEncounterIDs.contains(prerequisite) ? nil : prerequisite
                }
                UI48Panel(title: "記録", paper: true) {
                    Text(enemy.boss ? "地域の主" : "森で出会う魔物").font(.headline)
                    if let material = enemy.dropMaterialID {
                        HStack(spacing: 9) { AssetIcon(id: "ICO_" + material, size: 42); VStack(alignment: .leading) { Text("見つかる素材"); Text(GameText.name(material)).font(.caption) }; Spacer(); Text("所持 \(state.materials[material, default: 0])") }
                    } else { Text("記録された素材はありません。").font(.caption) }
                    if let prerequisite = prerequisiteMissing {
                        UI48Note(text: "先に \(catalog?.enemies.first { $0.id == prerequisite }?.name ?? prerequisite) の討伐が必要です。", warning: true)
                    }
                    if let prerequisite = prerequisiteMissing {
                        UI48Action(title: "必要な魔物を確認", symbol: "safari", secondary: true) { flow.enemyID = prerequisite }
                    } else if model.state.unlockedRegionIDs.contains(enemy.regionID) {
                        if known, enemy.dropMaterialID != nil {
                            if model.sharedPartyWorkR146Enabled {
                                UI48Action(title: "再調査の行き先にする", symbol: "magnifyingglass", secondary: true, disabled: model.busy || model.fighting, id: "ui48_enemy_investigate") {
                                    flow.pendingRecipeGather = nil
                                    flow.pendingInvestigation = nil
                                    flow.pendingResearchGather = nil
                                    flow.pendingEncounterAfterSwitch = nil
                                    flow.workTarget = .investigate(enemy.id)
                                    flow.regionID = enemy.regionID
                                    flow.materialID = enemy.dropMaterialID
                                    flow.go(12)
                                }
                            } else {
                                UI48Note(text: "再調査の派遣は現在利用できません。探索の魔物詳細から利用可能な行動を確認してください。", warning: true)
                            }
                        }
                        if model.state.activeRegionID != enemy.regionID {
                            UI48Action(title: "探索先を確認して挑戦", symbol: "map", disabled: model.busy || model.fighting) {
                                flow.clearDestination()
                                flow.enemyID = enemy.id
                                flow.regionID = enemy.regionID
                                model.tab = "探索"
                                flow.go(7)
                            }
                            UI48Note(text: "現在の探索先と異なるため、先に移動を確認してから挑戦できます。")
                        } else {
                            UI48Action(title: known ? "この魔物に再び挑む" : "完全自動戦闘で挑む", symbol: "shield", disabled: model.busy || model.fighting) {
                                model.chosenRegion = enemy.regionID; model.tab = "探索"; model.fight(enemy)
                            }
                        }
                    } else { UI48Note(text: "地域が未解放です。森の地図で進行条件を確認してください。", warning: true) }
                }
            }
            UI48Panel(title: "採集帳の見出し", paper: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 90), spacing: 7)], spacing: 7) {
                    ForEach(enemies) { enemy in
                        let known = state.completedEncounterIDs.contains(enemy.id)
                        Button { flow.enemyID = enemy.id } label: {
                            VStack(spacing: 4) { AssetIcon(id: "ACT_" + enemy.id, size: 45); Text(known ? enemy.name : "記録前").font(.caption2).lineLimit(1) }
                                .frame(maxWidth: .infinity, minHeight: 68).background(enemy.id == selectedID ? Color(hex48: 0xcbb782) : Color.white.opacity(0.30)).clipShape(UI48Frame(radius: 8))
                        }.buttonStyle(.plain).accessibilityIdentifier("ui48_enemy_record_\(enemy.id)")
                    }
                }
            }
        }
    }

    private var researchIndex: some View {
        let entries = catalog?.research ?? []
        return UI48Page(paper: true) {
            journalHeading("暮らしと冒険の研究", "不足するものを確かめ、採集先から一歩ずつ")
            Text("習得済み \(state.completedResearchIDs.intersection(Set(entries.map(\.id))).count) / \(entries.count)").font(.subheadline)
            ForEach(entries) { entry in
                let done = state.completedResearchIDs.contains(entry.id)
                Button { flow.researchID = entry.id; flow.go(32) } label: {
                    HStack { VStack(alignment: .leading, spacing: 5) { Text(entry.name).font(.headline); Text(done ? "習得済み" : costSummary(entry)).font(.caption).foregroundStyle(Color(hex48: 0x53634f)); Text(researchBenefit(entry)).font(.caption2).fixedSize(horizontal: false, vertical: true).foregroundStyle(Color(hex48: 0x53634f)) }; Spacer(); Image(systemName: done ? "checkmark.seal.fill" : "chevron.right").foregroundStyle(done ? UI48Theme.enamel : UI48Theme.paperInk) }
                        .padding(13).background(done ? UI48Theme.enamel.opacity(0.22) : Color.white.opacity(0.24)).clipShape(UI48Frame(radius: 12)).overlay(UI48Frame(radius: 12).stroke(UI48Theme.gold.opacity(0.5)))
                }.buttonStyle(.plain).accessibilityIdentifier("ui48_research_\(entry.id)")
            }
            UI48Action(title: "15の研究課題を見る", symbol: "sparkles") { flow.go(33) }
            UI48Note(text: "研究を選ぶと、効果と必要な素材を確認できます。")
        }
    }

    private var researchDetail: some View {
        guard let entry = research else { return AnyView(UI48Page(paper: true) { UI48Note(text: "研究を選び直してください。", warning: true) }) }
        let done = state.completedResearchIDs.contains(entry.id)
        let requirements = ResearchMaterialGuidanceR280.project(catalog: catalog, state: state, research: entry)
        return AnyView(UI48Page(paper: true) {
            journalHeading(entry.name, "研究の準備")
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex48: 0xd9c99f).opacity(0.38)).frame(width: 126, height: 126)
                    Circle().stroke(Color(hex48: 0x806431), lineWidth: 1.5).frame(width: 108, height: 108)
                    Image(systemName: "books.vertical.fill").font(.system(size: 46)).foregroundStyle(Color(hex48: 0x806431))
                }.accessibilityHidden(true)
                Text(entry.name).font(.system(.title3, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                Text(done ? "習得済み" : "不足する素材を確認して、研究の準備を整えます")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color(hex48: 0x62563a))
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
            UI48Panel(title: "研究の効果", paper: true) {
                Text(researchBenefit(entry)).font(.headline).fixedSize(horizontal: false, vertical: true)
                if catalog?.researchEffects[entry.effectID] == nil {
                    UI48Note(text: "効果の詳細は現在のカタログで確認できません。", warning: true)
                }
            }
            UI48Panel(title: "必要な素材", paper: true) {
                if entry.cost.isEmpty { Text("素材消費なし") }
                ForEach(entry.cost.keys.sorted(), id: \.self) { id in
                    let have = state.materials[id, default: 0], need = entry.cost[id, default: 0]
                    HStack { AssetIcon(id: "ICO_" + id, size: 34); Text(GameText.name(id)); Spacer(); Text("\(have) / \(need)").monospacedDigit().foregroundStyle(have >= need ? UI48Theme.paperInk : Color(hex48: 0x8c4030)) }
                    if have < need, let row = requirements.first(where: { $0.materialID == id }) { sourceActions(row, research: entry) }
                }
            }
            if done { UI48Note(text: "この研究は習得済みです。") }
            else { UI48Action(title: "研究する", symbol: "sparkles", disabled: model.busy || entry.cost.contains { state.materials[$0.key, default: 0] < $0.value }) { model.act(.completeResearch(entry.id), "研究の成果を記録しました。") } }
            UI48Note(text: "研究を実行すると、必要素材を消費して保存します。")
        })
    }

    @ViewBuilder private func sourceActions(_ requirement: ResearchMaterialGuidanceR280.Requirement, research: ResearchDefinition) -> some View {
        switch requirement.availability {
        case .unknownMaterial: UI48Note(text: "素材の入手先を確認できません。", warning: true)
        case .noGatherRegion: UI48Note(text: "採集できる地域は登録されていません。", warning: true)
        case .regions(let sources):
            ForEach(sources) { source in
                HStack { Text("あと\(requirement.missing) · \(source.regionName) · \(source.status.label)").font(.caption); Spacer(minLength: 4)
                    if case .available = source.status { Button("採集先へ") { flow.pendingResearchGather = ResearchGatherHandoffR310(researchID: research.id, materialID: requirement.materialID, regionID: source.regionID); flow.regionID = source.regionID; model.chosenRegion = source.regionID; model.tab = "探索"; flow.go(12) }.font(.caption).buttonStyle(.bordered) }
                }
            }
        }
    }

    private var challengeIndex: some View {
        let entries = catalog?.challenges ?? []
        let projected = catalog.map { PostClearGoalProjectionR122.project(catalog: $0, state: state).challenges } ?? []
        let regionIDs = (1...5).map { String(format: "R%02d", $0) }
        let visibleEntries = entries.filter { $0.region == selectedChallengeRegion }.sorted { $0.id < $1.id }
        let completedCount = projected.filter { $0.availability == .cleared }.count
        let regionName = catalog?.regions.first { $0.id == selectedChallengeRegion }?.name ?? selectedChallengeRegion
        return UI48Page(paper: true) {
            journalHeading("15の研究課題", "地域ごとの記録から次の挑戦を選ぶ")
            Text("達成 \(completedCount) / \(entries.count)")
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ui48_challenge_progress")
            HStack(spacing: 6) {
                ForEach(regionIDs, id: \.self) { regionID in
                    let selected = regionID == selectedChallengeRegion
                    Button {
                        selectedChallengeRegion = regionID
                        flow.challengeID = entries.first { $0.region == regionID }?.id
                    } label: {
                        Text(String(Int(regionID.suffix(2)) ?? 0))
                            .font(.system(.title3, design: .serif, weight: selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(selected ? UI48Theme.ivory : UI48Theme.paperInk)
                            .background(selected ? UI48Theme.enamel : Color.clear)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(UI48Theme.gold.opacity(0.72), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ui48_challenge_region_\(regionID)")
                }
            }
            Text(regionName).font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(UI48Theme.gold).frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                ForEach(visibleEntries.indices, id: \.self) { index in
                    let entry = visibleEntries[index]
                    let status = projected.first { $0.id == entry.id }?.availability ?? .locked
                    let cleared = status == .cleared
                    let locked = status == .locked
                    Button { flow.challengeID = entry.id; flow.go(34) } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(.title2, design: .serif)).foregroundStyle(UI48Theme.gold)
                                .frame(width: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.headline).foregroundStyle(UI48Theme.paperInk)
                                Text(cleared ? "達成済み" : locked ? "解放条件あり · \(gateDescription(entry))" : "挑戦できます")
                                    .font(.caption).foregroundStyle(Color(hex48: 0x53634f))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: cleared ? "checkmark" : locked ? "lock.fill" : "chevron.right")
                                .foregroundStyle(cleared ? UI48Theme.enamel : UI48Theme.gold)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.30))
                        .clipShape(UI48Frame(radius: 13))
                        .overlay(UI48Frame(radius: 13).stroke(UI48Theme.gold.opacity(0.68), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ui48_challenge_\(entry.id)")
                }
                if visibleEntries.isEmpty { UI48Note(text: "この地域の課題はカタログにありません。", warning: true) }
            }
            if entries.count != 15 { UI48Note(text: "現在は\(entries.count)件の研究課題を確認できます。", warning: true) }
            UI48Note(text: "課題を選ぶと解放条件、参加する魔物、報酬候補を確認できます。")
        }
        .onAppear {
            if let currentRegion = entries.first(where: { $0.id == flow.challengeID })?.region {
                selectedChallengeRegion = currentRegion
            } else if !entries.contains(where: { $0.region == selectedChallengeRegion }) {
                selectedChallengeRegion = regionIDs.first(where: { regionID in entries.contains(where: { $0.region == regionID }) }) ?? "R01"
            }
        }
    }

    private var challengeDetail: some View {
        guard let entry = challenge else { return AnyView(UI48Page(paper: true) { UI48Note(text: "課題を選び直してください。", warning: true) }) }
        let status = catalog.flatMap { PostClearGoalProjectionR122.project(catalog: $0, state: state).challenges.first { $0.id == entry.id }?.availability }
        let cleared = status == .cleared
        let locked = status != .available && !cleared
        let featuredEnemy = entry.enemyIDs.first.flatMap { id in catalog?.enemies.first { $0.id == id } }
        return AnyView(UI48Page {
            journalHeading(entry.name, "\(entry.region) · 研究課題")
            if let enemy = featuredEnemy {
                UI48Hero(assetID: "ACT_" + enemy.id, title: enemy.name,
                         subtitle: GameText.challengeMechanic(entry.id, fallback: entry.mechanic))
            }
            UI48Panel(title: "課題の記録") {
                Text(GameText.challengeMechanic(entry.id, fallback: entry.mechanic)).font(.headline)
                Text("参加する魔物").font(.caption)
                ForEach(entry.enemyIDs, id: \.self) { enemyID in
                    let enemy = catalog?.enemies.first { $0.id == enemyID }
                    HStack { UI48Item(assetID: "ACT_" + enemyID, size: 48); Text(enemy?.name ?? "魔物"); Spacer() }
                }
                Text(cleared ? "達成済み" : "結果は戦闘後に保存記録へ反映されます").font(.caption)
                if locked { UI48Note(text: "解放条件：\(gateDescription(entry))", warning: true) }
            }
            UI48Panel(title: "初回達成報酬") {
                Text("ローカル調整候補：魔法の粉 \(entry.firstClearPowder)")
                Text("この数値・課題ルールは正式仕様として未確定です。")
                    .font(.caption).foregroundStyle(UI48Theme.muted)
                Text(cleared ? "初回達成済み" : "初回報酬の状態は実際の戦闘後に保存記録で確認できます。")
                    .font(.caption)
            }
            if locked && gateEnemyID(entry) == nil {
                UI48Note(text: "解放条件を読み込めませんでした。いったん採集帳へ戻って確認してください。", warning: true)
            }
            UI48Note(text: "開始すると完全自動戦闘へ進みます。勝敗と報酬は実際の戦闘結果に従います。")
            UI48Note(text: "研究課題の強さと報酬は調整中です。挑戦は完全自動で進みます。", warning: true)
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            UI48ActionDock {
                if locked {
                    if let enemyID = gateEnemyID(entry) {
                        UI48Action(title: "解放に必要な魔物を確認", symbol: "map", secondary: true) {
                            flow.enemyID = enemyID
                            flow.regionID = catalog?.enemies.first { $0.id == enemyID }?.regionID
                            flow.go(7)
                        }
                    }
                } else {
                    UI48Action(title: cleared ? "もう一度挑戦する" : "完全自動戦闘で挑戦", symbol: "safari", disabled: model.busy || model.fighting) {
                        flow.enemyID = nil
                        model.challenge(entry)
                    }
                }
                UI48Action(title: "装備セットを確認", symbol: "shield.lefthalf.filled", secondary: true) { flow.go(17) }
            }
        })
    }

    private func gateEnemyID(_ entry: ChallengeDefinition) -> String? {
        guard entry.unlockGate != "G_START" else { return nil }
        let parts = entry.unlockGate.split(separator: "_")
        guard parts.count == 3, parts[0] == "G" else { return nil }
        return "B_\(parts[1])_\(parts[2])"
    }
    private func gateDescription(_ entry: ChallengeDefinition) -> String {
        guard entry.unlockGate != "G_START" else { return "解放済み" }
        guard let enemyID = gateEnemyID(entry) else { return "カタログ条件を確認してください" }
        return "先に \(catalog?.enemies.first { $0.id == enemyID }?.name ?? enemyID) を討伐"
    }

    private var lrCollection: some View {
        UI48Page(paper: true) {
            journalHeading("LR装備の収集帳", "所持する種類と、現在の入手候補を記録")
            if let catalog {
                let projection = GearLegendaryCollectionProjectionR384.make(
                    catalog: catalog, state: state,
                    policyEnabled: NaturalGearBuildPolicyR350.enabled,
                    latentPolicy: nil)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(projection.ownedQ4TemplateCount)").font(.system(size: 34, weight: .medium, design: .serif))
                    Text("種類を所持")
                }
                Text("同じ種類はまとめて表示します。装備を選ぶと、所持数と入手先を確認できます。").font(.caption)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 142), spacing: 10)], spacing: 12) {
                    ForEach(projection.entries) { entry in
                        let owned = entry.ownedInstances.filter(\.isLegendary)
                        let sources = Array(Set(owned.compactMap(\.naturalSourceRegionID))).sorted().compactMap { id in catalog.regions.first { $0.id == id }?.name }
                        VStack(alignment: .leading, spacing: 7) {
                            Button {
                                if let first = owned.first { flow.selectGear(first.id, screen: 15) }
                            } label: {
                                VStack(spacing: 7) {
                                    UI48Item(assetID: "ICO_\(entry.templateID)", qualityID: "Q4", count: owned.isEmpty ? "" : "×\(owned.count)", locked: owned.isEmpty, size: 82)
                                    Text(entry.name).font(.caption).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                                }.frame(maxWidth: .infinity, minHeight: 124).padding(8)
                            }.buttonStyle(.plain).disabled(owned.isEmpty)
                            if !sources.isEmpty { Text("発見：" + sources.joined(separator: "・")).font(.caption2).fixedSize(horizontal: false, vertical: true) }
                            Text(collectionRouteText(entry.route, catalog: catalog)).font(.caption2).fixedSize(horizontal: false, vertical: true)
                            if case .eligible(let regionID, _, _) = entry.route {
                                Button("探索先を見る") { model.chosenRegion = regionID; flow.home(model, tab: "探索") }
                                    .font(.caption).frame(minHeight: 40).disabled(model.busy || model.fighting)
                            }
                        }
                        .background(owned.isEmpty ? UI48Theme.ink.opacity(0.10) : UI48Theme.gold.opacity(0.20))
                        .clipShape(UI48Frame(radius: 12)).overlay(UI48Frame(radius: 12).stroke(owned.isEmpty ? UI48Theme.paperInk.opacity(0.22) : UI48Theme.gold, lineWidth: owned.isEmpty ? 1 : 2))
                    }
                }
                if projection.entries.isEmpty { UI48Note(text: "いま確認できるLR装備がありません。", warning: true) }
            } else { UI48Note(text: "装備の収集記録を読み込めません。", warning: true) }
            UI48Note(text: "現在所持している装備と、残っている入手記録を表示します。手放した装備の全履歴は残りません。")
            UI48Action(title: "魔導庫を開く", symbol: "moon.stars") { flow.go(36) }
        }
    }

    private func collectionRouteText(_ route: GearLegendaryCollectionProjectionR384.Route, catalog: GameCatalog) -> String {
        switch route {
        case .profileDisabled: return "現在の設定では入手候補を確認できません。"
        case .unknownTemplate: return "装備の詳細を確認できません。"
        case .noActiveRegion: return "探索地域を選ぶと候補を確認できます。"
        case .regionLocked: return "地域が未解放です。"
        case .actorNotJoined: return "対応する仲間の加入後に候補になります。"
        case .craftedDiscoveryRequired: return "工房で進化先を作ると探索候補に加わります。"
        case .recipeGatesRequired(let gates):
            let names = gates.compactMap { gate -> String? in
                let p = gate.split(separator: "_"); guard p.count == 3, p[0] == "G" else { return nil }
                return catalog.enemies.first { $0.id == "B_\(p[1])_\(p[2])" }?.name
            }
            return names.isEmpty ? "工房の条件を満たすと候補になります。" : "工房の条件：" + names.joined(separator: "・")
        case .eligible(let regionID, _, let period):
            let name = catalog.regions.first { $0.id == regionID }?.name ?? "探索"
            switch period {
            case .inFlight: return "進行中の周期で、\(name)の候補に含まれます。"
            case .followingPeriod: return "次の周期は\(name)で始めると候補になります。"
            case .newPeriod: return "\(name)で始める周期の候補です。"
            }
        }
    }

    private var vault: some View {
        UI48Page {
            journalHeading("星灯りの魔導庫", "所持券・目標・確率を確認してから鑑定", paper: false)
            UI48Hero(assetID: target.map { "ICO_" + $0.id } ?? "moon", title: target?.name ?? "目標装備を選ぶ", subtitle: "所持券によるローカル鑑定")
            Text("無料鑑定券　\(state.currency["ticket_free", default: 0])枚")
                .font(.subheadline.monospacedDigit()).accessibilityIdentifier("ui48_vault_free_balance")
            UI48Goal(caption: "目標装備", title: target?.name ?? "未選択", detail: "目標を選ぶだけでは鑑定しません") { flow.go(37) }
            UI48Panel(title: "鑑定", content: {
                UI48Note(text: "購入機能は未接続です。無料券によるローカル鑑定のみ操作できます。正式課金は行いません。")
                UI48Action(title: "既存の50回鑑定", symbol: "sparkles", secondary: true, disabled: !state.gachaUnlocked || state.currency["ticket_free", default: 0] < 50 || model.busy) { model.summon(50) }
            })
            if !state.gachaUnlocked { UI48Note(text: "鑑定はまだ解放されていません。物語の進行と装備比較を進めてください。", warning: true) }
            dailyClaim
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            UI48ActionDock {
                HStack(spacing: 8) {
                    vaultDrawButton(title: "1回鑑定", tickets: 1) { model.summon(1) }
                    vaultDrawButton(title: "5回鑑定", tickets: 5) { model.summon(5) }
                }
                UI48Action(title: "提供割合と保証を確認", symbol: "list.bullet.rectangle", secondary: true) { flow.go(38) }
            }
        }
    }

    private func vaultDrawButton(title: String, tickets: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(UI48Theme.gold)
                Text("無料券で\(title)").font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                Text("必要 \(tickets)枚").font(.caption).foregroundStyle(UI48Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(8)
            .background(UI48Theme.raised.opacity(0.7))
            .clipShape(UI48Frame(radius: 14))
            .overlay(UI48Frame(radius: 14).stroke(UI48Theme.gold.opacity(0.65), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!state.gachaUnlocked || state.currency["ticket_free", default: 0] < tickets || model.busy)
        .opacity(!state.gachaUnlocked || state.currency["ticket_free", default: 0] < tickets ? 0.55 : 1)
        .accessibilityIdentifier("ui48_vault_draw_\(tickets)")
    }

    private var dailyClaim: some View {
        let now = Date()
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let available = state.gachaUnlocked && (state.lastDailyClaimAt.map { now >= $0 && !utc.isDate($0, inSameDayAs: now) } ?? true)
        return UI48Action(title: available ? "今日の無料券を受け取る（\(catalog?.dailyFreeTicketGrant ?? 0)枚）" : "今日の無料券は受取済み", symbol: "gift", secondary: true, disabled: !available || model.busy) { model.daily() }
    }

    private var targetPicker: some View {
        UI48Page {
            journalHeading("探す装備を選ぶ", "種類から候補を選び、確認してから目標を変更します", paper: false)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: textSize.isAccessibilitySize ? 2 : 4), spacing: 4) {
                ForEach(Array([("杖", "staff"), ("本", "book"), ("鍛造道具", "smith"), ("使い魔", "familiar")].enumerated()), id: \.offset) { _, pair in
                    let label = pair.0
                    let key = pair.1
                    Button { selectedTargetCategory = label; selectedTargetGearSlot = nil; selectedTargetAccessoryMode = false } label: {
                        Text(label).font(.caption.weight(selectedTargetCategory == label ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(selectedTargetCategory == label ? UI48Theme.ink : UI48Theme.ivory)
                            .background(selectedTargetCategory == label ? UI48Theme.gold : UI48Theme.raised)
                            .clipShape(UI48Frame(radius: 9))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("ui48_target_category_\(key)")
                        .accessibilityAddTraits(selectedTargetCategory == label ? .isSelected : [])
                }
            }
            targetAccessoryFilters
            LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 112), spacing: 10)], spacing: 12) {
                ForEach((catalog?.gear ?? []).filter { gearMatchesTargetCategory($0) }) { item in
                    Button { flow.targetID = item.id } label: {
                        VStack(spacing: 7) { UI48Item(assetID: "ICO_" + item.id, qualityID: "Q4", size: 82); Text(item.name).font(.caption).lineLimit(2).multilineTextAlignment(.center); Text(gearSlotLabel(item.slot)).font(.caption2).foregroundStyle(UI48Theme.muted) }
                            .frame(maxWidth: .infinity, minHeight: 132).padding(7).background(UI48Theme.raised.opacity(0.5)).clipShape(UI48Frame(radius: 12)).overlay(UI48Frame(radius: 12).stroke(item.id == (flow.targetID ?? state.gachaPity.targetTemplateID) ? UI48Theme.gold : UI48Theme.gold.opacity(0.25)))
                    }.buttonStyle(.plain).accessibilityIdentifier("ui48_vault_target_\(item.id)")
                }
            }
            if (catalog?.gear.filter { gearMatchesTargetCategory($0) }.isEmpty ?? true) {
                UI48Note(text: "この種類に該当する装備は、現在のカタログにありません。")
            }
            if let selected = target {
                UI48Panel(title: "選択内容を確認") {
                    Text(selected.name).font(.headline)
                    Text("現在の目標：\(catalog?.gear.first { $0.id == state.gachaPity.targetTemplateID }?.name ?? "未設定")")
                        .font(.caption)
                    Text(targetConfirmationNeeded ? "変更すると、次回上位品質の目標保証が解除されます。" : "確定するまで保存内容は変わりません。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                UI48Note(text: "装備を選ぶと、ここに変更内容と確定操作が表示されます。")
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            if target != nil {
                UI48ActionDock {
                    UI48Action(title: "この装備を目標に設定", symbol: "checkmark", disabled: model.busy || flow.targetID == nil || flow.targetID == state.gachaPity.targetTemplateID) {
                        if targetConfirmationNeeded { confirmTarget = true } else { applyTarget() }
                    }
                    UI48Action(title: "変更せず戻る", symbol: "arrow.uturn.backward", secondary: true) { flow.go(36) }
                }
            }
        }
    }

    private var targetAccessoryFilters: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("防具・装飾品").font(.caption.weight(.semibold)).foregroundStyle(UI48Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: textSize.isAccessibilitySize ? 2 : 6), spacing: 4) {
                ForEach(["all", "body", "hands", "feet", "amulet", "ring"], id: \.self) { key in
                    targetAccessoryButton(key)
                }
            }
        }
    }

    private func targetAccessoryButton(_ key: String) -> some View {
        let slot: String? = key == "all" ? nil : key
        let selected = selectedTargetAccessoryMode && selectedTargetGearSlot == slot
        let label = key == "all" ? "すべて" : gearSlotLabel(key)
        return Button {
            selectedTargetGearSlot = slot
            selectedTargetAccessoryMode = true
        } label: {
            Text(label).font(.caption.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? UI48Theme.ink : UI48Theme.ivory)
                .background(selected ? UI48Theme.gold : UI48Theme.raised)
                .clipShape(UI48Frame(radius: 8))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("ui48_target_category_\(key)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var odds: some View {
        let odds = catalog?.gachaOddsBasisPoints ?? [:]
        return UI48Page(paper: true) {
            journalHeading("提供割合と保証", "実行時のカタログ・保存状態を表示")
            UI48Panel(title: "品質ごとの割合", paper: true) {
                ForEach(["Q0", "Q1", "Q2", "Q3", "Q4"], id: \.self) { quality in
                    HStack { Circle().fill(UI48Theme.quality(quality)).frame(width: 10, height: 10); Text(GameText.quality(quality)); Spacer(); Text(String(format: "%.2f%%", Double(odds[quality, default: 0]) / 100)).monospacedDigit() }
                }
            }
            UI48Panel(title: "現在の進行", paper: true) {
                Text("上位品質までの記録　\(state.gachaPity.drawsSinceTop)")
                Text("中位品質までの記録　\(state.gachaPity.drawsSinceMid)")
                Text(state.gachaPity.guaranteeTargetOnNextTop ? "次の上位品質は選択目標を保証" : "目標保証は次回上位品質まで未成立")
                Text("選択中：\(target?.name ?? "なし")")
            }
            UI48Note(text: "割合・保証ルールは現在のローカル開発カタログ値です。正式な商品仕様・確率としては未承認です。課金購入は未接続です。", warning: true)
        }
    }

    private var results: some View {
        UI48Page {
            journalHeading("鑑定の結果", "保存された今回の鑑定結果", paper: false)
            Text("今回届いた装備　\(model.opening.count)点").font(.headline)
            if model.opening.isEmpty { UI48Note(text: "今回の鑑定装備はありません。履歴は追加していません。") }
            if let featuredID = model.opening.first,
               let featured = state.gear.first(where: { $0.id == featuredID }),
               let definition = catalog?.gear.first(where: { $0.id == featured.definitionID }) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(UI48Theme.gold.opacity(0.42), lineWidth: 12).frame(width: 186, height: 186)
                        UI48Item(assetID: "ICO_\(featured.definitionID)", qualityID: featured.qualityID, count: "+\(featured.enhancement)", size: 136)
                    }
                    Text(definition.name).font(.system(.title2, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                    Text("\(GameText.quality(featured.qualityID)) · \(model.state.equippedGearIDs.values.contains(featured.id) ? "装備中" : "未装備")")
                        .font(.caption).foregroundStyle(UI48Theme.muted)
                    UI48Action(title: "この装備を比べる", symbol: "square.split.2x1", id: "ui48_result_compare_featured") {
                        openResultComparison(featured)
                    }
                }.frame(maxWidth: .infinity).padding(14)
                    .background(UI48Theme.raised.opacity(0.48)).clipShape(UI48Frame(radius: 16))
                    .overlay(UI48Frame(radius: 16).stroke(UI48Theme.gold.opacity(0.62), lineWidth: 1))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 96), spacing: 10)], spacing: 12) {
                ForEach(model.opening, id: \.self) { id in
                    if let item = state.gear.first(where: { $0.id == id }) {
                        let def = catalog?.gear.first { $0.id == item.definitionID }
                        Button { flow.selectGear(item.id, screen: 15) } label: { VStack(spacing: 5) { UI48Item(assetID: "ICO_" + item.definitionID, qualityID: item.qualityID, size: 78); Text(def?.name ?? item.definitionID).font(.caption).multilineTextAlignment(.center).lineLimit(2) } }.buttonStyle(.plain).accessibilityIdentifier("ui48_result_item_\(item.id.uuidString)")
                    }
                }
            }
            UI48Action(title: "魔導庫へ戻る", symbol: "moon.stars", secondary: true) { flow.go(36) }
            UI48Action(title: "持ちものを見る", symbol: "backpack") { model.tab = "仲間"; flow.go(14) }
            UI48Note(text: "表示は現在の保存データに含まれる装備のみです。")
        }
    }

    private var nextJournalGoal: String {
        if let entry = catalog?.research.first(where: { !state.completedResearchIDs.contains($0.id) }) { return entry.name }
        if let c = catalog?.challenges.first(where: { !state.completedEncounterIDs.contains($0.id) }) { return c.name }
        return "記録を振り返る"
    }
    private var nextJournalDetail: String {
        guard let entry = catalog?.research.first(where: { !state.completedResearchIDs.contains($0.id) }) else { return "記録の続きから、次の一歩を選びます" }
        let missing = entry.cost.reduce(0) { $0 + max(0, $1.value - state.materials[$1.key, default: 0]) }
        return missing == 0 ? "必要なものがそろっています" : "不足素材 合計 \(missing) · 入手先を確認できます"
    }
    private var nextJournalGoalScreen: Int {
        if catalog?.research.contains(where: { !state.completedResearchIDs.contains($0.id) }) == true { return 31 }
        if catalog?.challenges.contains(where: { !state.completedEncounterIDs.contains($0.id) }) == true { return 33 }
        return 31
    }
    private func costSummary(_ entry: ResearchDefinition) -> String {
        guard !entry.cost.isEmpty else { return "素材消費なし" }
        return entry.cost.keys.sorted().map { "\(GameText.name($0)) \(state.materials[$0, default: 0])/\(entry.cost[$0, default: 0])" }.joined(separator: " · ")
    }
    private func researchBenefit(_ entry: ResearchDefinition) -> String {
        guard let effect = catalog?.researchEffects[entry.effectID] else { return "効果の詳細は未登録です" }
        var values: [String] = []
        if effect.partyAttack > 0 { values.append("攻撃 +\(effect.partyAttack)") }
        if effect.partyMaxHP > 0 { values.append("体力 +\(effect.partyMaxHP)") }
        if effect.partyDefense > 0 { values.append("防御 +\(effect.partyDefense)") }
        return values.isEmpty ? "登録された能力効果はありません" : "仲間全員：" + values.joined(separator: " · ")
    }
    private func journalHeading(_ title: String, _ subtitle: String, paper: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(paper ? UI48Theme.paperInk : UI48Theme.ivory)
            Text(subtitle).font(.footnote).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(paper ? Color(hex48: 0x53634f) : UI48Theme.muted)
            HStack { Rectangle().fill(UI48Theme.gold.opacity(0.45)).frame(height: 1); Image(systemName: "sparkle").font(.caption2).foregroundStyle(Color(hex48: 0x806431)).accessibilityHidden(true) }
        }
    }
    private func journalHero(assetID: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().stroke(Color(hex48: 0x806431).opacity(0.35), lineWidth: 1).frame(width: 164, height: 164)
                Circle().stroke(Color(hex48: 0x806431).opacity(0.18), lineWidth: 1).frame(width: 188, height: 188)
                AssetIcon(id: assetID, size: 142).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 194)
            Text(title).font(.system(.title2, design: .serif, weight: .semibold)).multilineTextAlignment(.center).foregroundStyle(UI48Theme.paperInk)
            Text(subtitle).font(.footnote).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).foregroundStyle(Color(hex48: 0x53634f))
        }.frame(maxWidth: .infinity)
    }
    private func journalLink(_ title: String, detail: String, symbol: String, screen: Int) -> some View {
        Button { flow.go(screen) } label: { HStack(spacing: 10) { Image(systemName: symbol).font(.title3).foregroundStyle(Color(hex48: 0x806431)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).fixedSize(horizontal: false, vertical: true) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.foregroundStyle(UI48Theme.paperInk).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.22)).clipShape(UI48Frame(radius: 12)) }.buttonStyle(.plain).accessibilityIdentifier("ui48_journal_\(screen)")
    }
    private func applyTarget() {
        guard !model.busy, let id = flow.targetID else { return }
        flow.commit(.setGachaTarget(templateID: id), model: model,
                    title: "鑑定目標を保存しました。", resultScreen: 36)
    }

    private func gearMatchesTargetCategory(_ gear: GearDefinition) -> Bool {
        if selectedTargetAccessoryMode {
            if let selectedTargetGearSlot {
                return gear.slot == selectedTargetGearSlot || (selectedTargetGearSlot == "hands" && gear.slot == "hand")
            }
            return gear.slot != "weapon"
        }
        let actorID: String
        switch selectedTargetCategory {
        case "杖": actorID = "C_WITCH"
        case "本": actorID = "C_APPRENTICE"
        case "鍛造道具": actorID = "C_SMITH"
        default: actorID = "C_FAMILIAR"
        }
        return (gear.actorIDs.isEmpty || gear.actorIDs.contains(actorID)) && gear.slot == "weapon"
    }

    private func gearSlotLabel(_ slot: String) -> String {
        switch slot {
        case "weapon": return "武器"
        case "body": return "衣"
        case "hand", "hands": return "手"
        case "feet": return "足"
        case "amulet": return "護符"
        case "ring": return "指輪"
        default: return "装備"
        }
    }

    private func openResultComparison(_ item: GearInstance) {
        guard let catalog else { flow.selectGear(item.id, screen: 15); return }
        let originalActor = model.selectedActor
        let slot = catalog.gear.first(where: { $0.id == item.definitionID })?.slot ?? ""
        for actorID in state.partyActorIDs {
            model.selectedActor = actorID
            guard model.canEquip(item) else { continue }
            let usableIDs = Set(state.gear.filter { model.canEquip($0) }.map(\.id))
            let equippedID = state.equippedGearIDs["\(actorID)|\(slot)"]
            let actual = equippedID.flatMap { id in state.gear.first { $0.id == id } }
            let candidate: GearInstance
            let baseline: GearInstance?
            if actual?.id == item.id {
                guard let alternative = state.gear.first(where: { candidate in
                    guard candidate.id != item.id,
                          catalog.gear.first(where: { $0.id == candidate.definitionID })?.slot == slot else { return false }
                    return model.canEquip(candidate)
                }) else { continue }
                candidate = alternative
                baseline = actual
            } else {
                candidate = item
                baseline = actual ?? GearComparisonPartnerSelectionR210.selectCounterpart(
                    itemID: item.id, actorID: actorID, gear: state.gear, definitions: catalog.gear,
                    equippedGearIDs: state.equippedGearIDs, usableGearIDs: usableIDs
                ).flatMap { partnerID in state.gear.first { $0.id == partnerID && $0.id != item.id } }
            }
            guard let baseline, baseline.id != candidate.id else { continue }
            model.selectedActor = actorID
            flow.gearID = candidate.id
            model.comparison = [baseline.id, candidate.id]
            flow.go(16)
            return
        }
        model.selectedActor = originalActor
        flow.selectGear(item.id, screen: 15)
    }
}
