import Foundation
import CryptoKit
import SpriteKit

/// Presentation-only, simulator QA. It feeds synthetic CombatEvents to the
/// current LivingScene; it never dispatches GameEngine commands or edits saves.
@MainActor extension GameModel {
    func runEffectBudgetRegressionIfRequested() {
        #if targetEnvironment(simulator)
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("--qa-isolated"),
              args.contains("--qa-effect-budget-regression"),
              let rawKey=args.first(where:{$0.hasPrefix("--qa-save-key=")}),
              let saveURL, saveURL.lastPathComponent.hasPrefix("qa-") else{return}
        let folder=saveURL.deletingLastPathComponent()
        let key=String(rawKey.dropFirst("--qa-save-key=".count)).filter{$0.isLetter || $0.isNumber || $0=="-"}
        let reportURL=folder.appendingPathComponent("effect_budget_regression_\(key).json")
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(500))
            let initialState=state
            let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
            let initialSnapshot=(try? encoder.encode(initialState)) ?? Data()
            let initialSave=(try? Data(contentsOf:saveURL)) ?? Data()
            let initialRevision=state.revision
            var cases:[[String:Any]]=[]
            let began=ISO8601DateFormatter().string(from:Date())

            func event(_ kind:String,_ source:String,_ target:String,_ amount:Int,_ root:String,_ time:Int)->CombatEvent {
                CombatEvent(tick:time/1000,kind:kind,sourceID:source,targetID:target,amount:amount,
                            rootActionID:root,timestampMs:time)
            }
            func metadata(_ ids:[String])->CombatResult {
                let hp=Dictionary(uniqueKeysWithValues:ids.map{($0,10_000)})
                let map=Dictionary(uniqueKeysWithValues:ids.map { id in
                    (id,CombatEntityPresentation(entityID:id,kind:"enemy",catalogID:id,
                                                 label:id,assetKey:"ACT_"+id))
                })
                return CombatResult(won:false,ticks:0,events:[],remainingPartyHP:[:],
                                    initialEnemyHP:hp,remainingEnemyHP:hp,entityPresentation:map)
            }
            @MainActor func resetScene(_ ids:[String],events:[CombatEvent]) {
                scene.setEnemies(ids)
                let fixture=metadata(ids)
                scene.prepareCombatEntities(fixture)
                let partyHP=Dictionary(uniqueKeysWithValues:["C_WITCH","C_APPRENTICE","C_SMITH","C_FAMILIAR"].map{($0,10_000)})
                scene.beginBattle(partyHP:partyHP,enemyHP:fixture.initialEnemyHP)
                scene.prepareCombatEffects(events)
            }
            @MainActor func auditValue()->[String:Any] {
                guard let data=scene.artAuditJSON().data(using:.utf8),
                      let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return [:]}
                return obj
            }
            func trace(_ audit:[String:Any])->[[String:Any]] {
                ((audit["effects"] as? [String:Any])?["cueTrace"] as? [[String:Any]]) ?? []
            }
            func numeric(_ row:[String:Any],_ key:String)->CGFloat? {
                if let number=row[key] as? NSNumber { return CGFloat(number.doubleValue) }
                if let value=row[key] as? String,let parsed=Double(value) { return CGFloat(parsed) }
                return nil
            }
            func close(_ a:CGFloat?,_ b:CGFloat?,_ tolerance:CGFloat=0.05)->Bool {
                guard let a,let b,a.isFinite,b.isFinite else{return false}
                return abs(a-b)<=tolerance
            }
            // The current clip owns its anchor (R050 moth idle changes it per
            // frame). Reconstruct its affine transform from independently
            // recorded node geometry, never from the static art-index anchor.
            @MainActor func expectedAnchor(_ actorID:String,_ symbol:String,_ audit:[String:Any])->CGPoint? {
                guard let geometry=audit["geometry"] as? [String:[String:Any]],
                      let actor=geometry[actorID] else{return nil}
                return EffectAnchorProjectionQA.project(
                    BattleEffects.symbolicAnchorPoint(symbol,actorID:actorID), geometry:actor)
            }
            // LivingScene.centroid(..., ground:false) is intentionally different
            // from the effect's normalized art anchor: it uses node.position plus
            // half the unscaled sprite height. Mirror that production recipient rule.
            @MainActor func expectedRecipientCenter(_ actorID:String,_ audit:[String:Any])->CGPoint? {
                guard let geometry=audit["geometry"] as? [String:[String:Any]],let actor=geometry[actorID],
                      let x=(actor["x"] as? NSNumber)?.doubleValue,
                      let y=(actor["y"] as? NSNumber)?.doubleValue,
                      let height=(actor["height"] as? NSNumber)?.doubleValue else{return nil}
                return CGPoint(x:x,y:y+height*0.5)
            }
            @MainActor func pathChildPoint(_ effectID:String,_ childName:String)->CGPoint? {
                guard let effect=scene.children.first(where:{($0.userData?["effectID"] as? String)==effectID}),
                      let child=effect.childNode(withName:childName) else{return nil}
                return child.convert(.zero,to:scene)
            }
            @MainActor func pathArrivalDiameter(_ effectID:String)->CGFloat? {
                guard let effect=scene.children.first(where:{($0.userData?["effectID"] as? String)==effectID}),
                      let group=effect.childNode(withName:TransferPathGeometry.arrivalNodeName),
                      let rim=group.children.compactMap({$0 as? SKShapeNode}).first(where:{abs($0.lineWidth-1.5)<0.01}) else{return nil}
                let left=rim.convert(CGPoint(x:-7,y:0),to:scene),right=rim.convert(CGPoint(x:7,y:0),to:scene)
                return hypot(right.x-left.x,right.y-left.y)
            }
            @MainActor func supportNoticeSnapshot(_ effectID:String)->[String:Any]? {
                guard let effect=scene.children.first(where:{($0.userData?["effectID"] as? String)==effectID}),
                      let notice=effect.childNode(withName:TransferPathGeometry.noticeNodeName),
                      let backing=notice.children.compactMap({$0 as? SKShapeNode}).first,
                      let path=backing.path else{return nil}
                let rect=path.boundingBox
                let corners=[CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),
                             CGPoint(x:rect.maxX,y:rect.maxY),CGPoint(x:rect.minX,y:rect.maxY)]
                    .map{backing.convert($0,to:scene)}
                let minX=corners.map(\.x).min() ?? .nan,maxX=corners.map(\.x).max() ?? .nan
                let minY=corners.map(\.y).min() ?? .nan,maxY=corners.map(\.y).max() ?? .nan
                let center=notice.convert(CGPoint.zero,to:scene)
                let unitX=notice.convert(CGPoint(x:1,y:0),to:scene)
                let unitY=notice.convert(CGPoint(x:0,y:1),to:scene)
                let labels=notice.children.compactMap{$0 as? SKLabelNode}
                return ["centerX":center.x,"centerY":center.y,"minX":minX,"maxX":maxX,
                        "minY":minY,"maxY":maxY,"width":maxX-minX,"height":maxY-minY,
                        "unitXAxisDeltaY":unitX.y-center.y,"unitYAxisDeltaX":unitY.x-center.x,
                        "labelTexts":labels.compactMap(\.text),"labelCount":labels.count,
                        "noticeOpacity":notice.alpha,"noticeHasActions":notice.hasActions(),
                        "anchorX":(effect.childNode(withName:TransferPathGeometry.noticeAnchorNodeName)?.convert(.zero,to:scene).x ?? .nan),
                        "anchorY":(effect.childNode(withName:TransferPathGeometry.noticeAnchorNodeName)?.convert(.zero,to:scene).y ?? .nan)]
            }
            @MainActor func supportLabelCount(in node:SKNode)->Int {
                let own=(node as? SKLabelNode).flatMap{$0.text=="支援" ? 1:0} ?? 0
                return own+node.children.reduce(0){$0+supportLabelCount(in:$1)}
            }
            @MainActor func expectedSupportNotice(_ actorID:String,_ audit:[String:Any])->CGPoint? {
                guard let geometry=audit["geometry"] as? [String:[String:Any]],let actor=geometry[actorID],
                      let minX=(actor["accumulatedMinX"] as? NSNumber)?.doubleValue,
                      let maxX=(actor["accumulatedMaxX"] as? NSNumber)?.doubleValue,
                      let minY=(actor["accumulatedMinY"] as? NSNumber)?.doubleValue else{return nil}
                return CGPoint(x:(minX+maxX)*0.5,y:minY-TransferPathGeometry.noticeHeight/2-6)
            }
            @MainActor func hasTransferChild(_ node:SKNode)->Bool {
                if [TransferPathGeometry.startNodeName,TransferPathGeometry.endNodeName,
                    TransferPathGeometry.arrivalNodeName,TransferPathGeometry.noticeAnchorNodeName,
                    TransferPathGeometry.noticeNodeName].contains(node.name ?? "") { return true }
                return node.children.contains(where:hasTransferChild)
            }
            @MainActor func append(_ name:String,_ assertions:[String:Bool],_ extra:[String:Any]=[:]) async {
                let raw=auditValue(), effects=raw["effects"] as? [String:Any] ?? [:]
                await scene.finishCombatEffects()
                let cleanup=auditValue(), cleanupEffects=cleanup["effects"] as? [String:Any] ?? [:]
                var checks=assertions
                checks["activeEffectsCleaned"]=(cleanupEffects["activeCombat"] as? Int ?? -1)==0
                checks["pursuitNoticesCleanedAtResultOrReset"]=PursuitSuppressionNotice.count(in:scene)==0
                checks["transferPathChildrenCleanedAfterFinish"] = !scene.children.contains(where:hasTransferChild)
                let row:[String:Any]=["name":name,"assertions":checks,
                    "passed":checks.values.allSatisfy{$0},"peakCombat":effects["peakCombat"] ?? -1,
                    "activeCombatBeforeCleanup":effects["activeCombat"] ?? -1,"artAudit":raw,
                    "cleanupArtAudit":cleanup,"details":extra]
                cases.append(row)
            }
            do {
                guard !initialSave.isEmpty else{throw CoreError.invalidCommand("QA save missing; no fixture will be created by this probe")}
                tab="探索";chosenRegion="R03";syncScene()

                // Three prevented hits from one enemy must retain every root while
                // reusing its transient mist node, with enemy-owned target coordinates.
                let armorRoots=(1...3).map{"synthetic:armor:\($0)"}
                let armorEvents=armorRoots.enumerated().map { i,root in
                    event("enemy_armor","E_R02_02",["C_WITCH","C_SMITH","C_APPRENTICE"][i],7+i,root,100+i*40)
                }
                resetScene(["E_R02_02"],events:armorEvents)
                armorEvents.forEach{scene.present($0)}
                var a=auditValue(), t=trace(a)
                let armorRows=t.filter{(["direct_full:enemy_armor","coalesced:enemy_armor"].contains($0["step"] as? String ?? ""))}
                let represented=Set(armorRows.compactMap{$0["rootActionID"] as? String})==Set(armorRoots)
                let armorTargets=armorRows.allSatisfy{($0["targetIDs"] as? String)=="E_R02_02" || ($0["targetIDs"] as? String)=="ACT_E_R02_02"}
                let coords=armorRows.allSatisfy{row in
                    ["placement.sourceAnchor","placement.targetAnchor","placement.cueX","placement.cueY","placement.impactX","placement.impactY","placement.rotation","placement.scaleX"].allSatisfy{row[$0] != nil}
                }
                let coalesced=armorRows.filter{($0["step"] as? String)=="coalesced:enemy_armor"}.count
                let armorPeak=(a["effects"] as? [String:Any])?["peakCombat"] as? Int ?? -1
                await append("armor_three_roots_coalesce",[
                    "allThreeRootsRepresented":represented,"allVisualTargetsAreEnemy":armorTargets,
                    "allPlacementsRecorded":coords,"coalescesAtLeastTwice":coalesced>=2,
                    "peakAtMostTwo":armorPeak<=2
                ],["roots":armorRoots,"visualRows":armorRows])

                // Five E_R03_03 tell roots: two impacts and three same-root
                // party→enemy cancellations. A cancellation must never advance to impact.
                let enemy="E_R03_03"
                var comboEvents:[CombatEvent]=[]
                let comboRoots=(1...5).map{"synthetic:tool:\($0)"}
                for (i,root) in comboRoots.enumerated() {
                    let start=1_000+i*1_500
                    comboEvents.append(event("enemy_telegraph",enemy,"C_WITCH",1,root,start))
                    comboEvents.append(event("enemy_cast_start",enemy,root,800,root,start))
                    if i<2 {comboEvents.append(event("enemy_hit",enemy,"C_WITCH",12,root,start+800))}
                    else {comboEvents.append(event("cast_interrupt","C_SMITH",enemy,1,root,start+350))}
                }
                comboEvents.sort{($0.timestampMs ?? 0)<($1.timestampMs ?? 0)}
                resetScene([enemy],events:comboEvents);comboEvents.forEach{scene.present($0)}
                a=auditValue();t=trace(a)
                func steps(_ root:String)->[String]{t.filter{($0["rootActionID"] as? String)==root}.compactMap{$0["step"] as? String}}
                let impactRoots=Array(comboRoots.prefix(2)), cancelledRoots=Array(comboRoots.suffix(3))
                let impactOK=impactRoots.allSatisfy{root in let s=steps(root);return s.contains(where:{$0.hasPrefix("cue_hold:")}) && s.contains("impact_advance") && !s.contains(where:{$0.hasPrefix("cue_cancel:")})}
                let cancelOK=cancelledRoots.allSatisfy{root in let s=steps(root);return s.contains(where:{$0.hasPrefix("cue_hold:")}) && s.contains("cue_cancel:cast_interrupt") && !s.contains("impact_advance")}
                let cancelledCueRows=t.filter{cancelledRoots.contains($0["rootActionID"] as? String ?? "") && ($0["step"] as? String)=="cue_placement"}
                let cancelledTargetsPreserved=cancelledCueRows.count==cancelledRoots.count && cancelledCueRows.allSatisfy{
                    // Trace uses the renderer's display actor alias: C_WITCH → ERNA.
                    ($0["targetIDs"] as? String)=="ERNA" && ($0["targetIDs"] as? String ?? "").contains("root") == false
                }
                let comboPeak=(a["effects"] as? [String:Any])?["peakCombat"] as? Int ?? -1
                await append("tool_combo_two_impacts_three_cancels",[
                    "fiveTellRoots":comboRoots.allSatisfy{root in steps(root).contains(where:{$0.hasPrefix("cue_hold:")})},
                    "twoRootsAdvanceToImpact":impactOK,"threeRootsCancelWithoutImpact":cancelOK,
                    "cancelledCueTargetsRemainOriginalVictim":cancelledTargetsPreserved,
                    "peakAtMostTwo":comboPeak<=2
                ],["impactRoots":impactRoots,"cancelledRoots":cancelledRoots,"cancelledCuePlacements":cancelledCueRows])

                // The reverse enemy→party event is not the party→enemy cancellation
                // contract. Its target must not cancel an enemy-held cue.
                let reverseRoot="synthetic:tool:reverse-direction"
                let reverseEvents=[event("enemy_telegraph",enemy,"C_WITCH",1,reverseRoot,10_000),
                                   event("enemy_cast_start",enemy,reverseRoot,800,reverseRoot,10_000),
                                   event("cast_interrupt",enemy,"C_WITCH",1_000,reverseRoot,10_200),
                                   event("enemy_hit",enemy,"C_WITCH",12,reverseRoot,10_800)]
                resetScene([enemy],events:reverseEvents)
                scene.present(reverseEvents[0]);scene.present(reverseEvents[1]);scene.present(reverseEvents[2])
                var reverseAudit=auditValue();var reverseTrace=trace(reverseAudit)
                let noReverseCancel = !reverseTrace.contains{($0["rootActionID"] as? String)==reverseRoot && (($0["step"] as? String ?? "").hasPrefix("cue_cancel:"))}
                scene.present(reverseEvents[3]);reverseAudit=auditValue();reverseTrace=trace(reverseAudit)
                let reverseImpact=reverseTrace.contains{($0["rootActionID"] as? String)==reverseRoot && ($0["step"] as? String)=="impact_advance"}
                await append("enemy_to_party_interrupt_does_not_cancel",[
                    "reverseInterruptKeepsCuePending":noReverseCancel,"laterMatchingHitAdvancesCue":reverseImpact
                ],["root":reverseRoot,"beforeImpactTrace":reverseTrace])

                // An unsupported action family has no visual plan. An unmatched tell
                // without either an impact or a valid cancellation must remain effect-free.
                let unmatchedEnemy="E_R03_04",unmatchedRoot="synthetic:unmatched:no-impact"
                let unmatchedEvent=event("enemy_telegraph",unmatchedEnemy,"C_WITCH",1,unmatchedRoot,11_500)
                resetScene([unmatchedEnemy],events:[unmatchedEvent]);scene.present(unmatchedEvent)
                a=auditValue();t=trace(a)
                let unmatchedTrace=t.filter{($0["rootActionID"] as? String)==unmatchedRoot}
                let noPlanOrEffect = !unmatchedTrace.contains{(($0["step"] as? String ?? "").hasPrefix("cue_hold:") || ($0["step"] as? String ?? "").hasPrefix("direct_full:"))}
                    && ((a["effects"] as? [String:Any])?["activeCombat"] as? Int ?? -1)==0
                await append("unmatched_tell_without_impact_or_interrupt_stays_effect_free",[
                    "noPlanOrEffect":noPlanOrEffect,
                    "unplannedTellIsExplicit":unmatchedTrace.contains{($0["step"] as? String)=="unplanned_tell:enemy_telegraph"}
                ],["enemyID":unmatchedEnemy,"root":unmatchedRoot,"trace":unmatchedTrace])

                // Simulate an expired emitted cue and two unrelated active nodes.
                // Replayed root must dedupe before its capacity path can evict them.
                let duplicateRoot="synthetic:tool:duplicate-after-expiry"
                let duplicateEvents=[event("enemy_telegraph",enemy,"C_WITCH",1,duplicateRoot,12_000),
                                     event("enemy_hit",enemy,"C_WITCH",12,duplicateRoot,12_800)]
                resetScene([enemy],events:duplicateEvents)
                scene.present(duplicateEvents[0]);scene.present(duplicateEvents[1])
                for node in scene.children where (node.userData?["effectRootID"] as? String)==duplicateRoot {
                    node.removeAllActions();node.removeFromParent()
                }
                let slotNames=["combat_effect:synthetic_slot_a","combat_effect:synthetic_slot_b"]
                for name in slotNames {
                    let node=SKSpriteNode(color:.clear,size:CGSize(width:8,height:8));node.name=name;scene.addChild(node)
                }
                scene.present(duplicateEvents[0]);a=auditValue();t=trace(a)
                let stillPresent=slotNames.allSatisfy{name in scene.children.contains{$0.name==name}}
                let deduped=t.contains{($0["rootActionID"] as? String)==duplicateRoot && ($0["step"] as? String)=="dedupe"}
                await append("expired_duplicate_at_capacity_does_not_evict",[
                    "twoUnrelatedNodesRemain":stillPresent,"duplicateRootDeduped":deduped,
                    "activeCountAtMostTwo":((a["effects"] as? [String:Any])?["activeCombat"] as? Int ?? -1)<=2
                ],["root":duplicateRoot,"retainedNodeNames":slotNames])

                // Two pending telegraphs consume the budget; a third is explicitly
                // recorded as suppressed rather than exceeding the two-node ceiling.
                let capIDs=["E_R01_01","E_R02_01",enemy]
                var capEvents:[CombatEvent]=[]
                for (i,id) in capIDs.enumerated() {
                    let root="synthetic:cap:\(i+1)",time=14_000+i*100
                    capEvents.append(event("enemy_telegraph",id,"C_WITCH",1,root,time))
                    capEvents.append(event("enemy_hit",id,"C_WITCH",1,root,time+900))
                }
                resetScene(capIDs,events:capEvents)
                for i in 0..<3 {scene.present(capEvents[i*2])}
                a=auditValue();t=trace(a)
                let thirdRoot="synthetic:cap:3"
                let suppressed=t.contains{($0["rootActionID"] as? String)==thirdRoot && ($0["step"] as? String)=="capacity_suppressed:cue"}
                let held=scene.children.filter{$0.name?.hasPrefix("combat_effect:")==true}.count
                await append("two_held_cues_suppress_third_with_trace",[
                    "thirdCueSuppressionRecorded":suppressed,"activeCountExactlyTwo":held==2,
                    "peakAtMostTwo":((a["effects"] as? [String:Any])?["peakCombat"] as? Int ?? -1)<=2
                ],["thirdRoot":thirdRoot,"heldCount":held])


                // A source-only notification can precede an impact in the same root.
                // It must not advance a held cue or become a fifth AoE recipient.
                let recipients=["C_WITCH","C_FAMILIAR","C_APPRENTICE","C_SMITH"]
                let expectedDisplays=Set(["ERNA","NOIR","LUNA","AIRA"])
                let mixedCases=[("B_R02_B","enemy_scale_opening"),("B_R02_A","enemy_rest"),
                                ("B_R03_A","enemy_rest"),("B_R03_B","enemy_heat_release"),
                                ("E_R05_04","enemy_regen")]
                for (enemy,notification) in mixedCases {
                    let root="synthetic:mixed:"+enemy
                    let tell=event("telegraph_aoe",enemy,"party",1,root,20_000)
                    let status=event(notification,enemy,enemy,7,root,20_100)
                    let hits=recipients.map{event("enemy_hit",enemy,$0,5,root,20_500)}
                    let wound=event("direct","C_WITCH",enemy,100,"synthetic:wound",19_900)
                    let all=[wound,tell,status]+hits
                    resetScene([enemy],events:all)
                    scene.present(wound);scene.present(tell);scene.present(status)
                    let beforeHit=trace(auditValue())
                    let noEarlyImpact = !beforeHit.contains{($0["step"] as? String)=="impact_advance"}
                    hits.forEach{scene.present($0)}
                    a=auditValue();t=trace(a)
                    let placements=t.filter{["cue_placement","impact_placement"].contains($0["step"] as? String ?? "")}
                    let correctRecipients=placements.count==2 && placements.allSatisfy{
                        Set(($0["targetIDs"] as? String ?? "").split(separator:",").map(String.init))==expectedDisplays
                    }
                    let semanticOnly=t.contains{($0["step"] as? String)=="semantic_only:"+notification}
                    var assertions=["notificationDoesNotAdvanceCue":noEarlyImpact,
                        "cueAndImpactUseOnlyFourRecipients":correctRecipients,
                        "notificationExplicitlySeparated":semanticOnly,
                        "oneImpactAdvance":t.filter{($0["step"] as? String)=="impact_advance"}.count==1]
                    if notification=="enemy_regen" {
                        assertions["healingFeedbackRemainsOnSource"]=t.contains{
                            ($0["step"] as? String)=="healing_feedback:enemy_regen" && ($0["targetIDs"] as? String)=="ACT_"+enemy
                        }
                        // Independent fixture expectation: initial 10,000 - wound 100 + heal 7.
                        assertions["healingHPStillApplied"]=scene.hpMismatches(party:[:],enemies:[enemy:9_907]).isEmpty
                    }
                    await append("mixed_root_"+enemy+"_"+notification,assertions,["beforeHitTrace":beforeHit])
                }

                // Untold poison pressure is an AoE too. Aggregating the root must not
                // silently reduce four real recipients to the first dot_applied event.
                let aoeRoot="synthetic:untold:poison"
                let dots=recipients.map{event("dot_applied","B_R05_B",$0,3,aoeRoot,23_000)}
                resetScene(["B_R05_B"],events:dots);dots.forEach{scene.present($0)}
                a=auditValue();t=trace(a)
                let directRows=t.filter{($0["step"] as? String)=="direct_full:dot_applied"}
                await append("untold_poison_pressure_keeps_four_recipients",[
                    "oneVisualRoot":directRows.count==1,
                    "allFourRecipients":directRows.count==1 && Set((directRows[0]["targetIDs"] as? String ?? "").split(separator:",").map(String.init))==expectedDisplays
                ])

                // Legitimate self-support remains a recipient when no external hit
                // occurs in the action. Zero prevention must create no visual root.
                let supportRoot="synthetic:self-support"
                let support=[event("enemy_telegraph","E_R02_04","E_R02_04",1,supportRoot,24_000),
                             event("enemy_magic_support","E_R02_04","E_R02_04",1_500,supportRoot,25_000)]
                resetScene(["E_R02_04"],events:support);support.forEach{scene.present($0)}
                a=auditValue();t=trace(a)
                let supportRows=t.filter{["cue_placement","impact_placement"].contains($0["step"] as? String ?? "")}
                await append("self_support_is_not_discarded",[
                    "selfCueAndImpact":supportRows.count==2 && supportRows.allSatisfy{($0["targetIDs"] as? String)=="ACT_E_R02_04"}
                ])

                // R02's authored mote moves right→left along the support arc.
                // The exact recipient must drive both ends of the transformed
                // texture path; test the actual child nodes in scene coordinates,
                // not only the placement dictionary emitted by the same helper.
                let r02Source="E_R02_04",r02Target="E_R02_02"
                let r02Effect="ACT_E_R02_04_support_arc",r02Root="synthetic:path:r02:recipient"
                let r02Tell=event("enemy_telegraph",r02Source,r02Target,1,r02Root,25_500)
                let r02Impact=event("enemy_magic_support",r02Source,r02Target,1_500,r02Root,26_000)
                resetScene([r02Source,r02Target],events:[r02Tell,r02Impact])
                // Cue placement runs before requesting the anticipate pose.
                // Capture independent pre-event geometry for the
                // cue expectation; the later impact is intentionally checked
                // against the post-anticipate geometry used at impact time.
                let r02PreCueAudit=auditValue()
                let r02Anchors=BattleEffects.anchors(id:r02Effect)
                let r02CueExpectedStart=expectedAnchor("ACT_"+r02Source,r02Anchors["source"] ?? "",r02PreCueAudit)
                let r02CueExpectedEnd=expectedRecipientCenter("ACT_"+r02Target,r02PreCueAudit)
                scene.present(r02Tell)
                var pathAudit=auditValue(),pathTrace=trace(pathAudit)
                let r02Cue=pathTrace.first{$0["rootActionID"] as? String==r02Root && ($0["step"] as? String)=="cue_placement"} ?? [:]
                let r02PreImpactSourceGeometry=(pathAudit["geometry"] as? [String:[String:Any]])?["ACT_"+r02Source] ?? [:]
                let r02ExpectedStart=expectedAnchor("ACT_"+r02Source,r02Anchors["source"] ?? "",pathAudit)
                let r02ExpectedEnd=expectedRecipientCenter("ACT_"+r02Target,pathAudit)
                let r02CueStart=pathChildPoint(r02Effect,TransferPathGeometry.startNodeName)
                let r02CueEnd=pathChildPoint(r02Effect,TransferPathGeometry.endNodeName)
                let r02CuePathRegistered=(r02Cue["placement.transferPathRegistered"] as? String)=="true"
                let r02CuePixels=close(numeric(r02Cue,"placement.pathSourcePixelX"),94) && close(numeric(r02Cue,"placement.pathSourcePixelY"),59)
                    && close(numeric(r02Cue,"placement.pathTargetPixelX"),31) && close(numeric(r02Cue,"placement.pathTargetPixelY"),58)
                let r02CueConverted=close(r02CueStart?.x,r02CueExpectedStart?.x) && close(r02CueStart?.y,r02CueExpectedStart?.y)
                    && close(r02CueEnd?.x,r02CueExpectedEnd?.x) && close(r02CueEnd?.y,r02CueExpectedEnd?.y)
                    && close(numeric(r02Cue,"placement.pathExpectedStartX"),r02CueExpectedStart?.x)
                    && close(numeric(r02Cue,"placement.pathExpectedStartY"),r02CueExpectedStart?.y)
                    && close(numeric(r02Cue,"placement.pathExpectedEndX"),r02CueExpectedEnd?.x)
                    && close(numeric(r02Cue,"placement.pathExpectedEndY"),r02CueExpectedEnd?.y)
                    && close(numeric(r02Cue,"placement.pathStartX"),r02CueStart?.x)
                    && close(numeric(r02Cue,"placement.pathStartY"),r02CueStart?.y)
                    && close(numeric(r02Cue,"placement.pathEndX"),r02CueEnd?.x)
                    && close(numeric(r02Cue,"placement.pathEndY"),r02CueEnd?.y)
                let noPrematureArrival=scene.children.first(where:{($0.userData?["effectID"] as? String)==r02Effect})?.childNode(withName:TransferPathGeometry.arrivalNodeName)==nil
                let r02CueNoSupportNotice=scene.children.first(where:{($0.userData?["effectID"] as? String)==r02Effect})?.childNode(withName:TransferPathGeometry.noticeNodeName)==nil
                    && scene.children.first(where:{($0.userData?["effectID"] as? String)==r02Effect})?.childNode(withName:TransferPathGeometry.noticeAnchorNodeName) != nil
                scene.present(r02Impact)
                pathAudit=auditValue();pathTrace=trace(pathAudit)
                let r02ImpactRow=pathTrace.first{$0["rootActionID"] as? String==r02Root && ($0["step"] as? String)=="impact_placement"} ?? [:]
                let r02ImpactStart=pathChildPoint(r02Effect,TransferPathGeometry.startNodeName)
                let r02ImpactEnd=pathChildPoint(r02Effect,TransferPathGeometry.endNodeName)
                let r02Arrival=scene.children.first(where:{($0.userData?["effectID"] as? String)==r02Effect} )?.childNode(withName:TransferPathGeometry.arrivalNodeName)
                let r02ArrivalDiameter=pathArrivalDiameter(r02Effect)
                let r02Notice=supportNoticeSnapshot(r02Effect)
                let r02NoticeExpected=expectedSupportNotice("ACT_"+r02Target,pathAudit)
                let r02TargetGeometry=(pathAudit["geometry"] as? [String:[String:Any]])?["ACT_"+r02Target] ?? [:]
                let r02NoticeSingleLabel=(r02Notice?["labelCount"] as? Int)==1 && (r02Notice?["labelTexts"] as? [String])==["支援"]
                let r02NoticeFrame=close(numeric(r02Notice ?? [:],"width"),34,0.2) && close(numeric(r02Notice ?? [:],"height"),20,0.2)
                    && abs(numeric(r02Notice ?? [:],"unitXAxisDeltaY") ?? .infinity)<0.02
                    && abs(numeric(r02Notice ?? [:],"unitYAxisDeltaX") ?? .infinity)<0.02
                let r02NoticePlacement=close(numeric(r02Notice ?? [:],"centerX"),r02NoticeExpected?.x)
                    && close(numeric(r02Notice ?? [:],"centerY"),r02NoticeExpected?.y)
                    && close(numeric(r02ImpactRow,"placement.pathNoticeX"),r02NoticeExpected?.x)
                    && close(numeric(r02ImpactRow,"placement.pathNoticeY"),r02NoticeExpected?.y)
                    && close(numeric(r02Notice ?? [:],"maxY"), (r02TargetGeometry["accumulatedMinY"] as? NSNumber).map{CGFloat($0.doubleValue-6)})
                let r02ImpactConverted=close(r02ImpactStart?.x,r02ExpectedStart?.x) && close(r02ImpactStart?.y,r02ExpectedStart?.y)
                    && close(r02ImpactEnd?.x,r02ExpectedEnd?.x) && close(r02ImpactEnd?.y,r02ExpectedEnd?.y)
                    && close(numeric(r02ImpactRow,"placement.pathExpectedStartX"),r02ExpectedStart?.x)
                    && close(numeric(r02ImpactRow,"placement.pathExpectedStartY"),r02ExpectedStart?.y)
                    && close(numeric(r02ImpactRow,"placement.pathExpectedEndX"),r02ExpectedEnd?.x)
                    && close(numeric(r02ImpactRow,"placement.pathExpectedEndY"),r02ExpectedEnd?.y)
                    && close(numeric(r02ImpactRow,"placement.pathStartX"),r02ImpactStart?.x)
                    && close(numeric(r02ImpactRow,"placement.pathStartY"),r02ImpactStart?.y)
                    && close(numeric(r02ImpactRow,"placement.pathEndX"),r02ImpactEnd?.x)
                    && close(numeric(r02ImpactRow,"placement.pathEndY"),r02ImpactEnd?.y)
                await append("r02_magic_support_arc_recipient_path",[
                    "cueAndImpactSourceEffectAndTargetAreExact":r02Cue["sourceID"] as? String==r02Source && r02ImpactRow["sourceID"] as? String==r02Source
                        && r02Cue["effectID"] as? String==r02Effect && r02ImpactRow["effectID"] as? String==r02Effect
                        && r02Cue["targetIDs"] as? String=="ACT_"+r02Target && r02ImpactRow["targetIDs"] as? String=="ACT_"+r02Target,
                    "authoredRightToLeftSourceAnchors":r02CuePixels,
                    "cuePathUsesRegisteredTransform":r02CuePathRegistered && r02CueConverted,
                    "impactPathUsesRegisteredTransform":(r02ImpactRow["placement.transferPathRegistered"] as? String)=="true" && r02ImpactConverted,
                    "arrivalAccentOnlyAtImpactAndSevenPointRadius":noPrematureArrival && r02Arrival != nil && close(r02ArrivalDiameter,14,0.2),
                    "supportLabelAppearsOnlyAtImpact":r02CueNoSupportNotice && r02Notice != nil,
                    "supportLabelTextAndSingleInstance":r02NoticeSingleLabel,
                    "supportLabelUprightAnd34By20":r02NoticeFrame,
                    "supportLabelSixPointBelowRecipientBounds":r02NoticePlacement,
                    "usesOnlyOneCombatBudgetNode":((pathAudit["effects"] as? [String:Any])?["peakCombat"] as? Int)==1
                ],["preCueSourceGeometry":(r02PreCueAudit["geometry"] as? [String:[String:Any]])?["ACT_"+r02Source] ?? [:],
                   "preImpactSourceGeometry":r02PreImpactSourceGeometry,
                   "cuePlacement":r02Cue,"impactPlacement":r02ImpactRow,"cueExpectedStart":r02CueExpectedStart.map{[$0.x,$0.y]} ?? [],
                   "cueExpectedEnd":r02CueExpectedEnd.map{[$0.x,$0.y]} ?? [],"impactExpectedStart":r02ExpectedStart.map{[$0.x,$0.y]} ?? [],
                   "expectedEnd":r02ExpectedEnd.map{[$0.x,$0.y]} ?? [],"actualCueStart":r02CueStart.map{[$0.x,$0.y]} ?? [],
                   "actualCueEnd":r02CueEnd.map{[$0.x,$0.y]} ?? [],"actualImpactStart":r02ImpactStart.map{[$0.x,$0.y]} ?? [],
                   "actualImpactEnd":r02ImpactEnd.map{[$0.x,$0.y]} ?? [],"arrivalDiameter":r02ArrivalDiameter ?? -1,
                   "supportNotice":r02Notice ?? [:],"supportNoticeExpected":r02NoticeExpected.map{[$0.x,$0.y]} ?? []])

                // R05's light dot also moves right→left. Its authored segment is
                // diagonal; the transformed line must reach the adjacent target
                // without inventing a hit event or changing recipient selection.
                let r05Source="E_R05_03",r05Target="E_R05_02"
                let r05Effect="ACT_E_R05_03_light_transfer",r05Root="synthetic:path:r05:recipient"
                let r05Tell=event("enemy_telegraph",r05Source,r05Target,1,r05Root,27_000)
                let r05Impact=event("enemy_light_transfer",r05Source,r05Target,1,r05Root,27_500)
                resetScene([r05Source,r05Target],events:[r05Tell,r05Impact])
                let r05PreCueAudit=auditValue()
                let r05Anchors=BattleEffects.anchors(id:r05Effect)
                let r05CueExpectedStart=expectedAnchor("ACT_"+r05Source,r05Anchors["source"] ?? "",r05PreCueAudit)
                let r05CueExpectedEnd=expectedRecipientCenter("ACT_"+r05Target,r05PreCueAudit)
                scene.present(r05Tell)
                pathAudit=auditValue();pathTrace=trace(pathAudit)
                let r05Cue=pathTrace.first{$0["rootActionID"] as? String==r05Root && ($0["step"] as? String)=="cue_placement"} ?? [:]
                let r05ExpectedStart=expectedAnchor("ACT_"+r05Source,r05Anchors["source"] ?? "",pathAudit)
                let r05ExpectedEnd=expectedRecipientCenter("ACT_"+r05Target,pathAudit)
                let r05CueStart=pathChildPoint(r05Effect,TransferPathGeometry.startNodeName)
                let r05CueEnd=pathChildPoint(r05Effect,TransferPathGeometry.endNodeName)
                let r05CuePixels=close(numeric(r05Cue,"placement.pathSourcePixelX"),102) && close(numeric(r05Cue,"placement.pathSourcePixelY"),52)
                    && close(numeric(r05Cue,"placement.pathTargetPixelX"),28) && close(numeric(r05Cue,"placement.pathTargetPixelY"),68)
                let r05CueConverted=close(r05CueStart?.x,r05CueExpectedStart?.x) && close(r05CueStart?.y,r05CueExpectedStart?.y)
                    && close(r05CueEnd?.x,r05CueExpectedEnd?.x) && close(r05CueEnd?.y,r05CueExpectedEnd?.y)
                    && close(numeric(r05Cue,"placement.pathExpectedStartX"),r05CueExpectedStart?.x)
                    && close(numeric(r05Cue,"placement.pathExpectedStartY"),r05CueExpectedStart?.y)
                    && close(numeric(r05Cue,"placement.pathExpectedEndX"),r05CueExpectedEnd?.x)
                    && close(numeric(r05Cue,"placement.pathExpectedEndY"),r05CueExpectedEnd?.y)
                    && close(numeric(r05Cue,"placement.pathStartX"),r05CueStart?.x)
                    && close(numeric(r05Cue,"placement.pathStartY"),r05CueStart?.y)
                    && close(numeric(r05Cue,"placement.pathEndX"),r05CueEnd?.x)
                    && close(numeric(r05Cue,"placement.pathEndY"),r05CueEnd?.y)
                let r05NoPrematureArrival=scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})?.childNode(withName:TransferPathGeometry.arrivalNodeName)==nil
                let r05CueNoSupportNotice=scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})?.childNode(withName:TransferPathGeometry.noticeNodeName)==nil
                    && scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})?.childNode(withName:TransferPathGeometry.noticeAnchorNodeName) != nil
                scene.present(r05Impact)
                pathAudit=auditValue();pathTrace=trace(pathAudit)
                let r05ImpactRow=pathTrace.first{$0["rootActionID"] as? String==r05Root && ($0["step"] as? String)=="impact_placement"} ?? [:]
                let r05ImpactStart=pathChildPoint(r05Effect,TransferPathGeometry.startNodeName)
                let r05ImpactEnd=pathChildPoint(r05Effect,TransferPathGeometry.endNodeName)
                let r05ImpactConverted=close(r05ImpactStart?.x,r05ExpectedStart?.x) && close(r05ImpactStart?.y,r05ExpectedStart?.y)
                    && close(r05ImpactEnd?.x,r05ExpectedEnd?.x) && close(r05ImpactEnd?.y,r05ExpectedEnd?.y)
                    && close(numeric(r05ImpactRow,"placement.pathExpectedStartX"),r05ExpectedStart?.x)
                    && close(numeric(r05ImpactRow,"placement.pathExpectedStartY"),r05ExpectedStart?.y)
                    && close(numeric(r05ImpactRow,"placement.pathExpectedEndX"),r05ExpectedEnd?.x)
                    && close(numeric(r05ImpactRow,"placement.pathExpectedEndY"),r05ExpectedEnd?.y)
                    && close(numeric(r05ImpactRow,"placement.pathStartX"),r05ImpactStart?.x)
                    && close(numeric(r05ImpactRow,"placement.pathStartY"),r05ImpactStart?.y)
                    && close(numeric(r05ImpactRow,"placement.pathEndX"),r05ImpactEnd?.x)
                    && close(numeric(r05ImpactRow,"placement.pathEndY"),r05ImpactEnd?.y)
                let r05Arrival=scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})?.childNode(withName:TransferPathGeometry.arrivalNodeName)
                let r05ArrivalDiameter=pathArrivalDiameter(r05Effect)
                let r05Notice=supportNoticeSnapshot(r05Effect)
                let r05NoticeExpected=expectedSupportNotice("ACT_"+r05Target,pathAudit)
                let r05TargetGeometry=(pathAudit["geometry"] as? [String:[String:Any]])?["ACT_"+r05Target] ?? [:]
                let r05NoticeSingleLabel=(r05Notice?["labelCount"] as? Int)==1 && (r05Notice?["labelTexts"] as? [String])==["支援"]
                let r05NoticeFrame=close(numeric(r05Notice ?? [:],"width"),34,0.2) && close(numeric(r05Notice ?? [:],"height"),20,0.2)
                    && abs(numeric(r05Notice ?? [:],"unitXAxisDeltaY") ?? .infinity)<0.02
                    && abs(numeric(r05Notice ?? [:],"unitYAxisDeltaX") ?? .infinity)<0.02
                let r05NoticePlacement=close(numeric(r05Notice ?? [:],"centerX"),r05NoticeExpected?.x)
                    && close(numeric(r05Notice ?? [:],"centerY"),r05NoticeExpected?.y)
                    && close(numeric(r05ImpactRow,"placement.pathNoticeX"),r05NoticeExpected?.x)
                    && close(numeric(r05ImpactRow,"placement.pathNoticeY"),r05NoticeExpected?.y)
                    && close(numeric(r05Notice ?? [:],"maxY"), (r05TargetGeometry["accumulatedMinY"] as? NSNumber).map{CGFloat($0.doubleValue-6)})
                let r05HPUnchanged=scene.hpMismatches(party:["C_WITCH":10_000,"C_FAMILIAR":10_000,"C_APPRENTICE":10_000,"C_SMITH":10_000],
                    enemies:[r05Source:10_000,r05Target:10_000]).isEmpty
                await append("r05_light_transfer_recipient_path",[
                    "cueAndImpactSourceEffectAndTargetAreExact":r05Cue["sourceID"] as? String==r05Source && r05ImpactRow["sourceID"] as? String==r05Source
                        && r05Cue["effectID"] as? String==r05Effect && r05ImpactRow["effectID"] as? String==r05Effect
                        && r05Cue["targetIDs"] as? String=="ACT_"+r05Target && r05ImpactRow["targetIDs"] as? String=="ACT_"+r05Target,
                    "authoredRightToLeftDiagonalAnchors":r05CuePixels,
                    "cuePathUsesRegisteredTransform":(r05Cue["placement.transferPathRegistered"] as? String)=="true" && r05CueConverted,
                    "impactPathUsesRegisteredTransform":(r05ImpactRow["placement.transferPathRegistered"] as? String)=="true" && r05ImpactConverted,
                    "arrivalAccentOnlyAtImpactAndSevenPointRadius":r05NoPrematureArrival && r05Arrival != nil && close(r05ArrivalDiameter,14,0.2),
                    "supportLabelAppearsOnlyAtImpact":r05CueNoSupportNotice && r05Notice != nil,
                    "supportLabelTextAndSingleInstance":r05NoticeSingleLabel,
                    "supportLabelUprightAnd34By20":r05NoticeFrame,
                    "supportLabelSixPointBelowRecipientBounds":r05NoticePlacement,
                    "usesOnlyOneCombatBudgetNode":((pathAudit["effects"] as? [String:Any])?["peakCombat"] as? Int)==1,
                    "eventDoesNotApplyDamage":r05HPUnchanged
                ],["cuePlacement":r05Cue,"impactPlacement":r05ImpactRow,"cueExpectedStart":r05CueExpectedStart.map{[$0.x,$0.y]} ?? [],
                   "cueExpectedEnd":r05CueExpectedEnd.map{[$0.x,$0.y]} ?? [],"impactExpectedStart":r05ExpectedStart.map{[$0.x,$0.y]} ?? [],
                   "expectedEnd":r05ExpectedEnd.map{[$0.x,$0.y]} ?? [],"actualCueStart":r05CueStart.map{[$0.x,$0.y]} ?? [],
                   "actualCueEnd":r05CueEnd.map{[$0.x,$0.y]} ?? [],"actualImpactStart":r05ImpactStart.map{[$0.x,$0.y]} ?? [],
                   "actualImpactEnd":r05ImpactEnd.map{[$0.x,$0.y]} ?? [],"arrivalDiameter":r05ArrivalDiameter ?? -1,
                   "supportNotice":r05Notice ?? [:],"supportNoticeExpected":r05NoticeExpected.map{[$0.x,$0.y]} ?? []])

                // The arrival label belongs to the same effect parent. A paused
                // scene must freeze its lifetime; after unpausing, both label
                // and path parent must complete cleanup within the candidate window.
                let pauseRoot="synthetic:path:r05:notice-pause"
                let pauseTell=event("enemy_telegraph",r05Source,r05Target,1,pauseRoot,30_000)
                let pauseImpact=event("enemy_light_transfer",r05Source,r05Target,1,pauseRoot,30_500)
                resetScene([r05Source,r05Target],events:[pauseTell,pauseImpact])
                scene.present(pauseTell)
                let pauseCueHadNoNotice=scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})?.childNode(withName:TransferPathGeometry.noticeNodeName)==nil
                scene.present(pauseImpact)
                let pausedEffect=scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})
                let pausedNotice=pausedEffect?.childNode(withName:TransferPathGeometry.noticeNodeName)
                let pausedOpacity=pausedNotice?.alpha ?? -1
                scene.isPaused=true
                let pauseStarted=ProcessInfo.processInfo.systemUptime
                try await Task.sleep(for:.milliseconds(550))
                let pauseElapsed=ProcessInfo.processInfo.systemUptime-pauseStarted
                let scenePauseObserved=scene.isPaused
                let noticeActionWasRunning=pausedNotice?.hasActions() == true
                let parentAndNoticeHeld=scenePauseObserved && pausedEffect?.parent===scene && pausedNotice?.parent===pausedEffect
                    && abs((pausedNotice?.alpha ?? -2)-pausedOpacity)<0.001
                scene.isPaused=false
                let resumeStarted=ProcessInfo.processInfo.systemUptime
                var pauseCleanup=false
                while ProcessInfo.processInfo.systemUptime-resumeStarted<1.2 {
                    try await Task.sleep(for:.milliseconds(20))
                    let current=scene.children.first(where:{($0.userData?["effectID"] as? String)==r05Effect})
                    if current == nil && supportLabelCount(in:scene)==0 {
                        pauseCleanup=true;break
                    }
                }
                let resumeElapsed=ProcessInfo.processInfo.systemUptime-resumeStarted
                await append("transfer_notice_lifetime_pause_and_expiry",[
                    "cueHasNoPrematureLabel":pauseCueHadNoNotice,
                    "scenePauseHoldsParentNoticeAndOpacity":parentAndNoticeHeld && noticeActionWasRunning && pauseElapsed>=0.54,
                    "parentAndNoticeExpireAfterResume":pauseCleanup,
                    "resumeCleanupWithinExpectedWindow":pauseCleanup && resumeElapsed>=0.30 && resumeElapsed<=1.2,
                    "pauseWasExplicitSceneLifecycleState":scenePauseObserved && !scene.isPaused
                ],["syntheticScenePauseSeconds":pauseElapsed,"resumeUntilCleanupSeconds":resumeElapsed,
                   "noticeLifetimeSeconds":TransferPathGeometry.noticeLifetime,"pausedOpacity":pausedOpacity])

                // A typed party interruption cancels the held tell before its
                // support impact. No arrival label or support impact may appear.
                let noticeCancelRoot="synthetic:path:r02:notice-cancel"
                let noticeCancelTell=event("enemy_telegraph",r02Source,r02Target,1,noticeCancelRoot,31_000)
                let noticeCancelImpact=event("enemy_magic_support",r02Source,r02Target,1_500,noticeCancelRoot,31_500)
                let noticeCancelInterrupt=event("cast_interrupt","C_SMITH",r02Source,1,noticeCancelRoot,31_250)
                resetScene([r02Source,r02Target,"C_SMITH"],events:[noticeCancelTell,noticeCancelImpact,noticeCancelInterrupt])
                scene.present(noticeCancelTell)
                let cancelCueNoLabel=scene.children.first(where:{($0.userData?["effectID"] as? String)==r02Effect})?.childNode(withName:TransferPathGeometry.noticeNodeName)==nil
                scene.present(noticeCancelInterrupt)
                try await Task.sleep(for:.milliseconds(200))
                pathAudit=auditValue();pathTrace=trace(pathAudit)
                let noticeCancelRows=pathTrace.filter{$0["rootActionID"] as? String==noticeCancelRoot}
                let cancelParentGone=scene.children.first(where:{($0.userData?["effectID"] as? String)==r02Effect})==nil
                let noSupportLabel=supportLabelCount(in:scene)==0
                let cancelNoImpact = !noticeCancelRows.contains{$0["step"] as? String=="impact_placement" || $0["step"] as? String=="direct_full:enemy_magic_support"}
                await append("transfer_notice_cancelled_cue_never_arrives",[
                    "heldCueCancelledBySameRootInterrupt":noticeCancelRows.contains{$0["step"] as? String=="cue_cancel:cast_interrupt"},
                    "noArrivalNoticeBeforeOrAfterCancel":cancelCueNoLabel && noSupportLabel,
                    "cancelledEffectParentRemoved":cancelParentGone,
                    "noSupportImpactWasPresented":cancelNoImpact,
                    "cancelDoesNotCreateExtraBudgetNode":((pathAudit["effects"] as? [String:Any])?["peakCombat"] as? Int)==1
                ],["root":noticeCancelRoot,"interruptSource":"C_SMITH","interruptedEnemy":r02Source,"trace":noticeCancelRows])

                // An invalid explicit recipient must suppress the cue and impact;
                // a nearby valid enemy cannot be substituted as a fallback.
                let r02MissingRoot="synthetic:path:r02:missing-recipient",r02MissingID="E_R02_MISSING"
                let r02MissingTell=event("enemy_telegraph",r02Source,r02MissingID,1,r02MissingRoot,28_000)
                let r02MissingImpact=event("enemy_magic_support",r02Source,r02MissingID,1_500,r02MissingRoot,28_500)
                resetScene([r02Source,r02Target],events:[r02MissingTell,r02MissingImpact])
                scene.present(r02MissingTell);scene.present(r02MissingImpact)
                pathAudit=auditValue();pathTrace=trace(pathAudit)
                let missingRows=pathTrace.filter{$0["rootActionID"] as? String==r02MissingRoot}
                let missingRejections=missingRows.filter{($0["step"] as? String ?? "").hasPrefix("missing_target:")}
                await append("r02_magic_support_arc_missing_recipient_no_fallback",[
                    "cueAndImpactExplicitlyRejected":missingRows.contains{$0["step"] as? String=="missing_target:cue"}
                        && missingRows.contains{$0["step"] as? String=="missing_target:direct"},
                    "noWrongRecipientFallback":missingRejections.count==2
                        && missingRejections.allSatisfy{($0["targetIDs"] as? String)==r02MissingID}
                        && !missingRows.contains{["cue_placement","impact_placement"].contains($0["step"] as? String ?? "")}
                        && ((pathAudit["effects"] as? [String:Any])?["peakCombat"] as? Int)==0,
                    "noTransferGeometryOrPlacement":missingRows.allSatisfy{row in !row.keys.contains(where:{$0.contains("pathStart") || $0.contains("pathEnd") || $0.contains("transferPathRegistered")})}
                        && !scene.children.contains(where:{$0.name=="combat_effect:"+r02Effect}),
                    "validDecoyWasNotUsed":missingRows.allSatisfy{!($0["targetIDs"] as? String ?? "").contains("ACT_"+r02Target)}
                ],["root":r02MissingRoot,"missingRecipient":r02MissingID,"trace":missingRows])

                // A non-transfer charge retains its established generic placement
                // and does not receive transfer-path children or endpoint metadata.
                let genericRoot="synthetic:path:generic:control",genericSource="E_R01_01",genericTarget="C_WITCH"
                let genericTell=event("enemy_telegraph",genericSource,genericTarget,1,genericRoot,29_000)
                let genericHit=event("enemy_hit",genericSource,genericTarget,8,genericRoot,29_500)
                resetScene([genericSource],events:[genericTell,genericHit])
                scene.present(genericTell)
                pathAudit=auditValue();pathTrace=trace(pathAudit)
                let genericCue=pathTrace.first{$0["rootActionID"] as? String==genericRoot && ($0["step"] as? String)=="cue_placement"} ?? [:]
                let genericID="ACT_E_R01_01_charge",genericAnchors=BattleEffects.anchors(id:genericID)
                let genericExpectedStart=expectedAnchor("ACT_"+genericSource,genericAnchors["source"] ?? "",pathAudit)
                let genericTargetGeom=(pathAudit["geometry"] as? [String:[String:Any]])?["ERNA"] ?? [:]
                let genericExpectedGround:CGPoint? = {
                    guard let x=(genericTargetGeom["x"] as? NSNumber)?.doubleValue,
                          let y=(genericTargetGeom["y"] as? NSNumber)?.doubleValue else{return nil}
                    return CGPoint(x:x,y:y-2) // current legacy `ground_path` destination uses centroid(...,ground:true).
                }()
                let genericExpectedEnd:CGPoint? = genericExpectedStart.flatMap { start in
                    genericExpectedGround.map { ground in CGPoint(x:(start.x+ground.x)/2,y:ground.y) }
                }
                let genericCueStart=numeric(genericCue,"placement.cueX").map{CGPoint(x:$0,y:numeric(genericCue,"placement.cueY") ?? 0)}
                let genericCueEnd=numeric(genericCue,"placement.impactX").map{CGPoint(x:$0,y:numeric(genericCue,"placement.impactY") ?? 0)}
                let genericLegacyPosition=close(genericCueStart?.x,genericExpectedStart?.x) && close(genericCueStart?.y,genericExpectedStart?.y)
                    && close(genericCueEnd?.x,genericExpectedEnd?.x) && close(genericCueEnd?.y,genericExpectedEnd?.y)
                let genericNoPath=(genericCue["placement.transferPathRegistered"] == nil || (genericCue["placement.transferPathRegistered"] as? String)=="false")
                    && genericCue["placement.pathSourcePixelX"] == nil
                    && !scene.children.contains(where:hasTransferChild)
                let probe=SKSpriteNode(color:.white,size:CGSize(width:128,height:128))
                probe.position=CGPoint(x:7,y:9);probe.zRotation=0.25;probe.setScale(1.2)
                let sentinel=SKNode();sentinel.name=TransferPathGeometry.startNodeName;probe.addChild(sentinel)
                let beforePosition=probe.position,beforeRotation=probe.zRotation,beforeScale=probe.xScale
                let degenerateRejected=TransferPathGeometry.apply(to:probe,id:r02Effect,origin:.zero,destination:.zero)==nil
                let invalidRejected=TransferPathGeometry.apply(to:probe,id:"ACT_E_R01_01_charge",origin:.zero,destination:CGPoint(x:50,y:10))==nil
                let nonfiniteRejected=TransferPathGeometry.apply(to:probe,id:r05Effect,origin:CGPoint(x:CGFloat.infinity,y:0),destination:CGPoint(x:50,y:10))==nil
                let rejectedInputsLeaveNodeUnchanged=degenerateRejected && invalidRejected && nonfiniteRejected
                    && probe.position==beforePosition && probe.zRotation==beforeRotation && probe.xScale==beforeScale
                    && probe.childNode(withName:TransferPathGeometry.startNodeName)===sentinel
                scene.present(genericHit)
                pathTrace=trace(auditValue())
                let genericImpact=pathTrace.first{$0["rootActionID"] as? String==genericRoot && ($0["step"] as? String)=="impact_placement"} ?? [:]
                await append("unrelated_effect_placement_unchanged",[
                    "legacyCueAnchorsUnchanged":genericLegacyPosition,
                    "noTransferPathRegisteredOrChildren":genericNoPath,
                    "ordinaryAttackTargetsOriginalRecipient":genericCue["targetIDs"] as? String=="ERNA" && genericImpact["targetIDs"] as? String=="ERNA",
                    "ordinaryRotationAndScaleRemainLegacy":numeric(genericCue,"placement.rotation") != nil && numeric(genericCue,"placement.scaleX") != nil
                        && genericCue["placement.pathScale"] == nil,
                    "unknownDegenerateAndNonfiniteInputsAreSideEffectFree":rejectedInputsLeaveNodeUnchanged
                ],["cuePlacement":genericCue,"impactPlacement":genericImpact,"expectedStart":genericExpectedStart.map{[$0.x,$0.y]} ?? [],
                   "expectedEnd":genericExpectedEnd.map{[$0.x,$0.y]} ?? []])

                let zero=event("enemy_guard_absorb","E_R05_02","C_WITCH",0,"synthetic:guard:zero",26_000)
                let positive=event("enemy_guard_absorb","E_R05_02","C_WITCH",7,"synthetic:guard:positive",26_100)
                resetScene(["E_R05_02"],events:[zero,positive]);scene.present(zero)
                let zeroAudit=auditValue()
                scene.present(positive);a=auditValue();t=trace(a)
                let positiveRows=t.filter{($0["step"] as? String)=="direct_full:enemy_guard_absorb"}
                await append("zero_guard_suppressed_positive_targets_defender",[
                    "zeroCreatesNoEffect":((zeroAudit["effects"] as? [String:Any])?["activeCombat"] as? Int)==0,
                    "positiveDefenderTarget":positiveRows.count==1 && (positiveRows[0]["targetIDs"] as? String)=="ACT_E_R05_02"
                ])


                // An explicit unknown recipient must not fall back to the source or
                // first party sprite, even if another member of the same AoE resolves.
                for partial in [false,true] {
                    let root="synthetic:missing-target:"+String(partial)
                    let tell=event("telegraph_aoe","B_R02_B","party",1,root,27_000)
                    var hits=[event("enemy_hit","B_R02_B","MISSING_ACTOR",5,root,27_500)]
                    if partial {hits.append(event("enemy_hit","B_R02_B","C_WITCH",5,root,27_500))}
                    resetScene(["B_R02_B"],events:[tell]+hits)
                    scene.present(tell);hits.forEach{scene.present($0)}
                    a=auditValue();t=trace(a)
                    await append(partial ? "partly_missing_aoe_is_not_silently_reduced":"unknown_explicit_target_never_falls_back",[
                        "missingTargetRecorded":t.contains{($0["step"] as? String)=="missing_target:cue"},
                        "noEffectPlacement": !t.contains{($0["step"] as? String ?? "").contains("placement") || ($0["step"] as? String ?? "").hasPrefix("direct_full:")},
                        "noActiveCombatEffect":((a["effects"] as? [String:Any])?["activeCombat"] as? Int)==0
                    ])
                }


                // Different status recipients must not move a hit-bound action.
                let splitRoot="synthetic:hit-status-different-recipient"
                let splitTell=event("enemy_telegraph","E_R05_01","C_WITCH",1,splitRoot,28_000)
                let splitStatus=event("support_duration_reduced","E_R05_01","C_SMITH",1_000,splitRoot,28_100)
                let splitHit=event("enemy_hit","E_R05_01","C_WITCH",5,splitRoot,28_500)
                resetScene(["E_R05_01"],events:[splitTell,splitStatus,splitHit])
                scene.present(splitTell);scene.present(splitStatus)
                let noStatusAdvance = !trace(auditValue()).contains{($0["step"] as? String)=="impact_advance"}
                scene.present(splitHit);a=auditValue();t=trace(a)
                let splitPlacements=t.filter{["cue_placement","impact_placement"].contains($0["step"] as? String ?? "")}
                await append("hit_target_dominates_distinct_status_recipient",[
                    "statusDoesNotAdvance":noStatusAdvance,
                    "hitRecipientOnly":splitPlacements.count==2 && splitPlacements.allSatisfy{($0["targetIDs"] as? String)=="ERNA"},
                    "statusRemainsSemanticOnly":t.contains{($0["step"] as? String)=="semantic_only:support_duration_reduced"}
                ])

                // The mark locks the intended victim; Smith can still intercept
                // the eventual hit. Neither a later tell nor that hit may rewrite
                // the earlier mark's recipient.
                let magnetEnemy="E_R03_04",magnetEffect="ACT_E_R03_04_magnet_pullcue"
                let magnetRoot="synthetic:magnet:cover"
                let mark=event("enemy_magnet_mark",magnetEnemy,"C_WITCH",800,magnetRoot,30_000)
                let heavy=event("telegraph_heavy",magnetEnemy,"C_WITCH",1,magnetRoot,30_800)
                let cover=event("cover_redirect","C_SMITH","C_WITCH",1,magnetRoot,32_000)
                let coveredHit=event("enemy_hit",magnetEnemy,"C_SMITH",25,magnetRoot,32_000)
                resetScene([magnetEnemy],events:[mark,heavy,cover,coveredHit])
                scene.present(mark);scene.present(heavy);scene.present(cover)
                let beforeMagnetImpact=trace(auditValue())
                let markRows=beforeMagnetImpact.filter{($0["step"] as? String)=="cue_placement"}
                let cueNode=scene.children.first{($0.userData?["effectRootID"] as? String)==magnetRoot}
                let indicator=cueNode?.childNode(withName:MagnetMarkIndicator.nodeName)
                let noDuplicateMagnetNotice = !scene.children.contains{$0.name==MagnetMarkIndicator.noticeName(rootID:magnetRoot)}
                let groundPosition=indicator?.convert(CGPoint.zero,to:scene)
                let markedGeometry=((auditValue()["geometry"] as? [String:Any])?["ERNA"] as? [String:Any]) ?? [:]
                let indicatorAtGround=groundPosition.map { point in
                    abs(Double(point.x)-(markedGeometry["x"] as? Double ?? -10000))<0.01 &&
                    abs(Double(point.y)-((markedGeometry["y"] as? Double ?? -10000)-2))<0.01
                } ?? false
                let markAtTarget=markRows.first.map{row in
                    let x=Double(row["placement.impactX"] as? String ?? "nan") ?? .nan
                    let y=Double(row["placement.impactY"] as? String ?? "nan") ?? .nan
                    return x.isFinite && y.isFinite && abs(Double(cueNode?.position.x ?? -10000)-x)<0.001 && abs(Double(cueNode?.position.y ?? -10000)-y)<0.001
                } ?? false
                scene.present(coveredHit);t=trace(auditValue())
                let impactRows=t.filter{($0["step"] as? String)=="impact_placement"}
                await append("magnet_mark_and_cover_have_distinct_recipients",[
                    "cueRemainsOnIntendedVictim":markRows.count==1 && (markRows.first?["targetIDs"] as? String)=="ERNA",
                    "cueActuallyPlacedAtMarkedTarget":markAtTarget,
                    "persistentMarkIndicatorAtMarkedFeet":indicatorAtGround,
                    "noDuplicateHeadNotice":noDuplicateMagnetNotice,
                    "indicatorRemovedAtImpact":cueNode?.childNode(withName:MagnetMarkIndicator.nodeName)==nil,
                    "heavyAndCoverDoNotAdvance":!beforeMagnetImpact.contains{($0["step"] as? String)=="impact_advance"},
                    "impactUsesActualDefender":impactRows.count==1 && (impactRows.first?["targetIDs"] as? String)=="AIRA",
                    "oneCueAndOneImpact":t.filter{($0["step"] as? String)=="cue_hold:enemy_magnet_mark"}.count==1 && t.filter{($0["step"] as? String)=="impact_advance"}.count==1
                ])
                for reason in ["enemy_magnet_target_lost","cast_interrupt"] {
                    let root="synthetic:magnet:"+reason
                    let start=event("enemy_magnet_mark",magnetEnemy,"C_APPRENTICE",800,root,33_000)
                    let end=reason=="cast_interrupt"
                        ? event(reason,"C_SMITH",magnetEnemy,1,root,33_400)
                        : event(reason,magnetEnemy,"C_APPRENTICE",0,root,33_400)
                    resetScene([magnetEnemy],events:[start,end]);scene.present(start);scene.present(end)
                    t=trace(auditValue())
                    try? await Task.sleep(for:.milliseconds(250))
                    let cancellationRemovedNode = !scene.children.contains { ($0.userData?["effectRootID"] as? String)==root }
                    await append("magnet_cancel_"+reason,[
                        "fadeRemovesNodeBeforeCleanup":cancellationRemovedNode,
                        "markDisplayedBeforeCancellation":t.contains{($0["step"] as? String)=="cue_hold:enemy_magnet_mark"},
                        "sameRootCancelled":t.contains{($0["step"] as? String)=="cue_cancel:"+reason && ($0["rootActionID"] as? String)==root},
                        "neverAdvancesToImpact":!t.contains{($0["step"] as? String)=="impact_advance"}
                    ])
                }
                let cutRoot="synthetic:magnet:horizon"
                let cutMark=event("enemy_magnet_mark",magnetEnemy,"C_FAMILIAR",800,cutRoot,34_000)
                resetScene([magnetEnemy],events:[cutMark]);scene.present(cutMark);t=trace(auditValue())
                await append("magnet_terminal_mark_is_not_retrospectively_hidden",[
                    "committedMarkIsVisible":t.contains{($0["step"] as? String)=="cue_placement" && ($0["targetIDs"] as? String)=="NOIR"},
                    "noInventedImpact":!t.contains{($0["step"] as? String)=="impact_advance"}
                ])
                let legacyRoot="synthetic:magnet:legacy-heavy"
                let legacy=[event("telegraph_heavy",magnetEnemy,"C_WITCH",1,legacyRoot,35_000),event("enemy_hit",magnetEnemy,"C_WITCH",20,legacyRoot,37_000)]
                resetScene([magnetEnemy],events:legacy);legacy.forEach{scene.present($0)};a=auditValue();t=trace(a)
                await append("magnet_legacy_heavy_does_not_invent_mark",[
                    "noMagnetEffect":!t.contains{($0["step"] as? String)=="emit" && ($0["effectID"] as? String)==magnetEffect},
                    "unmarkedHitExplicit":t.contains{($0["step"] as? String)=="unmarked_magnet_hit"},
                    "damageStillApplied":scene.hpMismatches(party:["C_WITCH":9_980],enemies:[:]).isEmpty
                ])

                let suppressedRoot="synthetic:magnet:suppressed"
                let capMark=event("enemy_magnet_mark",magnetEnemy,"C_WITCH",800,suppressedRoot,40_000)
                let capHit=event("enemy_hit",magnetEnemy,"C_WITCH",25,suppressedRoot,42_000)
                let occupied=[event("enemy_telegraph","E_R01_01","C_SMITH",1,"synthetic:occupied:1",39_900),event("enemy_hit","E_R01_01","C_SMITH",1,"synthetic:occupied:1",45_000),event("enemy_telegraph","E_R02_01","C_APPRENTICE",1,"synthetic:occupied:2",39_900),event("enemy_hit","E_R02_01","C_APPRENTICE",1,"synthetic:occupied:2",45_000)]
                resetScene(["E_R01_01","E_R02_01",magnetEnemy],events:occupied+[capMark,capHit])
                scene.present(occupied[0]);scene.present(occupied[2]);scene.present(capMark)
                let suppressedTrace=trace(auditValue())
                let fallbackNoticePresent=scene.children.contains{$0.name==MagnetMarkIndicator.noticeName(rootID:suppressedRoot)}
                // Model the unrelated held nodes leaving the scene before impact.
                // The magnet cue was suppressed, so its real hit may use direct art.
                for node in scene.children where (node.userData?["effectRootID"] as? String)?.hasPrefix("synthetic:occupied:")==true {node.removeAllActions();node.removeFromParent()}
                scene.present(capHit);t=trace(auditValue())
                await append("magnet_suppressed_mark_uses_real_hit_fallback",[
                    "suppressionExplicit":suppressedTrace.contains{($0["rootActionID"] as? String)==suppressedRoot && ($0["step"] as? String)=="capacity_suppressed:cue"},
                    "noClaimedMarkPlacement":!suppressedTrace.contains{($0["rootActionID"] as? String)==suppressedRoot && ($0["step"] as? String)=="cue_placement"},
                    "suppressedCueHasOwnedNotice":fallbackNoticePresent,
                    "fallbackNoticeRemovedAtHit":!scene.children.contains{$0.name==MagnetMarkIndicator.noticeName(rootID:suppressedRoot)},
                    "actualHitGetsDirectEffect":t.contains{($0["rootActionID"] as? String)==suppressedRoot && ($0["step"] as? String)=="direct_full:enemy_hit" && ($0["targetIDs"] as? String)=="ERNA"},
                    "damageApplied":scene.hpMismatches(party:["C_WITCH":9_975],enemies:[:]).isEmpty
                ])

                for reason in ["cast_interrupt","enemy_magnet_target_lost"] {
                    let root="synthetic:magnet:suppressed-cancel:"+reason
                    let unrelatedRoot=root+":unrelated"
                    let cancelMark=event("enemy_magnet_mark",magnetEnemy,"C_APPRENTICE",800,root,43_000)
                    let otherEnd=event("enemy_magnet_target_lost",magnetEnemy,"C_WITCH",0,unrelatedRoot,43_200)
                    let end=reason=="cast_interrupt"
                        ? event(reason,"C_SMITH",magnetEnemy,1,root,43_400)
                        : event(reason,magnetEnemy,"C_APPRENTICE",0,root,43_400)
                    let blockers=[
                        event("enemy_telegraph","E_R01_01","C_SMITH",1,root+":block1",42_900),
                        event("enemy_hit","E_R01_01","C_SMITH",1,root+":block1",43_800),
                        event("enemy_telegraph","E_R02_01","C_WITCH",1,root+":block2",42_900),
                        event("enemy_hit","E_R02_01","C_WITCH",1,root+":block2",43_800)
                    ]
                    resetScene(["E_R01_01","E_R02_01",magnetEnemy],events:blockers+[cancelMark,otherEnd,end])
                    scene.present(blockers[0]);scene.present(blockers[2])
                    let blockerSetupAudit=auditValue(),blockerSetupTrace=trace(blockerSetupAudit)
                    let blockerHeldRoots=Set(blockerSetupTrace.filter{($0["step"] as? String)?.hasPrefix("cue_hold:")==true}.compactMap{$0["rootActionID"] as? String})
                    let blockerHPUnchanged=scene.hpMismatches(
                        party:["C_WITCH":10_000,"C_APPRENTICE":10_000,"C_SMITH":10_000,"C_FAMILIAR":10_000],
                        enemies:["E_R01_01":10_000,"E_R02_01":10_000,magnetEnemy:10_000]
                    ).isEmpty
                    scene.present(cancelMark)
                    let suppressed=trace(auditValue()).contains{($0["rootActionID"] as? String)==root && ($0["step"] as? String)=="capacity_suppressed:cue"}
                    let noticeName=MagnetMarkIndicator.noticeName(rootID:root)
                    let ownedBefore=scene.children.filter{$0.name==noticeName}.count==1
                    scene.present(otherEnd)
                    let survivesOtherRoot=scene.children.filter{$0.name==noticeName}.count==1
                    scene.present(end)
                    let removedAtTerminal = !scene.children.contains{$0.name==noticeName}
                    t=trace(auditValue())
                    let rootSteps=t.filter{($0["rootActionID"] as? String)==root}.compactMap{$0["step"] as? String}
                    let noHitOrImpact = !rootSteps.contains(where:{$0.contains("enemy_hit") || $0=="impact_advance" || $0.hasPrefix("direct_full:")})
                    let hpUnchanged=scene.hpMismatches(
                        party:["C_WITCH":10_000,"C_APPRENTICE":10_000,"C_SMITH":10_000,"C_FAMILIAR":10_000],
                        enemies:["E_R01_01":10_000,"E_R02_01":10_000,magnetEnemy:10_000]
                    ).isEmpty
                    await append("magnet_suppressed_cancel_"+reason,[
                        "twoBlockerCuesHeldBeforeMark":blockerHeldRoots==Set([root+":block1",root+":block2"]),
                        "blockerHPUnchangedBeforeMark":blockerHPUnchanged,
                        "capacitySuppressed":suppressed,
                        "fallbackNoticeOwnedBeforeTerminal":ownedBefore,
                        "differentRootTerminalDoesNotRemoveNotice":survivesOtherRoot,
                        "sameRootTerminalRemovesNoticeImmediately":removedAtTerminal,
                        "noImpactOrHitApplied":noHitOrImpact,
                        "HPUnchanged":hpUnchanged
                    ],["root":root,"unrelatedRoot":unrelatedRoot,"terminal":reason,"blockerHeldRoots":Array(blockerHeldRoots).sorted(),"blockerSetupHPUnchanged":blockerHPUnchanged])
                }

                // R04_01 follow-up cues can be suppressed when both bounded
                // combat slots hold tells. Show a target-owned fallback notice
                // only for that follow-up root; ordinary R04 hits stay silent.
                let pursuitEnemy="E_R04_01"
                let pursuitRoot="enemy:E_R04_01:followup:enemy:E_R04_02:1"
                let pursuitTell=event("enemy_telegraph",pursuitEnemy,"C_WITCH",1,pursuitRoot,50_000)
                let pursuitMarker=event("enemy_followup",pursuitEnemy,"C_WITCH",1,pursuitRoot,50_000)
                let pursuitHit=event("enemy_hit",pursuitEnemy,"C_WITCH",25,pursuitRoot,50_350)
                let pursuitBlockers=[
                    event("enemy_telegraph","E_R01_01","C_SMITH",1,"synthetic:pursuit:block1",49_900),
                    event("enemy_hit","E_R01_01","C_SMITH",1,"synthetic:pursuit:block1",50_700),
                    event("enemy_telegraph","E_R02_01","C_APPRENTICE",1,"synthetic:pursuit:block2",49_900),
                    event("enemy_hit","E_R02_01","C_APPRENTICE",1,"synthetic:pursuit:block2",50_700)
                ]
                resetScene(["E_R01_01","E_R02_01",pursuitEnemy],events:pursuitBlockers+[pursuitTell,pursuitMarker,pursuitHit])
                scene.present(pursuitBlockers[0]);scene.present(pursuitBlockers[2])
                let heldBeforePursuit=scene.children.filter{$0.name?.hasPrefix("combat_effect:")==true}.count==2
                scene.present(pursuitTell);scene.present(pursuitMarker)
                scene.present(pursuitTell) // repeated delivery must not duplicate the chip
                let fallbackTrace=trace(auditValue())
                let fallbackTargets=PursuitSuppressionNotice.targetIDs(rootID:pursuitRoot,in:scene)
                let fallbackSources=PursuitSuppressionNotice.sourceIDs(rootID:pursuitRoot,in:scene)
                let warningOwned = PursuitSuppressionNotice.contains(rootID:pursuitRoot,in:scene)
                let warningCount=fallbackTargets.count
                var pursuitChipGeometry:[String:CGFloat]=[:]
                var pursuitLabelTexts:[String]=[]
                var pursuitLabelMinY=CGFloat.infinity
                var pursuitLabelMaxY = -CGFloat.infinity
                var renderedNoticeGeometry:PursuitNoticeRenderedBoundsQA_R059.Result?
                scene.enumerateChildNodes(withName:"//"+PursuitSuppressionNotice.nodeName){group,_ in
                    guard group.userData?["pursuitRootID"] as? String==pursuitRoot else{return}
                    if let actualRecipient=group.parent as? SKSpriteNode,
                       let noticeTargetID=group.userData?["pursuitTargetID"] as? String,
                       fallbackTargets.count==1, fallbackTargets[0]==noticeTargetID {
                        renderedNoticeGeometry=PursuitNoticeRenderedBoundsQA_R059.inspect(
                            group:group,recipient:actualRecipient,scene:self.scene,
                            obstacles:self.scene.pursuitNoticeObstacleNodes(excluding:noticeTargetID))
                    }
                    pursuitChipGeometry["xOffset"]=group.position.x
                    var backingTop: CGFloat?
                    var backingHalfStroke: CGFloat?
                    for child in group.children {
                        if let backing=child as? SKShapeNode, backing.name == nil {
                            pursuitChipGeometry["backingWidth"]=backing.frame.width
                            backingTop=backing.path?.boundingBoxOfPath.maxY
                            backingHalfStroke=backing.lineWidth / 2
                        }
                        if let pointer=child as? SKShapeNode, pointer.name == PursuitSuppressionNotice.pointerName,
                           let path=pointer.path {
                            let bounds=path.boundingBoxOfPath
                            let strokedBounds=path.copy(strokingWithWidth:pointer.lineWidth, lineCap:pointer.lineCap,
                                                        lineJoin:pointer.lineJoin, miterLimit:pointer.miterLimit).boundingBoxOfPath
                            pursuitChipGeometry["pointerPathWidth"]=bounds.width
                            pursuitChipGeometry["pointerPathHeight"]=bounds.height
                            pursuitChipGeometry["pointerWidth"]=strokedBounds.width
                            pursuitChipGeometry["pointerHeight"]=strokedBounds.height
                            pursuitChipGeometry["pointerTipY"]=strokedBounds.maxY
                            if let recipient=group.parent as? SKSpriteNode {
                                let recipientLowerEdge = -recipient.anchorPoint.y * recipient.size.height
                                let pointerTipInRecipient = group.position.y + strokedBounds.maxY
                                pursuitChipGeometry["pointerTipClearance"]=recipientLowerEdge-pointerTipInRecipient
                                pursuitChipGeometry["sharedGeometryClearance"]=PursuitNoticePointerGeometryR059.clearance(
                                    anchorY: recipient.anchorPoint.y, height: recipient.size.height)
                            }
                            if let backingTop, let backingHalfStroke {
                                pursuitChipGeometry["pointerBaseOverlap"] =
                                    backingTop + backingHalfStroke - strokedBounds.minY
                            }
                        }
                        if let label=child as? SKLabelNode {
                            pursuitChipGeometry["labelWidth"]=max(pursuitChipGeometry["labelWidth"] ?? 0,label.frame.width)
                            pursuitLabelTexts.append(label.text ?? "")
                            pursuitLabelMinY=min(pursuitLabelMinY,label.frame.minY)
                            pursuitLabelMaxY=max(pursuitLabelMaxY,label.frame.maxY)
                        }
                    }
                }
                pursuitChipGeometry["labelMinY"]=pursuitLabelMinY
                pursuitChipGeometry["labelMaxY"]=pursuitLabelMaxY
                pursuitChipGeometry["labelStackHeight"]=pursuitLabelMaxY-pursuitLabelMinY
                let pursuitLabelFits =
                    (pursuitChipGeometry["labelWidth"] ?? .infinity) + CGFloat(PursuitNoticeCopyR059.horizontalInset * 2) <= (pursuitChipGeometry["backingWidth"] ?? 0) &&
                    pursuitLabelMinY >= -PursuitNoticePointerGeometryR059.panelHeight/2 + PursuitNoticePointerGeometryR059.panelStrokeWidth/2 &&
                    pursuitLabelMaxY <= PursuitNoticePointerGeometryR059.panelHeight/2 - PursuitNoticePointerGeometryR059.panelStrokeWidth/2
                let pursuitLabelNamesRecipient = pursuitLabelTexts == ["追撃", "エルナ"]
                let pursuitPanelNotchValid =
                    abs((pursuitChipGeometry["pointerWidth"] ?? -1)-PursuitSuppressionNotice.pointerWidth) < 0.01 &&
                    abs((pursuitChipGeometry["pointerHeight"] ?? -1)-PursuitSuppressionNotice.pointerHeight) < 0.01 &&
                    abs((pursuitChipGeometry["pointerPathWidth"] ?? -1)-5) < 0.01 &&
                    abs((pursuitChipGeometry["pointerPathHeight"] ?? -1)-5) < 0.01 &&
                    abs((pursuitChipGeometry["pointerBaseOverlap"] ?? -1)-0.6) < 0.01
                let pursuitPointerBridgesGap = pursuitPanelNotchValid && renderedNoticeGeometry?.passed == true
                let noParticlePlacement = !fallbackTrace.contains{
                    ($0["rootActionID"] as? String)==pursuitRoot && ($0["step"] as? String)=="cue_placement"
                }
                let suppressionWasRecorded=fallbackTrace.contains{
                    ($0["rootActionID"] as? String)==pursuitRoot && ($0["step"] as? String)=="capacity_suppressed:cue"
                }
                let noticeTrace=fallbackTrace.contains{
                    ($0["rootActionID"] as? String)==pursuitRoot && ($0["step"] as? String)=="fallback_notice:追撃"
                }
                // An unrelated hit from this actor must not consume the warning.
                let unrelatedPursuitHit=event("enemy_hit",pursuitEnemy,"C_WITCH",3,"enemy:E_R04_01:ordinary:1",50_200)
                scene.present(unrelatedPursuitHit)
                let survivesUnrelated=PursuitSuppressionNotice.contains(rootID:pursuitRoot,in:scene)
                scene.present(pursuitHit)
                let removedAtHit = !PursuitSuppressionNotice.contains(rootID:pursuitRoot,in:scene)
                t=trace(auditValue())
                await append("r04_followup_suppression_notice_tracks_hit",[
                    "twoSlotsHeldBeforeFollowup":heldBeforePursuit,
                    "capacitySuppressionRecorded":suppressionWasRecorded,
                    "noFalseParticlePlacement":noParticlePlacement,
                    "targetOwnedNoticeTraceRecorded":noticeTrace,
                    "exactlyOneNoticeAfterDuplicateTell":warningOwned && warningCount==1,
                    "compactNoticeGlyphsFitBacking":pursuitLabelFits,
                    "noticeTextIdentifiesActualRecipient":pursuitLabelNamesRecipient,
                    "renderedNoticeBoundsInsideScene":renderedNoticeGeometry?.actualBoundsInsideScene == true,
                    "noticePanelConnectorAndObservedBoundsPass":pursuitPointerBridgesGap,
                    "noticeUsesActualRecipient":fallbackTargets==["ERNA"],
                    "noticeRetainsSourceOwnership":fallbackSources==[pursuitEnemy],
                    "unrelatedRootDoesNotRemoveNotice":survivesUnrelated,
                    "matchingHitRemovesNotice":removedAtHit,
                    "committedDamageStillApplied":scene.hpMismatches(party:["C_WITCH":9_972],enemies:[:]).isEmpty,
                    "particleCapRemainsTwo":((auditValue()["effects"] as? [String:Any])?["peakCombat"] as? Int ?? -1)<=2
                ],["root":pursuitRoot,"targets":fallbackTargets,"sources":fallbackSources,"chipGeometry":pursuitChipGeometry,"fallbackTrace":fallbackTrace,
                   "noticeLabels":pursuitLabelTexts,"renderedNoticeActualCollisionIDs":renderedNoticeGeometry?.actualCollisionIDs ?? ["NO_READBACK"],
                   "renderedNoticePlacement":["candidateInstalled":renderedNoticeGeometry?.candidateInstalled ?? false,
                       "collisionPlacementFound":renderedNoticeGeometry?.collisionPlacementFound ?? false,
                       "displaced":renderedNoticeGeometry?.displaced ?? false,
                       "connectorRequired":renderedNoticeGeometry?.connectorRequired ?? false,
                       "attachmentWithinRecipient":renderedNoticeGeometry?.attachmentWithinRecipient ?? false,
                       "leaderPresent":renderedNoticeGeometry?.requiredLeaderPresent ?? false,
                       "leaderEndsAtPanelTip":renderedNoticeGeometry?.leaderEndsAtPanelTip ?? false],
                   "postHitTrace":t.filter{($0["rootActionID"] as? String)==pursuitRoot || ($0["rootActionID"] as? String)=="enemy:E_R04_01:ordinary:1"}])

                // An explicit terminal cancellation removes the same-root chip
                // immediately, without manufacturing an impact or HP change.
                let cancelRoot="enemy:E_R04_01:followup:enemy:E_R04_02:cancel"
                let cancelTell=event("enemy_telegraph",pursuitEnemy,"C_APPRENTICE",1,cancelRoot,51_000)
                let cancelMarker=event("enemy_followup",pursuitEnemy,"C_APPRENTICE",1,cancelRoot,51_000)
                let cancel=event("cast_interrupt","C_SMITH",pursuitEnemy,1,cancelRoot,51_120)
                let canceledFutureHit=event("enemy_hit",pursuitEnemy,"C_APPRENTICE",25,cancelRoot,51_350)
                // Include the committed-result hit when preparing the cue plan,
                // but deliver the interrupt first and never present that hit.
                resetScene(["E_R01_01","E_R02_01",pursuitEnemy],events:pursuitBlockers+[cancelTell,cancelMarker,cancel,canceledFutureHit])
                scene.present(pursuitBlockers[0]);scene.present(pursuitBlockers[2]);scene.present(cancelTell);scene.present(cancelMarker)
                let cancellationNoticeVisible=PursuitSuppressionNotice.contains(rootID:cancelRoot,in:scene)
                scene.present(cancel)
                let cancellationRemoved = !PursuitSuppressionNotice.contains(rootID:cancelRoot,in:scene)
                t=trace(auditValue())
                let cancelRows=t.filter{($0["rootActionID"] as? String)==cancelRoot}.compactMap{$0["step"] as? String}
                await append("r04_followup_suppression_notice_clears_on_cancel",[
                    "noticeWasPresentBeforeCancel":cancellationNoticeVisible,
                    "sameRootCancelRemovesNotice":cancellationRemoved,
                    "noImpactOrDamage":!cancelRows.contains(where:{$0=="impact_advance" || $0.hasPrefix("direct_full:") || $0.hasPrefix("coalesced:")}) && scene.hpMismatches(
                        party:["C_WITCH":10_000,"C_APPRENTICE":10_000,"C_SMITH":10_000,"C_FAMILIAR":10_000],
                        enemies:["E_R01_01":10_000,"E_R02_01":10_000,pursuitEnemy:10_000]).isEmpty,
                    "cancelIsExplicit":cancelRows.contains("cue_cancel:cast_interrupt") || cancelRows.contains("cancel_without_held_cue:cast_interrupt")
                ],["root":cancelRoot,"steps":cancelRows])

                // A missing explicit victim cannot inherit the source/first party
                // as a fallback target and must not receive a warning.
                let missingRoot="enemy:E_R04_01:followup:missing-recipient"
                let missingTell=event("enemy_telegraph",pursuitEnemy,"MISSING_ACTOR",1,missingRoot,52_000)
                let missingMarker=event("enemy_followup",pursuitEnemy,"MISSING_ACTOR",1,missingRoot,52_000)
                let missingHit=event("enemy_hit",pursuitEnemy,"MISSING_ACTOR",25,missingRoot,52_350)
                resetScene(["E_R01_01","E_R02_01",pursuitEnemy],events:pursuitBlockers+[missingTell,missingMarker,missingHit])
                scene.present(pursuitBlockers[0]);scene.present(pursuitBlockers[2]);scene.present(missingTell);scene.present(missingMarker)
                t=trace(auditValue())
                await append("r04_followup_missing_recipient_has_no_warning",[
                    "missingCueTargetRecorded":t.contains{($0["rootActionID"] as? String)==missingRoot && ($0["step"] as? String)=="missing_target:cue"},
                    "noCapacityFallbackWarning":!PursuitSuppressionNotice.contains(rootID:missingRoot,in:scene),
                    "noRecipientPlacement":!t.contains{($0["rootActionID"] as? String)==missingRoot && ($0["step"] as? String)=="fallback_notice:追撃" || ($0["rootActionID"] as? String)==missingRoot && ($0["step"] as? String)=="cue_placement"}
                ],["root":missingRoot])

                let ordinaryRoot="enemy:E_R04_01:2"
                let ordinaryTell=event("enemy_telegraph",pursuitEnemy,"C_WITCH",1,ordinaryRoot,53_000)
                let ordinaryHit=event("enemy_hit",pursuitEnemy,"C_WITCH",25,ordinaryRoot,53_350)
                resetScene(["E_R01_01","E_R02_01",pursuitEnemy],events:pursuitBlockers+[ordinaryTell,ordinaryHit])
                scene.present(pursuitBlockers[0]);scene.present(pursuitBlockers[2]);scene.present(ordinaryTell)
                t=trace(auditValue())
                await append("r04_ordinary_suppressed_cue_does_not_spam_notice",[
                    "cueSuppressionStillRecorded":t.contains{($0["rootActionID"] as? String)==ordinaryRoot && ($0["step"] as? String)=="capacity_suppressed:cue"},
                    "noFollowupChipForOrdinaryAction":!PursuitSuppressionNotice.contains(rootID:ordinaryRoot,in:scene),
                    "noFallbackNoticeTrace":!t.contains{($0["rootActionID"] as? String)==ordinaryRoot && ($0["step"] as? String)=="fallback_notice:追撃"}
                ],["root":ordinaryRoot])

                let resultRoot="enemy:E_R04_01:followup:result-cleanup"
                let resultTell=event("enemy_telegraph",pursuitEnemy,"C_WITCH",1,resultRoot,54_000)
                let resultMarker=event("enemy_followup",pursuitEnemy,"C_WITCH",1,resultRoot,54_000)
                let resultFutureHit=event("enemy_hit",pursuitEnemy,"C_WITCH",25,resultRoot,54_350)
                resetScene(["E_R01_01","E_R02_01",pursuitEnemy],events:pursuitBlockers+[resultTell,resultMarker,resultFutureHit])
                scene.present(pursuitBlockers[0]);scene.present(pursuitBlockers[2]);scene.present(resultTell);scene.present(resultMarker)
                let resultNoticeWasVisible=PursuitSuppressionNotice.contains(rootID:resultRoot,in:scene)
                await scene.finishCombatEffects()
                let resultNoticeRemoved = !PursuitSuppressionNotice.contains(rootID:resultRoot,in:scene)
                await append("r04_followup_suppression_notice_clears_at_result",[
                    "noticeWasVisibleBeforeResultCleanup":resultNoticeWasVisible,
                    "noticeRemovedByResultCleanup":resultNoticeRemoved,
                    "allNoticesRemoved":PursuitSuppressionNotice.count(in:scene)==0
                ],["root":resultRoot])

                let finalState=state
                let finalSnapshot=(try? encoder.encode(finalState)) ?? Data()
                let finalSave=(try? Data(contentsOf:saveURL)) ?? Data()
                let checks:[String:Bool]=[
                    "snapshotUnchanged":finalState==initialState && finalSnapshot==initialSnapshot,
                    "revisionUnchanged":finalState.revision==initialRevision,
                    "saveBytesUnchanged":finalSave==initialSave,
                    "allCasesPass":cases.count==36 && cases.allSatisfy{($0["passed"] as? Bool)==true}
                ]
                let report:[String:Any]=[
                    "status":checks.values.allSatisfy{$0} ? "PASS_SYNTHETIC_PRESENTATION_ONLY" : "FAIL",
                    "scope":"SYNTHETIC_COMBAT_EVENTS_NO_ENGINE_DISPATCH_NO_REWARDS_NOT_NATURAL_BATTLE",
                    "began":began,"saveKey":key,"snapshotRevisionBefore":initialRevision,
                    "snapshotRevisionAfter":finalState.revision,
                    "snapshotSHA256Before":SHA256.hash(data:initialSnapshot).map{String(format:"%02x",$0)}.joined(),
                    "snapshotSHA256After":SHA256.hash(data:finalSnapshot).map{String(format:"%02x",$0)}.joined(),
                    "saveSHA256Before":SHA256.hash(data:initialSave).map{String(format:"%02x",$0)}.joined(),
                    "saveSHA256After":SHA256.hash(data:finalSave).map{String(format:"%02x",$0)}.joined(),
                    "checks":checks,"cases":cases]
                let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                try data.write(to:reportURL,options:.atomic)
                writeReceipt("effect_budget_regression",report["status"] as? String ?? "UNKNOWN")
                await scene.finishCombatEffects()
            } catch {
                self.error="演出予算の検証に失敗しました。"+String(reflecting:error)
                let finalSave=(try? Data(contentsOf:saveURL)) ?? Data()
                let failure:[String:Any]=["status":"FAILED","scope":"SYNTHETIC_COMBAT_EVENTS_NO_ENGINE_DISPATCH_NO_REWARDS_NOT_NATURAL_BATTLE",
                    "began":began,"saveKey":key,"snapshotRevisionBefore":initialRevision,"snapshotRevisionAfter":state.revision,
                    "saveSHA256Before":SHA256.hash(data:initialSave).map{String(format:"%02x",$0)}.joined(),
                    "saveSHA256After":SHA256.hash(data:finalSave).map{String(format:"%02x",$0)}.joined(),
                    "failure":String(reflecting:error),"cases":cases]
                if let data=try? JSONSerialization.data(withJSONObject:failure,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:reportURL,options:.atomic)}
                writeReceipt("effect_budget_regression_error",String(reflecting:error))
            }
        }
        #endif
    }
}
