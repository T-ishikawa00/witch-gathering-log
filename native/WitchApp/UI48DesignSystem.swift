import SwiftUI

/// Native translation of the approved 390 × 844 reference. No baked screen artwork.
enum UI48Theme {
    static let ink = Color(hex48: 0x081719)
    static let enamel = Color(hex48: 0x183d3a)
    static let raised = Color(hex48: 0x203633)
    static let gold = Color(hex48: 0xd1b473)
    static let muted = Color(hex48: 0xc6bda7)
    static let ivory = Color(hex48: 0xecdec3)
    static let paper = Color(hex48: 0xdfd2b2)
    static let paperInk = Color(hex48: 0x273a33)
    static let background = RadialGradient(colors: [Color(hex48: 0x203434), ink], center: .topTrailing, startRadius: 0, endRadius: 720)
    static func quality(_ id: String) -> Color {
        switch id { case "Q1": return Color(hex48: 0x7f9c6f); case "Q2": return Color(hex48: 0x7f99d2); case "Q3": return Color(hex48: 0xb691d1); case "Q4": return Color(hex48: 0xe6c368); default: return Color(hex48: 0x8c9485) }
    }
}
extension Color {
    init(hex48: UInt32) { self.init(red: Double((hex48 >> 16) & 255)/255, green: Double((hex48 >> 8) & 255)/255, blue: Double(hex48 & 255)/255) }
}

struct UI48Frame: Shape {
    var radius: CGFloat = 20
    func path(in r: CGRect) -> Path {
        let a = min(radius, min(r.width,r.height)/2), b: CGFloat = 4
        var p = Path(); p.move(to: CGPoint(x:r.minX+a,y:r.minY))
        p.addLine(to:CGPoint(x:r.maxX-b,y:r.minY));p.addQuadCurve(to:CGPoint(x:r.maxX,y:r.minY+b),control:CGPoint(x:r.maxX,y:r.minY))
        p.addLine(to:CGPoint(x:r.maxX,y:r.maxY-a));p.addQuadCurve(to:CGPoint(x:r.maxX-a,y:r.maxY),control:CGPoint(x:r.maxX,y:r.maxY))
        p.addLine(to:CGPoint(x:r.minX+b,y:r.maxY));p.addQuadCurve(to:CGPoint(x:r.minX,y:r.maxY-b),control:CGPoint(x:r.minX,y:r.maxY))
        p.addLine(to:CGPoint(x:r.minX,y:r.minY+a));p.addQuadCurve(to:CGPoint(x:r.minX+a,y:r.minY),control:CGPoint(x:r.minX,y:r.minY));p.closeSubpath();return p
    }
}

struct UI48ButtonStyle: ButtonStyle {
    var secondary = false
    var danger = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, weight:.semibold)).foregroundStyle(UI48Theme.ivory)
            .padding(.horizontal,14).padding(.vertical,secondary ? 9:12).frame(maxWidth:.infinity,minHeight:secondary ? 44:52)
            .background(LinearGradient(colors:danger ? [Color(hex48:0x614740),Color(hex48:0x382a27)] : secondary ? [UI48Theme.raised.opacity(0.45),UI48Theme.ink] : [Color(hex48:0x42615a),UI48Theme.enamel,Color(hex48:0x0b2528)],startPoint:.top,endPoint:.bottom))
            .clipShape(UI48Frame()).overlay(UI48Frame().stroke(UI48Theme.gold.opacity(secondary ? 0.5:1),lineWidth:1))
            .overlay(UI48Frame(radius:17).stroke(UI48Theme.gold.opacity(0.25),lineWidth:1).padding(3))
            .shadow(color:.black.opacity(0.2),radius:5,y:3).opacity(enabled ? (configuration.isPressed ? 0.72:1):0.45)
            .scaleEffect(configuration.isPressed ? 0.985:1)
    }
}

struct UI48Action: View {
    let title: String
    var symbol: String = "chevron.right"
    var secondary = false
    var danger = false
    var disabled = false
    var id = ""
    let action: () -> Void
    var body: some View {
        Button(action:action) { HStack(spacing:10) { Image(systemName:symbol).accessibilityHidden(true);Text(title).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity); if !secondary { Image(systemName:"chevron.right").font(.caption).accessibilityHidden(true) } } }
            .buttonStyle(UI48ButtonStyle(secondary:secondary,danger:danger)).disabled(disabled).accessibilityIdentifier(id)
    }
}

struct UI48Page<Content: View>: View {
    var paper = false
    var transparent = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:16,content:content).padding(18).frame(maxWidth:.infinity,alignment:.leading) }
            .background { if !transparent { if paper { UI48Theme.paper } else { UI48EnamelBackground() } } }
            .foregroundStyle(paper ? UI48Theme.paperInk:UI48Theme.ivory)
            .scrollDismissesKeyboard(.interactively)
    }
}

/// Keeps the explicit next action visible while the supporting details scroll.
struct UI48ActionDock<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 8, content: content)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(UI48Theme.ink.opacity(0.98))
            .overlay(alignment: .top) {
                Rectangle().fill(UI48Theme.gold.opacity(0.5)).frame(height: 1)
            }
            // The pinned action dock is navigation chrome; limit it to a generous
            // accessibility size so its buttons remain tappable without consuming
            // the entire viewport. Body content elsewhere keeps the user's full size.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

struct UI48EnamelBackground: View {
    var body: some View {
        UI48Theme.background.overlay {
            Canvas { context, size in
                for x in stride(from: 4.0, to: size.width, by: 8) {
                    for y in stride(from: 4.0, to: size.height, by: 8) {
                        context.fill(Path(ellipseIn: CGRect(x:x,y:y,width:0.8,height:0.8)),with:.color(UI48Theme.gold.opacity(0.07)))
                    }
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct UI48Tabs: View {
    let labels: [String]
    @Binding var selection: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing:3) {
                        ForEach(Array(labels.enumerated()),id:\.offset) { index, label in
                            tabButton(index:index,label:label,accessibility:true).id(index)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(selection,anchor:.center) }
                .onChange(of: selection) { _, selected in
                    withAnimation(.easeInOut(duration:0.18)) { proxy.scrollTo(selected,anchor:.center) }
                }
                .padding(3).background(UI48Theme.ink.opacity(0.6))
                .overlay(alignment:.bottom){Rectangle().fill(UI48Theme.gold.opacity(0.65)).frame(height:1)}
            }
        } else {
            HStack(spacing:3) {
                ForEach(Array(labels.enumerated()),id:\.offset) { index, label in
                    tabButton(index:index,label:label,accessibility:false)
                }
            }
            .padding(3).background(UI48Theme.ink.opacity(0.6))
            .overlay(alignment:.bottom){Rectangle().fill(UI48Theme.gold.opacity(0.65)).frame(height:1)}
        }
    }

    private func tabButton(index: Int, label: String, accessibility: Bool) -> some View {
        Button {selection=index} label: {
            Group {
                if accessibility {
                    Text(label).font(.subheadline.weight(selection==index ? .semibold:.regular))
                        .fixedSize(horizontal:true,vertical:false).lineLimit(1).padding(.horizontal,12).frame(minHeight:44)
                } else {
                    Text(label).font(.subheadline.weight(selection==index ? .semibold:.regular)).frame(maxWidth:.infinity,minHeight:44)
                }
            }
            .foregroundStyle(selection==index ? UI48Theme.ink:UI48Theme.gold)
            .background {if selection==index {LinearGradient(colors:[Color(hex48:0xcfb985),Color(hex48:0xb3925b)],startPoint:.top,endPoint:.bottom)}}
            .clipShape(UnevenRoundedRectangle(topLeadingRadius:6,topTrailingRadius:6))
        }.buttonStyle(.plain).accessibilityAddTraits(selection==index ? .isSelected:[])
    }
}

/// Keeps compact action pairs side-by-side at ordinary sizes and stacks them
/// at accessibility sizes, without changing child identity or their actions.
struct UI48ResponsiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content() }
    }
}

struct UI48Panel<Content: View>: View {
    var title: String? = nil
    var paper = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment:.leading,spacing:12) { if let title { Text(title).font(.system(.headline,design:.serif)).foregroundStyle(paper ? UI48Theme.paperInk:UI48Theme.gold) }; content() }
            .padding(15).frame(maxWidth:.infinity,alignment:.leading)
            .background(LinearGradient(colors:paper ? [Color(hex48:0xf5ebd2),Color(hex48:0xd1bd90)] : [UI48Theme.raised,UI48Theme.ink],startPoint:.topLeading,endPoint:.bottomTrailing))
            .clipShape(UI48Frame(radius:17)).overlay(UI48Frame(radius:17).stroke(UI48Theme.gold.opacity(0.6),lineWidth:1))
            .overlay(alignment:.topLeading){Image(systemName:"sparkle").font(.system(size:9)).foregroundStyle(UI48Theme.gold).offset(x:-3,y:-3).accessibilityHidden(true)}
    }
}

struct UI48Note: View {
    let text: String
    var warning = false
    var body: some View { HStack(alignment:.top,spacing:9) { Image(systemName:warning ? "exclamationmark.circle":"info.circle").foregroundStyle(UI48Theme.gold);Text(text).font(.footnote).fixedSize(horizontal:false,vertical:true) }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(UI48Theme.enamel.opacity(0.22)).overlay(alignment:.leading){Rectangle().fill(UI48Theme.gold).frame(width:2)} }
}

struct UI48Heading: View {
    let title: String
    var subtitle = ""
    var body: some View { VStack(alignment:.leading,spacing:8){Text(title).font(.system(.title2,design:.serif,weight:.semibold)).fixedSize(horizontal:false,vertical:true);if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(UI48Theme.muted).fixedSize(horizontal:false,vertical:true) }; HStack{Rectangle().fill(UI48Theme.gold.opacity(0.3)).frame(height:1);Image(systemName:"sparkle").font(.caption2).foregroundStyle(UI48Theme.gold).accessibilityHidden(true)} } }
}

struct UI48Goal: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var caption = "次の目標"
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Group {
                if textSize.isAccessibilitySize {
                    VStack(alignment:.leading,spacing:10) {
                        HStack(spacing:10) {
                            Image(systemName:"scroll").font(.system(size:22)).accessibilityHidden(true)
                            Text(caption).font(.caption2).fixedSize(horizontal:false,vertical:true)
                            Spacer(minLength:0)
                            Image(systemName:"chevron.right").font(.system(size:16)).accessibilityHidden(true)
                        }.foregroundStyle(Color(hex48:0x72643f))
                        Text(title).font(.headline).fixedSize(horizontal:false,vertical:true)
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .accessibilityIdentifier("ui48_goal_accessibility_title")
                        Text(detail).font(.caption).fixedSize(horizontal:false,vertical:true)
                    }
                } else {
                    HStack(spacing:12) {
                        Image(systemName:"scroll").font(.title2).foregroundStyle(Color(hex48:0x806431))
                        VStack(alignment:.leading,spacing:4) {
                            Text(caption).font(.caption2).foregroundStyle(Color(hex48:0x72643f))
                            Text(title).font(.headline)
                            Text(detail).font(.caption).fixedSize(horizontal:false,vertical:true)
                        }
                        Spacer(minLength:0)
                        Image(systemName:"chevron.right").font(.caption)
                    }
                }
            }.foregroundStyle(UI48Theme.paperInk).padding(15)
                .frame(maxWidth:.infinity,minHeight:72,alignment:.leading)
                .background(LinearGradient(colors:[Color(hex48:0xe1d0aa),Color(hex48:0xcbbb95)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .clipShape(UI48Frame(radius:15))
                .overlay(alignment:.leading){Rectangle().fill(Color(hex48:0x52694b)).frame(width:3).padding(.leading,7)}
        }.buttonStyle(.plain)
    }
}

struct UI48Hero: View {
    let assetID: String
    let title: String
    var subtitle = ""
    var body: some View { VStack(spacing:8) { ZStack { Circle().stroke(UI48Theme.gold.opacity(0.35),lineWidth:1).frame(width:150,height:150);Circle().stroke(UI48Theme.gold.opacity(0.15),lineWidth:1).frame(width:168,height:168);AssetIcon(id:assetID,size:140).accessibilityHidden(true) }.frame(maxWidth:.infinity,minHeight:170);Text(title).font(.system(.title2,design:.serif,weight:.semibold)).multilineTextAlignment(.center);if !subtitle.isEmpty {Text(subtitle).font(.footnote).multilineTextAlignment(.center).foregroundStyle(UI48Theme.muted)} }.frame(maxWidth:.infinity) }
}

struct UI48Item: View {
    let assetID: String
    var qualityID = "Q0"
    var count = ""
    var locked = false
    var size: CGFloat = 76
    var body: some View { ZStack(alignment:.topLeading) { UI48Frame(radius:12).fill(RadialGradient(colors:[UI48Theme.quality(qualityID).opacity(0.5),UI48Theme.ink],center:.center,startRadius:0,endRadius:size));AssetIcon(id:assetID,size:size*0.82).frame(width:size,height:size).accessibilityHidden(true);Text(GameText.quality(qualityID)).font(.system(size:10,weight:.semibold)).padding(5);if locked {Image(systemName:"lock").font(.system(size:10)).padding(5).frame(maxWidth:.infinity,alignment:.trailing)};if !count.isEmpty {Text(count).font(.system(size:11)).padding(3).background(UI48Theme.ink.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius:3)).padding(4).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottomTrailing)} }.frame(width:size,height:size).clipShape(UI48Frame(radius:12)).overlay(UI48Frame(radius:12).stroke(UI48Theme.quality(qualityID),lineWidth:1.2)).foregroundStyle(UI48Theme.ivory) }
}

struct UI48Portrait: View {
    let actorID: String
    var size: CGFloat = 44
    var body: some View {
        AssetIcon(id:(GameModel.spriteIDs[actorID] ?? "ERNA")+"__idle",size:size)
            .scaleEffect(2.35).offset(y:size*0.22)
            .frame(width:size,height:size).background(UI48Theme.raised)
            .clipShape(Circle()).overlay(Circle().stroke(UI48Theme.gold.opacity(0.7),lineWidth:1))
            .accessibilityHidden(true)
    }
}

struct UI48ActorStrip: View {
    @ObservedObject var model: GameModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:12) {
                    ForEach(model.state.partyActorIDs,id:\.self) { actor in
                        actorButton(actor,accessibility:true).padding(.horizontal,12).padding(.vertical,8)
                            .background(model.selectedActor==actor ? UI48Theme.raised : UI48Theme.ink.opacity(0.5))
                            .clipShape(UI48Frame(radius:12))
                            .overlay(UI48Frame(radius:12).stroke(UI48Theme.gold.opacity(model.selectedActor==actor ? 1:0.35),lineWidth:1))
                    }
                }
            }
        } else {
            HStack(spacing:8) {
                ForEach(model.state.partyActorIDs,id:\.self) { actor in actorButton(actor,accessibility:false).frame(maxWidth:.infinity) }
            }
        }
    }

    private func actorButton(_ actor: String, accessibility: Bool) -> some View {
        let maximumWidth: CGFloat? = accessibility ? nil : .infinity
        return Button {model.selectedActor=actor} label: {
            VStack(spacing:5) {
                UI48Portrait(actorID:actor,size:43).overlay(Circle().stroke(UI48Theme.gold,lineWidth:model.selectedActor==actor ? 2:0.6))
                Group {
                    if accessibility {
                        Text(GameModel.actorNames[actor] ?? actor).font(.caption2).lineLimit(1).fixedSize(horizontal:true,vertical:false)
                    } else {
                        Text(GameModel.actorNames[actor] ?? actor).font(.caption2).fixedSize(horizontal:false,vertical:true)
                    }
                }
            }
            .frame(maxWidth:maximumWidth,minHeight:64)
            .padding(.bottom,5)
            .overlay(alignment:.bottom){if model.selectedActor==actor {Rectangle().fill(UI48Theme.gold).frame(height:1)}}
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ui48_actor_"+actor)
        .accessibilityAddTraits(model.selectedActor==actor ? .isSelected:[])
    }
}

@MainActor final class UI48Flow: ObservableObject {
    @Published var path: [Int] = []
    @Published var gearID: UUID?
    @Published var enemyID: String?
    @Published var materialID: String?
    @Published var researchID: String?
    @Published var challengeID: String?
    @Published var appearanceID: String?
    @Published var targetID: String?
    @Published var search = ""
    @Published var resultGearIDs: [UUID] = []
    @Published var resultTitle = "完成しました"
    @Published var resultDetail = ""
    @Published var pendingCommand: GameCommand?
    @Published var pendingTitle = ""
    @Published var pendingDetail = ""
    @Published var craftPhase: WorkshopPresentationR1.Phase?
    @Published var acceptedCraftGoal: RecipeGoalProjectionR035.Goal?
    @Published var craftFailure: String?
    @Published var pendingRecipeGather: RecipeGatherHandoffR039?
    @Published var pendingInvestigation: RecipeInvestigationHandoffR158?
    @Published var pendingResearchGather: ResearchGatherHandoffR310?
    @Published var pendingEncounterAfterSwitch: String?
    @Published var regionID: String?
    @Published var workTarget: PartyWorkTargetR144?
    @Published var battleSummary: GatheringSummary?
    @Published var newRegionIDs: [String] = []
    var battleBefore: GameSnapshot?
    var screen: Int { path.last ?? 1 }
    func go(_ id: Int) { guard path.last != id else{return};if path.last == 37 {targetID=nil};path.append(id) }
    func back() { if path.last == 37 {targetID=nil}; if path.last == 12 { clearDestination() }; if !path.isEmpty {path.removeLast()} }
    func clearDestination() {pendingRecipeGather=nil;pendingInvestigation=nil;pendingResearchGather=nil;pendingEncounterAfterSwitch=nil;regionID=nil;workTarget=nil;materialID=nil}
    func home(_ model: GameModel, tab: String = "家") { path=[];targetID=nil;clearDestination();model.sheet=nil;model.tab=tab;model.syncScene() }
    func selectGear(_ id: UUID, screen: Int = 15) {gearID=id;go(screen)}
    func recipe(_ id: String, model: GameModel, gearID: UUID? = nil) {
        guard !model.busy else { return }
        craftPhase=nil;acceptedCraftGoal=nil;craftFailure=nil
        model.previewRecipeID=id;model.previewRecipeGearID=gearID;go(model.previewRecipeGoal?.ready == true ? 21:20)
    }
    /// Uses the existing durable engine, then opens results only after a saved snapshot is read.
    func commit(_ command: GameCommand, model: GameModel, title: String, resultScreen: Int? = 26) {
        guard !model.busy,let engine=model.engine else{return}
        let isCraft: Bool
        if case .craftRecipe(let recipeID) = command {
            isCraft=true
            acceptedCraftGoal=model.recipeGoals.first { $0.recipeID == recipeID }
            craftPhase = .processing;craftFailure=nil
        } else { isCraft=false }
        model.busy=true
        Task { let before=model.state
            do {
                let receipt=try await engine.dispatchConfirmingSavedReceipt(command,operationID:UUID(),expectedRevision:before.revision)
                await model.refresh()
                #if targetEnvironment(simulator)
                // Observation-only pause after a real saved command. Strict isolated QA
                // gate; never changes costs, grants, outcomes, or ordinary launch timing.
                let arguments=ProcessInfo.processInfo.arguments
                if isCraft, UI48QALaunchGate.isValid(arguments:arguments), arguments.contains("--ui48-craft-observe") {
                    try? await Task.sleep(for:.seconds(6))
                }
                #endif
                WitchAudioCoordinator.shared.playAfterSuccessfulCommand(command,result:receipt.result)
                resultGearIDs=model.state.gear.filter { item in
                    before.gear.first(where: { $0.id == item.id }) != item
                }.map(\.id)
                // Refinement rank is stored separately from the gear instance. Its result
                // must still show the exact UUID that the saved command modified.
                switch command {
                case .enhance(let id), .refine(let id), .promoteQuality(let id), .evolveGear(let id, _):
                    if model.state.gear.contains(where: { $0.id == id }), !resultGearIDs.contains(id) {
                        resultGearIDs.insert(id, at: 0)
                    }
                default: break
                }
                resultTitle=title;resultDetail="保存しました";model.notice=title;pendingCommand=nil
                if let resultScreen {go(resultScreen)}
                if isCraft {craftPhase = .completed}
            }
            catch {
                model.error=model.commandErrorText(error);await model.refresh()
                if isCraft {craftFailure=model.error;craftPhase = .failed}
            };model.busy=false
        }
    }
}
