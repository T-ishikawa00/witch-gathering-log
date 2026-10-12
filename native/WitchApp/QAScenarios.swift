import Foundation

/// Explicit isolated test setup, never used by the normal save. Time is simulated only here.
enum QAScenarios {
    static func initial(catalog:GameCatalog,scenario:String?) async throws -> GameSnapshot {
        if scenario == "area-routing" {
            // Isolated render-flow fixture only: opens the two tested regions and
            // synthetic boss gate markers; it does not grant combat rewards.
            var state=GameSnapshot.newGame(catalog:catalog)
            state.lastClaimAt=Date()
            state.unlockedRegionIDs.formUnion(["R01","R04"])
            state.completedEncounterIDs.formUnion(["B_R01_A","B_R03_B","B_R04_A"])
            state.activeRegionID="R01"
            state.gatherTargetMaterialID=catalog.availableGatherMaterialIDs(in:"R01",unlockedRegionIDs:state.unlockedRegionIDs,completedEncounterIDs:state.completedEncounterIDs).first
            return state
        }
        if let scenario,scenario.hasPrefix("detail-item-") {
            let parts=scenario.components(separatedBy:"-")
            guard (parts.count==4 || parts.count==5),catalog.actorIDs.contains(parts[2]),
                  parts.count==4 || (parts[2]=="C_WITCH" && parts[4]=="travel"),
                  let definition=catalog.gear.first(where:{$0.id==parts[3] && $0.actorIDs.contains(parts[2])}) else{throw CoreError.invalidCommand("Invalid isolated single-detail fixture")}
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date()
            let item=GearInstance(definitionID:definition.id,ownerID:parts[2],qualityID:"Q1")
            initial.gear.append(item);initial.equippedGearIDs[parts[2]+"|"+definition.slot]=item.id
            if parts.count==5 {initial.ownedCosmeticIDs.insert("ERNA_TRAVEL");initial.selectedCosmeticIDs["C_WITCH"]="ERNA_TRAVEL"}
            return initial
        }
        if let scenario,scenario.hasPrefix("book-") {
            let id=String(scenario.dropFirst(5))
            guard ["EQ_A_01","EQ_A_02","EQ_A_03"].contains(id),let definition=catalog.gear.first(where:{$0.id==id && $0.actorIDs.contains("C_APPRENTICE")}) else{throw CoreError.invalidCommand("Invalid isolated book-art fixture")}
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date()
            let item=GearInstance(definitionID:id,ownerID:"C_APPRENTICE",qualityID:"Q1")
            initial.gear.append(item);initial.equippedGearIDs["C_APPRENTICE|"+definition.slot]=item.id
            return initial
        }
        if scenario == "erna-body-fit-r061" {
            // Off-live R061 fixture: both ERNA-compatible body candidates are owned,
            // neither is equipped. The XCTest must perform the real equip/replacement.
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date()
            guard let body01=catalog.gear.first(where:{$0.id=="EQ_BODY_01" && $0.actorIDs.contains("C_WITCH") && $0.slot=="body"}),
                  let body02=catalog.gear.first(where:{$0.id=="EQ_BODY_02" && $0.actorIDs.contains("C_WITCH") && $0.slot=="body"}) else {
                throw CoreError.invalidCommand("ERNA body-fit fixture requires both C_WITCH body definitions")
            }
            initial.gear.append(GearInstance(id:UUID(uuidString:"6A9220A2-77F0-4DB7-8DF3-01D4C7956101")!,definitionID:body01.id,qualityID:"Q1"))
            initial.gear.append(GearInstance(id:UUID(uuidString:"6A9220A2-77F0-4DB7-8DF3-01D4C7956102")!,definitionID:body02.id,qualityID:"Q1"))
            initial.ownedCosmeticIDs.insert("ERNA_TRAVEL")
            return initial
        }
        if let scenario,scenario.hasPrefix("details-") {
            let parts=scenario.components(separatedBy:"-")
            guard (parts.count==3 || parts.count==4),catalog.actorIDs.contains(parts[1]),["01","02","03"].contains(parts[2]),
                  parts.count==3 || (parts[1]=="C_WITCH" && parts[3]=="travel") else{throw CoreError.invalidCommand("Invalid isolated detail-art fixture")}
            let actor=parts[1],tier=parts[2]
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date()
            let ids=["EQ_BODY_","EQ_HAND_","EQ_FEET_","EQ_AMU_","EQ_RING_"].map{$0+tier}+(actor=="C_FAMILIAR" ? ["EQ_F_"+tier]:actor=="C_SMITH" && tier != "01" ? ["EQ_S_"+tier]:[])
            for definition in catalog.gear where ids.contains(definition.id) && definition.actorIDs.contains(actor) {
                let item=GearInstance(definitionID:definition.id,ownerID:actor,qualityID:"Q1")
                initial.gear.append(item);initial.equippedGearIDs[actor+"|"+definition.slot]=item.id
            }
            if parts.count==4 {
                initial.ownedCosmeticIDs.insert("ERNA_TRAVEL")
                initial.selectedCosmeticIDs["C_WITCH"]="ERNA_TRAVEL"
            }
            return initial
        }
        if let scenario,scenario.hasPrefix("gear-") {
            let parts=scenario.components(separatedBy:"-")
            guard parts.count>=3,let definition=catalog.gear.first(where:{$0.id==parts[1] && $0.actorIDs.contains("C_WITCH") && $0.slot=="weapon"}) else{throw NSError(domain:"WitchQA",code:1,userInfo:[NSLocalizedDescriptionKey:"Invalid isolated gear-art fixture"])}
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date()
            let item=GearInstance(definitionID:definition.id,ownerID:"C_WITCH",qualityID:"Q1")
            initial.gear.append(item);initial.equippedGearIDs["C_WITCH|weapon"]=item.id
            if parts[2]=="travel" {initial.ownedCosmeticIDs.insert("ERNA_TRAVEL");initial.selectedCosmeticIDs["C_WITCH"]="ERNA_TRAVEL"}
            if parts.count==4,parts[3]=="moon" {initial.ownedCosmeticIDs.insert("STAFF_MOON");initial.selectedWeaponAppearanceIDs["C_WITCH"]="STAFF_MOON"}
            return initial
        }
        if let scenario,scenario.hasPrefix("appearance-") {
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date()
            initial.ownedCosmeticIDs.formUnion(["ERNA_TRAVEL","STAFF_MOON","STAFF_BRANCH"])
            if scenario.contains("travel") {initial.selectedCosmeticIDs["C_WITCH"]="ERNA_TRAVEL"}
            initial.selectedWeaponAppearanceIDs["C_WITCH"]=scenario.hasSuffix("moon") ? "STAFF_MOON":"STAFF_BRANCH"
            return initial
        }
        if scenario=="gathering" {
            var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=Date().addingTimeInterval(-8*3600);return initial
        }
        if scenario=="gathering-cue-r01g3" {
            // A bounded visual QA fixture, not earned progression. The user-flow
            // test collects and dismisses the sheet through actual UI controls.
            var initial=GameSnapshot.newGame(catalog:catalog)
            initial.lastClaimAt=Date().addingTimeInterval(-8*3600)
            initial.completedEncounterIDs=Set(catalog.enemies.filter{$0.regionID=="R01"}.map(\.id))
            initial.gatherTargetMaterialID="M_R01_G3"
            return initial
        }
        if scenario=="exhausted-revision" {
            var state=GameSnapshot.newGame(catalog:catalog)
            state.lastClaimAt=Date()
            state.revision=Int64.max
            return state
        }
        if scenario=="challenge" {
            // Endgame rendering fixture, not evidence of earning these items/progression.
            var state=GameSnapshot.newGame(catalog:catalog);state.lastClaimAt=Date()
            state.unlockedRegionIDs=Set(catalog.regions.map(\.id));state.completedEncounterIDs=Set(catalog.enemies.map(\.id));state.activeRegionID="R05"
            state.gatherTargetMaterialID=catalog.regions.first{$0.id=="R05"}?.gatherMaterialIDs.first
            let build=["EQ_W_G2","EQ_A_03","EQ_S_03","EQ_F_03"]
            for (actor,template) in zip(state.partyActorIDs,build) {
                guard let def=catalog.gear.first(where:{$0.id==template}) else{continue}
                let item=GearInstance(definitionID:template,ownerID:actor,protected:true,enhancement:10,qualityID:"Q4")
                state.gear.append(item);state.equippedGearIDs[actor+"|"+def.slot]=item.id
            }
            return state
        }
        if scenario=="inventory" {
            // Stress-only fixture: currency and tutorial state are explicit QA inputs.
            var initial=GameSnapshot.newGame(catalog:catalog);initial.currency["ticket_free"]=500;initial.gachaUnlocked=true;initial.lastClaimAt=Date()
            let engine=try GameEngine(catalog:catalog,saves:SaveRepository(initial:initial))
            for seed in 1...10 {let state=await engine.snapshot();_ = try await engine.dispatch(.mockSummon(poolDefinitionIDs:catalog.gear.map(\.id),count:50,costCurrencyID:"ticket_free",seed:UInt64(seed)),operationID:UUID(),expectedRevision:state.revision)}
            return await engine.snapshot()
        }
        guard scenario=="onboarding" else{return .newGame(catalog:catalog)}
        guard let region=catalog.regions.first,region.gatherMaterialIDs.count>=2 else{return .newGame(catalog:catalog)}
        let now=Date();let work=Double(region.workSeconds)
        var initial=GameSnapshot.newGame(catalog:catalog);initial.lastClaimAt=now.addingTimeInterval(-work*12)
        let engine=try GameEngine(catalog:catalog,saves:SaveRepository(initial:initial))
        var current=await engine.snapshot()
        _ = try await engine.dispatch(.setGatherTargetAt(resourceID:region.gatherMaterialIDs[1],now:now.addingTimeInterval(-work*6)),operationID:UUID(),expectedRevision:current.revision)
        current=await engine.snapshot()
        _ = try await engine.claimOffline(now:now,operationID:UUID(),expectedRevision:current.revision)
        return await engine.snapshot()
    }
}
