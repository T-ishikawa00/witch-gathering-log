import XCTest
@testable import WitchGameCore

final class CandidatePresentationRegressionTests:XCTestCase {
    private func assertReplays(_ result:CombatResult,file:StaticString=#filePath,line:UInt=#line) {
        let initial=result.initialPartyHP.merging(result.initialEnemyHP){first,_ in first}
        let final=result.remainingPartyHP.merging(result.remainingEnemyHP){first,_ in first}
        XCTAssertEqual(R6CombatPresentationSemantics.replay(events:result.events,initialHP:initial),final,
                       "Presentation must replay the simulator's actual HP-changing events",file:file,line:line)
    }
    func testAllThirtyCandidateEnemiesReplayHPForThreeSeeds() throws {
        let catalog=try GameCatalog.bundledTestOverlay()
        let party=["C_WITCH","C_FAMILIAR","C_APPRENTICE","C_SMITH"].map {catalog.projectCombatant(for:$0,with:[])}
        XCTAssertEqual(catalog.enemies.count,30)
        for definition in catalog.enemies {
            let enemy=Combatant(id:definition.id,maxHP:definition.hp,attack:definition.attack,
                                defense:definition.defense,actionPattern:definition.actionPattern ?? "standard")
            for seed:UInt64 in [51,52,53] {
                let result=try R6TimelineSimulator.run(party:party,enemies:[enemy],seed:seed,maxDurationMs:35_000)
                assertReplays(result)
            }
        }
    }
    func testReflectionAndRegenerationReplayBeforeEitherSideDies() throws {
        let party=["C_WITCH","C_FAMILIAR","C_APPRENTICE","C_SMITH"].map {
            Combatant(id:$0,maxHP:20_000,attack:100,defense:0)
        }
        for (id,pattern,event) in [("E_R02_03","reflect","enemy_reflect_projectile"),
                                   ("E_R05_04","regenPoison","enemy_regen")] {
            let enemy=Combatant(id:id,maxHP:100_000,attack:20,defense:0,actionPattern:pattern,firstTelegraphMs:0)
            let result=try R6TimelineSimulator.run(party:party,enemies:[enemy],seed:51,maxDurationMs:20_000)
            XCTAssertTrue(result.events.contains {$0.kind==event && $0.amount>0},"Must exercise a real \(event), not only an enum classification")
            XCTAssertTrue(result.remainingPartyHP.values.allSatisfy {$0>0})
            XCTAssertGreaterThan(result.remainingEnemyHP[id] ?? 0,0,"A dead enemy could hide missed healing through zero clamping")
            assertReplays(result)
        }
    }
}
