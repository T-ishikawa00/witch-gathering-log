import XCTest
@testable import WitchGameCore

final class CandidateLatentTimelineR030Tests: XCTestCase {
    private func modifiers(_ values: [String: Int]) throws -> CandidateLatentCombatModifiersR005 {
        try CandidateLatentCombatModifiersR005(validating: values)
    }

    private func party(witchEffects: Set<String> = [], witchModifiers: CandidateLatentCombatModifiersR005? = nil,
                       apprenticeEffects: Set<String> = [], apprenticeModifiers: CandidateLatentCombatModifiersR005? = nil,
                       smithModifiers: CandidateLatentCombatModifiersR005? = nil) -> [Combatant] {
        [
            Combatant(id: "C_WITCH", maxHP: 10_000, attack: 300, defense: 0, effectIDs: witchEffects,
                      candidateLatentModifiersR004: witchModifiers),
            Combatant(id: "C_FAMILIAR", maxHP: 10_000, attack: 300, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 10_000, attack: 300, defense: 0, effectIDs: apprenticeEffects,
                      candidateLatentModifiersR004: apprenticeModifiers),
            Combatant(id: "C_SMITH", maxHP: 10_000, attack: 300, defense: 0,
                      candidateLatentModifiersR004: smithModifiers)
        ]
    }

    private let passiveEnemy = Combatant(id: "E_TEST", maxHP: 1_000_000, attack: 0, defense: 0,
                                         actionPattern: "stationary")

    func testOptionalCombatantModifierCodableRoundTripAndLegacyDecode() throws {
        let candidate = Combatant(id: "C_WITCH", maxHP: 100, attack: 20, defense: 3,
                                  candidateLatentModifiersR004: try modifiers(["crit_chance_bp": 1_250,
                                                                            "haste_bp": 1_100,
                                                                            "crit_multiplier_bp": 17_500]))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(candidate)
        XCTAssertEqual(try decoder.decode(Combatant.self, from: encoded), candidate)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(
            Combatant(id: "C_WITCH", maxHP: 100, attack: 20, defense: 3))) as? [String: Any])
        legacyObject.removeValue(forKey: "candidateLatentModifiersR004")
        let legacy = try decoder.decode(Combatant.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertNil(legacy.candidateLatentModifiersR004)

        let validModifiers = try modifiers(["crit_chance_bp": 1_250, "crit_multiplier_bp": 17_500])
        var invalidObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(validModifiers)) as? [String: Any])
        invalidObject["critChanceBP"] = Int.max
        let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)
        XCTAssertThrowsError(try decoder.decode(CandidateLatentCombatModifiersR005.self, from: invalidData))
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["direct_bonus_bp": -1]))
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["crit_chance_bp": Int.max]))
    }

    func testNilModifiersPreserveTimelineAndSourceProfileIgnoresCandidateAggregate() throws {
        let plainParty = party()
        let candidateParty = party(witchModifiers: try modifiers(["hp_pct": 5_000,
                                                                "power_pct": 4_000,
                                                                "defense_pct": 5_000,
                                                                "crit_chance_bp": 500,
                                                                "crit_multiplier_bp": 15_000,
                                                                "haste_bp": 0,
                                                                "guard_chance_bp": 4_500]))
        let plain = try R6TimelineSimulator.run(party: plainParty, enemies: [passiveEnemy], seed: 19, maxDurationMs: 5_000)
        let zeroCandidate = try R6TimelineSimulator.run(party: candidateParty, enemies: [passiveEnemy], seed: 19, maxDurationMs: 5_000)
        XCTAssertEqual(plain, zeroCandidate, "a fully baseline typed aggregate must not perturb candidate scheduling or events")

        let profileParty = party(witchModifiers: try modifiers(["crit_chance_bp": 6_000,
                                                              "crit_multiplier_bp": 22_500,
                                                              "direct_bonus_bp": 6_000,
                                                              "haste_bp": 5_000,
                                                              "cdr_bp": 2_500,
                                                              "dot_bonus_bp": 10_000]))
        let stripped = profileParty.map { actor in
            Combatant(id: actor.id, maxHP: actor.maxHP, attack: actor.attack, defense: actor.defense,
                      effectIDs: actor.effectIDs, actionPattern: actor.actionPattern, guardChanceBP: actor.guardChanceBP,
                      guardReductionBP: actor.guardReductionBP, level: actor.level, firstTelegraphMs: actor.firstTelegraphMs,
                      enemyActions: actor.enemyActions, r6SourceStats: actor.r6SourceStats, candidateAttackSide: actor.candidateAttackSide)
        }
        let withIgnoredField = try R6TimelineSimulator.run(party: profileParty, enemies: [passiveEnemy], seed: 19,
                                                            maxDurationMs: 5_000, sourceProfileSeed: "r030-profile")
        let withoutField = try R6TimelineSimulator.run(party: stripped, enemies: [passiveEnemy], seed: 19,
                                                        maxDurationMs: 5_000, sourceProfileSeed: "r030-profile")
        XCTAssertEqual(withIgnoredField, withoutField, "locked source-profile calculation must ignore latent candidate fields")
    }

    func testHasteChangesBasicEventIntervalsAndCooldownReductionMovesSkillReuse() throws {
        let noHaste = try R6TimelineSimulator.run(party: party(), enemies: [passiveEnemy], seed: 4, maxDurationMs: 6_000)
        let hasteParty = party(witchModifiers: try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000,
                                                           "haste_bp": 5_000]))
        let haste = try R6TimelineSimulator.run(party: hasteParty, enemies: [passiveEnemy], seed: 4, maxDurationMs: 6_000)
        let legacyTimes = noHaste.events.filter { $0.kind == "direct" && $0.sourceID == "C_WITCH" && $0.rootActionID?.contains(":basic:") == true }.compactMap(\.timestampMs)
        let hasteTimes = haste.events.filter { $0.kind == "direct" && $0.sourceID == "C_WITCH" && $0.rootActionID?.contains(":basic:") == true }.compactMap(\.timestampMs)
        XCTAssertEqual(legacyTimes.first, 1_800)
        XCTAssertEqual(hasteTimes.first, 1_200, "R2 haste scales the basic interval; the 250ms windup remains fixed")
        XCTAssertEqual(legacyTimes.prefix(3).map { $0 - legacyTimes[0] }, [0, 1_800, 3_600])
        XCTAssertEqual(hasteTimes.prefix(3).map { $0 - hasteTimes[0] }, [0, 1_200, 2_400])

        let poisonParty = party(witchEffects: ["POISON_STACK"])
        let cdrParty = party(witchEffects: ["POISON_STACK"], witchModifiers: try modifiers(["crit_chance_bp": 500,
                                                                                           "crit_multiplier_bp": 15_000,
                                                                                           "cdr_bp": 2_500]))
        let noCDR = try R6TimelineSimulator.run(party: poisonParty, enemies: [passiveEnemy], seed: 9, maxDurationMs: 18_000)
        let withCDR = try R6TimelineSimulator.run(party: cdrParty, enemies: [passiveEnemy], seed: 9, maxDurationMs: 18_000)
        let baseSeeds = noCDR.events.filter { $0.kind == "poison_seed" && $0.sourceID == "C_WITCH" }.compactMap(\.timestampMs)
        let reducedSeeds = withCDR.events.filter { $0.kind == "poison_seed" && $0.sourceID == "C_WITCH" }.compactMap(\.timestampMs)
        XCTAssertGreaterThanOrEqual(baseSeeds.count, 2)
        XCTAssertGreaterThanOrEqual(reducedSeeds.count, 2)
        XCTAssertLessThan(reducedSeeds[1] - reducedSeeds[0], baseSeeds[1] - baseSeeds[0])
        XCTAssertEqual(reducedSeeds[1] - reducedSeeds[0], 4_900, "4,500ms reduced readiness plus the next actor decision/cast timing; windup remains fixed")
    }

    func testDirectBonusAndCritAggregateChangeActualHitAmounts() throws {
        let baseline = try R6TimelineSimulator.run(party: party(), enemies: [passiveEnemy], seed: 1, maxDurationMs: 3_000)
        let boosted = try R6TimelineSimulator.run(party: party(witchModifiers: try modifiers(["crit_chance_bp": 500,
                                                                                           "crit_multiplier_bp": 15_000,
                                                                                           "direct_bonus_bp": 2_000])),
                                                  enemies: [passiveEnemy], seed: 1, maxDurationMs: 3_000)
        let baselineHit = try XCTUnwrap(baseline.events.first { $0.kind == "direct" && $0.sourceID == "C_WITCH" })
        let boostedHit = try XCTUnwrap(boosted.events.first { $0.kind == "direct" && $0.sourceID == "C_WITCH" })
        XCTAssertEqual(boostedHit.timestampMs, baselineHit.timestampMs)
        XCTAssertGreaterThan(boostedHit.amount, baselineHit.amount)
        XCTAssertEqual(boosted.remainingEnemyHP["E_TEST"], passiveEnemy.maxHP - boosted.events.filter { $0.kind == "direct" || $0.kind == "smith_hammer" || $0.kind == "poison_seed" }.reduce(0) { $0 + $1.amount })
        let critAggregate = try modifiers(["crit_chance_bp": 6_000, "crit_multiplier_bp": 22_500])
        var critPair: (CombatEvent, CombatEvent)?
        for seed in 1...64 {
            let base = try R6TimelineSimulator.run(party: party(), enemies: [passiveEnemy], seed: UInt64(seed), maxDurationMs: 2_000)
            let boostedCrit = try R6TimelineSimulator.run(party: party(witchModifiers: critAggregate), enemies: [passiveEnemy], seed: UInt64(seed), maxDurationMs: 2_000)
            guard let baseHit = base.events.first(where: { $0.kind == "direct" && $0.sourceID == "C_WITCH" }),
                  let critHit = boostedCrit.events.first(where: { $0.kind == "direct" && $0.sourceID == "C_WITCH" }) else { continue }
            if critHit.amount > baseHit.amount { critPair = (baseHit, critHit); break }
        }
        let (ordinaryCrit, boostedCrit) = try XCTUnwrap(critPair, "seed sweep must exercise the aggregate crit threshold/multiplier")
        XCTAssertEqual(boostedCrit.timestampMs, ordinaryCrit.timestampMs)
        XCTAssertGreaterThan(boostedCrit.amount, ordinaryCrit.amount)
    }

    func testPoisonBonusAndIncomingPeriodicResistanceChangeActualTicks() throws {
        let poisonEnemy = passiveEnemy
        let noBonus = try R6TimelineSimulator.run(party: party(witchEffects: ["POISON_STACK"]), enemies: [poisonEnemy],
                                                   seed: 17, maxDurationMs: 3_000)
        let poisonBonusParty = party(witchEffects: ["POISON_STACK"], witchModifiers: try modifiers(["crit_chance_bp": 500,
                                                                                                 "crit_multiplier_bp": 15_000,
                                                                                                 "dot_bonus_bp": 5_000]))
        let bonus = try R6TimelineSimulator.run(party: poisonBonusParty, enemies: [poisonEnemy], seed: 17, maxDurationMs: 3_000)
        let baseTick = try XCTUnwrap(noBonus.events.first { $0.kind == "poison_tick" })
        let boostedTick = try XCTUnwrap(bonus.events.first { $0.kind == "poison_tick" })
        XCTAssertEqual(baseTick.timestampMs, boostedTick.timestampMs)
        XCTAssertGreaterThan(boostedTick.amount, baseTick.amount)
        XCTAssertEqual(bonus.remainingEnemyHP["E_TEST"], poisonEnemy.maxHP - bonus.events.filter { ["direct", "smith_hammer", "poison_seed", "poison_tick"].contains($0.kind) }.reduce(0) { $0 + $1.amount })

        let dotEnemy = Combatant(id: "E_DOT", maxHP: 1_000_000, attack: 1, defense: 0,
                                 actionPattern: "seedGuardUltimate", firstTelegraphMs: 0)
        let noResist = try R6TimelineSimulator.run(party: party(), enemies: [dotEnemy], seed: 8, maxDurationMs: 5_000)
        let resistParty = party(witchModifiers: try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000,
                                                            "periodic_resist_bp": 5_000]))
        let resisted = try R6TimelineSimulator.run(party: resistParty, enemies: [dotEnemy], seed: 8, maxDurationMs: 5_000)
        let baseDot = try XCTUnwrap(noResist.events.first { $0.kind == "dot_tick" && $0.targetID == "C_WITCH" })
        let reducedDot = try XCTUnwrap(resisted.events.first { $0.kind == "dot_tick" && $0.targetID == "C_WITCH" })
        XCTAssertEqual(baseDot.timestampMs, reducedDot.timestampMs)
        XCTAssertEqual(baseDot.amount, 100)
        XCTAssertEqual(reducedDot.amount, 50)
        XCTAssertEqual(resisted.remainingPartyHP["C_WITCH"], 10_000 - resisted.events.filter { $0.kind == "dot_tick" && $0.targetID == "C_WITCH" }.reduce(0) { $0 + $1.amount })
    }

    func testDebuffResistanceHealAndBarrierBonusesChangeActualEvents() throws {
        let slowEnemy = Combatant(id: "E_SLOW", maxHP: 1_000_000, attack: 1_000, defense: 0,
                                  actionPattern: "slow", firstTelegraphMs: 0)
        let baseSlow = try R6TimelineSimulator.run(party: party(), enemies: [slowEnemy], seed: 21, maxDurationMs: 5_000)
        let slowResistance = try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000,
                                        "debuff_duration_resist_bp": 5_000])
        let resistant = try R6TimelineSimulator.run(party: party(witchModifiers: slowResistance,
                                                                  apprenticeModifiers: slowResistance),
                                                    enemies: [slowEnemy], seed: 21, maxDurationMs: 5_000)
        let baseSlowEvent = try XCTUnwrap(baseSlow.events.first { $0.kind == "party_slow" })
        let resistantSlowEvent = try XCTUnwrap(resistant.events.first { $0.kind == "party_slow" && $0.targetID == baseSlowEvent.targetID })
        XCTAssertEqual(baseSlowEvent.amount, 1_500)
        XCTAssertEqual(resistantSlowEvent.amount, 750)
        XCTAssertEqual(baseSlowEvent.timestampMs, resistantSlowEvent.timestampMs)

        let aoeEnemy = Combatant(id: "E_AOE", maxHP: 1_000_000, attack: 4_000, defense: 0,
                                 actionPattern: "aoe", firstTelegraphMs: 0)
        let injured = party(apprenticeEffects: ["HEAL_TO_BARRIER"])
        let strongerHeal = party(apprenticeEffects: ["HEAL_TO_BARRIER"],
                                 apprenticeModifiers: try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000,
                                                                  "heal_bonus_bp": 5_000, "barrier_bonus_bp": 5_000]))
        let healBase = try R6TimelineSimulator.run(party: injured, enemies: [aoeEnemy], seed: 13, maxDurationMs: 18_000)
        let healBoost = try R6TimelineSimulator.run(party: strongerHeal, enemies: [aoeEnemy], seed: 13, maxDurationMs: 18_000)
        let baseHeal = try XCTUnwrap(healBase.events.first { $0.kind == "heal" })
        let boostedHeal = try XCTUnwrap(healBoost.events.first { $0.kind == "heal" })
        XCTAssertEqual(baseHeal.targetID, boostedHeal.targetID)
        XCTAssertEqual(baseHeal.timestampMs, boostedHeal.timestampMs)
        XCTAssertGreaterThan(boostedHeal.amount, baseHeal.amount)
        let baseHealBarrier = try XCTUnwrap(healBase.events.first { $0.kind == "heal_barrier" })
        let boostedHealBarrier = try XCTUnwrap(healBoost.events.first { $0.kind == "heal_barrier" })
        XCTAssertGreaterThan(boostedHealBarrier.amount, baseHealBarrier.amount)

        let wardBase = try R6TimelineSimulator.run(party: party(witchEffects: ["BARRIER_WARD"]), enemies: [aoeEnemy],
                                                   seed: 13, maxDurationMs: 4_000)
        let wardBoosted = try R6TimelineSimulator.run(party: party(witchEffects: ["BARRIER_WARD"],
                                                                    witchModifiers: try modifiers(["crit_chance_bp": 500,
                                                                                               "crit_multiplier_bp": 15_000,
                                                                                               "barrier_bonus_bp": 5_000])),
                                                      enemies: [aoeEnemy], seed: 13, maxDurationMs: 4_000)
        let baseWard = try XCTUnwrap(wardBase.events.first { $0.kind == "barrier" && $0.sourceID == "C_WITCH" })
        let boostedWard = try XCTUnwrap(wardBoosted.events.first { $0.kind == "barrier" && $0.sourceID == "C_WITCH" })
        XCTAssertGreaterThan(boostedWard.amount, baseWard.amount)
    }

    func testCounterAndChaseBonusesChangeActualReactionDamage() throws {
        let stationary = Combatant(id: "E_REACTION", maxHP: 1_000_000, attack: 1_000, defense: 0,
                                   actionPattern: "frontRowCharge", firstTelegraphMs: 0)
        let smithMods = try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000,
                                   "direct_bonus_bp": 1_000, "counter_bonus_bp": 5_000])
        let smithParty = [
            Combatant(id: "C_WITCH", maxHP: 10_000, attack: 300, defense: 0),
            Combatant(id: "C_FAMILIAR", maxHP: 10_000, attack: 300, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 10_000, attack: 300, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 10_000, attack: 4_000, defense: 0, guardChanceBP: 4_500)
        ]
        let candidateSmithParty = smithParty.map { actor in
            actor.id == "C_SMITH"
                ? Combatant(id: actor.id, maxHP: actor.maxHP, attack: actor.attack, defense: actor.defense,
                            guardChanceBP: actor.guardChanceBP, candidateLatentModifiersR004: smithMods)
                : actor
        }
        var counterPair: (CombatResult, CombatResult)?
        for seed in 1...64 {
            let base = try R6TimelineSimulator.run(party: smithParty, enemies: [stationary], seed: UInt64(seed), maxDurationMs: 5_000)
            if base.events.contains(where: { $0.kind == "counter" }) {
                let candidate = try R6TimelineSimulator.run(party: candidateSmithParty, enemies: [stationary], seed: UInt64(seed), maxDurationMs: 5_000)
                counterPair = (base, candidate)
                break
            }
        }
        let (baseCounter, candidateCounter) = try XCTUnwrap(counterPair, "seed sweep must find a real Smith counter trigger")
        let baseCounterEvent = try XCTUnwrap(baseCounter.events.first { $0.kind == "counter" })
        let candidateCounterEvent = try XCTUnwrap(candidateCounter.events.first { $0.kind == "counter" })
        XCTAssertEqual(candidateCounterEvent.timestampMs, baseCounterEvent.timestampMs)
        XCTAssertEqual(candidateCounterEvent.rootActionID, baseCounterEvent.rootActionID)
        XCTAssertGreaterThan(candidateCounterEvent.amount, baseCounterEvent.amount)

        let familiarEffects: Set<String> = ["FAMILIAR_CHASE", "FAMILIAR_MARK_10S"]
        let chaseBaseParty = party(witchEffects: [], apprenticeEffects: [], smithModifiers: nil).map { actor in
            actor.id == "C_FAMILIAR"
                ? Combatant(id: actor.id, maxHP: actor.maxHP, attack: actor.attack, defense: actor.defense,
                            effectIDs: familiarEffects)
                : actor
        }
        let chaseMods = try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000,
                                   "direct_bonus_bp": 1_000, "chase_bonus_bp": 5_000])
        let chaseCandidateParty = chaseBaseParty.map { actor in
            actor.id == "C_FAMILIAR"
                ? Combatant(id: actor.id, maxHP: actor.maxHP, attack: actor.attack, defense: actor.defense,
                            effectIDs: familiarEffects, candidateLatentModifiersR004: chaseMods)
                : actor
        }
        let chaseBase = try R6TimelineSimulator.run(party: chaseBaseParty, enemies: [passiveEnemy], seed: 33, maxDurationMs: 5_000)
        let chaseCandidate = try R6TimelineSimulator.run(party: chaseCandidateParty, enemies: [passiveEnemy], seed: 33, maxDurationMs: 5_000)
        let baseChase = try XCTUnwrap(chaseBase.events.first { $0.kind == "chase" })
        let boostedChase = try XCTUnwrap(chaseCandidate.events.first { $0.kind == "chase" })
        XCTAssertEqual(boostedChase.timestampMs, baseChase.timestampMs)
        XCTAssertEqual(boostedChase.rootActionID, baseChase.rootActionID)
        XCTAssertGreaterThan(boostedChase.amount, baseChase.amount)
        XCTAssertEqual(chaseCandidate.remainingEnemyHP["E_TEST"], passiveEnemy.maxHP - chaseCandidate.events.filter { ["direct", "smith_hammer", "poison_seed", "chase"].contains($0.kind) }.reduce(0) { $0 + $1.amount })
    }

    func testInvalidCandidateAggregateAndOversizedCandidateArithmeticFailWithoutTrap() throws {
        let valid = try modifiers(["crit_chance_bp": 500, "crit_multiplier_bp": 15_000])
        let oversizedParty = [
            Combatant(id: "C_WITCH", maxHP: 100, attack: Int.max, defense: 0, candidateLatentModifiersR004: valid),
            Combatant(id: "C_FAMILIAR", maxHP: 100, attack: 1, defense: 0),
            Combatant(id: "C_APPRENTICE", maxHP: 100, attack: 1, defense: 0),
            Combatant(id: "C_SMITH", maxHP: 100, attack: 1, defense: 0)
        ]
        XCTAssertThrowsError(try R6TimelineSimulator.run(party: oversizedParty, enemies: [passiveEnemy], seed: 1))
        let validCandidateParty = party(witchModifiers: valid)
        XCTAssertThrowsError(try R6TimelineSimulator.run(party: validCandidateParty, enemies: [passiveEnemy],
                                                         seed: 1, maxDurationMs: 86_400_001))
        let excessiveCoefficient = Combatant(id: "E_BAD_ACTION", maxHP: 1_000, attack: 100, defense: 0,
                                             enemyActions: [EnemyActionDefinition(id: "bad", coefficientBP: 100_001,
                                                                                   windupMs: 0, hitOffsetsMs: [0], recoveryMs: 1)])
        XCTAssertThrowsError(try R6TimelineSimulator.run(party: validCandidateParty, enemies: [excessiveCoefficient], seed: 1))
    }
}
