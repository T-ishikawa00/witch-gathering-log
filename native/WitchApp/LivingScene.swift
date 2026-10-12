import SpriteKit
import UIKit

/// Original poses remain byte-identical. Runtime deformation fixes feet and is labelled partial in art ledger.
@MainActor final class LivingScene: SKScene {
    enum Place: Equatable { case home, field(String), portrait(String) }
    var place: Place = .home
    var cosmetics: [String:String] = [:]
    var furniture = Set<String>()
    private var figures: [String:SKSpriteNode] = [:]

    /// Shared recipient-excluded actor/equipment bounds for notice placement and QA readback.
    func pursuitNoticeObstacleNodes(excluding recipientID: String) -> [(String, SKNode)] {
        figures.keys.sorted()
            .filter { $0 != recipientID }
            .compactMap { actorID in figures[actorID].map { (actorID, $0 as SKNode) } }
            .flatMap { pair -> [(String, SKNode)] in
                let (actorID, body) = pair
                var result: [(String, SKNode)] = [(actorID, body)]
                for childName in ["luna_book", "weapon_attachment"] {
                    if let child = body.childNode(withName: childName) {
                        result.append((actorID + ":" + childName, child))
                    }
                }
                return result
            }
    }
    private var baseline: [String:CGPoint] = [:]
    private var baselineHeights:[String:CGFloat]=[:]
    private var partyShadows:[String:SKShapeNode]=[:]
    private var clock = 0.0
    private var last = 0.0
    private var poses: [String:(String,Double)] = [:]
    // Candidate-only: an authored party anticipate clip stays visible until its event root commits or is cancelled.
    private var partyCastHoldLifecycle = PartyCastHoldLifecycle()
    private var heldPartyPose = false
    private var holdingBattleResult = false
    private var frameAuditRequest:(actor:String,state:String,index:Int)?
    private var frameAuditHeld=false
    private var frameAuditRenderedFrames=0
    private var layeredHand:(CGPoint,CGFloat)?
    private var lunaBookHand:CGPoint?
    private var lunaBookFailureR010:LunaBookFailureInjectionR010?
    private var lunaBookObserverR010:LunaBookNativeObserverR010?
    private var hasLunaBook:Bool {LunaBookMotion.supportedGearIDs.contains(cosmetics["APPRENTICE_BOOK_GEAR"] ?? "")}
    private var hasSeparateWitchWeapon:Bool {cosmetics["C_WITCH"]=="ERNA_TRAVEL" || cosmetics["WITCH_WEAPON"] != nil}
    private var enemyIDs: [String] = []
    private var areaResolution:R015AreaSceneResolution?
    private var selectedGatherMaterialID:String?
    private var gatherNode:SKSpriteNode?
    private var gatherNodeMaterialID:String?
    private var gatherNodeAudit:[String:Any]=[:]
    private var groundedBattleEntryTargets: [String: CGPoint] = [:]
    private struct DragonEntryFootpathSessionR068R002 {
        let startRootScenePoint: CGPoint
        let homeRootScenePoint: CGPoint
        var actionElapsedSeconds: Double
    }
    private var dragonEntryFootpathSessionsR068R002: [String: DragonEntryFootpathSessionR068R002] = [:]
    private var battleEntryTrace: BattleEntryTraceQA?
    private var equipmentMotionTraceQA: EquipmentMotionTraceQA?
    private var equipmentMultiObserverR084: EquipmentMultiConsumerObserverR084?
    private var equipmentMultiShowcaseR084: EquipmentMultiConsumerShowcaseR084?
    var equipmentMultiActiveR084: Bool { equipmentMultiObserverR084 != nil }
    private var isolatedWalkCycleObserverR018: IsolatedWalkCycleObserverR018?
    private var syntheticDash2TailTraceR047: SyntheticDash2TailTraceR047?
    private var r047VideoSyncMarker: SKNode?
    private var r047VideoSyncMarkerSequence = 0
    private var ernaStaffMotionTraceQA_R040: ERNAStaffMotionTraceQA_R040?
    private var ernaStaffWalkCycleTraceQA_R002: ERNAStaffWalkCycleTraceQA_R002?
    private struct PendingERNAWalkCycleStart {
        let id: UUID
        let request: ERNAStaffWalkCycleRequestR002
        let outputDirectory: URL
        let requestedUptime: TimeInterval
        let onStatus: (String, [String: Any]) -> Void
        var stableGate = ERNAWalkCycleStableSceneGateR004()
    }
    private var pendingERNAWalkCycleStart: PendingERNAWalkCycleStart?
    private var preparedPartyCastRoots: [[String: String]] = []
    private var pendingFullBattleEquipmentMotionTrace: (request: EquipmentMotionTraceRequest, outputDirectory: URL, expectedPartyCastRoots: [[String: String]])?
    private var enemyLoopBoundaryTrace: EnemyLoopBoundaryTraceQA?
    private var enemyLoopBoundaryMotion: EnemyMotionController?
    private var pendingEnemyLoopBoundaryAction: (EnemyLoopBoundaryTraceQA.Action, EnemyMotionController)?
    private var dragonGaitR038SequenceQA: DragonGaitR038SequenceQA?
    private var dragonGaitR038SequenceMotion: EnemyMotionController?
    private var pendingDragonGaitR038SequenceAction: (DragonGaitR038SequenceQA.Action, EnemyMotionController)?
    private var gatherFrameTrace:GatherFrameTraceQA?
    private var gatherTraceRawDelta=0.0
    private var enemyPresentation: [String:CombatEntityPresentation] = [:]
    private var enemyMotions: [String:EnemyMotionController] = [:]
    private var renderBoundStateObserverR084: RenderBoundStateObserverR084?
    private var renderBoundStateMotionR084: EnemyMotionController?
    private var renderBoundStateCompletionR084: CheckedContinuation<String, Never>?
    private var renderBoundStateEventsR084: [RenderBoundStateObserverR084.Completion] = []
    private var renderBoundStateWatchdogR084: Task<Void, Never>?
    // Passive R058 observation only; never feeds an animation or gameplay decision.
    private var mothPassiveObserverR058: MothPassiveRenderObserverR058?
    private var hp: [String:Int] = [:]
    private var maxHP: [String:Int] = [:]
    private var hpBars: [String:SKShapeNode] = [:]
    private var hpTracks: [String:SKShapeNode] = [:]
    private var readingHands:SKCropNode?
    private let textureCache = CostBoundedCache<String, SKTexture>(maximumCost: 64 * 1024 * 1024, maximumEntryCount: 128)
    var frames = 0
    var maxFrameDelta = 0.0
    var artAudit:[String:Bool] = [:]
    private let frameStallTelemetry = FrameStallTelemetry.shared
    private var registeredRenderPreparationQA: [String: Any]?
    private var sceneGeneration = 0
    private var currentArtTelemetryContext = FrameStallTelemetry.Context(phase: "home", actorID: nil, state: nil, source: "scene")
    private var previousFrameTelemetryContext = FrameStallTelemetry.Context(phase: "home", actorID: nil, state: nil, source: "scene")
    private var effectCounts:[String:Int]=[:]
    private var effectLast:[String:Any]=[:]
    private var peakCombatEffects=0
    private var peakEnvironmentEffects=0
    private let effectCues=EffectCueCoordinator()
    private var pursuitNoticeRenderObserverR092: PursuitNoticeRenderObserverR092?
    private var environmentCycle = -1
    private let r04EnvironmentPolicy = R04TelegraphEnvironmentPolicy()
    private var r04WeatherPolicyQACache: [String: Any]?
    var damageNumberDivisor = 1
    static let names = ["ERNA","LUNA","AIRA","NOIR"]
    override func didMove(to view: SKView) { backgroundColor = UIColor(red:0.04,green:0.07,blue:0.10,alpha:1); rebuild() }
    override func didChangeSize(_ oldSize: CGSize) { if view != nil { rebuild() } }
    override func willMove(from view:SKView) {
        abortRenderBoundStateObserverR084(reason: "SCENE_REMOVED")
        abortFullBattleTrace(reason: "SCENE_REMOVED")
        isolatedWalkCycleObserverR018?.abort(reason: "SCENE_REMOVED")
        isolatedWalkCycleObserverR018 = nil
        abortDragonGaitR038Sequence(reason: "SCENE_REMOVED")
        partyCastHoldLifecycle.clearAll()
        _ = finishSyntheticDash2TailR047(observedMilliseconds: 0, sceneActive: false, cancelled: true)
        super.willMove(from:view)
    }
    @discardableResult func beginEquipmentMultiR084(request: EquipmentMultiConsumerRequestR084, outputDirectory: URL) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"), view != nil,
              equipmentMultiObserverR084 == nil, Self.names.allSatisfy({ figures[$0] != nil }) else { return false }
        equipmentMultiObserverR084 = EquipmentMultiConsumerObserverR084(request: request, scene: self, outputDirectory: outputDirectory)
        if request.evidenceMode == "forced_render_showcase" {
            var showcase = EquipmentMultiConsumerShowcaseR084(minimumRenderedFramesPerPhase: 90, maximumRenderedFramesPerPhase: 360)
            let first = showcase.start(); equipmentMultiShowcaseR084 = showcase
            if case .applyPose(let state) = first { auditPartyState(state) }
        }
        return true
    }
    func finishEquipmentMultiR084(reason: String) {
        guard let observer = equipmentMultiObserverR084 else { return }
        _ = observer.finish(sceneFrame: frames, sceneTime: last, reason: reason)
        equipmentMultiObserverR084 = nil; equipmentMultiShowcaseR084 = nil
    }
    private func sampleEquipmentMultiR084() {
        guard let observer = equipmentMultiObserverR084 else { return }
        let states = Dictionary(uniqueKeysWithValues: Self.names.map { actor in
            (actor, figures[actor]?.action(forKey: "party_walk_clip") != nil ? "walk" : poses[actor]?.0 ?? "idle")
        })
        observer.sample(scene: self, sceneFrame: frames, sceneTime: last, bodiesBySpriteID: figures, stateBySpriteID: states)
        if var showcase = equipmentMultiShowcaseR084 {
            let step = showcase.didRender(sceneFrame: frames, actualStateBySprite: states)
            equipmentMultiShowcaseR084 = showcase
            switch step {
            case .applyPose(let phase):
                // Apply on the next action evaluation, after the sampled marker
                // and body have been rendered together for this frame.
                run(.run { [weak self] in self?.auditPartyState(phase) })
            case .finished: finishEquipmentMultiR084(reason: "COMPLETED")
            case .incomplete(let reason): finishEquipmentMultiR084(reason: reason)
            case nil: break
            }
        }
    }
    private func abortFullBattleTrace(reason: String) {
        finishEquipmentMultiR084(reason: reason)
        if equipmentMotionTraceQA?.capturesFullBattle == true {
            equipmentMotionTraceQA?.abort(reason: reason, sceneGeneration: sceneGeneration)
            equipmentMotionTraceQA = nil
        }
        if let pending = pendingFullBattleEquipmentMotionTrace {
            let abandoned = EquipmentMotionTraceQA(scene: self, body: figures[EquipmentMotionTraceRequest.actorID],
                                                  request: pending.request, outputDirectory: pending.outputDirectory,
                                                  sceneGeneration: sceneGeneration)
            abandoned.setExpectedPartyCastRoots(pending.expectedPartyCastRoots)
            abandoned.abort(reason: reason + "_BEFORE_BATTLE", sceneGeneration: sceneGeneration)
            pendingFullBattleEquipmentMotionTrace = nil
        }
        ernaStaffMotionTraceQA_R040?.abort(reason: reason, sceneGeneration: sceneGeneration)
        ernaStaffMotionTraceQA_R040 = nil
    }
    func texture(_ id:String) -> SKTexture? {
        if AreaFlowQAHook.shouldFailFullFrameDecode(id: id) {
            AreaFlowQAHook.recordDecodeFailureBranch("fullframe_decode_branch", variantID: id)
            return nil
        }
        if let t=textureCache.value(forKey:id) { return t }
        if let img=ArtLibrary.image(id){let t=SKTexture(image:img);t.filteringMode = .linear;textureCache.insert(t,forKey:id,cost:estimatedRGBA8Cost(img));return t}
        return nil
    }
    private func estimatedRGBA8Cost(_ image:UIImage)->Int {
        guard let cgImage=image.cgImage else{return 0}
        let width=cgImage.width,height=cgImage.height
        guard width>0,height>0,width<=Int.max/height else{return 0}
        let pixels=width*height
        guard pixels<=Int.max/4 else{return 0}
        return pixels*4
    }
    func configure(place:Place,areaResolution:R015AreaSceneResolution?=nil,selectedGatherMaterialID:String?=nil,cosmetics:[String:String],furniture:Set<String>) {
        let areaChanged = self.areaResolution != areaResolution
        let gatherChanged = self.selectedGatherMaterialID != selectedGatherMaterialID
        if self.areaResolution?.selectionBasis == .activeFightEnemy,
           areaResolution?.selectionBasis != .activeFightEnemy {
            enemyIDs.removeAll();enemyPresentation.removeAll();hp.removeAll();maxHP.removeAll()
        }
        if self.place != place || areaChanged || gatherChanged || self.cosmetics != cosmetics || self.furniture != furniture {
            if self.place != place,case .field=place {enemyIDs.removeAll();enemyPresentation.removeAll();hp.removeAll();maxHP.removeAll()}
            self.place=place
            self.areaResolution=areaResolution
            self.selectedGatherMaterialID=selectedGatherMaterialID
            if frameStallTelemetry.enabled {
                currentArtTelemetryContext = FrameStallTelemetry.Context(phase: telemetryPhase(place), actorID: nil, state: nil, source: "scene.configure")
                frameStallTelemetry.setContext(currentArtTelemetryContext)
            }
            self.cosmetics=cosmetics;self.furniture=furniture; rebuild()
        }
    }
    private func image(_ id:String,_ height:CGFloat,_ point:CGPoint,_ depth:CGFloat)->SKSpriteNode? {
        guard let t=texture(id) else{return nil}; let n=SKSpriteNode(texture:t);n.size=CGSize(width:height*t.size().width/max(1,t.size().height),height:height);n.position=point;n.zPosition=depth;addChild(n);return n
    }
    private func rebuild(preservingPendingFullBattleTrace: Bool = false) {
        abortRenderBoundStateObserverR084(reason: "SCENE_REBUILT")
        for motion in enemyMotions.values { motion.restoreNormalEntryFootpathR068R002() }
        dragonEntryFootpathSessionsR068R002.removeAll()
        guard size.width>0,size.height>0 else{return}
        abortDragonGaitR038Sequence(reason: "SCENE_REBUILT")
        if equipmentMotionTraceQA?.capturesFullBattle == true {
            equipmentMotionTraceQA?.abort(reason: "SCENE_REBUILT", sceneGeneration: sceneGeneration)
            equipmentMotionTraceQA = nil
        }
        if ernaStaffMotionTraceQA_R040 != nil {
            abortFullBattleTrace(reason: "SCENE_REBUILT")
        }
        if let trace = ernaStaffWalkCycleTraceQA_R002 {
            trace.abort(reason: "SCENE_REBUILT", currentGeneration: sceneGeneration)
            ernaStaffWalkCycleTraceQA_R002 = nil
            heldPartyPose = false
        }
        if !preservingPendingFullBattleTrace, pendingFullBattleEquipmentMotionTrace != nil {
            abortFullBattleTrace(reason: "SCENE_REBUILT")
        }
        finishEquipmentMultiR084(reason: "SCENE_REBUILT")
        preparedPartyCastRoots.removeAll()
        sceneGeneration &+= 1; _ = finishSyntheticDash2TailR047(observedMilliseconds: 0, sceneActive: false, reason: "SCENE_REBUILT"); r047VideoSyncMarker?.removeFromParent(); r047VideoSyncMarker=nil; r047VideoSyncMarkerSequence=0; partyCastHoldLifecycle.clearAll(); groundedBattleEntryTargets.removeAll(); holdingBattleResult=false; registeredRenderPreparationQA = nil; removeAllChildren();environmentCycle = -1;r04EnvironmentPolicy.reset();r04WeatherPolicyQACache=nil;readingHands=nil;layeredHand=nil;lunaBookHand=nil;gatherNode=nil;gatherNodeMaterialID=nil;gatherNodeAudit=[:];figures.removeAll();baseline.removeAll();baselineHeights.removeAll();partyShadows.removeAll();poses.removeAll();enemyMotions.removeAll();hpBars.removeAll();hpTracks.removeAll()
        for key in Array(artAudit.keys) where key.hasPrefix("background_") || key.hasPrefix("gather_node_") { artAudit.removeValue(forKey: key) }
        var bgID:String
        switch place {
        case .home,.portrait:bgID="HOME_BASE"
        case .field(let id):
            let boss=enemyIDs.contains{$0.hasPrefix("ACT_B_"+id+"_")}
            bgID="BG_\(id)_"+(boss ? "BOSS":"FIELD")
        }
        var resolvedBackground=areaResolution
        if let resolution=resolvedBackground { bgID=resolution.renderedBackgroundID }
        var preparedVariantTexture:SKTexture?
        var preparedLayers:[(UIImage,CGFloat)]?

        func layerSpecs(for id:String)->[[String:Any]] {
            let entry=ArtLibrary.index[id] ?? [:]
            var specs=entry["sceneLayers"] as? [[String:Any]] ?? []
            if specs.isEmpty, id=="BG_R01_FIELD" {
                specs=["far.png","back.png","playfield.png","floor_foliage_under_actors.png","frame_foliage_over_actors.png"].enumerated().map { i,file in
                    ["path":"Backgrounds/BG_R01_FIELD/\(file)","z":i==4 ? 12:-20+i]
                }
            } else if specs.isEmpty, let paths=entry["layers"] as? [String] {
                specs=paths.enumerated().map { ["path":$0.element,"z":$0.element.contains("foreground") ? 12:-20+$0.offset] }
            }
            return specs
        }
        func decodeLayers(_ specs:[[String:Any]], variantID: String? = nil)->[(UIImage,CGFloat)]? {
            if let variantID, AreaFlowQAHook.shouldFailLayerDecode(variantID: variantID) {
                AreaFlowQAHook.recordDecodeFailureBranch("layer_decode_branch", variantID: variantID)
                return nil
            }
            guard !specs.isEmpty else { return nil }
            var result:[(UIImage,CGFloat)]=[]
            for spec in specs {
                guard let path=spec["path"] as? String,
                      let img=UIImage(contentsOfFile:ArtLibrary.root.appendingPathComponent(path).path) else { return nil }
                result.append((img,CGFloat((spec["z"] as? NSNumber)?.doubleValue ?? -20)))
            }
            return result
        }
        if let resolution=resolvedBackground {
            switch resolution.backgroundMode {
            case .fullFrameVariantReplacement:
                preparedVariantTexture=texture(resolution.renderedBackgroundID)
                if preparedVariantTexture == nil {
                    resolvedBackground=resolution.fallingBackToBase(reason:"variant_image_decode_failed:"+resolution.renderedBackgroundID)
                }
            case .layeredVariantReplacement:
                preparedLayers=decodeLayers(layerSpecs(for:resolution.renderedBackgroundID), variantID: resolution.renderedBackgroundID)
                if preparedLayers == nil {
                    resolvedBackground=resolution.fallingBackToBase(reason:"variant_layers_decode_failed:"+resolution.renderedBackgroundID)
                }
            case .regionBase:
                break
            }
        }
        if let resolvedBackground { areaResolution=resolvedBackground; bgID=resolvedBackground.renderedBackgroundID }
        if (resolvedBackground == nil || resolvedBackground?.backgroundMode == .regionBase),
           preparedVariantTexture == nil, preparedLayers == nil {
            preparedLayers=decodeLayers(layerSpecs(for:bgID))
        }
        var backgroundLoaded=false
        if let loadedLayers=preparedLayers {
            for (img,z) in loadedLayers {
                let n=SKSpriteNode(texture:SKTexture(image:img));let k=max(size.width/img.size.width,size.height/img.size.height)
                n.size=CGSize(width:img.size.width*k,height:img.size.height*k);n.position=CGPoint(x:size.width/2,y:size.height/2)
                n.zPosition=z;addChild(n)
            }
            backgroundLoaded=true
        } else if let t=preparedVariantTexture ?? texture(bgID) {
            let n=SKSpriteNode(texture:t);let scale=max(size.width/t.size().width,size.height/t.size().height)
            n.size=CGSize(width:t.size().width*scale,height:t.size().height*scale);n.position=CGPoint(x:size.width/2,y:size.height/2);n.zPosition = -20;addChild(n);backgroundLoaded=true
        }
        artAudit["background_"+bgID]=backgroundLoaded
        gatherNodeAudit=["state":"not_selected","loaded":false]
        if case .field(let regionID)=place, let materialID=selectedGatherMaterialID {
            if let nodeID=R016GatherNodePresentation.nodeID(for:materialID) {
                let presentID=nodeID+"__present"
                let auditKey="gather_node_"+nodeID
                if let projection=R016GatherNodePresentation.projection(materialID:materialID,regionID:regionID,resolution:areaResolution),
                   let presentTexture=texture(R016GatherNodePresentation.imageID(for:projection)) {
                    let textureSize=presentTexture.size()
                    if textureSize.width>0,textureSize.height>0 {
                        let node=SKSpriteNode(texture:presentTexture)
                        node.name="gather_node:"+projection.materialID
                        node.anchorPoint=CGPoint(x:0.5,y:0.08)
                        let nodeHeight=size.width*R016GatherNodePresentation.displayHeightMultiplier
                        node.size=CGSize(width:nodeHeight*textureSize.width/textureSize.height,height:nodeHeight)
                        node.position=CGPoint(x:size.width*R016GatherNodePresentation.normalizedGroundPoint.x,y:size.height*R016GatherNodePresentation.normalizedGroundPoint.y)
                        node.zPosition=9-node.position.y/size.height
                        addChild(node)
                        GatherNodePresentation.installContactShadow(on:node,materialID:projection.materialID)
                        gatherNode=node;gatherNodeMaterialID=projection.materialID
                        artAudit[auditKey]=true
                        gatherNodeAudit=["materialID":materialID,"nodeID":nodeID,"regionID":regionID,
                                         "state":"present","textureID":presentID,"loaded":true,"transition":"initial"]
                    } else {
                        artAudit[auditKey]=false
                        gatherNodeAudit=["materialID":materialID,"nodeID":nodeID,"regionID":regionID,
                                         "state":"present","textureID":presentID,"loaded":false,"transition":"invalid_texture_size"]
                    }
                } else {
                    artAudit[auditKey]=false
                    gatherNodeAudit=["materialID":materialID,"nodeID":nodeID,"regionID":regionID,
                                     "state":"present","textureID":presentID,"loaded":false,"transition":"missing_projection_or_texture"]
                }
            } else {
                gatherNodeAudit=["materialID":materialID,"regionID":regionID,"state":"unsupported","loaded":false]
            }
        }
        let isHome:Bool;switch place{case .home:isHome=true;default:isHome=false}
        let compact=size.height/size.width<1.45
        let coords:[CGPoint] = isHome ? [.init(x:0.32,y:0.46),.init(x:0.66,y:0.60),.init(x:0.79,y:0.45),.init(x:0.19,y:0.43)] : (compact ? [.init(x:0.14,y:0.65),.init(x:0.31,y:0.56),.init(x:0.44,y:0.66),.init(x:0.55,y:0.56)]:[.init(x:0.14,y:0.54),.init(x:0.30,y:0.42),.init(x:0.44,y:0.55),.init(x:0.53,y:0.43)])
        for (i,id) in Self.names.enumerated(){
            if case .portrait(let focus)=place, focus != id {continue}
            let h:CGFloat;let p:CGPoint
            if case .portrait=place{let layered=id=="ERNA" && hasSeparateWitchWeapon;h=size.height*(layered ? 0.52:0.62);p=CGPoint(x:size.width*(layered ? 0.43:0.5),y:size.height*0.30)}else{h=(id=="NOIR" ? 72:(!isHome && compact ? 102:133))*size.width/402;p=CGPoint(x:size.width*coords[i].x,y:size.height*coords[i].y)}
            let shadow=SKShapeNode(ellipseOf:CGSize(width:h*0.34,height:7));shadow.fillColor = .black.withAlphaComponent(0.25);shadow.strokeColor = .clear;shadow.position=p;shadow.zPosition=10-p.y/size.height;addChild(shadow)
            let reading=isHome && id=="LUNA" && FurniturePresentationR094.hasBotanicalDesk(furniture)
            var position=reading ? CGPoint(x:size.width*0.65,y:size.height*(compact ? 0.54:0.48)):(isHome && id=="AIRA" && FurniturePresentationR094.hasBotanicalDesk(furniture) ? CGPoint(x:size.width*0.83,y:size.height*0.65):p)
            if id=="ERNA",case .field=place {position.x=max(position.x,size.width*(cosmetics["C_WITCH"]=="ERNA_TRAVEL" ? 0.22:0.18))}
            if id=="AIRA",case .field=place,compact,
               areaResolution?.selectedSceneID=="SCN_A_R03_02",
               areaResolution?.backgroundMode == .fullFrameVariantReplacement {
                // This compact crop puts the ordinary rear-row smith over the
                // canyon. Use the open foreground stone floor in this scene.
                position=CGPoint(x:size.width*0.32,y:size.height*0.33)
                artAudit["grounding_AIRA_R03_02_compact_candidate"]=true
            }
            // R086 local composition candidate. The wide R04 dragon already
            // reaches the right viewport edge. Give NOIR a clear foreground
            // pocket for this encounter without shrinking or moving the dragon.
            if id == "NOIR", case .field = place, enemyIDs.count == 1,
               let opponent = enemyIDs.first,
               actorKey(enemyPresentation[opponent]?.assetKey ?? enemyPresentation[opponent]?.catalogID ?? opponent) == "ACT_B_R04_B" {
                position = CGPoint(x: size.width * (compact ? 0.48 : 0.47),
                                   y: size.height * (compact ? 0.48 : 0.37))
                shadow.zPosition = 10 - position.y / size.height
                artAudit["noir_dragon_spacing_r086_candidate"] = true
            }
            if case .field = place, let grounded = BattleGroundingLayoutCandidateR090.point(actorID: id, backgroundID: bgID, size: size) {
                position = grounded
                if id == "ERNA", cosmetics["C_WITCH"] == "ERNA_TRAVEL" { position.x = max(position.x, size.width * 0.22) }
                shadow.zPosition = 10 - position.y / size.height
                artAudit["grounding_" + id + "_R04_BOSS_r090_candidate"] = true
            }
            shadow.position=position;partyShadows[id]=shadow
            if let n=image(reading ? "LUNA_READING__0":appearance(id,"idle"),h,position,11-position.y/size.height){
                n.anchorPoint=CGPoint(x:0.5,y:0.04);figures[id]=n;baseline[id]=position;baselineHeights[id]=h
                if id=="ERNA" && hasSeparateWitchWeapon { attachStaff(to:n);syncWeapon(n,state:"idle") }
                if reading {bindEquipmentFrame(id,state:"reading",on:n);ActorBodyFrame.record("LUNA_READING__0",on:n);attachReadingHands(n)}else{pose(id,"idle")}
            }
        }
        if isHome && FurniturePresentationR094.hasBotanicalDesk(furniture) {
            _=image("FURN_DESK_BOTANICAL",size.width*0.39,CGPoint(x:size.width*0.65,y:size.height*(compact ? 0.55:0.49)),11.1)
        }
        if case .field=place {for (index,id) in enemyIDs.enumerated(){addEnemy(id,index:index)}}
        environmentCycle = -1
        if case .field(let region)=place {updateEnvironment(region:region)}else{ambient()}
    }
    private func attachReadingHands(_ body:SKSpriteNode){
        let hands=SKCropNode();hands.position=body.position;hands.zPosition=11.2
        let drawing=SKSpriteNode(texture:body.texture);drawing.size=body.size;drawing.anchorPoint=body.anchorPoint;hands.addChild(drawing)
        let mask=SKNode()
        for p in [CGPoint(x:0.39,y:0.39),CGPoint(x:0.60,y:0.39)] {
            let palm=SKShapeNode(ellipseOf:CGSize(width:body.size.width*0.19,height:body.size.height*0.20));palm.fillColor = .white;palm.strokeColor = .clear;palm.position=CGPoint(x:(p.x-0.5)*body.size.width,y:(p.y-0.04)*body.size.height);mask.addChild(palm)
        }
        hands.maskNode=mask;readingHands=hands;addChild(hands)
    }
    func setEnemy(_ id:String){setEnemies([id])}
    func setEnemies(_ ids:[String]){enemyPresentation.removeAll();enemyIDs=ids.map{actorKey($0)};hp.removeAll();maxHP.removeAll();resolveAreaFromActualEnemies();if case .field=place {rebuild()}}
    func prepareCombatEntities(_ battle:CombatResult){
        let actual=Set(battle.initialEnemyHP.keys.map{actorKey($0)})
        enemyIDs=enemyIDs.filter{actual.contains($0)}+actual.subtracting(enemyIDs).sorted()
        enemyPresentation=Dictionary(uniqueKeysWithValues:battle.entityPresentation.map{(actorKey($0.key),$0.value)})
        resolveAreaFromActualEnemies()
        if case .field=place {rebuild(preservingPendingFullBattleTrace: true)}
    }
    private func resolveAreaFromActualEnemies() {
        guard case .field(let regionID)=place else { return }
        let enemyID = enemyIDs.compactMap { displayID -> String? in
            let raw = enemyPresentation[displayID]?.catalogID ?? displayID
            return R015AreaSceneRouting.catalogEnemyID(fromRuntimeID:raw)
        }.first { id in R015AreaSceneRouting.routes.contains { $0.regionID == regionID && $0.enemyIDs.contains(id) } }
        guard let enemyID else { return }
        var availability=R015AreaSceneRouting.variantAvailability(index:ArtLibrary.index,artRoot:ArtLibrary.root)
        if let missing=AreaFlowQAHook.availabilityOverrideVariantID {
            availability = .init(fullFrameIDs: availability.fullFrameIDs.subtracting([missing]),
                                 layeredIDs: availability.layeredIDs.subtracting([missing]))
        }
        areaResolution=R015AreaSceneRouting.resolve(regionID:regionID,activeFightEnemyID:enemyID,
                                                     availableVariantIDs:availability.fullFrameIDs.union(availability.layeredIDs),
                                                     layeredVariantIDs:availability.layeredIDs)
    }
    func prepareCombatEffects(_ events:[CombatEvent], remainingPartyHP:[String:Int] = [:]) {
        let displayID: (String) -> String = { raw in
            self.actorKey(GameModel.spriteIDs[raw] ?? raw)
        }
        let holdEvents = events.map { event in
            let target = event.kind == "cast_start" ? event.targetID : displayID(event.targetID)
            return PartyCastHoldLifecycle.Event(kind:event.kind, sourceID:displayID(event.sourceID), targetID:target,
                                         rootActionID:event.rootActionID)
        }
        let defeated = Set(remainingPartyHP.compactMap { entry in entry.value <= 0 ? displayID(entry.key) : nil })
        partyCastHoldLifecycle = PartyCastHoldLifecycle(events:holdEvents, partyActorIDs:Set(Self.names), defeatedPartyActorIDs:defeated)
        let castRoots = events.compactMap { event -> [String: String]? in
            guard event.kind == "cast_start" else { return nil }
            let actor = displayID(event.sourceID)
            guard Self.names.contains(actor), let root = event.rootActionID, !root.isEmpty else { return nil }
            let castRoot = PartyCastHoldLifecycle.CastRoot(actorID: actor, rootActionID: root)
            guard case .commit(let terminalKind) = partyCastHoldLifecycle.plannedTerminals[castRoot] else { return nil }
            return ["actorID": actor, "rootActionID": root, "eventKind": event.kind,
                    "actionID": event.targetID, "terminalKind": terminalKind]
        }
        preparedPartyCastRoots = castRoots
        if let pending = pendingFullBattleEquipmentMotionTrace {
            pendingFullBattleEquipmentMotionTrace = (pending.request, pending.outputDirectory, castRoots)
        }
        equipmentMotionTraceQA?.setExpectedPartyCastRoots(castRoots)
        effectCues.prepare(events:events,sourceArtID:{[weak self] raw in self?.effectActorID(raw) ?? self?.actorKey(raw) ?? raw})
    }
    func cancelPendingPartyCasts() {
        partyCastHoldLifecycle.clearAll()
        preparedPartyCastRoots.removeAll()
        abortFullBattleTrace(reason: "BATTLE_CANCELLED")
    }
    private func addEnemy(_ id:String,index:Int){
        let count=enemyIDs.count
        let p=CGPoint(x:size.width*(count==1 ? 0.74:count>3 ? [0.70,0.87,0.70,0.87,0.70][index%5]:[0.72,0.82,0.72][index%3]),y:size.height*(count==1 ? 0.51:count>3 ? [0.70,0.59,0.48,0.37,0.26][index%5]:[0.60,0.45,0.32][index%3]))
        let meta=enemyPresentation[id]
        if meta?.kind=="prop" {
            // Dedicated authored flame/off frames; candidate ownership remains separate from art approval.
            if let n=image("PROP_LAMP__0",size.width*0.22,p,10-p.y/size.height){n.name=id;n.anchorPoint=CGPoint(x:0.5,y:0.0625);figures[id]=n;baseline[id]=p;let frames=[texture("PROP_LAMP__0"),texture("PROP_LAMP__1")].compactMap{$0};if !frames.isEmpty{n.run(.repeatForever(.animate(with:frames,timePerFrame:0.35)),withKey:"lamp_idle")};entityLabel(meta?.label ?? "灯瓶",above:n)}else{artAudit["load_"+id]=false}
            return
        }
        let artID=actorKey(meta?.assetKey ?? meta?.catalogID ?? id)
        do{let m=try EnemyMotionController(actorID:artID,artRoot:ArtLibrary.root);let n=m.node;let h=min(size.width*(count>3 ? 0.19:artID.hasPrefix("ACT_B_") ? 0.36:0.25),size.width*(count==1 ? 0.46:count>3 ? 0.23:0.31)/m.intrinsicAspectRatio);m.fit(height:h)
            // R085 local presentation candidate: this wolf source faces right,
            // while enemies occupy the right side and attack the party to the left.
            // Mirror the complete node so child/effect coordinates follow the body.
            if artID == "ACT_E_R04_01" {
                n.xScale = -abs(n.xScale)
                artAudit["wolf_left_facing_r085_candidate"] = true
            }
            n.position=p;n.zPosition=10-p.y/size.height;addChild(n);figures[id]=n;baseline[id]=p;enemyMotions[id]=m;_ = m.play(.idle);if id != artID {entityLabel(meta?.label ?? "増援",above:n)}}catch{artAudit["load_"+id]=false}
    }
    private func entityLabel(_ text:String,above node:SKSpriteNode){let label=SKLabelNode(fontNamed:"HiraginoSans-W6");label.text=text;label.fontSize=10;label.fontColor = .white;label.position=CGPoint(x:node.position.x,y:node.frame.maxY+12);label.zPosition=26;addChild(label)}

    /// Opt-in art QA request. The first active row is sampled by didFinishUpdate
    /// after SpriteKit evaluates the action; completion is emitted by the
    /// action's existing completion closure and joined to that same generation.
    func runRenderBoundStateRequestR084(requestID: String, actorID: String, state: EnemyMotionState,
                                       expectedSettledState: String, looping: Bool,
                                       expectedR064WalkBackend: Bool) async -> String {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              ProcessInfo.processInfo.arguments.contains("--qa-render-bound-enemy-state-r084"),
              renderBoundStateObserverR084 == nil,
              let motion = enemyMotions[actorID] else { return "INCOMPLETE_R084_PRECONDITION" }
        let observer = RenderBoundStateObserverR084(
            requestID: requestID, actorID: actorID, requestedState: state.rawValue,
            expectedSettledState: expectedSettledState, looping: looping,
            expectedR064WalkBackend: expectedR064WalkBackend,
            expectedR064SourceSHA256: expectedR064WalkBackend ? DragonFourLegStanceMountR064.sourceSHA256 : nil)
        return await withCheckedContinuation { continuation in
            renderBoundStateObserverR084 = observer
            renderBoundStateMotionR084 = motion
            renderBoundStateCompletionR084 = continuation
            renderBoundStateEventsR084.removeAll(keepingCapacity: true)
            motion.qaRenderBoundActionCompleted = { [weak self] completed in
                guard let self else { return }
                self.renderBoundStateEventsR084.append(.init(state: completed.rawValue,
                                                             renderGeneration: self.frames))
            }
            renderBoundStateWatchdogR084 = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(35)) } catch { return }
                guard let self,
                      self.renderBoundStateObserverR084?.requestID == requestID else { return }
                self.finishRenderBoundStateObserverR084(status: "INCOMPLETE", reason: "UPDATE_TIMEOUT")
            }
            artAudit[actorID + ":" + state.rawValue] = motion.play(state, restart: true)
            if artAudit[actorID + ":" + state.rawValue] != true {
                finishRenderBoundStateObserverR084(status: "INCOMPLETE", reason: "ACTION_REJECTED")
            }
        }
    }

    private func sampleRenderBoundStateObserverR084() {
        guard let observer = renderBoundStateObserverR084,
              let motion = renderBoundStateMotionR084 else { return }
        let events = renderBoundStateEventsR084.filter { $0.renderGeneration == frames }
        renderBoundStateEventsR084.removeAll(keepingCapacity: true)
        let root = [Double(motion.node.position.x), Double(motion.node.position.y)]
        let done = observer.sample(presentation: motion.presentationSnapshot,
                                   sceneFrame: frames, sceneTime: last,
                                   root: root, completionThisGeneration: events)
        if done {
            finishRenderBoundStateObserverR084(
                status: observer.settled ? "SETTLED_RENDER_READBACK" : "INCOMPLETE",
                reason: observer.settled ? "THREE_STABLE_RENDER_ROWS" : "ROW_LIMIT_OR_TIMEOUT")
        }
    }

    private func finishRenderBoundStateObserverR084(status: String, reason: String) {
        guard let observer = renderBoundStateObserverR084,
              let continuation = renderBoundStateCompletionR084 else { return }
        renderBoundStateMotionR084?.qaRenderBoundActionCompleted = nil
        renderBoundStateWatchdogR084?.cancel()
        renderBoundStateWatchdogR084 = nil
        let payload = observer.json(status: status, finishReason: reason)
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{\"status\":\"INCOMPLETE\",\"finishReason\":\"SERIALIZATION_FAILED\"}"
        renderBoundStateObserverR084 = nil
        renderBoundStateMotionR084 = nil
        renderBoundStateCompletionR084 = nil
        renderBoundStateEventsR084.removeAll(keepingCapacity: false)
        continuation.resume(returning: json)
    }

    private func abortRenderBoundStateObserverR084(reason: String) {
        guard renderBoundStateObserverR084 != nil else { return }
        finishRenderBoundStateObserverR084(status: "INCOMPLETE", reason: reason)
    }

    func auditEnemyState(_ state:EnemyMotionState) {
        if frameStallTelemetry.enabled {
            let ids = enemyMotions.keys.sorted().joined(separator: ",")
            currentArtTelemetryContext = FrameStallTelemetry.Context(phase: telemetryPhase(place), actorID: ids.isEmpty ? nil : ids, state: state.rawValue, source: "qa_enemy_state_request_all")
            frameStallTelemetry.setContext(currentArtTelemetryContext)
        }
        for (id,motion) in enemyMotions {
            artAudit[id+":"+state.rawValue]=motion.play(state,restart:true)
        }
    }
    func prepareRegisteredEnemyRendering() async -> String {
        let started = FrameStallTelemetry.nowNanoseconds()
        let generation = sceneGeneration
        let qa = ProcessInfo.processInfo.arguments.contains("--qa-isolated")
        let skipSnapshots = qa && ProcessInfo.processInfo.arguments.contains("--qa-skip-registered-render-snapshot")
        let candidates = enemyMotions.keys.sorted().compactMap { id in enemyMotions[id].map { (id, $0) } }
        guard let renderView = view else {
            guard generation == sceneGeneration else { return "{\"outcome\":\"stale_scene_discarded\"}" }
            registeredRenderPreparationQA = [
                "outcome": "failed",
                "actorIDs": candidates.map { $0.0 },
                "snapshotCount": 0,
                "successfulSnapshotCount": 0,
                "durationMilliseconds": Double(FrameStallTelemetry.nowNanoseconds() - started) / 1_000_000,
                "failureReason": "sprite_view_unavailable"
            ]
            return registeredRenderPreparationJSON()
        }
        let previousContext = currentArtTelemetryContext
        var reports: [[String: Any]] = []
        var cancelled = false
        var stale = false
        for (id, motion) in candidates {
            if Task.isCancelled { cancelled = true; break }
            guard generation == sceneGeneration,
                  enemyMotions[id] === motion,
                  figures[id] === motion.node else { stale = true; break }
            currentArtTelemetryContext = FrameStallTelemetry.Context(
                phase: telemetryPhase(place), actorID: id, state: "render_prepare", source: "battle_or_art_audit_prepare")
            frameStallTelemetry.setContext(currentArtTelemetryContext)
            let result = await motion.prepareRegisteredPoseRendering(in: renderView, captureSnapshots: !skipSnapshots) { [weak self, weak motion] in
                guard let self, let motion else { return false }
                return self.sceneGeneration == generation && self.enemyMotions[id] === motion && self.figures[id] === motion.node
            }
            guard generation == sceneGeneration else { stale = true; break }
            if Task.isCancelled { cancelled = true; break }
            guard enemyMotions[id] === motion, figures[id] === motion.node else { stale = true; break }
            if let result {
                frameStallTelemetry.recordRenderPreparation(actorID: id, result: result)
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(result),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    reports.append(["actorID": id].merging(object) { _, new in new })
                }
            }
        }
        guard generation == sceneGeneration else { return "{\"outcome\":\"stale_scene_discarded\"}" }
        currentArtTelemetryContext = previousContext
        frameStallTelemetry.setContext(previousContext)
        let snapshots = reports.reduce(0) { $0 + (($1["snapshotCount"] as? Int) ?? 0) }
        let succeeded = reports.reduce(0) { $0 + (($1["successfulSnapshotCount"] as? Int) ?? 0) }
        let textureMilliseconds = reports.reduce(0.0) { $0 + (($1["texturePreparationMilliseconds"] as? Double) ?? 0) }
        let snapshotMilliseconds = reports.reduce(0.0) { $0 + (($1["snapshotDurationMilliseconds"] as? Double) ?? 0) }
        let hadFailure = reports.contains { ($0["outcome"] as? String) == "failed" || ($0["outcome"] as? String) == "cancelled" }
        let outcome = cancelled || Task.isCancelled ? "cancelled" : (stale ? "stale_scene_discarded" : (reports.isEmpty ? "not_applicable" : (hadFailure ? "partial_or_failed" : (skipSnapshots ? "textures_prepared_snapshot_skipped" : "prepared"))))
        registeredRenderPreparationQA = [
            "outcome": outcome,
            "actorIDs": reports.compactMap { $0["actorID"] as? String },
            "actors": reports,
            "snapshotCount": snapshots,
            "successfulSnapshotCount": succeeded,
            "texturePreparationMilliseconds": textureMilliseconds,
            "snapshotDurationMilliseconds": snapshotMilliseconds,
            "durationMilliseconds": Double(FrameStallTelemetry.nowNanoseconds() - started) / 1_000_000,
            "mode": skipSnapshots ? "texture_only_qa_comparison" : "textures_plus_offscene_snapshot",
            "skipFlag": skipSnapshots ? ("--qa-skip-registered-render-snapshot" as Any) : NSNull(),
            "skipFlagHonoredOnlyWith": "--qa-isolated",
            "method": "existing_registered_shader_offscene_SKView_texture_snapshot",
            "controllerCacheScope": "per_enemy_motion_controller; rebuilds may require texture creation again"
        ]
        return registeredRenderPreparationJSON()
    }
    private func registeredRenderPreparationJSON() -> String {
        let payload = registeredRenderPreparationQA ?? ["outcome": "not_run"]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    @discardableResult
    func beginEquipmentMotionTrace(request: EquipmentMotionTraceRequest, outputDirectory: URL) -> Bool {
        guard let body = figures[EquipmentMotionTraceRequest.actorID],
              cosmetics["DETAIL|C_SMITH|weapon"] == EquipmentMotionTraceRequest.gearID else { return false }
        if request.captureScope == .fullBattleParty {
            pendingFullBattleEquipmentMotionTrace = (request, outputDirectory, preparedPartyCastRoots)
            return true
        }
        equipmentMotionTraceQA = EquipmentMotionTraceQA(scene: self, body: body,
                                                        request: request, outputDirectory: outputDirectory,
                                                        sceneGeneration: sceneGeneration)
        return true
    }
    /// Starts only the existing AIRA walk renderer, and only from the dedicated
    /// isolated R018 launch mode. This does not dispatch combat or touch GameState.
    @discardableResult
    func beginIsolatedWalkCycleR018(saveKey: String, outputDirectory: URL) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"), args.contains("--qa-equipment-walk-cycle-r018"),
              args.filter({ $0.hasPrefix("--qa-save-key=") }).count == 1,
              args.contains("--qa-save-key=" + saveKey),
              place != .home, equipmentMotionTraceQA == nil,
              isolatedWalkCycleObserverR018 == nil,
              cosmetics["DETAIL|C_SMITH|weapon"] == EquipmentMotionTraceRequest.gearID,
              let body = figures["AIRA"], body.parent === self else { return false }
        body.removeAction(forKey: "party_rest_clip")
        guard playWalk("AIRA", on: body), body.action(forKey: "party_walk_clip") != nil,
              let observer = IsolatedWalkCycleObserverR018(scene: self, body: body,
                outputDirectory: outputDirectory, saveKey: saveKey, sceneGeneration: sceneGeneration) else {
            body.removeAction(forKey: "party_walk_clip")
            return false
        }
        heldPartyPose = true
        isolatedWalkCycleObserverR018 = observer
        return true
    }
    @discardableResult
    func beginERNAStaffMotionTrace(request: ERNAStaffMotionTraceRequestR040, outputDirectory: URL) -> [String: Any] {
        let body = figures["ERNA"]
        let actualGearID = cosmetics["WITCH_EQUIPPED_GEAR"]
        let actualStaffAssetID = cosmetics["WITCH_WEAPON"]
        let actualCostume = cosmetics["C_WITCH"] == "ERNA_TRAVEL" ? "travel" : "standard"
        let checks: [String: Bool] = [
            "bodyExists": body != nil,
            "bodyParentIsScene": body?.parent === self,
            "equippedGearMatchesRequest": actualGearID == request.gearID,
            "staffAssetMatchesRequest": actualStaffAssetID == "STAFF_\(request.gearID)",
            "costumeMatchesRequest": actualCostume == request.costume
        ]
        let failedChecks = checks.filter { !$0.value }.map(\.key).sorted()
        let diagnostic: [String: Any] = [
            "checks": checks,
            "failedChecks": failedChecks,
            "expected": ["gearID": request.gearID, "staffAssetID": "STAFF_\(request.gearID)", "costume": request.costume],
            "actual": ["equippedGearID": actualGearID as Any? ?? NSNull(),
                       "staffAssetID": actualStaffAssetID as Any? ?? NSNull(),
                       "costume": actualCostume,
                       "bodyExists": body != nil,
                       "bodyParentIsScene": body?.parent === self,
                       "sceneGeneration": sceneGeneration]
        ]
        guard failedChecks.isEmpty else { return ["started": false, "diagnostic": diagnostic] }
        ernaStaffMotionTraceQA_R040 = ERNAStaffMotionTraceQA_R040(
            scene: self, request: request, outputDirectory: outputDirectory,
            sceneGeneration: sceneGeneration, expectedPartyCastRoots: preparedPartyCastRoots)
        return ["started": true, "diagnostic": diagnostic]
    }
    /// Queue the isolated observer until the SpriteKit view is attached and the
    /// scene generation/viewport remain stable across rendered callbacks.
    /// Once the trace actually starts, any later rebuild remains a hard failure.
    func beginERNAStaffWalkCycleTrace(request: ERNAStaffWalkCycleRequestR002, outputDirectory: URL,
                                      onStatus: @escaping (String, [String: Any]) -> Void) -> [String: Any] {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              ernaStaffWalkCycleTraceQA_R002 == nil,
              pendingERNAWalkCycleStart == nil,
              ernaStaffMotionTraceQA_R040 == nil,
              let body = figures["ERNA"], body.parent === self,
              cosmetics["WITCH_EQUIPPED_GEAR"] == request.gearID,
              cosmetics["WITCH_WEAPON"] == "STAFF_\(request.gearID)",
              (cosmetics["C_WITCH"] == "ERNA_TRAVEL" ? "travel" : "standard") == request.costume else {
            return ["started": false, "reason": "scene_or_equipped_asset_precondition_failed"]
        }
        let pendingID = UUID()
        pendingERNAWalkCycleStart = PendingERNAWalkCycleStart(
            id: pendingID, request: request, outputDirectory: outputDirectory,
            requestedUptime: ProcessInfo.processInfo.systemUptime, onStatus: onStatus)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5.0))
            self?.expirePendingERNAWalkCycleStart(id: pendingID)
        }
        return ["started": false, "queued": true, "status": "ARMING_STABLE_SCENE",
                "sceneGeneration": sceneGeneration, "sceneSize": [Double(size.width), Double(size.height)],
                "viewAttached": view != nil, "stableFrameRequirement": 4]
    }

    private func expirePendingERNAWalkCycleStart(id: UUID) {
        guard let pending = pendingERNAWalkCycleStart, pending.id == id else { return }
        pendingERNAWalkCycleStart = nil
        pending.onStatus("PRECONDITION_FAIL", ["reason": "stable_scene_wait_timeout",
            "sceneGeneration": sceneGeneration, "sceneSize": [Double(size.width), Double(size.height)],
            "viewAttached": view != nil,
            "stableRenderedFrames": pending.stableGate.stableRenderedFrames])
    }

    private func startERNAStaffWalkCycleTraceNow(request: ERNAStaffWalkCycleRequestR002,
                                                  outputDirectory: URL) -> [String: Any] {
        guard view != nil, size.width > 0, size.height > 0,
              ernaStaffWalkCycleTraceQA_R002 == nil, ernaStaffMotionTraceQA_R040 == nil,
              let body = figures["ERNA"], body.parent === self,
              cosmetics["WITCH_EQUIPPED_GEAR"] == request.gearID,
              cosmetics["WITCH_WEAPON"] == "STAFF_\(request.gearID)",
              (cosmetics["C_WITCH"] == "ERNA_TRAVEL" ? "travel" : "standard") == request.costume,
              let costumeEntry = LayeredWitchMotion.entries[request.costume],
              let clip = costumeEntry["walk"] as? [String: Any],
              let idleClip = costumeEntry["idle"] as? [String: Any],
              let idleRows = idleClip["frames"] as? [[String: Any]], !idleRows.isEmpty,
              let frameRows = clip["frames"] as? [[String: Any]], frameRows.count == 9 else {
            return ["started": false, "reason": "stable_scene_start_precondition_failed"]
        }
        let frameAssets = frameRows.compactMap { row -> String? in
            guard let path = row["path"] as? String, !path.isEmpty else { return nil }
            return "GeneratedArt/LayeredMotion/" + path
        }
        let idleAssets = idleRows.compactMap { row -> String? in
            guard let path = row["path"] as? String, !path.isEmpty else { return nil }
            return "GeneratedArt/LayeredMotion/" + path
        }
        guard frameAssets.count == 9, Set(frameAssets).count == 9,
              idleAssets.count == idleRows.count, !idleAssets.isEmpty,
              let fps = clip["fps"] as? Double, fps > 0, fps.isFinite else {
            return ["started": false, "reason": "walk_or_idle_manifest_invalid"]
        }
        heldPartyPose = true
        guard playWalk("ERNA", on: body), body.action(forKey: "party_walk_clip") != nil else {
            heldPartyPose = false
            return ["started": false, "reason": "existing_walk_action_failed_to_start"]
        }
        poses["ERNA"] = ("walk", clock)
        ernaStaffWalkCycleTraceQA_R002 = ERNAStaffWalkCycleTraceQA_R002(
            scene: self, request: request, outputDirectory: outputDirectory,
            sceneGeneration: sceneGeneration, expectedAssetIDs: frameAssets,
            expectedIdleAssetIDs: idleAssets)
        return ["started": true, "expectedFrameCount": frameAssets.count,
                "expectedAssetIDs": frameAssets, "manifestFPS": fps,
                "nominalCycleSeconds": Double(frameAssets.count) / fps,
                "expectedIdleAssetIDs": idleAssets,
                "requiredWraps": 3, "gearID": request.gearID, "costume": request.costume]
    }

    private func advancePendingERNAWalkCycleStart() {
        guard var pending = pendingERNAWalkCycleStart else { return }
        if ProcessInfo.processInfo.systemUptime - pending.requestedUptime > 5.0 {
            pendingERNAWalkCycleStart = nil
            pending.onStatus("PRECONDITION_FAIL", ["reason": "stable_scene_wait_timeout",
                "sceneGeneration": sceneGeneration, "sceneSize": [Double(size.width), Double(size.height)],
                "viewAttached": view != nil,
                "stableRenderedFrames": pending.stableGate.stableRenderedFrames])
            return
        }
        let sceneReady = figures["ERNA"].map { $0.parent === self } ?? false
        let stable = pending.stableGate.observe(
            viewAttached: view != nil && sceneReady, size: size, generation: sceneGeneration)
        guard stable else {
            pendingERNAWalkCycleStart = pending
            return
        }
        pendingERNAWalkCycleStart = nil
        let result = startERNAStaffWalkCycleTraceNow(request: pending.request,
                                                      outputDirectory: pending.outputDirectory)
        var receipt = result
        receipt["armedAfterStableRenderedFrames"] = pending.stableGate.stableRenderedFrames
        receipt["armedSceneGeneration"] = sceneGeneration
        receipt["armedSceneSize"] = [Double(size.width), Double(size.height)]
        pending.onStatus(result["started"] as? Bool == true ? "STARTED" : "PRECONDITION_FAIL", receipt)
    }

    func auditPartyState(_ state:String) {
        heldPartyPose=true
        if frameStallTelemetry.enabled {
            let ids = Self.names.filter { figures[$0] != nil }.joined(separator: ",")
            currentArtTelemetryContext = FrameStallTelemetry.Context(phase: telemetryPhase(place), actorID: ids.isEmpty ? nil : ids, state: state, source: "qa_party_state_request_all")
            frameStallTelemetry.setContext(currentArtTelemetryContext)
        }
        for id in Self.names {
            guard let figure=figures[id] else{continue}
            if state=="walk" {artAudit[id+":walk"]=playWalk(id,on:figure)}
            else {pose(id,state);artAudit[id+":"+state]=figure.texture != nil}
        }
    }
    /// Isolated QA only: stop on the frame assigned by the texture action itself.
    /// A wall-clock screenshot cannot establish an exact animation frame identity.
    func beginPartyFrameAudit(actor:String,state:String,index:Int)->Bool {
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated"),
              view != nil,Self.names.contains(actor),let node=figures[actor],
              ["idle","walk","anticipate","execute","recover","hit","resolve"].contains(state),
              (0...8).contains(index) else{return false}
        frameAuditRequest=(actor,state,index);frameAuditHeld=false;frameAuditRenderedFrames=0
        heldPartyPose=true;node.isPaused=false;node.removeAllActions();node.warpGeometry=nil
        if state=="walk" {_ = playWalk(actor,on:node)}else{pose(actor,state)}
        return true
    }
    var partyFrameAuditReady:Bool {
        guard frameAuditHeld,frameAuditRenderedFrames>=2,let request=frameAuditRequest,
              let node=figures[request.actor],node.isPaused else{return false}
        return ActorBodyFrame.current(on:node)?.frameIndex==request.index
    }
    override func didFinishUpdate() {
        if frameAuditHeld {frameAuditRenderedFrames+=1}
        applyPendingEnemyLoopBoundaryAction()
        enemyLoopBoundaryTrace?.deliverCompletionAfterRenderedFrame()
        applyPendingDragonGaitR038SequenceAction()
        dragonGaitR038SequenceQA?.deliverCompletionAfterRenderedFrame()
        applyGroundedEntryTargets()
        applyDragonEntryFootpathSessionsR068R002()
        sampleRenderBoundStateObserverR084()
        sampleEquipmentMultiR084()
        sampleEnemyLoopBoundaryTrace()
        sampleDragonGaitR038Sequence()
        sampleBattleEntryTrace(phase: "didFinishUpdate")
        let lunaArgs=ProcessInfo.processInfo.arguments
        if lunaArgs.contains("--qa-isolated"), lunaArgs.contains("--qa-luna-book-native-trace-r010") {
            if lunaBookObserverR010 == nil { lunaBookObserverR010=LunaBookNativeObserverR010(arguments:lunaArgs) }
            lunaBookObserverR010?.sample(scene:self,sceneFrame:frames,sceneTime:last,requestedState:poses["LUNA"]?.0 ?? "idle",
                                          body:figures["LUNA"],hand:lunaBookHand,fault:lunaBookFailureR010)
        }
        if let observer = mothPassiveObserverR058 {
            observer.sample(sceneTime: last, sceneClock: clock, sceneFrame: frames,
                            sceneGeneration: sceneGeneration,
                            motion: enemyMotions[observer.actorID], node: figures[observer.actorID])
        }
        if equipmentMotionTraceQA != nil || ernaStaffMotionTraceQA_R040 != nil || ernaStaffWalkCycleTraceQA_R002 != nil {
            let traceBody = figures["AIRA"]
            let traceState = traceBody?.action(forKey: "party_walk_clip") != nil ? "walk" : poses["AIRA"]?.0 ?? "idle"
            let party: [[String: Any]] = Self.names.map { actor in
                let node = figures[actor]
                let state = node?.action(forKey: "party_walk_clip") != nil ? "walk" : poses[actor]?.0 ?? "idle"
                let frame = node.flatMap { ActorBodyFrame.current(on: $0) }
                var row: [String: Any] = ["actorID": actor, "poseState": state,
                        "poseElapsedSceneSeconds": max(0, clock - (poses[actor]?.1 ?? clock)),
                        "pendingRootActionID": partyCastHoldLifecycle.pendingRoots[actor] as Any? ?? NSNull(),
                        "holdingAnticipate": partyCastHoldLifecycle.isHoldingAnticipate(actorID: actor, state: state),
                        "bodyAssetID": frame?.assetID ?? "", "bodyFrameIndex": frame?.frameIndex ?? -1,
                        "bodyCanvas": frame.map { [Double($0.canvasSize.width), Double($0.canvasSize.height)] } ?? [0.0, 0.0],
                        "bodyExists": node != nil,
                        "activePartyWalkAction": node?.action(forKey: "party_walk_clip") != nil,
                        "activePartyCastAction": node?.action(forKey: "party_cast_clip") != nil,
                        "activePartyRestAction": node?.action(forKey: "party_rest_clip") != nil,
                        "sceneClock": clock]
                if actor == "ERNA", ernaStaffMotionTraceQA_R040 != nil || ernaStaffWalkCycleTraceQA_R002 != nil {
                    row["ernaStaff"] = ERNAStaffFrameSnapshotR040.capture(
                        scene: self, body: node, costume: cosmetics["C_WITCH"],
                        selectedGearID: cosmetics["WITCH_EQUIPPED_GEAR"],
                        selectedStaffAssetID: cosmetics["WITCH_WEAPON"],
                        handAnchorNormalizedTopLeft: layeredHand?.0, handAngleRadians: layeredHand?.1,
                        poseState: state, activeWalkAction: node?.action(forKey: "party_walk_clip") != nil,
                        activeCastAction: node?.action(forKey: "party_cast_clip") != nil,
                        pendingRootActionID: partyCastHoldLifecycle.pendingRoots[actor],
                        holdingAnticipate: partyCastHoldLifecycle.isHoldingAnticipate(actorID: actor, state: state),
                        sceneFrame: frames, sceneTime: last, sceneClock: clock)
                }
                return row
            }
            equipmentMotionTraceQA?.sample(sceneTime: last, sceneFrame: frames, state: traceState,
                                           scene: self, body: traceBody, sceneGeneration: sceneGeneration,
                                           partyCastStates: party)
            if let trace = ernaStaffMotionTraceQA_R040 {
                let ernaStaff = party.first(where: { $0["actorID"] as? String == "ERNA" })?["ernaStaff"] as? [String: Any]
                    ?? ERNAStaffFrameSnapshotR040.capture(
                        scene: self, body: figures["ERNA"], costume: cosmetics["C_WITCH"],
                        selectedGearID: cosmetics["WITCH_EQUIPPED_GEAR"], selectedStaffAssetID: cosmetics["WITCH_WEAPON"],
                        handAnchorNormalizedTopLeft: layeredHand?.0, handAngleRadians: layeredHand?.1,
                        poseState: poses["ERNA"]?.0 ?? "idle",
                        activeWalkAction: figures["ERNA"]?.action(forKey: "party_walk_clip") != nil,
                        activeCastAction: figures["ERNA"]?.action(forKey: "party_cast_clip") != nil,
                        pendingRootActionID: partyCastHoldLifecycle.pendingRoots["ERNA"],
                        holdingAnticipate: partyCastHoldLifecycle.isHoldingAnticipate(actorID: "ERNA", state: poses["ERNA"]?.0 ?? "idle"),
                        sceneFrame: frames, sceneTime: last, sceneClock: clock)
                trace.sample(sceneFrame: frames, sceneTime: last, sceneGeneration: sceneGeneration,
                             partyCastStates: party, ernaStaff: ernaStaff, scene: self)
            }
            if let walkTrace = ernaStaffWalkCycleTraceQA_R002 {
                let bodyState = party.first(where: { $0["actorID"] as? String == "ERNA" }) ?? [:]
                let staff = bodyState["ernaStaff"] as? [String: Any] ?? [:]
                switch walkTrace.sample(bodyState: bodyState, staff: staff,
                                        sceneFrame: frames, sceneTime: last, sceneClock: clock,
                                        currentGeneration: sceneGeneration, scene: self) {
                case .continueObserving:
                    break
                case .restoreIdle:
                    heldPartyPose = false
                    if let body = figures["ERNA"] {
                        body.removeAction(forKey: "party_walk_clip")
                        pose("ERNA", "idle")
                    }
                case .finished:
                    ernaStaffWalkCycleTraceQA_R002 = nil
                }
            }
        }
        if let observer = isolatedWalkCycleObserverR018,
           observer.sample(sceneFrame: frames, sceneTime: last, sceneGeneration: sceneGeneration) {
            isolatedWalkCycleObserverR018 = nil
            heldPartyPose = false
            if let body = figures["AIRA"] {
                body.removeAction(forKey: "party_walk_clip")
                pose("AIRA", "idle")
            }
        }
        if syntheticDash2TailTraceR047 != nil {
            let body = figures["NOIR"]
            let markerVisible = r047VideoSyncMarker?.parent === self
            if markerVisible {
                r047VideoSyncMarkerSequence += 1
                (r047VideoSyncMarker?.childNode(withName: "r047_video_sync_marker_label") as? SKLabelNode)?.text = String(format: "R47 %04d", r047VideoSyncMarkerSequence)
            }
            syntheticDash2TailTraceR047?.sample(sceneFrame: frames, sceneTime: clock, spriteKitTime: last,
                currentGeneration: sceneGeneration, sceneActive: view?.window != nil,
                poseState: poses["NOIR"]?.0 ?? "none", body: body,
                markerVisible: markerVisible, markerSequence: markerVisible ? r047VideoSyncMarkerSequence : nil,
                markerPosition: r047VideoSyncMarker.map { [Double($0.position.x), Double($0.position.y)] } ?? [],
                markerSize: [112.0, 26.0])
        }
        // Start only after this rendered frame has completed its normal observers.
        // LayeredWitchMotion assigns the first texture from an SKAction.run on a
        // later SpriteKit action tick; starting above would let this same callback
        // sample the prior idle texture as if it were a walk frame.
        advancePendingERNAWalkCycleStart()
        reflowPursuitNoticesAfterSceneActionsR008()
        samplePursuitNoticeRenderR092()
    }

    private func pursuitNoticeGroupsR092() -> [SKNode] {
        var groups: [SKNode] = []
        enumerateChildNodes(withName: "//" + PursuitSuppressionNotice.nodeName) { node, _ in groups.append(node) }
        return groups
    }

    private func samplePursuitNoticeRenderR092() {
        let arguments = ProcessInfo.processInfo.arguments
        guard PursuitNoticeRenderObserverR092.isRequested(arguments: arguments) else { return }
        if pursuitNoticeRenderObserverR092 == nil {
            pursuitNoticeRenderObserverR092 = PursuitNoticeRenderObserverR092(arguments: arguments)
        }
        pursuitNoticeRenderObserverR092?.sample(
            scene: self, groups: pursuitNoticeGroupsR092(), recipients: figures,
            sceneFrame: frames, sceneTime: clock, spriteKitTime: last,
            sceneGeneration: sceneGeneration)
    }

    /// Runs after SpriteKit actions and before rendering. It never changes
    /// recipient identity, actor transforms, combat state, or notice lifetime.
    private func reflowPursuitNoticesAfterSceneActionsR008() {
        var groups: [SKNode] = []
        enumerateChildNodes(withName: "//" + PursuitSuppressionNotice.nodeName) { node, _ in groups.append(node) }
        for group in groups {
            guard let targetID = group.userData?["pursuitTargetID"] as? String,
                  let recipient = figures[targetID], group.parent === recipient else {
                group.userData?["r008LastDisposition"] = "skipped_target_identity_or_parent_mismatch"
                continue
            }
            let obstacles = pursuitNoticeObstacleNodes(excluding: targetID)
            _ = PursuitSuppressionNotice.reflow(group: group, recipient: recipient, scene: self,
                                                 obstacleNodes: obstacles, sceneFrame: frames)
        }
    }

    func runEnemyLoopBoundaryTrace(actorID: String, saveKey: String, outputDirectory: URL) async -> String {
        guard EnemyLoopBoundaryTraceQA.isRequested() else { return "NOT_REQUESTED" }
        guard let motion = enemyMotions.values.first(where: { $0.actorID == actorID }) else {
            return "INCONCLUSIVE_ACTOR_NOT_LOADED:\(actorID)"
        }
        let descriptors = [motion.loopBoundaryMode(for: .idle), motion.loopBoundaryMode(for: .walk)]
        guard let trace = EnemyLoopBoundaryTraceQA(requestedActorID: actorID, actorID: motion.actorID,
                                                    saveKey: saveKey, outputDirectory: outputDirectory,
                                                    descriptors: descriptors) else {
            return "FAILED_INVALID_SAVE_KEY"
        }
        return await withCheckedContinuation { continuation in
            enemyLoopBoundaryTrace = trace
            enemyLoopBoundaryMotion = motion
            let action = trace.start(in: self) { [weak self] result in
                self?.enemyLoopBoundaryTrace = nil
                self?.enemyLoopBoundaryMotion = nil
                self?.pendingEnemyLoopBoundaryAction = nil
                continuation.resume(returning: result)
            }
            pendingEnemyLoopBoundaryAction = (action, motion)
        }
    }
    private func applyPendingEnemyLoopBoundaryAction() {
        guard let (action, motion) = pendingEnemyLoopBoundaryAction else { return }
        pendingEnemyLoopBoundaryAction = nil
        switch action {
        case .none:
            break
        case .play(let state):
            if !motion.play(state, restart: true) {
                enemyLoopBoundaryTrace?.abort("INCONCLUSIVE_UNSUPPORTED_STATE:\(state.rawValue)")
            }
        case .finished:
            break
        }
    }
    private func sampleEnemyLoopBoundaryTrace() {
        guard let trace = enemyLoopBoundaryTrace, let motion = enemyLoopBoundaryMotion else { return }
        let snapshot = motion.presentationSnapshot
        let action = trace.sample(presentation: snapshot, root: motion.node.position,
                                  scene: self, sceneFrame: frames)
        switch action {
        case .none: break
        case .play, .finished: pendingEnemyLoopBoundaryAction = (action, motion)
        }
    }
    func hasDragonFlightState(actorID: String) -> Bool {
        enemyMotions[actorID]?.availableStates.contains(.flight) == true
    }

    func runDragonGaitR038SequenceQA(actorID: String, saveKey: String, outputDirectory: URL,
                                     includesFlight: Bool) async -> String {
        guard DragonGaitR038QA.isEnabled(arguments: ProcessInfo.processInfo.arguments),
              DragonGaitR038SequenceQA.isRequested(actorID: actorID),
              actorID == "ACT_B_R04_B",
              let motion = enemyMotions[actorID] else {
            return "INCOMPLETE_R038_SEQUENCE_PRECONDITION"
        }
        guard let observer = DragonGaitR038SequenceQA(actorID: actorID, saveKey: saveKey,
                                                       outputDirectory: outputDirectory,
                                                       includesFlight: includesFlight) else {
            return "FAILED_INVALID_SAVE_KEY"
        }
        abortDragonGaitR038Sequence(reason: "REPLACED_BY_NEW_REQUEST")
        return await withCheckedContinuation { continuation in
            dragonGaitR038SequenceQA = observer
            dragonGaitR038SequenceMotion = motion
            let action = observer.start(in: self) { [weak self] result in
                guard let self else { continuation.resume(returning: result); return }
                self.dragonGaitR038SequenceQA = nil
                self.dragonGaitR038SequenceMotion = nil
                self.pendingDragonGaitR038SequenceAction = nil
                continuation.resume(returning: result)
            }
            pendingDragonGaitR038SequenceAction = (action, motion)
        }
    }

    private func abortDragonGaitR038Sequence(reason: String) {
        guard let observer = dragonGaitR038SequenceQA else { return }
        observer.abort(reason)
        dragonGaitR038SequenceQA = nil
        dragonGaitR038SequenceMotion = nil
        pendingDragonGaitR038SequenceAction = nil
        // Teardown/rebuild can stop didFinishUpdate. Deliver the incomplete
        // receipt now so the async QA route cannot remain suspended forever.
        observer.deliverCompletionAfterRenderedFrame()
    }

    private func applyPendingDragonGaitR038SequenceAction() {
        guard let (action, motion) = pendingDragonGaitR038SequenceAction else { return }
        pendingDragonGaitR038SequenceAction = nil
        switch action {
        case .none:
            break
        case .play(let state):
            if !motion.play(state, restart: true) {
                dragonGaitR038SequenceQA?.abort("UNSUPPORTED_STATE_\(state.rawValue)")
                pendingDragonGaitR038SequenceAction = (.play(.idle), motion)
            }
        case .finished:
            break
        }
    }

    private func sampleDragonGaitR038Sequence() {
        guard let observer = dragonGaitR038SequenceQA,
              let motion = dragonGaitR038SequenceMotion else { return }
        let action = observer.sample(presentation: motion.presentationSnapshot,
                                     root: motion.node.position, scene: self, sceneFrame: frames)
        switch action {
        case .none: break
        case .play, .finished: pendingDragonGaitR038SequenceAction = (action, motion)
        }
    }

    private func applyGroundedEntryTargets() {
        for (id, home) in groundedBattleEntryTargets {
            guard let motion = enemyMotions[id] else { groundedBattleEntryTargets.removeValue(forKey: id); continue }
            if let offset = motion.groundedEntryOffset(in: self) {
                motion.node.position = CGPoint(x: home.x - offset.x, y: home.y - offset.y)
            } else {
                motion.node.position = home
                groundedBattleEntryTargets.removeValue(forKey: id)
            }
        }
    }

    /// Applies the R068 local candidate after normal SKActions and before the
    /// same-frame trace readback. Elapsed time comes from a sibling customAction
    /// in the unchanged 0.6s arrival group, rather than the capped scene clock.
    private func applyDragonEntryFootpathSessionsR068R002() {
        for (id, session) in Array(dragonEntryFootpathSessionsR068R002) {
            guard let motion = enemyMotions[id], motion.currentMotionState == .walk,
                  motion.node.action(forKey: "battle_arrival") != nil else {
                enemyMotions[id]?.restoreNormalEntryFootpathR068R002()
                dragonEntryFootpathSessionsR068R002.removeValue(forKey: id)
                continue
            }
            let elapsed = min(DragonEntryFootpathIKR068R002.duration,
                              max(0, session.actionElapsedSeconds))
            let current = motion.node.convert(CGPoint.zero, to: self)
            guard motion.applyNormalEntryFootpathR068R002(elapsed: elapsed,
                    entryStartRootScene: session.startRootScenePoint,
                    currentRootScene: current, homeRootScene: session.homeRootScenePoint,
                    scene: self) != nil else {
                motion.restoreNormalEntryFootpathR068R002()
                dragonEntryFootpathSessionsR068R002.removeValue(forKey: id)
                continue
            }
        }
    }
    func auditBattleEntryLifecycle(phase: String) {
        guard ProcessInfo.processInfo.arguments.contains("--qa-entry-lifecycle-trace") else { return }
        sampleBattleEntryTrace(phase: "lifecycle_" + phase)
    }
    private func sampleBattleEntryTrace(phase: String) {
        guard let trace = battleEntryTrace, trace.isRecording else { return }
        var actors: [String: Any] = [:]
        for (id, motion) in enemyMotions {
            let n = motion.node
            actors[id] = ["root": [n.position.x, n.position.y],
                          "home": baseline[id].map { [$0.x, $0.y] } ?? [],
                          "scale": [n.xScale, n.yScale],
                          "arrivalAction": n.action(forKey: "battle_arrival") != nil,
                          "presentation": motion.entryTraceSnapshot(in: self)]
        }
        trace.sample(phase: phase, sceneTime: last, sceneClock: clock, sceneFrame: frames,
                     rawDelta: gatherTraceRawDelta, scene: self, actors: actors)
    }
    func artAuditJSON()->String {
        let geometry=figures.mapValues{node->[String:Any] in
            let bounds=node.calculateAccumulatedFrame()
            let frame=ActorBodyFrame.current(on:node)
            return ["width":node.size.width,"height":node.size.height,"xScale":node.xScale,"yScale":node.yScale,"x":node.position.x,"y":node.position.y,"textureWidth":node.texture?.size().width ?? 0,"textureHeight":node.texture?.size().height ?? 0,"accumulatedMinX":bounds.minX,"accumulatedMaxX":bounds.maxX,"accumulatedMinY":bounds.minY,"accumulatedMaxY":bounds.maxY,"anchorX":node.anchorPoint.x,"anchorY":node.anchorPoint.y,"zRotation":node.zRotation,"bodyAssetID":frame?.assetID ?? "","bodyFrameIndex":frame?.frameIndex ?? -1,"bodyCanvasWidth":frame?.canvasSize.width ?? 0,"bodyCanvasHeight":frame?.canvasSize.height ?? 0,"isPaused":node.isPaused,"equipmentRegistration":node.userData?["equipmentDetailRegistrationQA"] as? [String:Any] ?? [:]]
        }
        let r04Owned=children.filter{($0.name ?? "").hasPrefix("environment_effect:ENV_R04_") && ($0.userData?["environmentOwner"] as? String)=="R04"}
        let effects:[String:Any]=["counts":effectCounts,"last":effectLast,"cueTrace":effectCues.audit,"peakCombat":peakCombatEffects,"peakEnvironment":peakEnvironmentEffects,"activeCombat":children.filter{$0.name?.hasPrefix("combat_effect:")==true}.count,"activeEnvironment":children.filter{$0.name?.hasPrefix("environment_effect:")==true}.count,"r04EnvironmentPolicy":r04EnvironmentPolicy.snapshot(currentOwnedEmitterCount:r04Owned.count,currentHiddenEmitterCount:r04Owned.filter{$0.isHidden}.count)]
        let hold:[String:Any]=["actor":frameAuditRequest?.actor ?? "","state":frameAuditRequest?.state ?? "","index":frameAuditRequest?.index ?? -1,"held":frameAuditHeld,"renderedFrames":frameAuditRenderedFrames,"warp":"disabled_for_isolated_frame_fit"]
        var payload:[String:Any] = ["actorIDs":enemyIDs,"states":artAudit,"geometry":geometry,"appearance":cosmetics,"effects":effects,"frameHold":hold,"expectedPartyHeights":baselineHeights,"frames":frames,"maxFrameDeltaSeconds":maxFrameDelta,"gatherNode":gatherNodeAudit,"textureCache":textureCache.snapshot()]
        payload["enemyPresentation"]=enemyMotions.mapValues(\.presentationSnapshot)
        if let observer = pursuitNoticeRenderObserverR092 {
            payload["pursuitNoticeRenderR092"] = observer.receipt()
        }
        payload["holdingBattleResult"]=holdingBattleResult
        let qaArguments = ProcessInfo.processInfo.arguments
        if qaArguments.contains("--qa-isolated") && qaArguments.contains("--qa-r04-weather-policy") {
            if r04WeatherPolicyQACache == nil { r04WeatherPolicyQACache = R04WeatherQA.run() }
            payload["r04EnvironmentPolicyQA"] = r04WeatherPolicyQACache
        }
        if let node=gatherNode {
            payload["gatherNodeGeometry"]=["x":node.position.x,"y":node.position.y,"width":node.size.width,"height":node.size.height,"sceneWidth":size.width,"sceneHeight":size.height,"alpha":node.alpha,"hidden":node.isHidden,"nodeCount":children.filter{$0.name?.hasPrefix("gather_node:")==true}.count]
        } else {payload["gatherNodeGeometry"]=["nodeCount":0]}
        if let areaResolution { payload["areaBackground"] = areaResolution.qaReceipt() }
        if let injection = AreaFlowQAHook.injectionReceipt { payload["fallbackInjection"] = injection }
        if let observer = mothPassiveObserverR058 {
            payload["r058PassiveMothObservation"] = observer.receipt()
        }
        if let observer=lunaBookObserverR010 { payload["lunaBookNativeR010"]=observer.receipt(fault:lunaBookFailureR010) }
        if frameStallTelemetry.enabled {
            payload["frameStallTelemetry"] = frameStallTelemetry.snapshot()
            payload["registeredRenderPreparation"] = registeredRenderPreparationQA ?? ["outcome": "not_run"]
        }
        let d=(try? JSONSerialization.data(withJSONObject:payload,options:.sortedKeys)) ?? Data();return String(data:d,encoding:.utf8) ?? "{}"
    }
#if targetEnvironment(simulator)
    func textureRetentionSnapshot()->[String:Any] { textureCache.snapshot() }
    func clearRetainedTexturesForQA() { textureCache.clear() }
#endif
    private func telemetryPhase(_ place:Place)->String {
        switch place {
        case .home:return "home"
        case .field(let region):return "field:"+region
        case .portrait(let actor):return "portrait:"+actor
        }
    }
    func arriveForBattle() {
        for motion in enemyMotions.values { motion.restoreNormalEntryFootpathR068R002() }
        dragonEntryFootpathSessionsR068R002.removeAll()
        partyCastHoldLifecycle.clearAll()
        groundedBattleEntryTargets.removeAll()
        battleEntryTrace = BattleEntryTraceQA.begin(in: self)
        holdingBattleResult=false
        heldPartyPose=false
        for id in Self.names {
            guard let figure=figures[id],let home=baseline[id] else{continue}
            let accepted=playWalk(id,on:figure)
            artAudit[id+":battle_entry_walk"]=accepted
            guard accepted else{continue}
            figure.position.x -= min(22,size.width*0.04)
            let enter=SKAction.move(to:home,duration:0.6);enter.timingMode = .easeOut
            figure.run(.sequence([enter,.run{[weak self] in self?.pose(id,"idle")}]),withKey:"battle_arrival")
        }
        for (id,motion) in enemyMotions {
            let grounded = motion.beginGroundedEntryIfRequested()
            let accepted=grounded || motion.play(.walk,restart:true);artAudit[id+":battle_entry_walk"]=accepted
            guard accepted,let home=baseline[id] else{continue}
            let enter: SKAction
            if grounded {
                groundedBattleEntryTargets[id] = home
                enter = .wait(forDuration: 0.6)
            } else {
                motion.node.position.x += min(22,size.width*0.04)
                if id == "ACT_B_R04_B" {
                    let startScene = motion.node.convert(CGPoint.zero, to: self)
                    let homeScene = (motion.node.parent ?? self).convert(home, to: self)
                    if motion.beginNormalEntryFootpathR068R002() {
                        dragonEntryFootpathSessionsR068R002[id] = DragonEntryFootpathSessionR068R002(
                            startRootScenePoint: startScene, homeRootScenePoint: homeScene,
                            actionElapsedSeconds: 0)
                    }
                }
                enter = .move(to: home, duration: 0.6); enter.timingMode = .easeOut
            }
            let arrivalMotion: SKAction
            if dragonEntryFootpathSessionsR068R002[id] != nil {
                let elapsedProbe = SKAction.customAction(withDuration: DragonEntryFootpathIKR068R002.duration) { [weak self] _, elapsed in
                    guard let self, var session = self.dragonEntryFootpathSessionsR068R002[id] else { return }
                    session.actionElapsedSeconds = Double(elapsed)
                    self.dragonEntryFootpathSessionsR068R002[id] = session
                }
                arrivalMotion = .group([enter, elapsedProbe])
            } else {
                arrivalMotion = enter
            }
            motion.node.run(.sequence([arrivalMotion,.run{[weak motion] in _ = motion?.play(.idle,restart:true)}]),withKey:"battle_arrival")
        }
        applyGroundedEntryTargets()
        sampleBattleEntryTrace(phase: "arrivalScheduled")
    }
    @discardableResult
    func finishBattle(won:Bool)->Double {
        for motion in enemyMotions.values { motion.restoreNormalEntryFootpathR068R002() }
        dragonEntryFootpathSessionsR068R002.removeAll()
        equipmentMotionTraceQA?.battleFinished(won: won)
        ernaStaffMotionTraceQA_R040?.battleFinished(won: won)
        partyCastHoldLifecycle.clearAll()
        holdingBattleResult=true
        WitchAudioCoordinator.shared.play(won ? .victory:.defeat)
        for (id,motion) in enemyMotions {if won || hp[id]==0 {_ = motion.play(.resolve)}}
        for id in Self.names {let state=(hp[id] ?? 1)>0 && won ? "resolve":"hit";pose(id,state)}
        let longest=enemyMotions.filter{won || hp[$0.key]==0}.values.map(\.resolveDuration).max() ?? 0
        return max(1.25,longest+0.25)
    }
    func releaseBattleResult() { partyCastHoldLifecycle.clearAll();holdingBattleResult=false }
    func beginSyntheticDash2TailR047(request: SyntheticDash2TailRequestR047) {
        syntheticDash2TailTraceR047 = SyntheticDash2TailTraceR047(request: request, sceneGeneration: sceneGeneration)
    }
    func finishSyntheticDash2TailR047(observedMilliseconds: Int, sceneActive: Bool, cancelled: Bool = false, reason: String? = nil) -> [String: Any] {
        guard let trace = syntheticDash2TailTraceR047 else { return ["status":"INCOMPLETE_OBSERVER_MISSING"] }
        let receipt = trace.finish(observedMilliseconds: observedMilliseconds,
                                   currentGeneration: sceneGeneration, sceneActive: sceneActive, cancelled: cancelled, reason: reason)
        syntheticDash2TailTraceR047 = nil
        r047VideoSyncMarker?.removeFromParent(); r047VideoSyncMarker=nil; r047VideoSyncMarkerSequence=0
        return receipt
    }
    var presentationClock:TimeInterval {clock}
    var isForegroundRenderedForR047: Bool { view?.window != nil && view?.isPaused == false }
    var battleResolutionSnapshot:[String:Any] {
        ["sceneClock":clock,"sceneFrames":frames,"enemyIDs":enemyIDs,"holdingBattleResult":holdingBattleResult,
         "enemies":enemyMotions.mapValues(\.presentationSnapshot),
         "party":Dictionary(uniqueKeysWithValues:Self.names.map{($0,poses[$0]?.0 ?? "none")})]
    }
    func playGatherCollection(materialID:String) {
        guard materialID==selectedGatherMaterialID,materialID==gatherNodeMaterialID,
              let regionID={if case .field(let value)=place{return value};return nil}(),
              let collectedProjection=R016GatherNodePresentation.projection(materialID:materialID,regionID:regionID,resolution:areaResolution,state:.collected),
              let presentProjection=R016GatherNodePresentation.projection(materialID:materialID,regionID:regionID,resolution:areaResolution,state:.present),
              let collected=texture(R016GatherNodePresentation.imageID(for:collectedProjection)),
              let node=gatherNode,
              let present=texture(R016GatherNodePresentation.imageID(for:presentProjection)) else{return}
        node.removeAction(forKey:"gather_visual_respawn")
        node.alpha=1
        GatherNodePresentation.playCollectionCue(on:node,materialID:materialID)
        let collectedTextureID=R016GatherNodePresentation.imageID(for:collectedProjection)
        let presentTextureID=R016GatherNodePresentation.imageID(for:presentProjection)
        gatherNodeAudit=["materialID":materialID,"nodeID":collectedProjection.nodeID,"regionID":regionID,
                         "state":"collected","textureID":collectedTextureID,"loaded":true,"transition":"collecting"]
        var actions=R016GatherNodePresentation.successfulClaimActions(collected:collected,present:present)
        actions.append(.run { [weak self, weak node] in
            guard let self, let node, self.gatherNode === node else{return}
            self.gatherNodeAudit=["materialID":materialID,"nodeID":collectedProjection.nodeID,"regionID":regionID,
                                 "state":"present","textureID":presentTextureID,"loaded":true,"transition":"respawned"]
        })
        node.run(.sequence(actions),withKey:"gather_visual_respawn")
        gatherFrameTrace=GatherFrameTraceQA.begin(materialID:materialID)
        gatherFrameTrace?.sample(phase:"scheduled",sceneTime:last,rawDelta:0,scene:self,node:node)
    }
    func beginBattle(partyHP:[String:Int],enemyHP:[String:Int]) {
        clearCombatEffects();effectCounts.removeAll();effectLast.removeAll();peakCombatEffects=0;peakEnvironmentEffects=0
        if let observer = MothPassiveRenderObserverR058.make(arguments: ProcessInfo.processInfo.arguments) {
            mothPassiveObserverR058 = observer
            observer.beginBattle(sceneTime: last, sceneClock: clock, sceneFrame: frames,
                                 sceneGeneration: sceneGeneration,
                                 actorPresent: enemyMotions[observer.actorID] != nil && figures[observer.actorID] != nil)
        } else {
            mothPassiveObserverR058 = nil
        }
        hp=Dictionary(uniqueKeysWithValues:(partyHP.merging(enemyHP){a,_ in a}).map{(actorKey(GameModel.spriteIDs[$0.key] ?? $0.key),$0.value)})
        maxHP=hp
        for (id,value) in hp {setHP(id,value)}
        if let pending = pendingFullBattleEquipmentMotionTrace {
            let trace = EquipmentMotionTraceQA(scene: self, body: figures[EquipmentMotionTraceRequest.actorID],
                                               request: pending.request, outputDirectory: pending.outputDirectory,
                                               sceneGeneration: sceneGeneration)
            trace.setExpectedPartyCastRoots(pending.expectedPartyCastRoots)
            equipmentMotionTraceQA = trace
            pendingFullBattleEquipmentMotionTrace = nil
        }
    }
    func finishHP(party:[String:Int],enemies:[String:Int]){for (id,value) in party.merging(enemies,uniquingKeysWith:{$1}){setHP(actorKey(GameModel.spriteIDs[id] ?? id),value)}}
    func hpMismatches(party:[String:Int],enemies:[String:Int])->[String:[Int]] {
        var mismatches:[String:[Int]]=[:]
        for (id,expected) in party.merging(enemies,uniquingKeysWith:{$1}) {
            let key=actorKey(GameModel.spriteIDs[id] ?? id),actual=hp[key] ?? -1
            if actual != expected {mismatches[id]=[actual,expected]}
        }
        return mismatches
    }
    private func setHP(_ id:String,_ value:Int){
        hp[id]=max(0,value);if value<=0{_ = clearPendingPartyCast(id)};guard let figure=figures[id],let maximum=maxHP[id],maximum>0 else{return}
        let bar:SKShapeNode
        if let existing=hpBars[id]{bar=existing}else{
            bar=SKShapeNode();bar.strokeColor = .clear;bar.zPosition=25;hpBars[id]=bar;addChild(bar)
            let track=SKShapeNode(rectOf:CGSize(width:42,height:4),cornerRadius:2);track.fillColor = .black.withAlphaComponent(0.6);track.strokeColor = .clear;track.zPosition=24;hpTracks[id]=track;track.position=CGPoint(x:figure.position.x,y:figure.frame.maxY+5);addChild(track)
        }
        let width=40*CGFloat(max(0,value))/CGFloat(maximum)
        bar.path=CGPath(roundedRect:CGRect(x:0,y:0,width:width,height:3),cornerWidth:1,cornerHeight:1,transform:nil)
        bar.fillColor=Self.names.contains(id) ? .systemMint:.systemOrange
        bar.position=CGPoint(x:figure.position.x-20,y:figure.frame.maxY+3)
        if value<=0{if enemyPresentation[id]?.kind=="prop" {figure.removeAction(forKey:"lamp_idle");figure.removeAction(forKey:"lamp_heal");figure.texture=texture("PROP_LAMP__3")};if let motion=enemyMotions[id]{_ = motion.play(.resolve)};figure.alpha=0.5}
    }
    private func pose(_ id:String,_ state:String){
        if frameStallTelemetry.enabled {
            currentArtTelemetryContext = FrameStallTelemetry.Context(phase: telemetryPhase(place), actorID: id, state: state, source: "scene.pose_request")
            frameStallTelemetry.setContext(currentArtTelemetryContext)
        }
        if let enemy=enemyMotions[id],let mode=EnemyMotionState(rawValue:state){_ = enemy.play(mode,restart:true);return}
        guard let figure=figures[id] else{return};poses[id]=(state,clock)
        bindEquipmentFrame(id,state:state,on:figure)
        if let height=baselineHeights[id]{figure.size.height=height}
        figure.removeAction(forKey:"party_walk_clip")
        figure.removeAction(forKey:"party_rest_clip")
        if id=="ERNA" {layeredHand=nil}
        artAudit[id+":authored_"+state]=false
        if id=="LUNA",hasLunaBook,playLunaBook(state,on:figure){artAudit[id+":authored_"+state]=true;return}
        if id=="ERNA",hasSeparateWitchWeapon,playLayered(state,on:figure){artAudit[id+":authored_"+state]=true;return}
        let candidateEnabled=id != "ERNA" || !hasSeparateWitchWeapon
        if candidateEnabled && PartyAuthoredMotion.play(actor:id,state:state,on:figure){artAudit[id+":authored_"+state]=true;return}
        if candidateEnabled && CharacterClips.play(actor:id,state:state,on:figure){artAudit[id+":authored_"+state]=true;return}
        figure.removeAction(forKey:"party_cast_clip")
        if let texture=texture(appearance(id,state)){figure.texture=texture;figure.size.width=figure.size.height*texture.size().width/texture.size().height;figure.anchorPoint=CGPoint(x:0.5,y:0.04);ActorBodyFrame.record(appearance(id,state),on:figure)}
    }
    private func bindEquipmentFrame(_ actor:String,state:String,on node:SKSpriteNode) {
        ActorBodyFrame.bind(on:node) { [weak self,weak node] sample in
            guard let self,let node else{return}
            let hand=actor=="ERNA" ? self.layeredHand?.0:(actor=="LUNA" ? self.lunaBookHand:nil)
            for (gear,loaded) in EquipmentDetailRenderer.update(actor:actor,state:state,on:node,equipment:self.cosmetics,hand:hand) {
                self.artAudit["detail_"+gear+":"+state]=loaded
            }
            if let request=self.frameAuditRequest,request.actor==actor,request.state==state,request.index==sample.frameIndex {
                node.warpGeometry=nil;node.isPaused=true;self.frameAuditHeld=true
            }
        }
    }
    private func playWalk(_ id:String,on figure:SKSpriteNode)->Bool {
        bindEquipmentFrame(id,state:"walk",on:figure)
        if let height=baselineHeights[id]{figure.size.height=height}
        figure.removeAction(forKey:"party_rest_clip")
        if id=="LUNA",hasLunaBook {
            return LunaBookWalkFallbackR009.play(
                bookAttempt: { self.playLunaBook("walk",on:figure) },
                bodyFallback: {
                    self.lunaBookHand = nil
                    return CharacterLocomotion.play(actor:id,on:figure)
                }
            )
        }
        guard id=="ERNA",hasSeparateWitchWeapon else{return CharacterLocomotion.play(actor:id,on:figure)}
        return playLayered("walk",on:figure)
    }
    private func playLayered(_ state:String,on figure:SKSpriteNode)->Bool {
        LayeredWitchMotion.play(costume:cosmetics["C_WITCH"]=="ERNA_TRAVEL" ? "travel":"standard",state:state,on:figure){[weak self] node,hand,angle in self?.layeredHand=(hand,angle);self?.syncWeapon(node,state:state,handOverride:hand,angleOverride:angle)}
    }
    private func playLunaBook(_ state:String,on figure:SKSpriteNode)->Bool {
        let args=ProcessInfo.processInfo.arguments
        let gearID=cosmetics["APPRENTICE_BOOK_GEAR"] ?? ""
        let qaEnabled=args.contains("--qa-isolated") && args.contains("--qa-luna-book-native-trace-r010")
        let injectFailure=qaEnabled && args.contains("--qa-luna-book-failure-after-success-r010")
        var loaded:Bool
        if injectFailure {
            if lunaBookFailureR010 == nil,
               let lastWalk=LunaBookMotion.frames(state:"walk",gearID:gearID)?.last {
                lunaBookFailureR010=LunaBookFailureInjectionR010(missingWalkAssetID:lastWalk.bodyAssetID)
            }
            if let fault=lunaBookFailureR010 {
                loaded=LunaBookSpriteMotion.playResolvedR010(state:state,gearID:gearID,on:figure,
                    resolveTexture:{ assetID in
                        guard !fault.shouldReject(state:state,assetID:assetID) else { return nil }
                        return LunaBookSpriteMotion.qaDefaultTextureR010(assetID)
                    },
                    attach:{[weak self] hand in self?.lunaBookHand=hand})
                fault.noteResult(state:state,loaded:loaded)
            } else {
                loaded=LunaBookSpriteMotion.play(state:state,gearID:gearID,on:figure){[weak self] hand in self?.lunaBookHand=hand}
            }
        } else {
            loaded=LunaBookSpriteMotion.play(state:state,gearID:gearID,on:figure){[weak self] hand in self?.lunaBookHand=hand}
        }
        if !loaded { lunaBookHand=LunaBookWalkFallbackR009.handAfterAttempt(loaded:false,previous:lunaBookHand) }
        artAudit["LUNA:book_"+state]=loaded
        return loaded
    }
    private func clearPendingPartyCast(_ actor:String,root:String?=nil)->Bool {
        partyCastHoldLifecycle.clear(actorID:actor,rootActionID:root)
    }
    private func installR047VideoSyncMarker() {
        r047VideoSyncMarker?.removeFromParent()
        let marker = SKNode()
        marker.name = "r047_video_sync_marker"
        marker.zPosition = 20_000
        let backing = SKShapeNode(rectOf: CGSize(width: 112, height: 26), cornerRadius: 3)
        backing.name = "r047_video_sync_marker_back"
        backing.fillColor = .black.withAlphaComponent(0.88)
        backing.strokeColor = .white.withAlphaComponent(0.9)
        backing.lineWidth = 1
        marker.addChild(backing)
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "R47 0000"
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.name = "r047_video_sync_marker_label"
        marker.addChild(label)
        marker.position = CGPoint(x: 68, y: size.height - 76)
        addChild(marker)
        r047VideoSyncMarker = marker
        r047VideoSyncMarkerSequence = 0
    }

    func present(_ event:CombatEvent){
        let source=actorKey(GameModel.spriteIDs[event.sourceID] ?? event.sourceID)
        let target=actorKey(GameModel.spriteIDs[event.targetID] ?? event.targetID)
        if syntheticDash2TailTraceR047?.recordPresented(event, sceneFrame: frames, sceneTime: clock, spriteKitTime: last) == true {
            installR047VideoSyncMarker()
        }
        equipmentMotionTraceQA?.recordPartyCombatEvent(kind:event.kind,actorID:source,rootActionID:event.rootActionID,sceneFrame:frames)
        ernaStaffMotionTraceQA_R040?.recordPartyCombatEvent(kind:event.kind,actorID:source,rootActionID:event.rootActionID,sceneFrame:frames)
        let classification=R6CombatPresentationSemantics.classify(event.kind)
        if event.kind=="cast_start" || event.kind=="enemy_cast_start" || event.kind.contains("telegraph") || event.kind == "enemy_magnet_mark" {
            if event.kind=="cast_start",Self.names.contains(source) {
                if let root=event.rootActionID {
                    _ = partyCastHoldLifecycle.begin(actorID:source,rootActionID:root,qaPoseHeld:heldPartyPose || frameAuditHeld || holdingBattleResult)
                } else {_ = clearPendingPartyCast(source)}
            }
            let plan=effectCues.plan(rootActionID:event.rootActionID,sourceID:event.sourceID)
            if let plan {
                startEffectCue(plan,source:source)
            } else { effectCues.record("unplanned_tell:"+event.kind,root:event.rootActionID ?? "",source:event.sourceID) }
            if case .field(let region)=place { _ = reconcileR04EnvironmentPolicy(region:region) }
            if event.kind == "enemy_magnet_mark",
               plan.flatMap({effectCues.pendingNode(for:$0.key)}) == nil {
                // Capacity suppression still gets a brief notice, owned by this
                // action so cancellation or impact cannot leave stale text.
                statusLabel("磁印",at:target,name:event.rootActionID.map{MagnetMarkIndicator.noticeName(rootID:$0)})
            }
            pose(source,"anticipate");return
        }
        if event.kind=="cast_interrupt",Self.names.contains(target),
           partyCastHoldLifecycle.interrupt(actorID:target,terminalEventRootActionID:event.rootActionID) {pose(target,"recover")}
        if classification == .damage,Self.names.contains(target) {_ = partyCastHoldLifecycle.hit(actorID:target)}
        if Self.names.contains(source),let root=event.rootActionID,
           partyCastHoldLifecycle.commit(actorID:source,rootActionID:root,eventKind:event.kind) {
            let existingCommitPresentation=classification == .damage || classification == .healing || (classification == .barrier && event.kind != "barrier_absorb")
            if !existingCommitPresentation {pose(source,"execute")}
        }
        if ["cast_interrupt","enemy_magnet_target_lost","enemy_hit"].contains(event.kind),let root=event.rootActionID {
            for notice in children where notice.name==MagnetMarkIndicator.noticeName(rootID:root) {
                notice.removeAllActions();notice.removeFromParent()
            }
            if PursuitSuppressionNotice.contains(rootID: root, in: self) {
                pursuitNoticeRenderObserverR092?.recordRemoval(
                    rootID: root, reason: event.kind, sceneFrame: frames,
                    sceneTime: clock, spriteKitTime: last, sceneGeneration: sceneGeneration)
            }
            _ = PursuitSuppressionNotice.remove(rootID:root,from:self)
        }
        if event.kind == "cast_interrupt" {
            // Party→enemy interrupts carry the interrupted enemy's root and target.
            // Enemy→party interruption cues keep their distinct source/event binding.
            effectCues.cancel(rootActionID:event.rootActionID,sourceID:event.targetID,reason:event.kind)
        }
        if event.kind == "enemy_magnet_target_lost" {
            effectCues.cancel(rootActionID:event.rootActionID,sourceID:event.sourceID,reason:event.kind)
            pose(source,"recover")
        }
        if ["cast_interrupt","enemy_magnet_target_lost"].contains(event.kind), case .field(let region)=place {
            _ = reconcileR04EnvironmentPolicy(region:region)
        }
        presentCombatEffect(event,source:source,target:target)
        let heal=classification == .healing
        if event.kind=="lamp_support",let prop=figures[source],let flare=texture("PROP_LAMP__2"),let rest=texture("PROP_LAMP__0"){prop.run(.sequence([.setTexture(flare),.wait(forDuration:0.18),.setTexture(rest)]),withKey:"lamp_heal")}
        if classification == .damage || heal {
            if let before=hp[target]{setHP(target,min(maxHP[target] ?? Int.max,before+(heal ? event.amount:-event.amount)))}
            perform(source:source,target:target,kind:heal ? "heal":event.kind,amount:event.amount)
            if heal {
                effectCues.record("healing_feedback:"+event.kind,root:event.rootActionID ?? "",source:event.sourceID,targets:[target])
            }
        } else if classification == .barrier {
            statusLabel(event.kind=="barrier_absorb" ? "防御":"結界",at:target)
            if event.kind != "barrier_absorb" {pose(source,"execute")}
        } else {
            let labels=["mark":"標的","cover_stance":"守護","guard":"防御","enemy_guard_stance":"守護態勢","enemy_guard_absorb":"防御","poison_stack":"毒 \(event.amount)","dot_applied":"毒付与","poison_burst":"毒の崩壊","enemy_regen":"再生 \(event.amount)","support_duration_reduced":"結界短縮","enemy_weaken":"弱体","party_weaken":"弱体","party_slow":"減速","cast_interrupt":"中断","party_cast_slow":"詠唱遅延","party_drowse":"眠気","enemy_buff":"高揚","enemy_phase_shift":"形態変化","phase_heat":"蓄熱 \(event.amount)","echo_grant":"共鳴","cover_redirect":"かばう"]
            if let label=labels[event.kind]{statusLabel(label,at:figures[target] != nil ? target:source)}
        }
    }
    private func statusLabel(_ text:String,at id:String,name:String?=nil){guard let node=figures[id] else{return};let label=SKLabelNode(fontNamed:"HiraginoSans-W6");label.name=name;label.text=text;label.fontSize=12;label.fontColor = .systemTeal;label.position=CGPoint(x:node.position.x,y:node.frame.maxY+14);label.zPosition=40;addChild(label);label.run(.sequence([.wait(forDuration:0.45),.fadeOut(withDuration:0.25),.removeFromParent()]))}

    private func effectActorID(_ raw:String)->String {
        let display=actorKey(GameModel.spriteIDs[raw] ?? raw)
        return actorKey(enemyPresentation[display]?.assetKey ?? enemyPresentation[display]?.catalogID ?? display)
    }
    private func displayActorID(_ raw:String)->String { actorKey(GameModel.spriteIDs[raw] ?? raw) }
    private func effectAnchor(_ symbol:String,actorID:String)->CGPoint? {
        guard let actor=figures[actorID] else{return nil}
        let normalized=BattleEffects.symbolicAnchorPoint(symbol,actorID:effectActorID(actorID))
        let local=CGPoint(x:(normalized.x-actor.anchorPoint.x)*actor.size.width,
                          y:(normalized.y-actor.anchorPoint.y)*actor.size.height)
        return actor.convert(local,to:self)
    }
    private func normalizedTargets(_ rawIDs:[String],fallback:String)->[String] {
        let resolved=rawIDs.map(displayActorID)
        // An explicit missing target is an integration error. Do not quietly
        // replace it with a different actor or drop it from an AoE recipient set.
        if !resolved.isEmpty {
            guard resolved.allSatisfy({figures[$0] != nil}) else{return []}
            return Array(NSOrderedSet(array:resolved)) as? [String] ?? resolved
        }
        return figures[fallback] != nil ? [fallback] : []
    }
    private func centroid(_ ids:[String],ground:Bool)->CGPoint? {
        let points=ids.compactMap{id -> CGPoint? in
            guard let node=figures[id] else{return nil}
            return ground ? CGPoint(x:node.position.x,y:(baseline[id]?.y ?? node.position.y)-2)
                          : CGPoint(x:node.position.x,y:node.position.y+node.size.height*0.5)
        }
        guard !points.isEmpty else{return nil}
        return CGPoint(x:points.map{$0.x}.reduce(0,+)/CGFloat(points.count),y:points.map{$0.y}.reduce(0,+)/CGFloat(points.count))
    }
    private func placeEffect(_ node:SKSpriteNode,id:String,source:String,targets:[String],phase:String) -> [String:Any] {
        let anchors=BattleEffects.anchors(id:id),sourceSymbol=anchors["source"] ?? "action_origin",targetSymbol=anchors["target"] ?? "target_center"
        let origin=effectAnchor(sourceSymbol,actorID:source) ?? figures[source]?.position ?? .zero
        let targetCenter=centroid(targets,ground:false) ?? origin
        let targetGround=centroid(targets,ground:true) ?? origin
        let focus:CGPoint
        switch targetSymbol {
        case "ground","ground_target_area": focus=targetGround
        case "ground_path": focus=CGPoint(x:(origin.x+targetGround.x)/2,y:targetGround.y)
        case "action_origin": focus=origin
        case "target_status_anchor": focus=targets.first.flatMap{effectAnchor("head_anchor",actorID:$0)} ?? targetCenter
        case "target_fan_area","target_area","adjacent_enemy","target_ally_and_target_enemy": focus=targetCenter
        default: focus=targetCenter
        }
        if var registered=TransferPathGeometry.apply(to:node,id:id,origin:origin,destination:focus) {
            // These two support actions have one explicit recipient. Do not
            // guess a badge owner if a future action supplies multiple targets.
            if targets.count==1,let recipient=targets.first.flatMap({figures[$0]}) {
                let bounds=recipient.calculateAccumulatedFrame()
                let point=CGPoint(x:bounds.midX,y:bounds.minY-TransferPathGeometry.noticeHeight/2-6)
                registered.merge(TransferPathGeometry.registerNoticeAnchor(on:node,point:point)){_,new in new}
            }
            return ["sourceAnchor":sourceSymbol,"targetAnchor":targetSymbol,
                    "cueX":origin.x,"cueY":origin.y,"impactX":focus.x,"impactY":focus.y]
                .merging(registered){_,new in new}
        }
        let pos=phase=="cue" ? origin:focus
        node.position=pos
        let dx=focus.x-origin.x,dy=focus.y-origin.y
        let directional=["ground_path","target_fan_area","target_area","target_status_anchor","adjacent_enemy","target_ally_and_target_enemy"]
        let followsPath=directional.contains(targetSymbol) || id.contains("charge") || id.contains("silk") || id.contains("arc") || id.contains("fan") || id.contains("transfer") || id.contains("unbind") || id.contains("pursuit")
        if followsPath && (abs(dx)+abs(dy))>1 {node.zRotation=atan2(dy,dx);node.xScale=min(2.1,max(1.0,hypot(dx,dy)/136))}
        else {node.zRotation=0;node.xScale=1}
        node.yScale=1
        return ["sourceAnchor":sourceSymbol,"targetAnchor":targetSymbol,"cueX":origin.x,"cueY":origin.y,"impactX":focus.x,"impactY":focus.y,"rotation":node.zRotation,"scaleX":node.xScale]
    }
    private func startEffectCue(_ plan:EffectCueCoordinator.Plan,source:String) {
        if effectCues.emitted.contains(plan.rootActionID+"|"+plan.sourceID) {
            effectCues.record("dedupe",root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID);return
        }
        let targets=normalizedTargets(plan.cueTargetIDs,fallback:source)
        guard figures[source] != nil, !targets.isEmpty else {
            effectCues.record("missing_target:cue",root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID,targets:plan.cueTargetIDs)
            return
        }
        guard let node=BattleEffects.makeNode(id:plan.effectID) else{artAudit["effect_"+plan.effectID]=false;return}
        let active=children.filter{$0.name?.hasPrefix("combat_effect:")==true}
        if active.count >= 2 {
            // A tell has priority over an already playing transient pulse. Held tells
            // cannot evict each other, and the two-node rendering budget stays intact.
            if let transient=active.first(where:{node in !effectCues.pendingNodes.values.contains(where:{$0 === node})}) {
                effectCues.record("preempted_for_cue",root:transient.userData?["effectRootID"] as? String ?? "",source:transient.userData?["effectSourceID"] as? String ?? "",effect:transient.userData?["effectID"] as? String ?? "")
                transient.removeAllActions();transient.removeFromParent()
            } else {
                effectCues.record("capacity_suppressed:cue",root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID)
                // Only the authored R04_01 multi-enemy follow-up gets this
                // fallback. Ordinary attacks remain quiet when their particle
                // cue is suppressed, and the two-node cap is unchanged.
                if plan.sourceArtID == "ACT_E_R04_01",
                   plan.rootActionID.contains(":followup:"),
                   targets.count == 1,
                   targets[0] != source,
                   let recipient = figures[targets[0]] {
                    let noticeObstacles = pursuitNoticeObstacleNodes(excluding: targets[0])
                    let installed = PursuitSuppressionNotice.install(
                        on:recipient,in:self,obstacleNodes:noticeObstacles,
                        rootID:plan.rootActionID,sourceID:plan.sourceID,targetID:targets[0])
                    if installed {
                        if pursuitNoticeRenderObserverR092 == nil {
                            pursuitNoticeRenderObserverR092 = PursuitNoticeRenderObserverR092(
                                arguments: ProcessInfo.processInfo.arguments)
                        }
                        pursuitNoticeRenderObserverR092?.recordInstall(
                            rootID: plan.rootActionID, sourceID: plan.sourceID,
                            targetID: targets[0], effectID: plan.effectID,
                            sceneFrame: frames, sceneTime: clock,
                            spriteKitTime: last, sceneGeneration: sceneGeneration)
                    }
                    effectCues.record(installed ? "fallback_notice:追撃" : "fallback_notice_deduped:追撃",
                                       root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID,targets:targets)
                }
                return
            }
        }
        // A magnet mark is attached to its intended recipient, without moving
        // either actor. Ordinary attack anticipation remains at the source.
        let placement=placeEffect(node,id:plan.effectID,source:source,targets:targets,
                                  phase:plan.telegraphKind == "enemy_magnet_mark" ? "target_cue":"cue")
        if plan.telegraphKind == "enemy_magnet_mark", let ground=centroid(targets,ground:true) {
            MagnetMarkIndicator.install(on:node,groundOffset:CGPoint(x:ground.x-node.position.x,y:ground.y-node.position.y))
        }
        let identity=plan.rootActionID
        guard effectCues.markEmitted(actionIdentity:identity,effectID:plan.effectID,sourceID:plan.sourceID) else{return}
        node.userData=["effectSourceID":plan.sourceID,"effectRootID":identity,"effectID":plan.effectID]
        effectCues.hold(node,for:plan);addChild(node);BattleEffects.playCue(id:plan.effectID,on:node)
        effectCues.record("cue_placement",root:identity,source:plan.sourceID,effect:plan.effectID,targets:targets,placement:placement)
        effectCounts[plan.effectID,default:0]+=1;artAudit["effect_"+plan.effectID]=true
        peakCombatEffects=max(peakCombatEffects,children.filter{$0.name?.hasPrefix("combat_effect:")==true}.count)
        effectLast=["id":plan.effectID,"source":source,"targetIDs":targets,"event":"cue:"+plan.telegraphKind,"phase":"cue_hold"] .merging(placement){_,new in new}
    }
    private func presentCombatEffect(_ event:CombatEvent,source:String,target:String) {
        let isPrevention = event.kind == "enemy_armor" || event.kind == "enemy_guard_absorb"
        guard !isPrevention || event.amount > 0 else { return }
        let actor=effectActorID(event.sourceID)
        if actor == "ACT_E_R03_04", effectCues.plan(rootActionID:event.rootActionID,sourceID:event.sourceID) == nil {
            if event.kind == "enemy_hit" { effectCues.record("unmarked_magnet_hit",root:event.rootActionID ?? "",source:event.sourceID) }
            return
        }
        let recipients=effectCues.recipients(rootActionID:event.rootActionID,sourceID:event.sourceID)
        if let recipients, !recipients.eventKinds.contains(event.kind),
           BattleEffects.binding(actor:actor)?.eventKinds.contains(event.kind) == true {
            // Same-root recovery/opening notifications cannot redirect or advance an
            // attack. The ordinary presentation path still applies HP and healing cues.
            effectCues.record("semantic_only:"+event.kind,root:event.rootActionID ?? "",source:event.sourceID)
            return
        }
        if let plan=effectCues.plan(rootActionID:event.rootActionID,sourceID:event.sourceID),plan.impactKinds.contains(event.kind),
           let node=effectCues.pendingNode(for:plan.key) {
            let rawTargets=isPrevention ? [event.sourceID] : plan.targetIDs
            let targets=normalizedTargets(rawTargets,fallback:target)
            guard figures[source] != nil, !targets.isEmpty else {
                effectCues.record("missing_target:impact",root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID,targets:rawTargets)
                effectCues.cancel(rootActionID:plan.rootActionID,sourceID:plan.sourceID,reason:"missing_target")
                return
            }
            let placement=placeEffect(node,id:plan.effectID,source:source,targets:targets,phase:"impact")
            effectCues.clearPending(plan.key);BattleEffects.playImpact(id:plan.effectID,on:node)
            effectCues.record("impact_placement",root:plan.rootActionID,source:plan.sourceID,effect:plan.effectID,targets:targets,placement:placement)
            effectLast=["id":plan.effectID,"source":source,"targetIDs":targets,"event":event.kind,"rootActionID":event.rootActionID ?? "","phase":"impact_recover"] .merging(placement){_,new in new}
            return
        }
        guard let id=BattleEffects.combatID(actor:actor,event:event.kind,telegraph:nil) else{return}
        let identity=event.rootActionID ?? "tick:\(event.timestampMs ?? event.tick*1000)"
        if effectCues.emitted.contains(identity+"|"+event.sourceID) {
            effectCues.record("dedupe",root:identity,source:event.sourceID,effect:id);return
        }
        // Prevention cues belong to the defending enemy. CombatEvent.targetID remains the
        // attacking ally for diagnostics; the shell pulse itself must stay on its source.
        let visualTargetIDs = isPrevention ? [event.sourceID] : (recipients?.targetIDs ?? [event.targetID])
        let targets=normalizedTargets(visualTargetIDs,fallback:target)
        guard figures[source] != nil, !targets.isEmpty else {
            effectCues.record("missing_target:direct",root:identity,source:event.sourceID,effect:id,targets:visualTargetIDs)
            return
        }
        if isPrevention,let node=children.first(where:{candidate in candidate.name=="combat_effect:"+id && (candidate.userData?["effectSourceID"] as? String)==event.sourceID && (candidate.userData?["effectEventKind"] as? String)==event.kind && !effectCues.pendingNodes.values.contains(where:{$0 === candidate})}) as? SKSpriteNode {
            guard effectCues.markEmitted(actionIdentity:identity,effectID:id,sourceID:event.sourceID) else{return}
            let placement=placeEffect(node,id:id,source:source,targets:targets,phase:"impact")
            node.userData?["effectRootID"]=identity
            BattleEffects.playAll(id:id,on:node);effectCounts[id,default:0]+=1
            effectCues.record("coalesced:"+event.kind,root:identity,source:event.sourceID,effect:id,targets:targets,placement:placement)
            effectLast=["id":id,"source":source,"targetIDs":targets,"event":event.kind,"rootActionID":identity,"phase":"coalesced_full"] .merging(placement){_,new in new}
            return
        }
        guard children.filter({$0.name?.hasPrefix("combat_effect:")==true}).count < 2 else {
            effectCues.record("capacity_suppressed:"+event.kind,root:identity,source:event.sourceID,effect:id,targets:targets);return
        }
        guard effectCues.markEmitted(actionIdentity:identity,effectID:id,sourceID:event.sourceID),let node=BattleEffects.makeNode(id:id) else{return}
        node.userData=["effectSourceID":event.sourceID,"effectRootID":identity,"effectID":id,"effectEventKind":event.kind]
        let placement=placeEffect(node,id:id,source:source,targets:targets,phase:"impact")
        addChild(node);BattleEffects.playAll(id:id,on:node);effectCounts[id,default:0]+=1;artAudit["effect_"+id]=true
        peakCombatEffects=max(peakCombatEffects,children.filter{$0.name?.hasPrefix("combat_effect:")==true}.count)
        effectCues.record("direct_full:"+event.kind,root:identity,source:event.sourceID,effect:id,targets:targets,placement:placement)
        effectLast=["id":id,"source":source,"targetIDs":targets,"event":event.kind,"rootActionID":identity,"phase":"direct_full"] .merging(placement){_,new in new}
    }
    func finishCombatEffects() async {
        // Do not let an unresolved fallback notice survive into the result UI
        // while transient particles finish their existing cleanup window.
        pursuitNoticeRenderObserverR092?.recordLifecycleRemoval(
            groups: pursuitNoticeGroupsR092(), reason: "FINISH_COMBAT_EFFECTS",
            sceneFrame: frames, sceneTime: clock, spriteKitTime: last,
            sceneGeneration: sceneGeneration)
        PursuitSuppressionNotice.removeAll(from:self)
        let active=children.contains{$0.name?.hasPrefix("combat_effect:")==true}
        if active {try? await Task.sleep(for:.milliseconds(820))}
        clearCombatEffects()
        pursuitNoticeRenderObserverR092?.requestBattleEnd(
            sceneFrame: frames, sceneGeneration: sceneGeneration,
            activeGroups: pursuitNoticeGroupsR092())
    }
    private func clearCombatEffects() {
        effectCues.finish()
        pursuitNoticeRenderObserverR092?.recordLifecycleRemoval(
            groups: pursuitNoticeGroupsR092(), reason: "CLEAR_COMBAT_EFFECTS",
            sceneFrame: frames, sceneTime: clock, spriteKitTime: last,
            sceneGeneration: sceneGeneration)
        PursuitSuppressionNotice.removeAll(from:self)
        if case .field(let region)=place { _ = reconcileR04EnvironmentPolicy(region:region) }
        for node in children where node.name?.hasPrefix("combat_effect:")==true {node.removeAllActions();node.removeFromParent()}
    }
    private func appearance(_ id:String,_ state:String)->String {
        if id=="LUNA",let gear=cosmetics["APPRENTICE_BOOK_GEAR"],let first=LunaBookMotion.frames(state:state,gearID:gear)?.first {return first.bodyAssetID}
        guard id=="ERNA" else{return id+"__"+state}
        if cosmetics["C_WITCH"]=="ERNA_TRAVEL" {return "ERNA_TRAVEL__"+state}
        if hasSeparateWitchWeapon {return "ERNA_STANDARD_BODY__"+state}
        return id+"__"+state
    }
    private func attachStaff(to node:SKSpriteNode){
        let assetID=cosmetics["WITCH_WEAPON"] ?? "STAFF_BRANCH"
        guard let t=texture(assetID)else{return}
        let n=SKSpriteNode(texture:t);let h=node.size.height*0.98;n.size=CGSize(width:h*t.size().width/t.size().height,height:h);n.anchorPoint=CGPoint(x:assetID=="STAFF_MOON" ? 0.451:0.547,y:0.50);n.zPosition = 1;n.name="weapon_attachment";n.userData=NSMutableDictionary();n.userData?["qaTextureAssetID"]=assetID;node.addChild(n)
        let hand=SKCropNode();hand.name="weapon_hand";hand.zPosition=2
        let copy=SKSpriteNode(texture:node.texture);copy.size=node.size;copy.anchorPoint=node.anchorPoint;hand.addChild(copy)
        let mask=SKShapeNode(ellipseOf:CGSize(width:node.size.width*0.095,height:node.size.height*0.07));mask.fillColor = .white;mask.strokeColor = .clear;mask.position=CGPoint(x:node.size.width * -0.13,y:node.size.height*0.34);hand.maskNode=mask;node.addChild(hand)
    }
    private func syncWeapon(_ node:SKSpriteNode,state:String,handOverride:CGPoint?=nil,angleOverride:CGFloat?=nil) {
        guard let weapon=node.childNode(withName:"weapon_attachment"),let hand=node.childNode(withName:"weapon_hand") as? SKCropNode else{return}
        let points:[String:CGPoint] = ["idle":.init(x:0.37,y:0.38),"anticipate":.init(x:0.245,y:0.39),"execute":.init(x:0.856,y:0.487),"recover":.init(x:0.48,y:0.45),"hit":.init(x:0.58,y:0.44),"resolve":.init(x:0.31,y:0.58)]
        let standard:[String:CGPoint]=["idle":.init(x:158,y:149),"anticipate":.init(x:181,y:132),"execute":.init(x:194,y:123),"recover":.init(x:138,y:168),"hit":.init(x:163,y:165),"resolve":.init(x:181,y:129)]
        let travel=cosmetics["C_WITCH"]=="ERNA_TRAVEL"
        let pixel=standard[state] ?? CGPoint(x:158,y:149)
        let p=handOverride ?? layeredHand?.0 ?? (travel ? (points[state] ?? CGPoint(x:0.37,y:0.38)):CGPoint(x:pixel.x/256,y:1-pixel.y/256))
        let at=CGPoint(x:(p.x-node.anchorPoint.x)*node.size.width,y:(p.y-node.anchorPoint.y)*node.size.height)
        let angle:CGFloat
        if state=="execute" {angle = -0.45}
        else if state=="recover" {angle = travel ? 0.70:-0.50}
        else if state=="hit" {angle = -0.35}
        else {angle = travel ? 0.38:0.08}
        weapon.position=at;weapon.zRotation=angleOverride ?? layeredHand?.1 ?? angle;hand.maskNode?.position=at
        if let copy=hand.children.first as? SKSpriteNode {copy.texture=node.texture;copy.size=node.size;copy.anchorPoint=node.anchorPoint}
    }
    private func ambient(){
        for i in 0..<14 {let f=SKShapeNode(circleOfRadius:CGFloat(i%3+1)*0.5);f.fillColor=UIColor(red:0.94,green:0.83,blue:0.50,alpha:0.45);f.strokeColor = .clear;f.position=CGPoint(x:CGFloat((i*73+29)%397)/397*size.width,y:CGFloat((i*117+41)%601)/601*size.height);f.zPosition=15;addChild(f);let a=SKAction.sequence([.group([.moveBy(x:CGFloat(i%2==0 ? 12:-12),y:16,duration:Double(3+i%4)),.fadeAlpha(to:0.06,duration:3)]),.group([.moveBy(x:CGFloat(i%2==0 ? -12:12),y:-16,duration:Double(3+i%4)),.fadeAlpha(to:0.45,duration:3)])]);f.run(.repeatForever(a))}
    }
    private func reconcileR04EnvironmentPolicy(region:String) -> Bool {
        let owned=children.filter{($0.name ?? "").hasPrefix("environment_effect:ENV_R04_") && ($0.userData?["environmentOwner"] as? String)=="R04"}
        return r04EnvironmentPolicy.reconcile(region:region,cueNodeCount:effectCues.pendingNodes.count,nodes:owned)
    }
    private func updateEnvironment(region:String) {
        // R04 reuses its authored ENV_R04_* emitters. Hide only those owned nodes
        // while a cue is held; leave their loop actions intact for clean restore.
        if reconcileR04EnvironmentPolicy(region:region) { return }
        // Two low-opacity emitters at a time; the third authored motif rotates in.
        let cycle=Int(clock/4)
        guard cycle != environmentCycle else{return};environmentCycle=cycle
        for n in children where n.name?.hasPrefix("environment_effect:")==true {n.removeFromParent()}
        let ids=BattleEffects.environmentIDs(region:region);guard !ids.isEmpty else{return}
        let selectedIDs = region == "R04" ? R04TelegraphEnvironmentPolicy.selectedIDs(ids, cycle: cycle) : (0..<min(2,ids.count)).map { ids[(cycle+$0)%ids.count] }
        for (slot,id) in selectedIDs.enumerated() {
            guard let n=BattleEffects.makeNode(id:id,environment:true) else{artAudit["effect_"+id]=false;continue}
            if region == "R04" { r04EnvironmentPolicy.place(n,id:id,slot:slot,sceneSize:size) }
            else {
                n.setScale(size.width/402 * 1.3)
                n.position=CGPoint(x:size.width*(slot==0 ? 0.16:0.80),y:size.height*(slot==0 ? 0.73:0.34))
            }
            addChild(n);BattleEffects.playEnvironment(id:id,on:n);effectCounts[id,default:0]+=1;artAudit["effect_"+id]=true
        }
        _ = reconcileR04EnvironmentPolicy(region:region)
        peakEnvironmentEffects=max(peakEnvironmentEffects,children.filter{$0.name?.hasPrefix("environment_effect:")==true}.count)
    }
    func auditEffect(_ id:String) {
        // QA calls the same finite emitter renderer, without damage/reward changes.
        guard BattleEffects.entries[id] != nil else{artAudit["effect_"+id]=false;return}
        guard let node=BattleEffects.makeNode(id:id) else{artAudit["effect_"+id]=false;return}
        let placement=placeEffect(node,id:id,source:"ERNA",targets:["LUNA"],phase:"impact")
        addChild(node);BattleEffects.playAll(id:id,on:node);effectCounts[id,default:0]+=1;artAudit["effect_"+id]=true
        peakCombatEffects=max(peakCombatEffects,children.filter{$0.name?.hasPrefix("combat_effect:")==true}.count)
        effectLast=["id":id,"source":"ERNA","target":"LUNA","event":"isolated_effect_audit","phase":"isolated_full"] .merging(placement){_,new in new}
    }
    func actorKey(_ id:String)->String { let u=id.uppercased();if Self.names.contains(u){return u};if u.hasPrefix("ACT_"){return u};return "ACT_"+u }
    func perform(source:String,target:String,kind:String,amount:Int){
        let s=actorKey(source),t=actorKey(target)
        if kind != "heal",amount>0 {WitchAudioCoordinator.shared.play(Self.names.contains(t) ? .hit:.attack)}
        if let motion=enemyMotions[s]{_ = motion.play(.execute,restart:true)}
        if kind != "heal",let motion=enemyMotions[t],(hp[t] ?? 1)>0{_ = motion.play(.hit,restart:true)}
        if let actor=figures[s],Self.names.contains(s) {
            pose(s,"execute")
            let home=baseline[s] ?? actor.position
            let direction:CGFloat=Self.names.contains(s) ? 1:-1
            let move=SKAction.moveBy(x:direction*10,y:2,duration:0.12);move.timingMode = .easeIn
            actor.run(.sequence([move,.move(to:home,duration:0.25)]),withKey:"action")
        }
        if let node=figures[t] {
            let healing=kind=="heal"
            let label=SKLabelNode(fontNamed:"HiraginoSans-W6");label.text=(healing ? "+":"")+(damageNumberDivisor==1 ? String(amount):String(format:"%.1f",Double(amount)/Double(damageNumberDivisor)));label.fontColor=healing ? UIColor(red:0.50,green:1,blue:0.75,alpha:1):UIColor(red:1,green:0.91,blue:0.69,alpha:1);label.fontSize=19;label.position=CGPoint(x:node.position.x,y:node.position.y+node.frame.height*0.55);label.zPosition=40;addChild(label);label.run(.sequence([.group([.moveBy(x:0,y:25,duration:0.8),.fadeOut(withDuration:0.8)]),.removeFromParent()]))
            if !healing && Self.names.contains(t) {pose(t,"hit");node.run(.sequence([.colorize(with:.white,colorBlendFactor:0.6,duration:0.04),.colorize(with:.white,colorBlendFactor:0,duration:0.16)]))}
            let ring=SKShapeNode(circleOfRadius:healing ? 25:12);ring.strokeColor=healing ? .systemMint:.systemYellow;ring.glowWidth=2;ring.position=CGPoint(x:node.position.x,y:node.position.y+node.frame.height*0.32);ring.zPosition=30;addChild(ring);ring.run(.sequence([.group([.scale(to:1.7,duration:0.3),.fadeOut(withDuration:0.3)]),.removeFromParent()]))
        }
    }
    override func update(_ currentTime: TimeInterval){
        if last==0{last=currentTime}
        let previousTime=last
        let rawDelta=max(0,currentTime-previousTime)
        gatherTraceRawDelta=rawDelta
        gatherFrameTrace?.sample(phase:"update",sceneTime:currentTime,rawDelta:rawDelta,scene:self,node:gatherNode)
        let delta=min(0.1,rawDelta)
        if frameStallTelemetry.enabled && rawDelta>=FrameStallTelemetry.thresholdSeconds {
            frameStallTelemetry.recordStall(rawDelta:rawDelta,clampedDelta:delta,sceneTimeBefore:previousTime,sceneTimeAfter:currentTime,previous:previousFrameTelemetryContext,current:currentArtTelemetryContext)
        }
        last=currentTime;previousFrameTelemetryContext=currentArtTelemetryContext;clock+=delta;frames+=1;maxFrameDelta=max(maxFrameDelta,rawDelta)
        RuntimeMetrics.shared.frame(delta:rawDelta,time:currentTime,nodeCount:children.count,context:String(describing:place))
        if case .field(let region)=place {updateEnvironment(region:region)}
        for (id,n) in figures {
            if let track=hpTracks[id],let bar=hpBars[id] {track.position=CGPoint(x:n.position.x,y:n.frame.maxY+5);bar.position=CGPoint(x:n.position.x-20,y:n.frame.maxY+3)}
            if enemyMotions[id] != nil || enemyPresentation[id]?.kind=="prop" {continue}
            if frameAuditHeld,frameAuditRequest?.actor==id {continue}
            partyShadows[id]?.position=n.position
            let detailHand=id=="ERNA" ? layeredHand?.0:(id=="LUNA" ? lunaBookHand:nil)
            let detailState=n.action(forKey:"party_walk_clip") != nil ? "walk":poses[id]?.0 ?? "idle"
            for (gear,loaded) in EquipmentDetailRenderer.update(actor:id,state:detailState,on:n,equipment:cosmetics,hand:detailHand) {artAudit["detail_"+gear+":"+detailState]=loaded}
            if n.action(forKey:"party_walk_clip") != nil {continue}
            let p=poses[id] ?? ("idle",clock);let elapsed=clock-p.1
            let heldCastAnticipate=p.0=="anticipate" && partyCastHoldLifecycle.isHoldingAnticipate(actorID:id,state:p.0)
            if !heldPartyPose && !holdingBattleResult && !heldCastAnticipate && p.0 != "idle" && p.0 != "resolve" && elapsed>0.35 {let next=p.0=="execute" ? "recover":"idle";pose(id,next)}
            if id=="LUNA",case .home=place,FurniturePresentationR094.hasBotanicalDesk(furniture) {
                let sequence=[0,0,0,0,1,0,0,2,2,0,3,0];let frame=sequence[Int(clock*2)%sequence.count]
                if let tex=texture("LUNA_READING__\(frame)"){n.texture=tex;(readingHands?.children.first as? SKSpriteNode)?.texture=tex;ActorBodyFrame.record("LUNA_READING__\(frame)",index:frame,on:n)}
            }
            if id=="ERNA" {syncWeapon(n,state:poses[id]?.0 ?? "idle")}
            n.warpGeometry=((id=="ERNA" && layeredHand != nil) || (id=="LUNA" && lunaBookHand != nil)) ? nil:CharacterMotion.grid(actor:id,state:poses[id]?.0 ?? "idle",elapsed:elapsed,clock:clock)
        }
    }
    override func didEvaluateActions() {
        gatherFrameTrace?.sample(phase:"afterActions",sceneTime:last,rawDelta:gatherTraceRawDelta,scene:self,node:gatherNode)
    }
}
