import SwiftUI
import SpriteKit

extension GameModel {
    var recyclableGearIDs:[UUID] {
        var remaining=Dictionary(grouping:state.gear,by: \.definitionID).mapValues{$0.count-1}
        return state.gear.reversed().compactMap{item in
            guard item.qualityID=="Q0",!item.protected,!state.equippedGearIDs.values.contains(item.id),remaining[item.definitionID,default:0]>0 else{return nil}
            remaining[item.definitionID,default:0]-=1;return item.id
        }
    }
    func salvage(_ ids:[UUID]) {
        guard !busy,let engine else{return};busy=true
        Task {var count=0
            do {for id in ids {
                let current=await engine.snapshot()
                guard let item=current.gear.first(where:{$0.id==id}),item.qualityID=="Q0",!item.protected,!current.equippedGearIDs.values.contains(id),current.gear.filter({$0.definitionID==item.definitionID}).count>1 else{continue}
                _ = try await engine.dispatch(.dismantle(gearID:id),operationID:UUID(),expectedRevision:current.revision);count+=1
            };notice="\(count)個の装備を研成の粉に戻しました。"}
            catch{self.error="\(count)個を分解しました。残りは保持しています。\n"+GameText.error(error)}
            await refresh();busy=false
        }
    }

    /// Each step is separately durable. Retry is safe and never grants a purchased entitlement.
    func wearCandidate(_ id:String,kind:String,actorID:String? = nil,onSuccess:(()->Void)? = nil) {
        guard !busy,let engine else{return};busy=true
        let recipient = actorID ?? selectedActor
        Task {do {
            if !state.ownedCosmeticIDs.contains(id) {
                _ = try await engine.dispatch(.setCosmetic(id,owned:true),operationID:UUID(),expectedRevision:state.revision);await refresh()
            }
            let cmd:GameCommand = kind=="weapon" ? .selectWeaponAppearance(actorID:recipient,appearanceID:id):.selectCosmetic(actorID:recipient,cosmeticID:id)
            _ = try await engine.dispatch(cmd,operationID:UUID(),expectedRevision:state.revision)
            await refresh();notice="旅支度を保存しました。";onSuccess?()
        }catch{self.error=GameText.error(error);await refresh()};busy=false}
    }
    func resetWardrobeAppearance(_ command:GameCommand,message:String,onSuccess:(()->Void)? = nil) {
        guard !busy,let engine else{return};busy=true
        Task {do {
            _ = try await engine.dispatch(command,operationID:UUID(),expectedRevision:state.revision)
            await refresh();notice=message;onSuccess?()
        }catch{self.error=GameText.error(error);await refresh()};busy=false}
    }
    func challenge(_ challenge:ChallengeDefinition){
        guard !busy,let engine else{return};busy=true;fighting=true
        chosenRegion=challenge.region;tab="探索";sheet=nil
        activeAreaFightEnemyID=challenge.enemyIDs.first
        syncScene()
        scene.setEnemies(challenge.enemyIDs)
        playbackTask=Task {do {
            let r=try await engine.dispatch(.resolveChallenge(challengeID:challenge.id,seed:UInt64(bitPattern: state.revision) &+ 1001),operationID:UUID(),expectedRevision:state.revision)
            await refresh()
            if let battle=state.lastCombatResult {await play(battle);await presentBattleResolution(won:battle.won);notice=battle.won ? "研究課題を達成しました。":"装備を整え、もう一度挑戦しよう。"}
            writeReceipt("challenge",challenge.id+":"+r.result);writeReceipt("challenge_art",scene.artAuditJSON())
        }catch{self.error=GameText.error(error)};activeAreaFightEnemyID=nil;busy=false;fighting=false
            // A research challenge temporarily changes the displayed field only.
            // Return to the saved expedition without resetting its gathering clock.
            chosenRegion=state.activeRegionID ?? challenge.region
            syncScene()}

    }
    func compare(_ item:GearInstance){
        guard let definition=catalog?.gear.first(where:{$0.id==item.definitionID}), let other=state.gear.first(where:{candidate in candidate.id != item.id && catalog?.gear.first(where:{$0.id==candidate.definitionID}).map{$0.slot==definition.slot && ($0.actorIDs.isEmpty || $0.actorIDs.contains(selectedActor))}==true})else{error="同じ部位の装備をもう一つ制作すると比較できます。";return}
        comparison=[item.id,other.id];sheet="比較"
    }
}

struct WardrobeView:View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model:GameModel
    let names=["ERNA_TRAVEL":"露草色の旅支度","STAFF_BRANCH":"若枝の杖","STAFF_MOON":"月環の杖"]
    @State private var previewSelection = WardrobePreviewSelectionR094()
    @State private var wardrobeActorID:String?
    private var appearanceActorIDs:[String] {
        model.state.partyActorIDs.filter { actor in model.catalog?.appearances.contains(where:{$0.actorIDs.contains(actor)}) ?? false }
    }
    private var activeWardrobeActorID:String {
        if let wardrobeActorID, appearanceActorIDs.contains(wardrobeActorID) { return wardrobeActorID }
        if appearanceActorIDs.contains(model.selectedActor) { return model.selectedActor }
        return appearanceActorIDs.first ?? model.selectedActor
    }
    private var actorBinding:Binding<String> {
        Binding(get:{activeWardrobeActorID},set:{wardrobeActorID=$0;previewSelection.clear()})
    }
    private var previewOverrides:[String:String] { previewSelection.applying(to:model.sceneAppearance) }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("旅支度").font(.system(.title,design:.serif))
            Text("見た目を変えても、装備の性能は変わりません。").font(.caption).foregroundStyle(Palette.gold)
            let layout:AnyLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)):AnyLayout(HStackLayout(spacing:12))
            layout {
                WardrobePortrait(model:model,actorID:activeWardrobeActorID,appearanceOverrides:previewOverrides).frame(width:170,height:220).clipShape(RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:10) {
                    if !appearanceActorIDs.isEmpty {
                        Picker("試着する仲間",selection:actorBinding) {
                            ForEach(appearanceActorIDs,id:\.self) { actor in Text(GameModel.actorNames[actor] ?? "仲間").tag(actor) }
                        }.pickerStyle(.menu).accessibilityIdentifier("wardrobe_actor_picker")
                    }
                    Text(GameModel.actorNames[activeWardrobeActorID] ?? "仲間")
                    Button("標準衣装に戻す") { model.resetWardrobeAppearance(.selectCosmetic(actorID:activeWardrobeActorID,cosmeticID:nil),message:"標準衣装に戻しました。",onSuccess:{previewSelection.clear()}) }.frame(minHeight:44)
                    Button("標準の武器外観に戻す") { model.resetWardrobeAppearance(.selectWeaponAppearance(actorID:activeWardrobeActorID,appearanceID:nil),message:"標準の武器外観に戻しました。",onSuccess:{previewSelection.clear()}) }.frame(minHeight:44).accessibilityIdentifier("reset_weapon_appearance")
                }.fixedSize(horizontal:false,vertical:true)
            }
            if appearanceActorIDs.isEmpty { Text("試着できる見た目はありません。").font(.caption) }
            ForEach(model.catalog?.appearances.filter{$0.actorIDs.contains(activeWardrobeActorID)} ?? []){a in
                let selected = model.state.selectedCosmeticIDs[activeWardrobeActorID] == a.id || model.state.selectedWeaponAppearanceIDs[activeWardrobeActorID] == a.id
                HStack(alignment:.center,spacing:10) {
                    AssetIcon(id:a.kind=="costume" ? a.id+"__idle":a.id,size:64).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:5) {
                        Text(names[a.id] ?? a.id)
                        Text(a.kind=="costume" ? "衣装":"武器の見た目").font(.caption).foregroundStyle(Palette.gold)
                        Button(previewSelection.appearanceID == a.id ? "試着中":"この見た目を試す") {
                            previewSelection.show(appearanceID:a.id,kind:a.kind)
                        }.frame(minHeight:44).accessibilityIdentifier("preview_appearance_"+a.id)
                        Button(selected ? "選択中":"この見た目を使う") {
                            model.wearCandidate(a.id,kind:a.kind,actorID:activeWardrobeActorID,onSuccess:{previewSelection.clear()})
                        }.frame(minHeight:44).disabled(selected).accessibilityIdentifier("use_appearance_"+a.id)
                    }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("appearance_"+a.id)
            }
            Text("追加衣装・武器は制作検証用です。正式販売品ではありません。").font(.caption).foregroundStyle(Palette.gold)
        }.disabled(model.busy)
        .onChange(of:activeWardrobeActorID){_,_ in previewSelection.clear()}
    }
}

/// Uses the same body, weapon anchor and hand occlusion as home and combat.
struct WardrobePortrait:View {
    @ObservedObject var model:GameModel
    let actorID:String
    let appearanceOverrides:[String:String]
    @State private var preview=LivingScene(size:CGSize(width:170,height:220))
    var body:some View {
        SpriteView(scene:preview).accessibilityElement(children:.ignore).accessibilityLabel((GameModel.actorNames[actorID] ?? "仲間")+"の試着見本").onAppear{update()}
            .onChange(of:appearanceOverrides){_,_ in update()}
            .onChange(of:actorID){_,_ in update()}
    }
    private func update(){preview.scaleMode = .resizeFill;preview.configure(place:.portrait(GameModel.spriteIDs[actorID] ?? "ERNA"),cosmetics:appearanceOverrides,furniture:[])}
}

struct InventoryView:View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model:GameModel
    let opening:Bool
    @State private var dismantleTarget:UUID?
    @State private var quality="すべて"
    @State private var search=""
    @State private var showBulk=false
    var visible:[GearInstance]{model.state.gear.reversed().filter{g in (!opening || model.opening.contains(g.id)) && (quality=="すべて" || g.qualityID==quality) && (search.isEmpty || (model.catalog?.gear.first{$0.id==g.definitionID}?.name ?? g.definitionID).localizedCaseInsensitiveContains(search))}}
    var recyclable:[UUID]{model.recyclableGearIDs}
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Text(opening ? "届いた装備":"持ちもの").font(.system(.title,design:.serif))
            if dynamicTypeSize.isAccessibilitySize {
                Picker("装備する仲間",selection:$model.selectedActor){ForEach(model.state.partyActorIDs,id:\.self){Text(GameModel.actorNames[$0] ?? $0).tag($0)}}.pickerStyle(.menu).accessibilityIdentifier("inventory_actor_picker")
            } else {
                Picker("装備する仲間",selection:$model.selectedActor){ForEach(model.state.partyActorIDs,id:\.self){Text(GameModel.actorNames[$0] ?? $0).tag($0)}}.pickerStyle(.segmented)
            }
            Text("研成の粉  \(model.state.materials["refine_dust",default:0])").font(.caption).foregroundStyle(Palette.gold)
            Text("所持 \(model.state.gear.count) / 表示 \(visible.count)").font(.caption).accessibilityIdentifier("inventory_count")
            TextField("装備名で探す",text:$search,prompt:Text("装備名で探す").foregroundColor(Palette.text.opacity(0.8))).textFieldStyle(.roundedBorder).accessibilityIdentifier("inventory_search")
            if dynamicTypeSize.isAccessibilitySize {
                Picker("品質",selection:$quality){Text("すべて").tag("すべて");ForEach(["Q0","Q1","Q2","Q3","Q4"],id:\.self){Text(GameText.quality($0)).tag($0)}}.pickerStyle(.menu).accessibilityIdentifier("inventory_quality_picker")
            } else {
                Picker("品質",selection:$quality){Text("すべて").tag("すべて");ForEach(["Q0","Q1","Q2","Q3","Q4"],id:\.self){Text(GameText.quality($0)).tag($0)}}.pickerStyle(.segmented)
            }
            if !opening && !recyclable.isEmpty {Button("未保護のC装備をまとめて分解（\(recyclable.count)個）"){showBulk=true}.font(.caption).frame(minHeight:44).disabled(model.busy).accessibilityIdentifier("bulk_salvage")}
            LazyVStack(spacing:14){ForEach(visible){g in gearRow(g)}}
        }.confirmationDialog("この装備を分解しますか？",isPresented:Binding(get:{dismantleTarget != nil},set:{if !$0{dismantleTarget=nil}}),titleVisibility:.visible){Button("分解する",role:.destructive){if let id=dismantleTarget{model.act(.dismantle(gearID:id),"研成の粉を取り出しました。")};dismantleTarget=nil};Button("キャンセル",role:.cancel){dismantleTarget=nil}}message:{Text("分解した装備は元に戻せません。保護中・使用中の装備は分解できません。")}
        .alert("未保護・未使用のC装備を\(recyclable.count)個分解しますか？",isPresented:$showBulk){Button("まとめて分解する",role:.destructive){model.salvage(recyclable)};Button("キャンセル",role:.cancel){}}message:{Text("保護中・使用中の装備と、各種類の最後の1個は残ります。分解は取り消せません。")}

    }
    func gearRow(_ g:GearInstance)->some View {
        let def=model.catalog?.gear.first{$0.id==g.definitionID}
        let evolution=model.catalog?.recipes.filter{$0.parentTemplateID==g.definitionID && $0.kind=="evolve_in_place"} ?? []
        return VStack(alignment:.leading,spacing:10){
            HStack{AssetIcon(id:"ICO_"+g.definitionID,size:52).accessibilityHidden(true);VStack(alignment:.leading,spacing:4){Text(def?.name ?? g.definitionID).font(.subheadline);Text("\(GameText.quality(g.qualityID))  +\(g.enhancement)  研成\(g.refinement)").font(.caption).foregroundStyle(Palette.gold);if g.ownerID != nil{Text("使用中").font(.caption)}};Spacer();Button{model.act(.protect(gearID:g.id,protected:!g.protected),g.protected ? "保護を解除しました。":"保護しました。")}label:{Image(systemName:g.protected ? "lock.fill":"lock.open").frame(width:44,height:44)}.accessibilityLabel(g.protected ? "\(def?.name ?? "装備")の保護を解除":"\(def?.name ?? "装備")を保護").accessibilityValue(g.protected ? "保護中":"保護なし").accessibilityHint("誤分解を防ぐ設定です")}
            GearLatentDetailsView(model: model, item: g)
            Group {
                if dynamicTypeSize >= .accessibility3 {
                    VStack(spacing:10) { gearActions(g,definition:def,evolution:evolution) }
                } else if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                        gearActions(g,definition:def,evolution:evolution)
                    }
                } else { HStack { gearActions(g,definition:def,evolution:evolution) } }
            }.font(.caption).buttonStyle(.bordered).disabled(model.busy)
        }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("gear_"+g.id.uuidString)
    }
    @ViewBuilder private func gearActions(_ item:GearInstance,definition:GearDefinition?,evolution:[RecipeDefinition])->some View {
        Button { model.compare(item) } label: { actionLabel("比較") }
        Button { model.act(.equip(gearID:item.id,actorID:model.selectedActor),"装備を更新しました。") } label: { actionLabel("装備") }
            .disabled(!model.canEquip(item))
        Menu {
            Button("強化") { model.act(.enhance(gearID:item.id),"強化しました。") }
            Button("研成") { model.act(.refine(gearID:item.id),"研成しました。") }
            Button("品質を昇格") { model.act(.promoteQuality(gearID:item.id),"品質が上がりました。") }
            ForEach(evolution) { recipe in
                Button("進化: "+(model.catalog?.gear.first{$0.id==recipe.outputGearID}?.name ?? recipe.id)) {
                    model.showRecipeGoal(recipe.id, gearID: item.id)
                }
            }
        } label: { actionLabel("育てる") }
        Button(role:.destructive) { dismantleTarget=item.id } label: { actionLabel("分解") }
            .disabled(item.protected || model.state.equippedGearIDs.values.contains(item.id))
    }
    private func actionLabel(_ title:String)->some View {
        Text(title).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44)
    }

}

struct GearComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: GameModel
    var items: [GearInstance] { model.comparison.compactMap { id in model.state.gear.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("装備を比べる").font(.system(.title, design: .serif))
            Text("装備全体の性能と、選んだ仲間に有効な潜在効果を比べられます。")
                .font(.caption).foregroundStyle(Palette.gold)
            let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout { ForEach(items) { item in comparisonCard(item) } }
            if items.count == 2 {
                Button {
                    model.act(.markGearComparisonSeen(firstGearID: items[0].id, secondGearID: items[1].id),
                              "装備の違いを発見しました。魔導庫で無料鑑定ができます。")
                    model.sheet = "装備"
                } label: {
                    Text("比較を終える").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                .accessibilityIdentifier("finish_comparison").disabled(model.busy)
            }
        }
    }

    private func comparisonCard(_ item: GearInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AssetIcon(id: "ICO_" + item.definitionID, size: 100)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(model.catalog?.gear.first { $0.id == item.definitionID }?.name ?? item.definitionID)
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            LabeledContent("品質", value: GameText.quality(item.qualityID))
            LabeledContent("強化", value: "+\(item.enhancement)")
            LabeledContent("研成", value: "\(item.refinement)")
            Divider()
            switch Result(catching: { try model.comparisonStats(item) }) {
            case .success(let preview):
                Text("装着時の仲間の性能").foregroundStyle(Palette.gold)
                LabeledContent("攻撃", value: "\(preview.combatant.attack)")
                LabeledContent("体力", value: "\(preview.combatant.maxHP)")
                LabeledContent("防御", value: "\(preview.combatant.defense)")
                ForEach(preview.combatant.effectIDs.sorted().filter { !$0.hasPrefix("AF_") }, id: \.self) {
                    Text(GameText.effect($0)).fixedSize(horizontal: false, vertical: true)
                }
                if let latent = preview.latent { GearLatentAggregateView(projection: latent, actorID: model.selectedActor, effectIDs: preview.combatant.effectIDs) }
            case .failure(let error):
                Text(GameText.error(error)).foregroundStyle(Palette.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            GearLatentDetailsView(model: model, item: item)
            Button {
                model.act(.equip(gearID: item.id, actorID: model.selectedActor), "装備を更新しました。")
            } label: {
                Text("こちらを装備").fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.bordered).disabled(model.busy || !model.canEquip(item))
            .accessibilityIdentifier("compare_equip_" + item.id.uuidString)
        }
        .font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: 12))
        // A parent identifier propagates to child rows/buttons in SwiftUI; keep their individual IDs.
    }
}

struct ResearchView:View {
    @ObservedObject var model:GameModel
    private var challengesUnlocked:Bool { model.state.completedEncounterIDs.contains("B_R05_B") }
    private func benefit(_ research:ResearchDefinition)->String {
        guard let effect=model.catalog?.researchEffects[research.effectID] else { return "効果を確認できません" }
        var values:[String]=[]
        if effect.partyAttack > 0 { values.append("攻撃 +\(effect.partyAttack)") }
        if effect.partyMaxHP > 0 { values.append("体力 +\(effect.partyMaxHP)") }
        if effect.partyDefense > 0 { values.append("防御 +\(effect.partyDefense)") }
        return "仲間全員の"+values.joined(separator:"・")
    }
    private func lockReason(_ research:ResearchDefinition)->String? {
        if let gate=model.catalog?.recipes.first(where:{$0.id==research.id})?.gateID,gate != "G_START" {
            let parts=gate.split(separator:"_")
            guard parts.count==3,parts[0]=="G" else { return "解放条件を確認できません" }
            let enemyID="B_\(parts[1])_\(parts[2])"
            if !model.state.completedEncounterIDs.contains(enemyID) {
                let name=model.catalog?.enemies.first(where:{$0.id==enemyID})?.name ?? "手前のボス"
                return name+"の討伐で解放"
            }
        }
        if research.cost.contains(where:{model.state.materials[$0.key,default:0] < $0.value}) {
            return "必要な素材を集めると研究できます"
        }
        return nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("採集帳").font(.system(.title,design:.serif));Text("出会った魔物 \(model.state.completedEncounterIDs.filter{!$0.hasPrefix("CHALLENGE")}.count) / 30").font(.caption).foregroundStyle(Palette.gold)
            Text("暮らしと冒険の研究").font(.title3)
            ForEach(model.catalog?.research ?? []) { r in
                VStack(alignment:.leading,spacing:10) {
                    Text(r.name).font(.headline)
                    Text(benefit(r)).foregroundStyle(Palette.text)
                        .accessibilityIdentifier("research_benefit_"+r.id)
                    Text(r.cost.isEmpty ? "素材消費なし" : r.cost.sorted{$0.key<$1.key}.map{"\(GameText.name($0.key)) \(model.state.materials[$0.key,default:0])/\($0.value)"}.joined(separator:" · "))
                        .font(.caption).foregroundStyle(Palette.gold).fixedSize(horizontal:false,vertical:true)
                    if model.state.completedResearchIDs.contains(r.id) {
                        Label("習得済み",systemImage:"checkmark.seal.fill")
                            .foregroundStyle(Palette.gold).frame(minHeight:44)
                            .accessibilityIdentifier("research_complete_"+r.id)
                    } else if let reason=lockReason(r) {
                        Label(reason,systemImage:"lock.fill").font(.caption)
                            .foregroundStyle(Palette.text).fixedSize(horizontal:false,vertical:true)
                            .frame(minHeight:44,alignment:.leading)
                            .accessibilityIdentifier("research_lock_"+r.id)
                    } else {
                        Button("研究する") { model.act(.completeResearch(r.id),"研究の成果を記録しました。") }
                            .buttonStyle(.borderedProminent).foregroundStyle(Palette.ink)
                            .disabled(model.busy).frame(minHeight:44)
                            .accessibilityIdentifier("research_action_"+r.id)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                    .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
            }
            Text("深まる森の15課題").font(.title3);Text("第五地域の最終ボスを越えると挑めます。").font(.caption).foregroundStyle(Palette.gold)
            ForEach(model.catalog?.challenges ?? []) { c in
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text(c.name).font(.headline)
                        Spacer()
                        if model.state.completedEncounterIDs.contains("CHALLENGE_CLEAR|"+c.id) {
                            Image(systemName:"checkmark.seal.fill").foregroundStyle(Palette.gold)
                        }
                    }
                    Text(GameText.challengeMechanic(c.id,fallback:c.mechanic)).font(.caption).foregroundStyle(Palette.gold)
                    if challengesUnlocked {
                        Button("研究課題に挑む") { model.challenge(c) }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Palette.ink)
                            .disabled(model.busy)
                            .frame(minHeight:44)
                            .accessibilityIdentifier("challenge_"+c.id)
                    } else {
                        Label("第五地域の最終ボス討伐で解放",systemImage:"lock.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal:false,vertical:true)
                            .frame(minHeight:44,alignment:.leading)
                            .accessibilityElement(children:.combine)
                            .accessibilityIdentifier("challenge_lock_"+c.id)
                    }
                }.padding(12).background(Palette.panel).clipShape(RoundedRectangle(cornerRadius:12))
            }
        }
    }
}
