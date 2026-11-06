import Foundation
import XCTest
@testable import WitchGameCore

final class ProductWorkshopR1Tests: XCTestCase {
    private func goal(_ runtime: GameRuntimeConfigurationR098, state: GameSnapshot) throws -> RecipeGoalProjectionR035.Goal {
        try XCTUnwrap(RecipeGoalProjectionR035.goals(catalog:runtime.catalog, materialCounts:state.materials,
            ownedGearTemplateIDs:Set(state.gear.map(\.definitionID)), unlockedRegionIDs:state.unlockedRegionIDs,
            completedEncounterIDs:state.completedEncounterIDs,
            firstCraftAidEligibleR179:state.firstCraftAidEligibleR179 == true,
            craftedGearOnce:state.craftedGearOnce, firstCraftAidCapabilityR179:.enabled)
            .first { $0.recipeID == "RC_EQ_F_01" })
    }

    func testPresentationHoldsAcceptedFirstCraftCostsUntilCompletion() throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        var state = try runtime.makeNewSnapshot()
        state.firstCraftAidEligibleR179 = true
        let missing = try goal(runtime,state:state)
        XCTAssertFalse(missing.ready)
        XCTAssertEqual(WorkshopPresentationR1(liveGoal:missing,confirmation:false).phase,.missingRequirements)
        state.materials.merge(FirstCraftCostProjectionR179.eligibleFirstCraft) { _, new in new }
        let accepted = try goal(runtime,state:state)
        XCTAssertTrue(accepted.ready)
        XCTAssertEqual(WorkshopPresentationR1(liveGoal:accepted,confirmation:false).phase,.ready)
        XCTAssertEqual(WorkshopPresentationR1(liveGoal:accepted,confirmation:true).phase,.awaitingConfirmation)
        state.craftedGearOnce = true
        state.materials = [:]
        let next = try goal(runtime,state:state)
        XCTAssertFalse(next.ready)
        XCTAssertNotEqual(next.requirements,accepted.requirements)
        let processing = WorkshopPresentationR1(liveGoal:next,confirmation:true,
            operationPhase:.processing,acceptedGoal:accepted)
        XCTAssertEqual(processing.phase,.processing)
        XCTAssertEqual(processing.goal,accepted,"A post-save refresh must not replace the cost shown for the accepted craft with next-craft costs")
        XCTAssertEqual(WorkshopPresentationR1(liveGoal:next,confirmation:true,operationPhase:.failed).goal,next)
        XCTAssertEqual(WorkshopPresentationR1(liveGoal:next,confirmation:true,operationPhase:.completed).phase,.completed)
        XCTAssertEqual(WorkshopPresentationR1(liveGoal:nil,confirmation:false).phase,.selected)
    }

    func testSelectingGoalAndCancellingPreviewNeverSpendsOrCrafts() async throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        let initial = try runtime.makeNewSnapshot()
        let saves = try SaveRepository(initial:initial)
        let engine = try runtime.makeEngine(saves:saves)
        _ = try await engine.dispatchConfirmingSavedReceipt(.setTrackedRecipe("RC_EQ_F_01"),operationID:UUID(),expectedRevision:initial.revision)
        let selected = await engine.snapshot()
        _ = WorkshopPresentationR1(liveGoal:try goal(runtime,state:selected),confirmation:false)
        _ = WorkshopPresentationR1(liveGoal:try goal(runtime,state:selected),confirmation:true)
        let cancelled = await engine.snapshot()
        XCTAssertEqual(selected,cancelled)
        XCTAssertEqual(initial.materials,cancelled.materials)
        XCTAssertEqual(initial.gear,cancelled.gear)
        XCTAssertFalse(cancelled.craftedGearOnce)
    }

    func testCraftWriteFailureEveryPhaseAndSameOperationColdReplay() async throws {
        let runtime = try GameRuntimeConfigurationR098.resolve()
        // Synthetic inventory is confined to this fault test; it is not earned progression evidence.
        var initial = try runtime.makeNewSnapshot()
        initial.materials = Dictionary(uniqueKeysWithValues:runtime.catalog.materialIDs.map { ($0,100) })
        for phase in [SaveWritePhase.beforeStage,.afterStageSync,.afterBackupReplace,.beforePrimaryReplace,.afterPrimaryReplace] {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("product-craft-r1-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let url=directory.appendingPathComponent("save.json")
            let seed=try SaveRepository(initial:initial,fileURL:url)
            _ = try await seed.transact(expectedRevision:initial.revision,operationID:UUID(),requestFingerprint:"seed") { _ in "seed" }
            let before=await seed.snapshot()
            let bytes=try Data(contentsOf:url)
            let saves=try SaveRepository(fileURL:url,faultInjector:{ reached in
                if reached == phase {throw SaveRepositoryError.injectedWriteFailure(phase.rawValue)}
            })
            let engine=try runtime.makeEngine(saves:saves)
            let op=UUID()
            do {
                let receipt=try await engine.dispatchConfirmingSavedReceipt(.craftRecipe("RC_EQ_F_01"),operationID:op,expectedRevision:before.revision)
                XCTAssertEqual(phase,.afterPrimaryReplace)
                XCTAssertEqual(receipt.revision,before.revision+1)
            } catch {
                XCTAssertNotEqual(phase,.afterPrimaryReplace,"Confirmed saved operation must be presented as completed: \(error)")
                XCTAssertEqual(try Data(contentsOf:url),bytes)
            }
            let cold=try SaveRepository(fileURL:url)
            let state=await cold.snapshot()
            if phase == .afterPrimaryReplace {
                XCTAssertEqual(state.gear.count,before.gear.count+1)
                let recipe=try XCTUnwrap(runtime.catalog.recipes.first{$0.id == "RC_EQ_F_01"})
                for (id,cost) in recipe.costs {XCTAssertEqual(state.materials[id,default:0],before.materials[id,default:0]-cost)}
                let reopened=try runtime.makeEngine(saves:cold)
                _ = try await reopened.dispatchConfirmingSavedReceipt(.craftRecipe("RC_EQ_F_01"),operationID:op,expectedRevision:before.revision)
                let replay=await reopened.snapshot()
                XCTAssertEqual(replay,state,"Same operation after restart cannot spend or grant twice")
            } else {XCTAssertEqual(state,before)}
        }
    }

    func testConcurrentConfirmationsAtSameRevisionCanOnlyCraftOnce() async throws {
        let runtime=try GameRuntimeConfigurationR098.resolve()
        var initial=try runtime.makeNewSnapshot()
        initial.materials=Dictionary(uniqueKeysWithValues:runtime.catalog.materialIDs.map{($0,100)})
        let engine=try runtime.makeEngine(saves:SaveRepository(initial:initial))
        let revision=initial.revision
        let successes=await withTaskGroup(of:Bool.self,returning:Int.self) { group in
            for _ in 0..<8 {group.addTask {
                do {_ = try await engine.dispatchConfirmingSavedReceipt(.craftRecipe("RC_EQ_F_01"),operationID:UUID(),expectedRevision:revision);return true}
                catch {return false}
            }}
            var count=0
            for await success in group {if success {count+=1}}
            return count
        }
        XCTAssertEqual(successes,1)
        let after=await engine.snapshot()
        XCTAssertEqual(after.gear.count,initial.gear.count+1)
    }

    func testOfflineClaimPostReplaceRecoveryCannotGrantTwice() async throws {
        let runtime=try GameRuntimeConfigurationR098.resolve()
        var initial=try runtime.makeNewSnapshot()
        let region=try XCTUnwrap(runtime.catalog.regions.first)
        let now=Date(timeIntervalSince1970:1_800_000_000)
        initial.activeRegionID=region.id
        initial.gatherTargetMaterialID=try XCTUnwrap(region.gatherMaterialIDs.first)
        initial.lastClaimAt=now.addingTimeInterval(-Double(region.workSeconds)*2)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("product-claim-r1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent("save.json")
        let repository=try SaveRepository(initial:initial,fileURL:url,faultInjector:{phase in
            if phase == .afterPrimaryReplace {throw SaveRepositoryError.injectedWriteFailure("after replace")}
        })
        let engine=try runtime.makeEngine(saves:repository)
        let operationID=UUID()
        let receipt=try await engine.claimOfflineConfirmingSavedReceipt(now:now,operationID:operationID,expectedRevision:initial.revision)
        let saved=await engine.snapshot()
        XCTAssertEqual(saved.materials[initial.gatherTargetMaterialID!,default:0],initial.materials[initial.gatherTargetMaterialID!,default:0]+2)
        let cold=try runtime.makeEngine(saves:SaveRepository(fileURL:url))
        let replay=try await cold.claimOfflineConfirmingSavedReceipt(now:now,operationID:operationID,expectedRevision:initial.revision)
        XCTAssertEqual(replay,receipt)
        let after=await cold.snapshot()
        XCTAssertEqual(after,saved)
    }
}
