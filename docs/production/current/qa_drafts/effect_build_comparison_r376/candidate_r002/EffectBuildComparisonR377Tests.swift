import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// Four fixed read-only previews from UUIDs already present in archived R368 simulation inventory.
/// Latent slot rolls differ naturally, so outcomes are observational, not causal effect estimates.
final class EffectBuildComparisonR377Tests: XCTestCase {
    struct Pin: Decodable { let path:String; let sha256:String; let sizeBytes:Int }
    struct Pair: Decodable {
        let family:String; let challengeID:String; let actorID:String; let actorSlot:String
        let candidateID:String; let controlID:String; let candidateDefinitionID:String; let controlDefinitionID:String
        let qualityID:String; let enhancement:Int; let refinement:Int; let investmentDust:Int; let catalogAttack:Int
        let candidateLatentAffix:String; let controlLatentAffix:String; let expectedEffectKinds:[String]
    }
    struct Input: Decodable {
        let schema:String; let status:String; let fixedWorktree:String
        let r368InputManifest:Pin; let save:Pin; let report:Pin; let appIdentity:Pin; let pairLedger:Pin; let seeds:[UInt64]; let pairs:[Pair]
    }
    struct GearEvidence:Encodable {
        let id:String; let definitionID:String; let qualityID:String; let enhancement:Int; let refinement:Int; let investmentDust:Int
        let ownerID:String?; let latentSlots:CandidateLatentSlotsR003?; let activeFirstSlot:String?
    }
    struct Row:Encodable {
        let family:String; let challengeID:String; let seed:UInt64; let arm:String; let actorID:String; let actorSlot:String
        let gear:GearEvidence; let won:Bool; let ticks:Int; let initialPartyHP:[String:Int]; let remainingPartyHP:[String:Int]
        let initialEnemyHP:[String:Int]; let remainingEnemyHP:[String:Int]; let eventCounts:[String:Int]; let events:[CombatEvent]
    }
    struct Report:Encodable {
        let schema:String; let status:String; let sourceSaveSHA256:String; let sourceReportSHA256:String; let r368InputManifestSHA256:String
        let runtimeProfileID:String; let runtimeFingerprint:String; let workPolicyFingerprint:String; let seeds:[UInt64]
        let previewCount:Int; let previews:[Row]; let interpretation:[String]
    }
    func testFourEarnedEffectFamiliesAcrossThreeSeeds() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let mp=env["WITCH_R377_INPUT_MANIFEST"],mp.hasPrefix("/"),let ms=env["WITCH_R377_INPUT_MANIFEST_SHA256"],
              env["WITCH_R377_WORKTREE"]=="/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg",
              let op=env["WITCH_R377_OUTPUT"],op.hasPrefix("/"),URL(fileURLWithPath:op).lastPathComponent=="report.json" else {
            throw CoreError.invalidCommand("R377 requires absolute pinned paths and a fresh report.json")
        }
        let root=URL(fileURLWithPath:env["WITCH_R377_WORKTREE"]!,isDirectory:true).standardizedFileURL
        let manifestURL=URL(fileURLWithPath:mp).standardizedFileURL
        guard manifestURL.path.hasPrefix(root.path+"/") else { throw CoreError.invalidCommand("manifest escaped fixed worktree") }
        let mb=try Data(contentsOf:manifestURL); XCTAssertEqual(Self.sha(mb),ms)
        let input=try JSONDecoder().decode(Input.self,from:mb)
        XCTAssertEqual(input.schema,"effect-build-comparison-r377-input-r001"); XCTAssertEqual(input.status,"PREPARED_NOT_RUN")
        XCTAssertEqual(input.fixedWorktree,root.path); XCTAssertEqual(input.seeds,[37701,37702,37703])
        XCTAssertEqual(input.pairs.map(\.family),["barrier_ward","smith_counter_latent","apprentice_heal_latent","familiar_chase_latent"])
        func pinned(_ p:Pin)throws->(URL,Data){
            let u=root.appendingPathComponent(p.path).standardizedFileURL
            guard u.path.hasPrefix(root.path+"/") else { throw CoreError.invalidCommand("pinned file escaped worktree") }
            let d=try Data(contentsOf:u); XCTAssertEqual(d.count,p.sizeBytes); XCTAssertEqual(Self.sha(d),p.sha256); return(u,d)
        }
        let (saveURL,saveBytes)=try pinned(input.save), (reportURL,reportBytes)=try pinned(input.report), (identityURL,identityBytes)=try pinned(input.appIdentity)
        let (_,ledgerBytes)=try pinned(input.pairLedger); XCTAssertEqual(Self.sha(ledgerBytes),input.pairLedger.sha256)
        let ledger=try XCTUnwrap(JSONSerialization.jsonObject(with:ledgerBytes) as? [String:Any])
        XCTAssertEqual(ledger["schema"] as? String,"r377-owned-effect-pair-ledger-r001")
        XCTAssertEqual(ledger["status"] as? String,"READ_ONLY_INVENTORY_FACTS")
        let ledgerPairs=try XCTUnwrap(ledger["pairs"] as? [[String:Any]])
        XCTAssertEqual(ledgerPairs.count,input.pairs.count)
        for pair in input.pairs {
            let fact=try XCTUnwrap(ledgerPairs.first{$0["family"] as? String==pair.family})
            XCTAssertEqual(fact["challengeID"] as? String,pair.challengeID)
            XCTAssertEqual(fact["actorID"] as? String,pair.actorID)
            XCTAssertEqual(fact["actorSlot"] as? String,pair.actorSlot)
            let candidateFact=try XCTUnwrap(fact["candidate"] as? [String:Any])
            let controlFact=try XCTUnwrap(fact["control"] as? [String:Any])
            XCTAssertEqual(candidateFact["id"] as? String,pair.candidateID)
            XCTAssertEqual(controlFact["id"] as? String,pair.controlID)
        }
        let upstreamURL=root.appendingPathComponent(input.r368InputManifest.path).standardizedFileURL
        let upstream=try Data(contentsOf:upstreamURL); XCTAssertEqual(Self.sha(upstream),input.r368InputManifest.sha256)
        let envObj=try XCTUnwrap(JSONSerialization.jsonObject(with:saveBytes) as? [String:Any])
        let snapObj=try XCTUnwrap(envObj["snapshot"] as? [String:Any])
        let snapData=try JSONSerialization.data(withJSONObject:snapObj,options:[.sortedKeys,.withoutEscapingSlashes])
        let snapshot=try JSONDecoder().decode(GameSnapshot.self,from:snapData)
        for id in ["CH_R02_01","CH_R02_02","CH_R04_02","CH_R05_03"] { XCTAssertTrue(snapshot.completedEncounterIDs.contains("CHALLENGE_CLEAR|\(id)")) }
        let source=try XCTUnwrap(JSONSerialization.jsonObject(with:reportBytes) as? [String:Any])
        XCTAssertEqual(source["status"] as? String,"RUNNER_FINISHED_XCTEST_RESULT_SEPARATE")
        XCTAssertEqual(source["baseRuntimeProfileID"] as? String,base.profileID)
        XCTAssertEqual(source["baseRuntimeConfigurationFingerprint"] as? String,base.configurationFingerprint)
        XCTAssertEqual(source["runtimeProfileID"] as? String,r230.profileID)
        XCTAssertEqual(source["runtimeConfigurationFingerprint"] as? String,r230.configurationFingerprint)
        XCTAssertEqual(source["partyWorkPolicyFingerprint"] as? String,work.policyFingerprint)
        XCTAssertEqual(source["paidSummonDrawCount"] as? Int,0); XCTAssertEqual(source["freeSummonDrawCount"] as? Int,155)
        XCTAssertEqual((source["syntheticGrantReceipts"] as? [Any])?.count,0); XCTAssertEqual((source["naturalGearAcquisitionRecords"] as? [Any])?.count,96)
        let base=try GameRuntimeConfigurationR098.resolve(growthStrengthBP:500)
        XCTAssertEqual(base.profileID,"app-candidate-r098-v1-growth-500bp")
        XCTAssertEqual(base.configurationFingerprint,"4b556e250948bd35ff31a7bdc9dbbc01a671e358565182f556ab1d8d3bf4efb0")
        let r230=try GameRuntimeEnhancementProfileR230(base:base)
        let integrated=GameRuntimeIntegratedEquipmentProfileR355(base:r230)
        let work=try PartyWorkPolicyR144(baseProfileID:base.profileID,baseConfigurationFingerprint:base.configurationFingerprint)
        let store=try SaveRepository(initial:snapshot,fileURL:nil)
        let engine=try integrated.makeEngine(saves:store,candidatePartyWorkPolicyR144:work,firstCraftAidCapabilityR179:.enabled)
        var outcomes:[Row]=[]
        for pair in input.pairs {
            let candID=try XCTUnwrap(UUID(uuidString:pair.candidateID)), ctrlID=try XCTUnwrap(UUID(uuidString:pair.controlID))
            let cand=try XCTUnwrap(snapshot.gear.first{$0.id==candID}), ctrl=try XCTUnwrap(snapshot.gear.first{$0.id==ctrlID})
            XCTAssertNil(cand.ownerID); XCTAssertNil(ctrl.ownerID)
            XCTAssertEqual(cand.definitionID,pair.candidateDefinitionID); XCTAssertEqual(ctrl.definitionID,pair.controlDefinitionID)
            for gear in [cand,ctrl] { XCTAssertEqual(gear.qualityID,pair.qualityID); XCTAssertEqual(gear.enhancement,pair.enhancement); XCTAssertEqual(gear.refinement,pair.refinement); XCTAssertEqual(gear.investmentDust,pair.investmentDust) }
            XCTAssertFalse(Set(snapshot.equippedGearIDs.values).contains(candID)); XCTAssertFalse(Set(snapshot.equippedGearIDs.values).contains(ctrlID))
            XCTAssertEqual(engine.catalog.gear.first{$0.id==cand.definitionID}?.slot,pair.actorSlot.split(separator:"|").last.map { String($0) })
            if pair.catalogAttack>0 { XCTAssertEqual(base.catalog.gearAttackBonuses[cand.definitionID],pair.catalogAttack); XCTAssertEqual(base.catalog.gearAttackBonuses[ctrl.definitionID],pair.catalogAttack) }
            XCTAssertEqual(cand.candidateLatentSlots?.slots.first?.affixID,pair.candidateLatentAffix)
            XCTAssertEqual(ctrl.candidateLatentSlots?.slots.first?.affixID,pair.controlLatentAffix)
            XCTAssertNotEqual(cand.candidateLatentSlots,ctrl.candidateLatentSlots,"natural latent rolls are retained as confounds")
            var cm=snapshot.equippedGearIDs, xm=snapshot.equippedGearIDs; cm[pair.actorSlot]=candID; xm[pair.actorSlot]=ctrlID
            let loadouts=[OwnedPartyLoadoutR181(id:"\(pair.family)_candidate",gearByActorSlot:cm),OwnedPartyLoadoutR181(id:"\(pair.family)_control",gearByActorSlot:xm)]
            for seed in input.seeds {
                let previews=try engine.previewChallengeOwnedPartyLoadoutsR181(challengeID:pair.challengeID,seed:seed,snapshot:snapshot,loadouts:loadouts)
                XCTAssertEqual(previews.count,2)
                for preview in previews {
                    let isCand=preview.loadoutID.hasSuffix("_candidate"), gear=isCand ? cand : ctrl
                    let counts=Dictionary(grouping:preview.result.events.map(\.kind),by:{$0}).mapValues(\.count)
                    outcomes.append(Row(family:pair.family,challengeID:pair.challengeID,seed:seed,arm:isCand ? "candidate_effect":"control",actorID:pair.actorID,actorSlot:pair.actorSlot,
                        gear:GearEvidence(id:gear.id.uuidString,definitionID:gear.definitionID,qualityID:gear.qualityID,enhancement:gear.enhancement,refinement:gear.refinement,investmentDust:gear.investmentDust,ownerID:gear.ownerID,latentSlots:gear.candidateLatentSlots,activeFirstSlot:gear.candidateLatentSlots?.slots.first?.affixID),
                        won:preview.result.won,ticks:preview.result.ticks,initialPartyHP:preview.result.initialPartyHP,remainingPartyHP:preview.result.remainingPartyHP,initialEnemyHP:preview.result.initialEnemyHP,remainingEnemyHP:preview.result.remainingEnemyHP,eventCounts:counts,events:preview.result.events))
                }
            }
        }
        XCTAssertEqual(outcomes.count,24)
        for pair in input.pairs {
            let candRows=outcomes.filter{$0.family==pair.family && $0.arm=="candidate_effect"}
            XCTAssertEqual(candRows.count,3)
            XCTAssertTrue(candRows.contains{ row in pair.expectedEffectKinds.contains{row.eventCounts[$0,default:0]>0} },"candidate effect not observed: \(pair.family)")
        }
        let after=await store.snapshot(); XCTAssertEqual(after,snapshot)
        XCTAssertEqual(try Data(contentsOf:saveURL),saveBytes); XCTAssertEqual(try Data(contentsOf:reportURL),reportBytes); XCTAssertEqual(try Data(contentsOf:identityURL),identityBytes)
        let output=URL(fileURLWithPath:op).standardizedFileURL
        guard output.path.hasPrefix(root.path+"/"),!FileManager.default.fileExists(atPath:output.path) else { throw CoreError.invalidCommand("R377 report must be new inside worktree") }
        let reportOut=Report(schema:"effect-build-comparison-r377-v1",status:"OBSERVATIONAL_OWNED_EFFECT_PREVIEWS_NOT_BALANCE_ACCEPTANCE",sourceSaveSHA256:input.save.sha256,sourceReportSHA256:input.report.sha256,r368InputManifestSHA256:input.r368InputManifest.sha256,runtimeProfileID:r230.profileID,runtimeFingerprint:r230.configurationFingerprint,workPolicyFingerprint:work.policyFingerprint,seeds:input.seeds,previewCount:outcomes.count,previews:outcomes,interpretation:["24 no-reward previews across four existing-inventory pairs and three fixed seeds.","Same saved party/runtime/seed/challenge within each pair; one gear UUID changes in one occupied slot.","Natural latent rolls differ, including non-active slots; outcomes are descriptive, not a pure causal estimate.","R368 is a virtual cohort; no ordinary human acquisition, balance, optimality, fun, paid value, approval, or 15-design-completion claim."])
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        try encoder.encode(reportOut).write(to:output,options:.withoutOverwriting)
    }
    private static func sha(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
}
