import Foundation
import XCTest
@testable import WitchGameCore

final class R6EncounterFixtureTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Actor: Decodable {
            let id: String
            let level: Int
            let hp: Int
            let basicAt: Int
            let stats: Stats
            enum CodingKeys: String, CodingKey { case id, level, hp, basicAt = "basic_at", stats }
        }
        struct Stats: Decodable {
            let hp: Int
            let power: Int
            let defense: Int
            let guardChanceBP: Int
            let critChanceBP: Int
            let critMultiplierBP: Int
            let directBonusBP: Int?
            let healBonusBP: Int?
            let barrierBonusBP: Int?
            let dotBonusBP: Int?
            let chaseBonusBP: Int?
            enum CodingKeys: String, CodingKey {
                case hp, power, defense, guardChanceBP = "guard_chance_bp", critChanceBP = "crit_chance_bp"
                case critMultiplierBP = "crit_multiplier_bp", directBonusBP = "direct_bonus_bp"
                case healBonusBP = "heal_bonus_bp", barrierBonusBP = "barrier_bonus_bp", dotBonusBP = "dot_bonus_bp"
                case chaseBonusBP = "chase_bonus_bp"
            }
        }
        struct Boss: Decodable {
            let id: String
            let hp: Int
            let power: Int
            let defense: Int
            let level: Int
            let firstTelegraphMs: Int
            let actions: [EnemyActionDefinition]
            enum CodingKeys: String, CodingKey { case id, hp, power, defense, level, firstTelegraphMs = "first_telegraph_ms", actions }
        }
        struct ReferenceEvent: Decodable {
            struct Forecast: Decodable { let danger: Bool; let loss: Int; let hpAfter: Int; enum CodingKeys: String, CodingKey { case danger, loss, hpAfter = "hp_after" } }
            let tMs: Int
            let kind: String
            let source: String?
            let actor: String?
            let target: String?
            let skill: String?
            let selected: [String]?
            let forecasts: [String: Forecast]?
            let amount: Int?
            let hpLoss: Int?
            let effective: Int?
            let stacks: Int?
            let expiry: Int?
            let root: String?
            enum CodingKeys: String, CodingKey { case tMs = "t_ms", kind, source, actor, target, skill, selected, forecasts, amount, hpLoss = "hp_loss", effective, stacks, expiry, root }
        }
        struct Result: Decodable {
            let elapsedMs: Int
            let outcome: String
            let bossRemainingHP: Int
            let partyRemainingHP: [String: Int]
            let metrics: [String: Int]
            let logSHA256: String
            let inputFingerprint: String
            let log: [ReferenceEvent]
            enum CodingKeys: String, CodingKey { case elapsedMs = "elapsed_ms", outcome, bossRemainingHP = "boss_remaining_hp", partyRemainingHP = "party_remaining_hp", metrics, logSHA256 = "log_sha256", inputFingerprint = "input_fingerprint", log }
        }
        struct Profile: Decodable {
            let seed: String
            let inputFingerprint: String
            let referenceLogSHA256: String
            enum CodingKeys: String, CodingKey { case seed, inputFingerprint = "input_fingerprint", referenceLogSHA256 = "reference_log_sha256" }
        }
        let actors: [String: Actor]
        let boss: Boss
        let sourceProfile: Profile
        let referenceResult: Result
        enum CodingKeys: String, CodingKey { case actors, boss, sourceProfile, referenceResult }
    }

    func testFullLockedR6EncounterFixtureLoadsAndCapturesFirstRuntimeDivergence() throws {
        let fixtureURL = Bundle.module.url(forResource: "R6B_KNOWN_100049_TRACE_R1", withExtension: "json", subdirectory: "Fixtures")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/R6B_KNOWN_100049_TRACE_R1.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(fixture.sourceProfile.seed, "100049")
        XCTAssertEqual(fixture.sourceProfile.inputFingerprint, "e7680816642e0131891e2ccf78e6ef3b4e5d39beff3dd71ba95c27951e637ca9")
        XCTAssertEqual(fixture.referenceResult.inputFingerprint, fixture.sourceProfile.inputFingerprint)
        XCTAssertEqual(fixture.referenceResult.logSHA256, fixture.sourceProfile.referenceLogSHA256)
        XCTAssertEqual(fixture.referenceResult.log.count, 1_043)
        XCTAssertEqual(fixture.referenceResult.log.last?.tMs, 67_150)

        let effects: [String: Set<String>] = ["C_WITCH": ["POISON_STACK"], "C_FAMILIAR": ["FAMILIAR_CHASE"]]
        let order = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]
        let party = try order.map { actorID -> Combatant in
            let actor = try XCTUnwrap(fixture.actors[actorID])
            return Combatant(id: actor.id, maxHP: actor.hp, attack: actor.stats.power, defense: actor.stats.defense,
                             effectIDs: effects[actorID] ?? [], guardChanceBP: actor.stats.guardChanceBP,
                             level: actor.level,
                             r6SourceStats: R6SourceCombatStats(directBonusBP: actor.stats.directBonusBP ?? 0,
                                                               critChanceBP: actor.stats.critChanceBP,
                                                               critMultiplierBP: actor.stats.critMultiplierBP,
                                                               healBonusBP: actor.stats.healBonusBP ?? 0,
                                                               barrierBonusBP: actor.stats.barrierBonusBP ?? 0,
                                                               dotBonusBP: actor.stats.dotBonusBP ?? 0,
                                                               chaseBonusBP: actor.stats.chaseBonusBP ?? 0))
        }
        let enemy = Combatant(id: fixture.boss.id, maxHP: fixture.boss.hp, attack: fixture.boss.power,
                              defense: fixture.boss.defense, level: fixture.boss.level,
                              firstTelegraphMs: fixture.boss.firstTelegraphMs, enemyActions: fixture.boss.actions)
        let swiftTrace = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 100_049, maxDurationMs: 120_000,
                                                    sourceProfileSeed: "100049", initialBarriers: ["C_WITCH": (918_425, 6_000)])
        let repeatTrace = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 100_049, maxDurationMs: 120_000,
                                                     sourceProfileSeed: "100049", initialBarriers: ["C_WITCH": (918_425, 6_000)])
        XCTAssertEqual(swiftTrace, repeatTrace, "full fixed-input four-party encounter must be deterministic within Swift")
        XCTAssertEqual(swiftTrace.initialEnemyHP[fixture.boss.id], fixture.boss.hp)
        XCTAssertFalse(swiftTrace.events.isEmpty)
        let pythonInitialSmithDecision = try XCTUnwrap(fixture.referenceResult.log.first {
            $0.tMs == 0 && $0.kind == "support_decision" && $0.actor == "C_SMITH"
        })
        XCTAssertEqual(pythonInitialSmithDecision.selected, ["SK_S_HAMMER", "boss"])
        let swiftInitialSmithDecisionIndex = try XCTUnwrap(swiftTrace.events.firstIndex {
            $0.timestampMs == 0 && $0.kind == "support_decision" && $0.sourceID == "C_SMITH"
        })
        let swiftInitialSmithDecision = swiftTrace.events[swiftInitialSmithDecisionIndex]
        XCTAssertEqual(swiftInitialSmithDecision.targetID, "SK_S_HAMMER|boss")
        let swiftInitialSmithCastIndex = try XCTUnwrap(swiftTrace.events.firstIndex {
            $0.timestampMs == 0 && $0.kind == "cast_start" && $0.sourceID == "C_SMITH"
        })
        XCTAssertLessThan(swiftInitialSmithDecisionIndex, swiftInitialSmithCastIndex,
                          "source support-decision record must precede the cast at the same timestamp")
        let attackKinds: Set<String> = ["direct", "poison_seed", "smith_hammer", "chase", "counter"]
        let swiftAttackEvents = swiftTrace.events.filter { attackKinds.contains($0.kind) }
        let swiftHeals = swiftTrace.events.filter { $0.kind == "heal" }
        let swiftDots = swiftTrace.events.filter { $0.kind == "poison_tick" }
        print("R6_FINAL_COMPARE,won=\(swiftTrace.won),ticks=\(swiftTrace.ticks),party=\(swiftTrace.remainingPartyHP),enemy=\(swiftTrace.remainingEnemyHP),damageEvents=\(swiftAttackEvents.count),damageSum=\(swiftAttackEvents.reduce(0) { $0 + $1.amount }),heals=\(swiftHeals.count),dots=\(swiftDots.count):\(swiftDots.suffix(8).map { "\($0.timestampMs ?? -1)/\($0.amount)" })")

        let sourceFirst = try XCTUnwrap(fixture.referenceResult.log.first)
        let swiftFirst = try XCTUnwrap(swiftTrace.events.first)
        print("R6_FULL_TRACE_COMPARE,fixture=R6B_KNOWN_100049_BEFORE,pythonEvents=\(fixture.referenceResult.log.count),swiftEvents=\(swiftTrace.events.count),pythonElapsed=\(fixture.referenceResult.elapsedMs),swiftElapsed=\(swiftTrace.events.last?.timestampMs ?? 0),pythonFirst=\(sourceFirst.tMs):\(sourceFirst.kind):\(sourceFirst.source ?? ""):\(sourceFirst.target ?? ""),swiftFirst=\(swiftFirst.timestampMs ?? 0):\(swiftFirst.kind):\(swiftFirst.sourceID):\(swiftFirst.targetID),pythonLogSHA256=\(fixture.referenceResult.logSHA256)")
        XCTAssertEqual(sourceFirst.kind, "barrier")
        XCTAssertEqual(swiftFirst.kind, "barrier", "source-profile start barrier should match before actor decisions")
        let sourceDamage = fixture.referenceResult.log.filter { $0.kind == "damage" }
        let swiftDamage = swiftTrace.events.filter { ["direct", "poison_seed", "smith_hammer", "chase", "counter"].contains($0.kind) }
        let swiftByKey = Dictionary(grouping: swiftDamage, by: { "\($0.timestampMs ?? -1)|\($0.rootActionID ?? "")|\($0.sourceID)" })
        let firstDamageDifference = sourceDamage.first { source in
            let key = "\(source.tMs)|\(source.root ?? "")|\(source.source ?? "")"
            guard let matching = swiftByKey[key]?.first else { return true }
            return (source.hpLoss ?? 0) != matching.amount
        }
        if let firstDamageDifference {
            let key = "\(firstDamageDifference.tMs)|\(firstDamageDifference.root ?? "")|\(firstDamageDifference.source ?? "")"
            let swift = swiftByKey[key]?.first
            let nearestSwift = swiftDamage.first { $0.rootActionID == firstDamageDifference.root && $0.sourceID == firstDamageDifference.source }
            print("R6_FIRST_DAMAGE_DIVERGENCE,t=\(firstDamageDifference.tMs),root=\(firstDamageDifference.root ?? ""),source=\(firstDamageDifference.source ?? ""),skill=\(firstDamageDifference.skill ?? ""),pythonHP=\(firstDamageDifference.hpLoss ?? -1),swiftKind=\(swift?.kind ?? "missing"),swiftHP=\(swift?.amount ?? -1),swiftSameRootT=\(nearestSwift?.timestampMs ?? -1),swiftSameRootHP=\(nearestSwift?.amount ?? -1)")
        }
        let sourceDamageKeys = Set(sourceDamage.map { "\($0.tMs)|\($0.root ?? "")|\($0.source ?? "")" })
        if let extra = swiftDamage.first(where: { !sourceDamageKeys.contains("\($0.timestampMs ?? -1)|\($0.rootActionID ?? "")|\($0.sourceID)") }) {
            print("R6_FIRST_EXTRA_SWIFT_DAMAGE,t=\(extra.timestampMs ?? -1),root=\(extra.rootActionID ?? ""),source=\(extra.sourceID),kind=\(extra.kind),amount=\(extra.amount)")
        }
        let sourceHits = fixture.referenceResult.log.filter { $0.kind == "enemy_hit" }
        let swiftHits = swiftTrace.events.filter { $0.kind == "enemy_hit" }
        let swiftHitByKey = Dictionary(grouping: swiftHits, by: { "\($0.timestampMs ?? -1)|\($0.rootActionID ?? "")|\($0.targetID)" })
        if let mismatch = sourceHits.first(where: { source in
            let key = "\(source.tMs)|\(source.root ?? "")|\(source.target ?? "")"
            return swiftHitByKey[key]?.first?.amount != source.hpLoss
        }) {
            let key = "\(mismatch.tMs)|\(mismatch.root ?? "")|\(mismatch.target ?? "")"
            print("R6_FIRST_ENEMY_HIT_DIVERGENCE,t=\(mismatch.tMs),root=\(mismatch.root ?? ""),target=\(mismatch.target ?? ""),pythonHP=\(mismatch.hpLoss ?? -1),swiftHP=\(swiftHitByKey[key]?.first?.amount ?? -1)")
        }
        let sourceHitKeys = Set(sourceHits.map { "\($0.tMs)|\($0.root ?? "")|\($0.target ?? "")" })
        if let extra = swiftHits.first(where: { !sourceHitKeys.contains("\($0.timestampMs ?? -1)|\($0.rootActionID ?? "")|\($0.targetID)") }) {
            print("R6_FIRST_EXTRA_SWIFT_HIT,t=\(extra.timestampMs ?? -1),root=\(extra.rootActionID ?? ""),target=\(extra.targetID),hp=\(extra.amount)")
        }
        let pythonCasts = fixture.referenceResult.log.filter { $0.kind == "cast_start" }
        let swiftCasts = swiftTrace.events.filter { $0.kind == "cast_start" }
        let swiftCastByRoot = Dictionary(uniqueKeysWithValues: swiftCasts.compactMap { event -> (String, CombatEvent)? in
            guard let root = event.rootActionID else { return nil }; return (root, event)
        })
        if let mismatch = pythonCasts.first(where: { source in swiftCastByRoot[source.root ?? ""]?.timestampMs != source.tMs }) {
            let matched = swiftCastByRoot[mismatch.root ?? ""]
            print("R6_FIRST_CAST_TIMING_DIVERGENCE,pythonT=\(mismatch.tMs),swiftT=\(matched?.timestampMs ?? -1),root=\(mismatch.root ?? ""),skill=\(mismatch.skill ?? "")")
        }
        let sourceOpening = fixture.referenceResult.log.filter { $0.tMs == 0 && $0.kind == "cast_start" }.compactMap { "\($0.source ?? ""):\($0.skill ?? "")" }
        let swiftOpening = swiftTrace.events.filter { $0.timestampMs == 0 && $0.kind == "cast_start" }.map { "\($0.sourceID):\(Self.referenceSkill(for: $0.targetID))" }
        XCTAssertEqual(sourceOpening, swiftOpening, "first three actor choices and cast starts should match source ordering at t=0")
        let firstSweepPython = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log
            .filter { $0.tMs == 8_600 && $0.kind == "enemy_hit" }
            .compactMap { event in event.target.flatMap { target in event.hpLoss.map { (target, $0) } } })
        let firstSweepSwift = Dictionary(uniqueKeysWithValues: swiftTrace.events
            .filter { $0.timestampMs == 8_600 && $0.kind == "enemy_hit" }
            .map { ($0.targetID, $0.amount) })
        XCTAssertEqual(firstSweepPython.count, 4)
        XCTAssertEqual(firstSweepSwift, firstSweepPython,
                       "source AoE coefficients already include the authored multiplier; do not halve again")
        let pythonLethalHit = try XCTUnwrap(fixture.referenceResult.log.first { $0.tMs == 62_850 && $0.kind == "enemy_hit" && $0.target == "C_FAMILIAR" })
        let swiftLethalHit = try XCTUnwrap(swiftTrace.events.first { $0.timestampMs == 62_850 && $0.kind == "enemy_hit" && $0.targetID == "C_FAMILIAR" })
        XCTAssertEqual(swiftLethalHit.amount, pythonLethalHit.hpLoss,
                       "hit event amount records capped effective HP loss, not overkill damage")
        let sourceCounter = try XCTUnwrap(fixture.referenceResult.log.first { $0.tMs == 39_050 && $0.kind == "damage" && $0.skill == "PS_counter" })
        let swiftCounter = try XCTUnwrap(swiftTrace.events.first { $0.timestampMs == 39_050 && $0.kind == "counter" })
        XCTAssertEqual(swiftCounter.amount, sourceCounter.hpLoss,
                       "the 75% Smith counter is direct damage and must include the active 6% mark before defense")
        let pythonEarlyWard = try XCTUnwrap(fixture.referenceResult.log.first { $0.tMs == 13_700 && $0.kind == "support_decision" && $0.actor == "C_APPRENTICE" })
        XCTAssertEqual(pythonEarlyWard.selected, ["SK_A_WARD", "C_SMITH"])
        let swiftEarlyWard = try XCTUnwrap(swiftTrace.events.first { $0.kind == "support_decision" && $0.timestampMs == 13_700 && $0.sourceID == "C_APPRENTICE" && $0.targetID == "ward|C_SMITH" })
        XCTAssertEqual(swiftEarlyWard.diagnostics?["C_SMITH.threat3000"], pythonEarlyWard.forecasts?["C_SMITH"]?.loss)
        XCTAssertTrue(swiftTrace.events.contains { $0.kind == "cast_start" && $0.sourceID == "C_APPRENTICE" && $0.targetID == "ward" && $0.timestampMs == pythonEarlyWard.tMs })
        let pythonWard = try XCTUnwrap(fixture.referenceResult.log.first { $0.tMs == 37_900 && $0.kind == "support_decision" && $0.actor == "C_APPRENTICE" })
        XCTAssertEqual(pythonWard.selected, ["SK_A_WARD", "C_SMITH"])
        let swiftWard = try XCTUnwrap(swiftTrace.events.first { $0.kind == "support_decision" && $0.timestampMs == 37_900 && $0.sourceID == "C_APPRENTICE" && $0.targetID == "ward|C_SMITH" })
        XCTAssertEqual(swiftWard.diagnostics?["C_SMITH.hp"], 4_595_177)
        XCTAssertEqual(swiftWard.diagnostics?["C_SMITH.threat1500"], pythonWard.forecasts?["C_SMITH"]?.loss)
        XCTAssertTrue(swiftTrace.events.contains { $0.kind == "cast_start" && $0.sourceID == "C_APPRENTICE" && $0.targetID == "ward" && $0.timestampMs == pythonWard.tMs })
        XCTAssertEqual(swiftTrace.events.first { $0.kind == "barrier" && $0.sourceID == "C_APPRENTICE" && $0.targetID == "C_SMITH" && $0.timestampMs == 38_150 }?.amount, 1_133_790)
        let pythonKinds = Dictionary(grouping: fixture.referenceResult.log, by: { $0.kind }).mapValues(\.count)
        let swiftKinds = Dictionary(grouping: swiftTrace.events, by: { $0.kind }).mapValues(\.count)
        let pythonSupportActors = Dictionary(grouping: fixture.referenceResult.log.filter { $0.kind == "support_decision" }, by: { $0.actor ?? "unknown" }).mapValues(\.count)
        let swiftSupportActors = Dictionary(grouping: swiftTrace.events.filter { $0.kind == "support_decision" }, by: { $0.sourceID }).mapValues(\.count)
        let sourceSmithDecisionKeys = Set(fixture.referenceResult.log.filter { $0.kind == "support_decision" && $0.actor == "C_SMITH" }.map {
            "\($0.tMs)|\(($0.selected ?? ["none", "boss"]).joined(separator: "|"))"
        })
        let swiftSmithDecisionKeys = Set(swiftTrace.events.filter { $0.kind == "support_decision" && $0.sourceID == "C_SMITH" }.map {
            "\($0.timestampMs ?? -1)|\($0.targetID)"
        })
        func decisionTime(_ key: String) -> Int { Int(key.split(separator: "|", maxSplits: 1).first ?? "-1") ?? -1 }
        let firstMissingSmithDecision = sourceSmithDecisionKeys.subtracting(swiftSmithDecisionKeys).min { decisionTime($0) < decisionTime($1) } ?? "none"
        let firstExtraSmithDecision = swiftSmithDecisionKeys.subtracting(sourceSmithDecisionKeys).min { decisionTime($0) < decisionTime($1) } ?? "none"
        print("R6_TRACE_KIND_COUNTS,python=\(pythonKinds),swift=\(swiftKinds),pythonSupportActors=\(pythonSupportActors),swiftSupportActors=\(swiftSupportActors),smithDecisionKeyIntersection=\(sourceSmithDecisionKeys.intersection(swiftSmithDecisionKeys).count)/\(sourceSmithDecisionKeys.count),firstMissingSmith=\(firstMissingSmithDecision),firstExtraSmith=\(firstExtraSmithDecision)")
        let pythonCastKeys = Set(fixture.referenceResult.log.filter { $0.kind == "cast_start" }.compactMap { event in event.root.map { "\(event.tMs)|\(event.source ?? "")|\($0)" } })
        let swiftCastKeys = Set(swiftTrace.events.filter { $0.kind == "cast_start" }.compactMap { event in event.rootActionID.map { "\(event.timestampMs ?? -1)|\(event.sourceID)|\($0)" } })
        let normPythonDamageByKey = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "damage" }.compactMap { event -> (String, Int)? in
            guard let root = event.root, let source = event.source, let amount = event.hpLoss else { return nil }
            return ("\(event.tMs)|\(root)|\(source)", amount)
        })
        let normSwiftDamageByKey = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { ["direct", "poison_seed", "smith_hammer", "chase", "counter"].contains($0.kind) }.compactMap { event -> (String, Int)? in
            guard let root = event.rootActionID else { return nil }
            return ("\(event.timestampMs ?? -1)|\(root)|\(event.sourceID)", event.amount)
        })
        let normPythonHitByKey = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "enemy_hit" }.compactMap { event -> (String, Int)? in
            guard let root = event.root, let target = event.target, let amount = event.hpLoss else { return nil }
            return ("\(event.tMs)|\(root)|\(target)", amount)
        })
        let normSwiftHitByKey = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { $0.kind == "enemy_hit" }.compactMap { event -> (String, Int)? in
            guard let root = event.rootActionID else { return nil }
            return ("\(event.timestampMs ?? -1)|\(root)|\(event.targetID)", event.amount)
        })
        let normPythonDotByTime = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "dot" }.compactMap { event -> (Int, Int)? in
            guard let amount = event.hpLoss else { return nil }; return (event.tMs, amount)
        })
        let normSwiftDotByTime = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { $0.kind == "poison_tick" }.compactMap { event -> (Int, Int)? in
            guard let time = event.timestampMs else { return nil }; return (time, event.amount)
        })
        let normPythonHealByKey = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "heal" }.compactMap { event -> (String, Int)? in
            guard let source = event.source, let target = event.target, let amount = event.effective else { return nil }
            return ("\(event.tMs)|\(source)|\(target)", amount)
        })
        let normSwiftHealByKey = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { $0.kind == "heal" }.map { ("\($0.timestampMs ?? -1)|\($0.sourceID)|\($0.targetID)", $0.amount) })
        let normPythonBarrierByKey = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "barrier" }.compactMap { event -> (String, Int)? in
            guard let source = event.source, let target = event.target, let amount = event.amount else { return nil }
            return ("\(event.tMs)|\(source)|\(target)", amount)
        })
        let normSwiftBarrierByKey = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { ["barrier", "heal_barrier"].contains($0.kind) }.map {
            ("\($0.timestampMs ?? -1)|\($0.sourceID)|\($0.targetID)", $0.amount)
        })
        let normPythonMarkByKey = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "mark" }.compactMap { event -> (String, Int)? in
            guard let source = event.source, let expiry = event.expiry else { return nil }
            return ("\(event.tMs)|\(source)", expiry - event.tMs)
        })
        let normSwiftMarkByKey = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { $0.kind == "mark" }.map {
            ("\($0.timestampMs ?? -1)|\($0.sourceID)", $0.amount)
        })
        let normPythonPoisonApplyByKey = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "poison_apply" }.compactMap { event -> (String, Int)? in
            guard let source = event.source, let stacks = event.stacks else { return nil }
            return ("\(event.tMs)|\(source)", stacks)
        })
        let normSwiftPoisonApplyByKey = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { $0.kind == "poison_stack" }.map {
            ("\($0.timestampMs ?? -1)|\($0.sourceID)", $0.amount)
        })
        func exactMatches<K: Hashable>(_ lhs: [K: Int], _ rhs: [K: Int]) -> Int {
            lhs.keys.filter { rhs[$0] == lhs[$0] }.count
        }
        print("R6_NORMALIZED_EXACT,castStart=\(pythonCastKeys.intersection(swiftCastKeys).count)/\(pythonCastKeys.count),damage=\(exactMatches(normPythonDamageByKey, normSwiftDamageByKey))/\(normPythonDamageByKey.count),enemyHit=\(exactMatches(normPythonHitByKey, normSwiftHitByKey))/\(normPythonHitByKey.count),poisonTick=\(exactMatches(normPythonDotByTime, normSwiftDotByTime))/\(normPythonDotByTime.count),poisonApply=\(exactMatches(normPythonPoisonApplyByKey, normSwiftPoisonApplyByKey))/\(normPythonPoisonApplyByKey.count),heal=\(exactMatches(normPythonHealByKey, normSwiftHealByKey))/\(normPythonHealByKey.count),barrier=\(exactMatches(normPythonBarrierByKey, normSwiftBarrierByKey))/\(normPythonBarrierByKey.count),mark=\(exactMatches(normPythonMarkByKey, normSwiftMarkByKey))/\(normPythonMarkByKey.count),sourceBarrierExpiry=\(pythonKinds["barrier_expiry", default: 0]),sourceDeath=\(pythonKinds["death", default: 0])")
        XCTAssertEqual(pythonCastKeys, swiftCastKeys)
        XCTAssertEqual(normPythonDamageByKey, normSwiftDamageByKey)
        XCTAssertEqual(normPythonHitByKey, normSwiftHitByKey)
        XCTAssertEqual(normPythonDotByTime, normSwiftDotByTime)
        XCTAssertEqual(normPythonHealByKey, normSwiftHealByKey)
        XCTAssertEqual(normPythonBarrierByKey, normSwiftBarrierByKey)
        XCTAssertEqual(normPythonMarkByKey, normSwiftMarkByKey)
        XCTAssertEqual(normPythonPoisonApplyByKey, normSwiftPoisonApplyByKey)
        XCTAssertNotEqual(swiftTrace.events.count, fixture.referenceResult.log.count, "diagnostic-only: trace schemas/mechanics are not yet aligned")
        XCTAssertTrue(swiftTrace.won)
        XCTAssertEqual(swiftTrace.remainingEnemyHP[fixture.boss.id], fixture.referenceResult.bossRemainingHP)
        XCTAssertEqual(swiftTrace.remainingPartyHP, fixture.referenceResult.partyRemainingHP)
        XCTAssertEqual(swiftTrace.events.last?.timestampMs, fixture.referenceResult.elapsedMs)
        let sourceDamageByKey = Dictionary(uniqueKeysWithValues: sourceDamage.compactMap { event -> (String, Int)? in
            guard let root = event.root, let source = event.source, let hpLoss = event.hpLoss else { return nil }
            return ("\(event.tMs)|\(root)|\(source)", hpLoss)
        })
        let swiftDamageByKey = Dictionary(uniqueKeysWithValues: swiftDamage.compactMap { event -> (String, Int)? in
            guard let root = event.rootActionID else { return nil }
            return ("\(event.timestampMs ?? -1)|\(root)|\(event.sourceID)", event.amount)
        })
        XCTAssertEqual(swiftDamageByKey, sourceDamageByKey, "all committed source damage events, including lethal HP loss, must match")
        let sourceDotByTime = Dictionary(uniqueKeysWithValues: fixture.referenceResult.log.filter { $0.kind == "dot" }.compactMap { event -> (Int, Int)? in
            guard let hpLoss = event.hpLoss else { return nil }; return (event.tMs, hpLoss)
        })
        let swiftDotByTime = Dictionary(uniqueKeysWithValues: swiftTrace.events.filter { $0.kind == "poison_tick" }.compactMap { event -> (Int, Int)? in
            guard let time = event.timestampMs else { return nil }; return (time, event.amount)
        })
        XCTAssertEqual(swiftDotByTime, sourceDotByTime, "poison ticks apply source dot_bonus_bp and stop at victory")
    }

    func testIndependentR6Seed100069FixtureMatchesDamageAndFinalState() throws {
        let fixtureURL = Bundle.module.url(forResource: "R6B_KNOWN_100069_TRACE_R1", withExtension: "json", subdirectory: "Fixtures")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/R6B_KNOWN_100069_TRACE_R1.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(fixture.sourceProfile.seed, "100069")
        XCTAssertEqual(fixture.referenceResult.logSHA256, fixture.sourceProfile.referenceLogSHA256)
        let effects: [String: Set<String>] = ["C_WITCH": ["POISON_STACK"], "C_FAMILIAR": ["FAMILIAR_CHASE"]]
        let order = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]
        let party = try order.map { actorID -> Combatant in
            let actor = try XCTUnwrap(fixture.actors[actorID])
            return Combatant(id: actor.id, maxHP: actor.hp, attack: actor.stats.power, defense: actor.stats.defense,
                             effectIDs: effects[actorID] ?? [], guardChanceBP: actor.stats.guardChanceBP,
                             level: actor.level,
                             r6SourceStats: R6SourceCombatStats(directBonusBP: actor.stats.directBonusBP ?? 0,
                                                               critChanceBP: actor.stats.critChanceBP,
                                                               critMultiplierBP: actor.stats.critMultiplierBP,
                                                               healBonusBP: actor.stats.healBonusBP ?? 0,
                                                               barrierBonusBP: actor.stats.barrierBonusBP ?? 0,
                                                               dotBonusBP: actor.stats.dotBonusBP ?? 0,
                                                               chaseBonusBP: actor.stats.chaseBonusBP ?? 0))
        }
        let enemy = Combatant(id: fixture.boss.id, maxHP: fixture.boss.hp, attack: fixture.boss.power,
                              defense: fixture.boss.defense, level: fixture.boss.level,
                              firstTelegraphMs: fixture.boss.firstTelegraphMs, enemyActions: fixture.boss.actions)
        let trace = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: 100_069, maxDurationMs: 120_000,
                                               sourceProfileSeed: "100069", initialBarriers: ["C_WITCH": (918_425, 6_000)])
        let sourceDamage = fixture.referenceResult.log.filter { $0.kind == "damage" }
        let swiftDamage = trace.events.filter { ["direct", "poison_seed", "smith_hammer", "chase", "counter"].contains($0.kind) }
        let sourceByKey = Dictionary(uniqueKeysWithValues: sourceDamage.compactMap { event -> (String, Int)? in
            guard let root = event.root, let source = event.source, let loss = event.hpLoss else { return nil }
            return ("\(event.tMs)|\(root)|\(source)", loss)
        })
        let swiftByKey = Dictionary(uniqueKeysWithValues: swiftDamage.compactMap { event -> (String, Int)? in
            guard let root = event.rootActionID else { return nil }
            return ("\(event.timestampMs ?? -1)|\(root)|\(event.sourceID)", event.amount)
        })
        XCTAssertEqual(swiftByKey, sourceByKey, "independent seed must match all committed damage, not just the tuned seed")
        XCTAssertTrue(trace.won)
        XCTAssertEqual(trace.remainingEnemyHP[fixture.boss.id], fixture.referenceResult.bossRemainingHP)
        XCTAssertEqual(trace.remainingPartyHP, fixture.referenceResult.partyRemainingHP)
        XCTAssertEqual(trace.events.last?.timestampMs, fixture.referenceResult.elapsedMs)
    }

    func testExportActualSwiftSourceProfileTracesForBothLockedSeeds() throws {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WITCH_R6_TRACE_EXPORT_DIR"]
                        ?? NSTemporaryDirectory().appending("witch-r6-traces"), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for seed in ["100049", "100069"] {
            let url = Bundle.module.url(forResource: "R6B_KNOWN_\(seed)_TRACE_R1", withExtension: "json", subdirectory: "Fixtures")
                ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/R6B_KNOWN_\(seed)_TRACE_R1.json")
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
            let effects: [String: Set<String>] = ["C_WITCH": ["POISON_STACK"], "C_FAMILIAR": ["FAMILIAR_CHASE"]]
            let party = try ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"].map { actorID -> Combatant in
                let actor = try XCTUnwrap(fixture.actors[actorID])
                return Combatant(id: actor.id, maxHP: actor.hp, attack: actor.stats.power, defense: actor.stats.defense,
                                 effectIDs: effects[actorID] ?? [], guardChanceBP: actor.stats.guardChanceBP,
                                 level: actor.level,
                                 r6SourceStats: R6SourceCombatStats(directBonusBP: actor.stats.directBonusBP ?? 0,
                                                                   critChanceBP: actor.stats.critChanceBP,
                                                                   critMultiplierBP: actor.stats.critMultiplierBP,
                                                                   healBonusBP: actor.stats.healBonusBP ?? 0,
                                                                   barrierBonusBP: actor.stats.barrierBonusBP ?? 0,
                                                                   dotBonusBP: actor.stats.dotBonusBP ?? 0,
                                                                   chaseBonusBP: actor.stats.chaseBonusBP ?? 0))
            }
            let enemy = Combatant(id: fixture.boss.id, maxHP: fixture.boss.hp, attack: fixture.boss.power,
                                  defense: fixture.boss.defense, level: fixture.boss.level,
                                  firstTelegraphMs: fixture.boss.firstTelegraphMs, enemyActions: fixture.boss.actions)
            let trace = try R6TimelineSimulator.run(party: party, enemies: [enemy], seed: UInt64(seed) ?? 0,
                                                   maxDurationMs: 120_000, sourceProfileSeed: seed,
                                                   initialBarriers: ["C_WITCH": (918_425, 6_000)])
            let eventsURL = output.appendingPathComponent("swift_\(seed)_events.json")
            try encoder.encode(trace.events).write(to: eventsURL, options: .atomic)
            let summary: [String: Any] = [
                "seed": seed, "sourceFixture": url.path, "sourceFixtureReferenceLogSHA256": fixture.referenceResult.logSHA256,
                "sourceProfileReferenceLogSHA256": fixture.sourceProfile.referenceLogSHA256,
                "swiftEventCount": trace.events.count, "swiftElapsedMs": trace.events.last?.timestampMs ?? 0,
                "swiftWon": trace.won, "swiftRemainingEnemyHP": trace.remainingEnemyHP,
                "swiftRemainingPartyHP": trace.remainingPartyHP,
                "swiftTicks": trace.ticks, "swiftEventsFile": eventsURL.lastPathComponent
            ]
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("swift_\(seed)_summary.json"), options: .atomic)
        }
        print("R6_TRACE_EXPORT_DIR,\(output.path)")
    }

    private static func referenceSkill(for action: String) -> String {
        switch action {
        case "seed": "SK_W_SEED"; case "burst": "SK_W_BURST"; case "mark": "SK_F_MARK"
        case "dash": "SK_F_DASH"; case "heal": "SK_A_HEAL"; case "ward": "SK_A_WARD"
        case "guard": "SK_S_GUARD"; case "hammer": "SK_S_HAMMER"
        case "basic": "C_WITCH_BASIC"; default: action
        }
    }
}
