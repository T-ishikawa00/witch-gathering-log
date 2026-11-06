import SwiftUI
import SpriteKit

struct UI48AdventureView: View {
    @ObservedObject var model: GameModel
    @ObservedObject var flow: UI48Flow
    let screen: Int
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selectionMode = 0
    @State private var switching = false
    private var region: RegionDefinition? { model.catalog?.regions.first{$0.id==model.chosenRegion} }
    private var enemy: EnemyDefinition? { model.catalog?.enemies.first{$0.id==flow.enemyID} }
    private var goal: RecipeGoalProjectionR035.Goal? {
        if model.state.craftedGearOnce && !model.state.gearComparisonSeen {return nil}
        return model.trackedRecipeGoal ?? model.recipeGoals.first{$0.firstCraftAidApplied} ?? model.recipeGoals.first{$0.kind=="craft_new" && !$0.outputOwned && $0.gateCleared}
    }
    var body: some View {
        Group {switch screen {
        case 1,2,4: living
        case 3: summaryPage
        case 5: map
        case 6: destinations
        case 7: enemyDetail
        case 8: battle
        case 9: victory
        case 10: defeat
        case 11: unlocked
        default: switchConfirmation
        }}
    }
    private var goalTitle: String {
        if let g=goal {if g.ready {return model.recipeGearName(g.outputGearID)+"をつくろう"};if let r=g.requirements.first(where:{$0.missing>0}) {return GameText.name(r.materialID)+"をあと\(r.missing)個集める"};return model.recipeGearName(g.outputGearID)+"を目指す"}
        if model.state.craftedGearOnce && !model.state.gearComparisonSeen {return "つくった装備を比べよう"}
        return model.state.gachaUnlocked ? "次の発見を探そう":"最初の道具をつくろう"
    }
    private var goalDetail: String { if let g=goal {return g.ready ? "材料が揃っています。工房で確認できます":"次の道具："+model.recipeGearName(g.outputGearID)};return model.state.craftedGearOnce ? "仲間に合う装備で、冒険の準備を":"必要な材料を森で探す" }
    private func openGoal() {
        if let g=goal {flow.recipe(g.recipeID,model:model)}
        else if model.state.craftedGearOnce && !model.state.gearComparisonSeen, let c=model.catalog {
            let original=model.selectedActor
            for item in model.state.gear.reversed() {
                guard let definition=c.gear.first(where:{$0.id==item.definitionID}) else{continue}
                for actor in model.state.partyActorIDs {
                    model.selectedActor=actor
                    if model.canEquip(item), let counterpart=model.state.equippedGearIDs[actor+"|"+definition.slot],counterpart != item.id {
                        flow.gearID=item.id;model.comparison=[counterpart,item.id];flow.go(16);return
                    }
                }
            }
            model.selectedActor=original;flow.go(14)
        } else {flow.go(model.state.gachaUnlocked ? 36:19)}
    }
    private var living: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene:model.scene).accessibilityRepresentation {
                    Text(model.tab=="家" ? "魔女の家で4人が過ごしています":"森で仲間たちが探索しています").accessibilityIdentifier("living_scene")
                }
                LinearGradient(colors:[.clear,.clear,UI48Theme.ink.opacity(0.95)],startPoint:.top,endPoint:.bottom).allowsHitTesting(false)
                if textSize.isAccessibilitySize {
                    // Large text needs one continuous scroll flow. The compact
                    // scene overlay's separate capped bottom area would overlap
                    // the expanded goal and speech card on a short display.
                    ScrollView {
                        VStack(spacing:16) {
                            UI48Goal(title:goalTitle,detail:goalDetail,action:openGoal).accessibilityIdentifier("ui48_home_goal")
                            if screen == 4 {
                                Button { flow.go(5) } label: {
                                    Label(region?.name ?? "旅の地図",systemImage:"safari")
                                        .frame(maxWidth:.infinity,minHeight:44)
                                }.buttonStyle(UI48ButtonStyle(secondary:true)).accessibilityIdentifier("ui48_map")
                                UI48Panel {
                                    progress
                                    UI48Action(title:"成果を受け取る",symbol:"bag",disabled:model.busy,id:"claim_offline"){model.collect()}
                                    UI48Action(title:"採集・魔物",symbol:"safari",secondary:true,id:"ui48_destinations"){flow.go(6)}
                                }
                            } else {
                                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                                    smallTool("衣装","tshirt",40);smallTool("模様替え","chair",42)
                                    smallTool("商店","bag",43);smallTool("魔導庫","star",36)
                                }
                                homeBottom
                            }
                        }.padding(15)
                    }.accessibilityIdentifier("ui48_living_accessibility_scroll")
                } else { VStack(spacing:12) {
                    UI48Goal(title:goalTitle,detail:goalDetail,action:openGoal).accessibilityIdentifier("ui48_home_goal")
                    if screen == 4 {
                        Button{flow.go(5)}label:{Label(region?.name ?? "旅の地図",systemImage:"safari").font(.footnote).padding(.horizontal,16).frame(minHeight:44).background(UI48Theme.enamel.opacity(0.9)).clipShape(Capsule()).overlay(Capsule().stroke(UI48Theme.gold.opacity(0.7),lineWidth:1))}.buttonStyle(.plain).accessibilityIdentifier("ui48_map")
                            .frame(maxWidth:.infinity,alignment:geometry.size.height/geometry.size.width < 1.45 ? .trailing:.center)
                    } else {
                        HStack(spacing:8){Spacer();smallTool("衣装","tshirt",40);smallTool("模様替え","chair",42);smallTool("商店","bag",43);smallTool("魔導庫","star",36)}
                    }
                    Spacer(minLength:20)
                    ScrollView {
                        VStack(spacing:12) {
                            if screen == 4 { UI48Panel { progress; UI48ResponsiveRow(spacing:10){UI48Action(title:"成果を受け取る",symbol:"bag",disabled:model.busy,id:"claim_offline"){model.collect()};UI48Action(title:"採集・魔物",symbol:"safari",secondary:true,id:"ui48_destinations"){flow.go(6)}} } }
                            else { homeBottom }
                        }.padding(.vertical,5)
                    }.scrollIndicators(.hidden).fixedSize(horizontal:false,vertical:true).frame(maxHeight:geometry.size.height*(textSize.isAccessibilitySize ? 0.5:0.39))
                }.padding(15) }
            }
        }
    }
    private func smallTool(_ name:String,_ symbol:String,_ id:Int) -> some View { Button{flow.go(id)}label:{Label(name,systemImage:symbol).font(.caption).padding(.horizontal,10).frame(minHeight:44).background(UI48Theme.ink.opacity(0.88)).clipShape(UI48Frame(radius:12)).overlay(UI48Frame(radius:12).stroke(UI48Theme.gold,lineWidth:1))}.buttonStyle(.plain) }
    private var homeBottom: some View {
        TimelineView(.periodic(from:.now,by:1)) { time in
            let values = model.catalog.flatMap{SharedPartyWorkProgressR146.project(state:model.state,catalog:$0,now:time.date)}
            VStack(spacing:12) {
                if let values,values.ready>0 {
                    HStack(spacing:12) {
                        Image(systemName:"bag.fill").font(.system(size:64)).foregroundStyle(UI48Theme.gold).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:8) {
                            Text("森からの持ち帰り").font(.caption).foregroundStyle(UI48Theme.paperInk)
                            Text("素材の成果が届いています").font(.headline).foregroundStyle(UI48Theme.paperInk)
                            UI48Item(assetID:"ICO_"+values.materialID,count:"\(values.ready)",size:49)
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(UI48Theme.paper).clipShape(UI48Frame(radius:15))
                    }
                    UI48Action(title:"成果を受け取る",symbol:"bag",disabled:model.busy,id:"claim_offline"){model.collect()}
                } else {
                    HStack(spacing:12) { UI48Portrait(actorID:"C_WITCH",size:42);Text("まずは、森の贈りものを\n探しにいきましょう。").accessibilityIdentifier("ui48_home_guidance").font(.system(.body,design:.serif)).fixedSize(horizontal:false,vertical:true) }.padding(15).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(UI48Theme.paperInk).background(UI48Theme.paper).clipShape(UI48Frame(radius:17))
                    UI48Action(title:"材料を探す",symbol:"leaf",id:"ui48_home_explore"){flow.home(model,tab:"探索")}
                }
                Text("採集は画面を閉じている間も進みます。").font(.caption2).multilineTextAlignment(.center)
            }
        }
    }
    private var progress: some View {
        TimelineView(.periodic(from:.now,by:1)) {time in
            if let catalog=model.catalog,let v=SharedPartyWorkProgressR146.project(state:model.state,catalog:catalog,now:time.date) {
                HStack{AssetIcon(id:"ICO_"+v.materialID,size:48);VStack(alignment:.leading,spacing:4){Text(v.target).font(.headline);Text("受け取れる成果 \(v.ready)単位").font(.caption).foregroundStyle(UI48Theme.muted)}}
                ProgressView(value:Double(v.interval-v.secondsToNext),total:Double(v.interval)).tint(Color(hex48:0xb7ce8e))
                Text(v.capped ? "48時間分の保管上限に達しています":"次の素材まで \(v.secondsToNext/60):\(String(format:"%02d",v.secondsToNext%60))").font(.caption).frame(maxWidth:.infinity,alignment:.trailing)
            } else if let catalog=model.catalog {GatheringProgressViewR041(catalog:catalog,state:model.state)}
        }
    }
    private var summaryPage: some View {
        UI48Page {UI48Heading(title:"おかえりなさい。",subtitle:model.collectionSummary?.isEmpty == true ? "次の発見を待っています。":"仲間が持ち帰った成果をしまいました。")
            if let s=model.collectionSummary {summaryContent(s);Text("成果を保存しました。再表示で重複受取はしません。").font(.caption).foregroundStyle(UI48Theme.muted);if !s.gainedGear.isEmpty {UI48Action(title:"新しい装備を見る",symbol:"bag"){model.opening=s.gainedGear.map(\.id);flow.go(39)}}}
            UI48Goal(title:goalTitle,detail:goalDetail,action:openGoal).accessibilityIdentifier("ui48_home_goal")
            UI48Action(title:"家に戻る",secondary:true){flow.home(model);model.presentPendingGatherVisualAfterResultDismissal()}
        }
    }
    @ViewBuilder private func summaryContent(_ s: GatheringSummary) -> some View {
        if !s.materials.isEmpty {
            HStack(spacing:18) {ForEach(Array(s.materials.filter{$0.0 != "dust"}.prefix(3)),id:\.0){id,_ in AssetIcon(id:"ICO_"+id,size:75)}}
                .frame(maxWidth:.infinity,minHeight:90).padding(.vertical,8)
        }
        if !s.gainedGear.isEmpty {UI48Panel(title:"見つけた装備") {LazyVGrid(columns:[GridItem(.adaptive(minimum:76))]){ForEach(s.gainedGear){item in Button{flow.selectGear(item.id)}label:{UI48Item(assetID:"ICO_"+item.definitionID,qualityID:item.qualityID,count:"NEW")}.buttonStyle(.plain).accessibilityLabel(s.gearName(item))}}}}
        UI48Panel(title:"採集した素材") {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:textSize.isAccessibilitySize ? 280:145))],alignment:.leading,spacing:12) {
                ForEach(s.materials,id:\.0){id,count in
                    HStack(spacing:8){AssetIcon(id:"ICO_"+id,size:32);VStack(alignment:.leading,spacing:3){Text(GameText.name(id)).font(.caption);Text("+\(count)").font(.headline).monospacedDigit()}}
                }
            }
            if s.materials.isEmpty {Text("新しい素材はありません").font(.footnote)}
        }
        if !s.currency.isEmpty || !s.experience.isEmpty {
            UI48Panel(title:"今回の成果") {
                ForEach(s.currency,id:\.0){id,count in LabeledContent(GameText.name(id),value:"+\(count)").font(.footnote)}
                LazyVGrid(columns:[GridItem(.adaptive(minimum:textSize.isAccessibilitySize ? 280:145))],alignment:.leading,spacing:8) {
                    ForEach(s.experience,id:\.0){id,count in HStack{Text(GameModel.actorNames[id] ?? id);Spacer(minLength:4);Text("+\(count) EXP").monospacedDigit()}.font(.caption)}
                }
            }
        }
    }
    private var map: some View {
        UI48Page {UI48Heading(title:"次は、どこへ。",subtitle:"5つの地域に眠る道具と発見。")
            ForEach(Array((model.catalog?.regions ?? []).enumerated()),id:\.element.id){index,r in
                Button {clearHandoffs();flow.regionID=r.id;flow.pendingTitle=r.name;flow.workTarget=nil;flow.go(12)}label:{HStack(spacing:14){Text(String(format:"%02d",index+1)).font(.system(.largeTitle,design:.serif)).foregroundStyle(UI48Theme.gold);VStack(alignment:.leading,spacing:5){Text(r.name).font(.system(.headline,design:.serif));Text(model.state.unlockedRegionIDs.contains(r.id) ? "討伐 \(r.enemyIDs.filter{model.state.completedEncounterIDs.contains($0)}.count) / \(r.enemyIDs.count)":"手前の地域の主を倒すと解放").font(.caption)};Spacer();Image(systemName:model.state.unlockedRegionIDs.contains(r.id) ? "chevron.right":"lock")}.padding(14).frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:textSize.isAccessibilitySize ? 170:100).background{UI48BackgroundArt(id:"BG_"+r.id+"_FIELD").overlay(UI48Theme.ink.opacity(0.55)).allowsHitTesting(false)}.clipShape(UI48Frame(radius:17)).overlay(UI48Frame(radius:17).stroke(UI48Theme.gold,lineWidth:1).allowsHitTesting(false)).contentShape(UI48Frame(radius:17))}.buttonStyle(.plain).accessibilityLabel(r.name + (model.state.unlockedRegionIDs.contains(r.id) ? "、解放済み":"、手前の地域の主を倒すと解放")).accessibilityIdentifier("ui48_region_"+r.id)
            }
            UI48Action(title:"地図を閉じる",secondary:true){flow.back()}
        }
    }
    private var destinations: some View {
        UI48Page {UI48Heading(title:"探したいものを選ぶ",subtitle:"素材集めと魔物の再調査は、同じ作業時間を使います。")
            UI48Tabs(labels:["採集する","魔物を探す"],selection:$selectionMode)
            if selectionMode==0 {ForEach(region?.gatherMaterialIDs ?? [],id:\.self){id in Button{flow.materialID=id;flow.regionID=model.chosenRegion;flow.workTarget = .gather(id);clearHandoffs();flow.go(12)}label:{artRow("ICO_"+id,GameText.name(id),"所持 \(model.state.materials[id,default:0])個",trail:model.availableMaterials[model.chosenRegion]?.contains(id)==true ? "入手先へ":"未解放")}.buttonStyle(.plain).accessibilityIdentifier("gather_"+id)}}
            ForEach(model.catalog?.enemies.filter{$0.regionID==model.chosenRegion} ?? []){e in
                if selectionMode==1 || goal?.requirements.contains(where:{$0.materialID==e.dropMaterialID && $0.missing>0})==true {Button{flow.enemyID=e.id;flow.go(7)}label:{artRow("ACT_"+e.id,e.name,e.dropMaterialID.map(GameText.name) ?? "戦いの記録",trail:model.state.completedEncounterIDs.contains(e.id) ? "討伐済み":"未討伐")}.buttonStyle(.plain).accessibilityIdentifier("ui48_enemy_"+e.id)}
            }
            UI48Note(text:"材料を選ぶと、必要な行き先と現在の条件を確認できます。")
            UI48Action(title:"探索を続ける",secondary:true){flow.home(model,tab:"探索")}
        }
    }
    private func artRow(_ asset:String,_ title:String,_ detail:String,trail:String="") -> some View {
        HStack(spacing:12){AssetIcon(id:asset,size:55);VStack(alignment:.leading,spacing:5){Text(title).font(.headline);Text(detail).font(.caption).foregroundStyle(UI48Theme.muted)};Spacer();Text(trail).font(.caption2).foregroundStyle(UI48Theme.gold);Image(systemName:"chevron.right").font(.caption)}.padding(.vertical,13).frame(maxWidth:.infinity,minHeight:70,alignment:.leading).overlay(alignment:.bottom){Rectangle().fill(UI48Theme.gold.opacity(0.25)).frame(height:1)}.contentShape(Rectangle())
    }
    private var enemyDetail: some View {
        UI48Page {if let e=enemy {
            Text((model.catalog?.regions.first{$0.id==e.regionID}?.name ?? "")+" / "+(model.state.completedEncounterIDs.contains(e.id) ? "討伐済み":"未討伐")).font(.caption).foregroundStyle(UI48Theme.gold)
            UI48Hero(assetID:"ACT_"+e.id,title:e.name,subtitle:e.boss ? "地域に待つ主":"森で出会う魔物")
            UI48Panel(title:"手に入るもの"){if let id=e.dropMaterialID {artRow("ICO_"+id,GameText.name(id),model.state.completedEncounterIDs.contains(e.id) ? "討伐済み。再調査で時間をかけて集めます":"初回討伐で発見する素材")}}
            UI48Panel(title:"4人で挑戦"){UI48ActorStrip(model:model);Text("攻撃・回復・支援は、仲間たちが自動で行います。").font(.footnote)}
            if let prior=e.prerequisiteEncounterID,!model.state.completedEncounterIDs.contains(prior) {UI48Note(text:"先に「\(model.catalog?.enemies.first{$0.id==prior}?.name ?? prior)」の討伐が必要です。",warning:true);UI48Action(title:"前の魔物を確認する",symbol:"safari"){flow.enemyID=prior}}
            else if !model.state.unlockedRegionIDs.contains(e.regionID) {UI48Action(title:"地域の解放条件を見る",symbol:"map"){flow.go(5)}}
            else if model.state.activeRegionID != e.regionID {
                UI48Note(text:"現在の探索先と異なる地域です。採集の成果を確認してから移動できます。")
                UI48Action(title:"この地域への移動を確認する",symbol:"map",id:"ui48_enemy_region_switch") {
                    flow.clearDestination();flow.regionID=e.regionID;flow.pendingEncounterAfterSwitch=e.id;flow.go(12)
                }
            }
            else {UI48Action(title:"この魔物に挑む",symbol:"shield",disabled:model.busy,id:"fight_"+e.id){model.chosenRegion=e.regionID;model.tab="探索";model.fight(e)}
                if model.sharedPartyWorkR146Enabled && model.state.completedEncounterIDs.contains(e.id) && e.dropMaterialID != nil {UI48Action(title:"再調査で素材を集める",symbol:"magnifyingglass",secondary:true){clearHandoffs();flow.workTarget = .investigate(e.id);flow.regionID=e.regionID;flow.materialID=e.dropMaterialID;flow.go(12)}}
            }
            UI48Action(title:"装備を確認する",symbol:"shield",secondary:true){flow.go(13)}
        } else {UI48Note(text:"魔物を選び直してください。");UI48Action(title:"魔物を探す"){flow.go(6)}}}
    }
    private var battle: some View {
        ZStack {
            SpriteView(scene:model.scene).accessibilityRepresentation { Text("4人完全自動戦闘") }
            LinearGradient(colors:[.clear,.clear,UI48Theme.ink.opacity(0.9)],startPoint:.top,endPoint:.bottom).allowsHitTesting(false)
            VStack(spacing:14) {
                TimelineView(.periodic(from:.now,by:0.25)) {_ in
                    UI48Panel {
                        Text(model.catalog?.enemies.first{$0.id==model.activeAreaFightEnemyID}?.name ?? "戦闘中").font(.headline).frame(maxWidth:.infinity)
                        if let id=model.activeAreaFightEnemyID,let v=model.scene.ui48DisplayedVitals(id) {
                            ProgressView(value:Double(v.current),total:Double(v.maximum)).tint(UI48Theme.gold)
                            Text("体力 \(Int(Double(v.current)*100/Double(v.maximum)))%").font(.caption).frame(maxWidth:.infinity,alignment:.trailing)
                        } else {Text(model.preparationMessage ?? "仲間の準備をしています").font(.caption)}
                    }
                }
                Spacer(minLength:20)
                if let warning=model.battleTargetWarningTextR299 {UI48Note(text:warning)}
                TimelineView(.periodic(from:.now,by:0.25)) {_ in
                    HStack(spacing:12) {
                        ForEach(model.state.partyActorIDs,id:\.self) {actor in
                            VStack(spacing:7) {
                                UI48Portrait(actorID:actor,size:44)
                                if let v=model.scene.ui48DisplayedVitals(actor) {
                                    ProgressView(value:Double(v.current),total:Double(v.maximum)).tint(Color(hex48:0xb7ce8e))
                                        .accessibilityLabel("\(GameModel.actorNames[actor] ?? actor) 体力 \(v.current) / \(v.maximum)")
                                }
                                Text(GameModel.actorNames[actor] ?? actor).font(.caption2)
                            }.frame(maxWidth:.infinity)
                        }
                    }.padding(.bottom,12)
                }
                VStack(alignment:.leading,spacing:12) {
                    HStack{Text("完全自動戦闘").font(.headline);Spacer();Text(String(format:"%02d:%02d",model.battleElapsed/60,model.battleElapsed%60)).monospacedDigit()}
                    Text(model.battleResolutionMessage ?? "仲間の装備と固有効果が、戦い方を変えます。").font(.caption)
                }.padding(16).frame(maxWidth:.infinity).background(UI48Theme.ink.opacity(0.85))
            }.padding(16)
        }
    }
    private var victory: some View {
        UI48Page {Image(systemName:"leaf").font(.system(size:42)).foregroundStyle(UI48Theme.gold).frame(maxWidth:.infinity).padding(.vertical,12);UI48Heading(title:"森に、道がひらけた。",subtitle:(model.catalog?.enemies.first{$0.id==model.state.lastEncounterID}?.name ?? model.catalog?.challenges.first{$0.id==flow.challengeID}?.name ?? "魔物")+"を乗り越えました。")
            if let s=flow.battleSummary {summaryContent(s)}
            UI48Goal(title:goalTitle,detail:goalDetail,action:openGoal).accessibilityIdentifier("ui48_home_goal")
            if !flow.newRegionIDs.isEmpty {UI48Action(title:"新しい地域が開きました",symbol:"map"){flow.regionID=flow.newRegionIDs.first;flow.go(11)}}
            UI48Action(title:"工房で確認する",symbol:"hammer"){flow.home(model,tab:"工房")}
            UI48Action(title:"探索へ戻る",secondary:true){flow.home(model,tab:"探索")}
        }
    }
    private var defeat: some View {
        UI48Page {UI48Heading(title:"旅は、まだ続く。",subtitle:"今回は、少しだけ準備を整えましょう。")
            UI48ActorStrip(model:model).padding(.vertical,25)
            UI48Note(text:"装備や素材は失っていません。")
            UI48Panel(title:"今回の振り返り") {if let result=model.state.lastCombatResult {let fallen=model.state.partyActorIDs.filter{result.remainingPartyHP[$0,default:1]<=0};LabeledContent("倒れた仲間",value:fallen.map{GameModel.actorNames[$0] ?? $0}.joined(separator:"・"));ForEach(result.remainingEnemyHP.keys.sorted(),id:\.self){id in LabeledContent(model.catalog?.enemies.first{$0.id==id}?.name ?? "敵",value:"残り体力 \(result.remainingEnemyHP[id,default:0])")}};Text(DefeatGuidanceR229.message(state:model.state,catalog:model.catalog)).font(.footnote)}
            UI48Action(title:"持ちものを確認する",symbol:"shield"){flow.go(14)}
            UI48Action(title:"研究を確認する",symbol:"book",secondary:true){flow.go(31)}
            UI48Action(title:"再挑戦の準備",secondary:true){
                if let id=model.state.lastEncounterID,model.catalog?.challenges.contains(where:{$0.id==id}) == true {
                    flow.challengeID=id;flow.go(34)
                } else {flow.enemyID=model.state.lastEncounterID;flow.go(7)}
            }
            UI48Action(title:"森に戻る",secondary:true){flow.home(model,tab:"探索")}
        }
    }
    private var unlocked: some View {
        let r=model.catalog?.regions.first{$0.id==(flow.regionID ?? flow.newRegionIDs.first)}
        return ZStack {UI48BackgroundArt(id:"BG_"+(r?.id ?? "R01")+"_FIELD");LinearGradient(colors:[UI48Theme.ink.opacity(0.15),UI48Theme.ink],startPoint:.top,endPoint:.bottom)
            UI48Page(transparent:true) {Text(model.state.unlockedRegionIDs.contains(r?.id ?? "") ? "新しい地域が開きました":"地域の解放条件を確認してください").font(.caption).padding(.top,45).frame(maxWidth:.infinity);Text(r?.name ?? "旅の地図").font(.system(.largeTitle,design:.serif)).frame(maxWidth:.infinity).padding(.vertical,20);Spacer(minLength:180);HStack{ForEach(Array((r?.gatherMaterialIDs ?? []).prefix(3)),id:\.self){id in UI48Item(assetID:"ICO_"+id)}}.frame(maxWidth:.infinity);Text("新しい素材・魔物・制作レシピに出会えます。").font(.footnote);UI48Action(title:"新しい地域へ",symbol:"safari",disabled:!model.state.unlockedRegionIDs.contains(r?.id ?? "")){flow.regionID=r?.id;flow.workTarget=nil;clearHandoffs();flow.go(12)};UI48Action(title:"今の地域に残る",secondary:true){flow.home(model,tab:"探索")}}
        }
    }
    private var switchConfirmation: some View {
        UI48Page {UI48Heading(title:"目標の材料を集める",subtitle:"今の作業と、切り替え先を確認しましょう。")
            if let material=flow.pendingRecipeGather?.materialID ?? flow.pendingInvestigation?.materialID ?? flow.pendingResearchGather?.materialID ?? flow.materialID {UI48Hero(assetID:"ICO_"+material,title:GameText.name(material),subtitle:"所持 \(model.state.materials[material,default:0])個")}
            UI48Panel(title:"入手先") {Text(destinationName).font(.headline);Text(switchAllowed ? "この行き先を選べます":"まだ解放されていません。地図・魔物の条件を確認してください。").font(.footnote)}
            UI48Panel(title:"今の作業") {progress;Text("切替前の完了した成果は保存します。端数の時間の扱いは現在の作業ルールに従います。").font(.footnote)}
            UI48Note(text:"この確認を閉じても作業は変わりません。素材が揃っても自動では制作しません。")
            UI48Action(title:"この行き先へ切り替える",symbol:"safari",disabled:model.busy || switching || !switchAllowed,id:"ui48_switch_apply",action:applySwitch)
            if !switchAllowed {
                if let required=requiredEncounter {
                    UI48Note(text:"先に「\(required.name)」を討伐すると先へ進めます。",warning:true)
                    UI48Action(title:"\(required.name)を確認する",secondary:true){flow.enemyID=required.id;flow.go(7)}
                } else {UI48Action(title:"魔物と採集条件を確認する",secondary:true){flow.go(6)}}
            }
            UI48Action(title:"いまの採集を続ける",secondary:true){flow.back();clearHandoffs()}
        }
    }
    private var requiredEncounter: EnemyDefinition? {
        guard let c=model.catalog else{return nil}
        if !model.state.unlockedRegionIDs.contains(destinationRegion),let i=c.regions.firstIndex(where:{$0.id==destinationRegion}),i>0 {
            return c.enemies.first{$0.regionID==c.regions[i-1].id && $0.boss}
        }
        if flow.workTarget?.kind == .investigate {return c.enemies.first{$0.id==flow.workTarget?.targetID}}
        return c.enemies.first{$0.regionID==destinationRegion && !model.state.completedEncounterIDs.contains($0.id)}
    }
    private var destinationRegion: String { flow.pendingRecipeGather?.regionID ?? flow.pendingInvestigation?.regionID ?? flow.pendingResearchGather?.regionID ?? flow.regionID ?? model.chosenRegion }
    private var destinationName: String {let r=model.catalog?.regions.first{$0.id==destinationRegion}?.name ?? "地域";if let enemyID=flow.pendingInvestigation?.enemyID ?? (flow.workTarget?.kind == .investigate ? flow.workTarget?.targetID:nil) {return r+" / "+(model.catalog?.enemies.first{$0.id==enemyID}?.name ?? "魔物")};return r}
    private var switchAllowed: Bool {
        guard model.state.unlockedRegionIDs.contains(destinationRegion) else{return false}
        if flow.workTarget?.kind == .investigate && !model.sharedPartyWorkR146Enabled {return false}
        if let r=flow.pendingRecipeGather {return model.availableMaterials[r.regionID]?.contains(r.materialID)==true}
        if let r=flow.pendingResearchGather {return ResearchGatherRouteR310.resolve(r,catalog:model.catalog,state:model.state) != nil}
        if let r=flow.pendingInvestigation {guard let c=model.catalog,let g=model.recipeGoals.first(where:{$0.recipeID==r.recipeID}) else{return false};return RecipeInvestigationRouteR158.contains(r,goal:g,catalog:c,state:model.state,sharedWorkEnabled:model.sharedPartyWorkR146Enabled)}
        if let target=flow.workTarget {if target.kind == .gather {return model.availableMaterials[destinationRegion]?.contains(target.targetID)==true};return model.state.completedEncounterIDs.contains(target.targetID)}
        return true
    }
    private func clearHandoffs(){flow.pendingRecipeGather=nil;flow.pendingInvestigation=nil;flow.pendingResearchGather=nil;flow.pendingEncounterAfterSwitch=nil}
    private func applySwitch() {
        guard !model.busy,!switching,switchAllowed else{return}
        guard model.engine != nil else {model.error="保存状態の準備ができていません。もう一度読み込んでください。";return}
        switching=true
        Task {defer {switching=false};do {
            if let route=flow.pendingRecipeGather {try await model.applyRecipeGatherHandoffR039(route)}
            else if let route=flow.pendingInvestigation {try await model.applyRecipeInvestigationHandoffR158(route)}
            else if let route=flow.pendingResearchGather {try await model.applyResearchGatherHandoffR310(route)}
            else if let engine=model.engine {
                model.busy=true;defer{model.busy=false}
                if destinationRegion != model.state.activeRegionID {_ = try await engine.dispatchConfirmingSavedReceipt(.startExpeditionAt(regionID:destinationRegion,now:Date()),operationID:UUID(),expectedRevision:model.state.revision);await model.refresh()}
                if let target=flow.workTarget {if model.sharedPartyWorkR146Enabled {_ = try await engine.setPartyWorkTargetR144(target,now:Date(),operationID:UUID(),expectedRevision:model.state.revision)}else if target.kind == .gather {_ = try await engine.dispatchConfirmingSavedReceipt(.setGatherTargetAt(resourceID:target.targetID,now:Date()),operationID:UUID(),expectedRevision:model.state.revision)};await model.refresh()}
                model.chosenRegion=destinationRegion
            }
            let encounterAfterSwitch=flow.pendingEncounterAfterSwitch
            clearHandoffs();flow.home(model,tab:"探索")
            if let encounterAfterSwitch {flow.enemyID=encounterAfterSwitch;flow.go(7)}
        }catch{model.error=model.commandErrorText(error);await model.refresh()}}
    }
}

struct UI48BackgroundArt: View {
    let id: String
    var body: some View {GeometryReader {g in if let image=ArtLibrary.image(id) {Image(uiImage:image).resizable().scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()}else{UI48Theme.background}}.accessibilityHidden(true)}
}
