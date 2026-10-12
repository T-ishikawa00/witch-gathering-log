import Foundation

public struct EnemyActionDefinition: Codable, Sendable, Equatable {
    public let id: String
    public let coefficientBP: Int
    public let windupMs: Int
    public let hitOffsetsMs: [Int]
    public let recoveryMs: Int
    public let restMs: Int
    public let aoe: Bool
    public let heavy: Bool
    public init(id: String, coefficientBP: Int, windupMs: Int, hitOffsetsMs: [Int], recoveryMs: Int, restMs: Int = 0, aoe: Bool = false, heavy: Bool = false) {
        self.id = id; self.coefficientBP = coefficientBP; self.windupMs = windupMs; self.hitOffsetsMs = hitOffsetsMs
        self.recoveryMs = recoveryMs; self.restMs = restMs; self.aoe = aoe; self.heavy = heavy
    }
    enum CodingKeys: String, CodingKey { case id, coefficientBP = "coefficient_bp", windupMs = "windup_ms", hitOffsetsMs = "hit_offsets_ms", recoveryMs = "recovery_ms", restMs = "rest_ms", aoe, heavy }
}

/// Optional per-actor fixed-point values decoded from a locked R6 source
/// fixture. Nil preserves the existing campaign overlay calculations.
public struct R6SourceCombatStats: Codable, Sendable, Equatable {
    public let directBonusBP: Int
    public let critChanceBP: Int
    public let critMultiplierBP: Int
    public let healBonusBP: Int
    public let barrierBonusBP: Int
    public let dotBonusBP: Int
    public let chaseBonusBP: Int
    public init(directBonusBP: Int = 0, critChanceBP: Int = 0, critMultiplierBP: Int = 15_000,
                healBonusBP: Int = 0, barrierBonusBP: Int = 0, dotBonusBP: Int = 0, chaseBonusBP: Int = 0) {
        self.directBonusBP = directBonusBP; self.critChanceBP = critChanceBP; self.critMultiplierBP = critMultiplierBP
        self.healBonusBP = healBonusBP; self.barrierBonusBP = barrierBonusBP
        self.dotBonusBP = dotBonusBP; self.chaseBonusBP = chaseBonusBP
    }
}

/// Optional direction metadata for unapproved R4 combat candidates. Missing
/// values preserve the existing front-facing combat input convention.
public enum CandidateAttackSide: String, Codable, Sendable { case front, flank }

/// Provisional R4 E_R03_04 mechanics for isolated experiments only.
/// Values are UNAPPROVED_TEST_OVERLAY and are never read from the live catalog.
public struct MagnetMechanicParameters: Sendable, Equatable {
    public let markWindowMs: Int
    public let strikeWindupMs: Int
    public let strikeCoefficientBP: Int

    public init(markWindowMs: Int, strikeWindupMs: Int, strikeCoefficientBP: Int) {
        self.markWindowMs = markWindowMs
        self.strikeWindupMs = strikeWindupMs
        self.strikeCoefficientBP = strikeCoefficientBP
    }

    /// Candidate work is bounded to a short authored telegraph, avoiding both
    /// unbounded battle stalls and overflow when event deadlines are added.
    public var isValidForExperiment: Bool {
        guard (1...30_000).contains(markWindowMs), (1...30_000).contains(strikeWindupMs),
              (10_000...30_000).contains(strikeCoefficientBP) else { return false }
        let (_, overflow) = markWindowMs.addingReportingOverflow(strikeWindupMs)
        return !overflow && markWindowMs + strikeWindupMs <= 60_000
    }
}

public struct Combatant: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var maxHP: Int
    public var attack: Int
    public var defense: Int
    public var guardChanceBP: Int
    public var guardReductionBP: Int
    public var effectIDs: Set<String>
    public var actionPattern: String
    public var level: Int?
    public var firstTelegraphMs: Int?
    public var enemyActions: [EnemyActionDefinition]?
    public var r6SourceStats: R6SourceCombatStats?
    public var candidateAttackSide: CandidateAttackSide?
    /// Typed, Domain-projected R004 equipment aggregate. It is consumed only by
    /// the non-source-profile candidate timeline; HP/power/defense/guard are
    /// already reflected in the scalar fields above and are never reapplied.
    public var candidateLatentModifiersR004: CandidateLatentCombatModifiersR005?
    public init(id: String, maxHP: Int, attack: Int, defense: Int, effectIDs: Set<String> = [], actionPattern: String = "standard", guardChanceBP: Int = 0, guardReductionBP: Int = 3_500, level: Int? = nil, firstTelegraphMs: Int? = nil, enemyActions: [EnemyActionDefinition]? = nil, r6SourceStats: R6SourceCombatStats? = nil, candidateAttackSide: CandidateAttackSide? = nil, candidateLatentModifiersR004: CandidateLatentCombatModifiersR005? = nil) {
        self.id = id; self.maxHP = maxHP; self.attack = attack; self.defense = defense; self.effectIDs = effectIDs; self.actionPattern = actionPattern; self.guardChanceBP = max(0, min(10_000, guardChanceBP)); self.guardReductionBP = max(0, min(10_000, guardReductionBP)); self.level = level; self.firstTelegraphMs = firstTelegraphMs; self.enemyActions = enemyActions; self.r6SourceStats = r6SourceStats; self.candidateAttackSide = candidateAttackSide; self.candidateLatentModifiersR004 = candidateLatentModifiersR004
    }
}
public struct CombatEvent: Codable, Sendable, Equatable {
    public let tick: Int
    public let kind: String
    public let sourceID: String
    public let targetID: String
    public let amount: Int
    public let rootActionID: String?
    public let timestampMs: Int?
    public let diagnostics: [String: Int]?
    public init(tick: Int, kind: String, sourceID: String, targetID: String, amount: Int, rootActionID: String? = nil, timestampMs: Int? = nil, diagnostics: [String: Int]? = nil) {
        self.tick = tick; self.kind = kind; self.sourceID = sourceID; self.targetID = targetID; self.amount = amount; self.rootActionID = rootActionID; self.timestampMs = timestampMs; self.diagnostics = diagnostics
    }
}

/// Stable render mapping for battle entities; labels are presentation fallbacks, not canonical localization.
public struct CombatEntityPresentation: Codable, Sendable, Equatable {
    public let entityID: String
    public let kind: String
    public let catalogID: String?
    public let label: String
    public let assetKey: String?

    public init(entityID: String, kind: String, catalogID: String? = nil, label: String, assetKey: String? = nil) {
        self.entityID = entityID; self.kind = kind; self.catalogID = catalogID; self.label = label; self.assetKey = assetKey
    }
}

public struct CombatResult: Codable, Sendable, Equatable {
    public let won: Bool
    public let ticks: Int
    public let events: [CombatEvent]
    public let remainingPartyHP: [String: Int]
    public let initialPartyHP: [String: Int]
    public let initialEnemyHP: [String: Int]
    public let remainingEnemyHP: [String: Int]
    public let entityPresentation: [String: CombatEntityPresentation]

    public init(won: Bool, ticks: Int, events: [CombatEvent], remainingPartyHP: [String: Int], initialPartyHP: [String: Int] = [:], initialEnemyHP: [String: Int] = [:], remainingEnemyHP: [String: Int] = [:], entityPresentation: [String: CombatEntityPresentation] = [:]) {
        self.won = won; self.ticks = ticks; self.events = events; self.remainingPartyHP = remainingPartyHP
        self.initialPartyHP = initialPartyHP; self.initialEnemyHP = initialEnemyHP; self.remainingEnemyHP = remainingEnemyHP
        self.entityPresentation = entityPresentation
    }

    enum CodingKeys: String, CodingKey { case won, ticks, events, remainingPartyHP, initialPartyHP, initialEnemyHP, remainingEnemyHP, entityPresentation }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        won = try c.decode(Bool.self, forKey: .won); ticks = try c.decode(Int.self, forKey: .ticks)
        events = try c.decode([CombatEvent].self, forKey: .events)
        remainingPartyHP = try c.decodeIfPresent([String: Int].self, forKey: .remainingPartyHP) ?? [:]
        initialPartyHP = try c.decodeIfPresent([String: Int].self, forKey: .initialPartyHP) ?? [:]
        initialEnemyHP = try c.decodeIfPresent([String: Int].self, forKey: .initialEnemyHP) ?? [:]
        remainingEnemyHP = try c.decodeIfPresent([String: Int].self, forKey: .remainingEnemyHP) ?? [:]
        entityPresentation = try c.decodeIfPresent([String: CombatEntityPresentation].self, forKey: .entityPresentation) ?? [:]
    }
}

/// Deterministic, four-actor, auto-only implementation overlay. Candidate challenge patterns are not R6-B parity.
public enum CombatSimulator {
    public static let authority = BalanceAuthority.unapprovedTestOverlay
    public static func run(party: [Combatant], enemies: [Combatant], seed: UInt64, maxTicks: Int = 600) throws -> CombatResult {
        guard party.count == 4, !enemies.isEmpty, maxTicks > 0, (party + enemies).allSatisfy({ $0.maxHP > 0 && $0.attack >= 0 && $0.defense >= 0 }) else { throw CoreError.invalidCommand("combat requires four valid allies and at least one valid enemy") }
        var allyHP = party.map(\.maxHP), foeHP = enemies.map(\.maxHP), events: [CombatEvent] = []
        var poisonStacks = Array(repeating: 0, count: enemies.count), poisonNextTick = Array(repeating: 0, count: enemies.count), poisonExpiry = Array(repeating: 0, count: enemies.count), poisonPowerSnapshot = Array(repeating: 0, count: enemies.count)
        var smithWeakenExpiry = Array(repeating: 0, count: enemies.count)
        var witchSeedReady = 0, witchBurstReady = 0
        var smithHammerReady = 0
        var allyDot = Array(repeating: 0, count: party.count)
        var wardHP = Array(repeating: 0, count: party.count), wardExpiry = Array(repeating: 0, count: party.count), wardReady = Array(repeating: 0, count: party.count), reflectReady = Array(repeating: 0, count: party.count)
        var familiarChaseReady = Array(repeating: 0, count: party.count), familiarMarkExpiry = Array(repeating: 0, count: party.count)
        var pressure = 0
        var counteredRoots = Set<String>()
        var rng = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        func roll(_ state: inout UInt64) -> Int { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return Int(state % 100) }
        func emit(_ tick: Int, _ kind: String, _ source: String, _ target: String, _ amount: Int = 0, _ root: String? = nil) {
            events.append(CombatEvent(tick: tick, kind: kind, sourceID: source, targetID: target, amount: amount, rootActionID: root))
        }
        func result(_ won: Bool, _ tick: Int) -> CombatResult {
            CombatResult(won: won, ticks: tick, events: events,
                         remainingPartyHP: Dictionary(uniqueKeysWithValues: party.indices.map { (party[$0].id, allyHP[$0]) }),
                         initialPartyHP: Dictionary(uniqueKeysWithValues: party.map { ($0.id, $0.maxHP) }),
                         initialEnemyHP: Dictionary(uniqueKeysWithValues: enemies.map { ($0.id, $0.maxHP) }),
                         remainingEnemyHP: Dictionary(uniqueKeysWithValues: enemies.indices.map { (enemies[$0].id, foeHP[$0]) }))
        }
        for tick in 1...maxTicks {
            for i in party.indices where allyHP[i] > 0 && allyDot[i] > 0 {
                let d = min(allyHP[i], 2); allyHP[i] -= d; allyDot[i] -= 1; emit(tick, "dot_tick", "enemy", party[i].id, d, "enemy_dot:\(tick)")
            }
            for i in enemies.indices where foeHP[i] > 0 && poisonStacks[i] > 0 {
                if poisonNextTick[i] > 0 && poisonNextTick[i] <= tick && poisonNextTick[i] <= poisonExpiry[i] {
                    let raw = poisonPowerSnapshot[i] * 600 * poisonStacks[i] / 10_000
                    let d = min(foeHP[i], raw); foeHP[i] -= d
                    emit(tick, "poison_tick", "C_WITCH", enemies[i].id, d, "poison:\(tick)")
                    poisonNextTick[i] += 1
                }
                if tick >= poisonExpiry[i] {
                    poisonStacks[i] = 0; poisonNextTick[i] = 0; poisonPowerSnapshot[i] = 0
                    emit(tick, "poison_expire", "C_WITCH", enemies[i].id, 0, "poison:\(tick)")
                }
            }
            if foeHP.allSatisfy({ $0 <= 0 }) { return result(true, tick) }

            for ai in party.indices where allyHP[ai] > 0 && foeHP.contains(where: { $0 > 0 }) {
                guard let ti = foeHP.indices.first(where: { foeHP[$0] > 0 }) else { break }
                let actor = party[ai], foe = enemies[ti], root = "ally:\(actor.id):\(tick)"
                var usedHammer = false
                if actor.effectIDs.contains("BARRIER_WARD"), tick >= wardReady[ai] {
                    if tick > wardExpiry[ai] { wardHP[ai] = 0 }
                    var forecast = Array(repeating: 0, count: party.count)
                    let living = party.indices.filter { allyHP[$0] > 0 }
                    for ei in enemies.indices where foeHP[ei] > 0 {
                        let incoming = enemies[ei]
                        if incoming.actionPattern == "heavy", tick % 3 == 1 { continue }
                        if incoming.actionPattern == "aoe" || (incoming.actionPattern == "combined" && tick % 2 == 0) {
                            for target in living { forecast[target] += max(1, incoming.attack / 2) }
                        } else {
                            let amount = incoming.actionPattern == "heavy" && tick % 3 == 2 ? incoming.attack * 2 : incoming.attack
                            let hits = incoming.actionPattern == "multiHit" ? 3 : 1
                            if let target = living.first { forecast[target] += max(1, amount / (incoming.actionPattern == "multiHit" ? 2 : 1)) * hits }
                        }
                    }
                    if let target = party.indices.filter({ allyHP[$0] > 0 && forecast[$0] > wardHP[$0] })
                        .max(by: { forecast[$0] < forecast[$1] }), forecast[target] > 0 {
                        let existing = wardHP[target]
                        let room = max(0, party[target].maxHP * 35 / 100 - existing)
                        let shield = min(actor.attack * 2, room)
                        if shield > 0 {
                            wardHP[target] += shield; wardExpiry[target] = tick + 6
                            wardReady[ai] = tick + 10
                            emit(tick, "ward_create", actor.id, party[target].id, shield, root)
                        }
                    }
                }
                let armorActive = foe.actionPattern == "armor" && (tick - 1) % 10 < 6
                if armorActive { emit(tick, "enemy_armor", foe.id, actor.id, 5_000, root) }
                var damage = max(1, actor.attack - foe.defense + roll(&rng) % 3)
                if actor.id == "C_SMITH", actor.effectIDs.contains("SMITH_PRESSURE"), pressure > 0, tick >= smithHammerReady {
                    damage = max(1, actor.attack * (16_000 + 2_000 * pressure) / 10_000 - foe.defense)
                    smithHammerReady = tick + 8
                    smithWeakenExpiry[ti] = tick + 6
                    emit(tick, "smith_hammer", actor.id, foe.id, damage, root)
                    emit(tick, "enemy_weaken", actor.id, foe.id, 1_200, root)
                    pressure = 0
                    usedHammer = true
                }
                let canUsePoisonSkills = actor.id == "C_WITCH" && actor.effectIDs.contains("POISON_STACK")
                let poisonCap = actor.effectIDs.contains("POISON_STACK_CAP_2") ? 7 : 5
                let shouldSeed = canUsePoisonSkills && tick >= witchSeedReady &&
                    (poisonStacks[ti] == 0 || tick >= poisonExpiry[ti] - 2 || poisonStacks[ti] < poisonCap)
                let shouldBurst = canUsePoisonSkills && actor.effectIDs.contains("POISON_SHATTER") &&
                    poisonStacks[ti] >= 5 && tick >= witchBurstReady && !shouldSeed
                if shouldSeed {
                    damage = max(1, actor.attack * 2_500 / 10_000 - foe.defense)
                    witchSeedReady = tick + 6
                    if poisonStacks[ti] == 0 { poisonNextTick[ti] = tick + 1 }
                    poisonPowerSnapshot[ti] = actor.attack
                    poisonStacks[ti] = min(poisonCap, poisonStacks[ti] + 2)
                    poisonExpiry[ti] = tick + 9
                    emit(tick, "poison_seed", actor.id, foe.id, 2, root)
                    emit(tick, "poison_stack", actor.id, foe.id, poisonStacks[ti], root)
                } else if shouldBurst {
                    let bonusBP = actor.effectIDs.contains("POISON_BURST_25_AT_5") ? 2_500 : 0
                    damage = max(1, actor.attack * (24_000 + bonusBP) / 10_000 - foe.defense)
                    witchBurstReady = tick + 7
                    emit(tick, "poison_burst", actor.id, foe.id, damage, root)
                }
                if armorActive { damage = max(1, damage / 2) }
                foeHP[ti] -= damage
                if !usedHammer { emit(tick, "direct", actor.id, foe.id, damage, root) }
                if actor.id == "C_FAMILIAR", actor.effectIDs.contains("FAMILIAR_MARK_10S") { familiarMarkExpiry[ai] = tick + 10; emit(tick, "familiar_mark", actor.id, foe.id, 10, root) }
                if actor.id == "C_FAMILIAR", actor.effectIDs.contains("FAMILIAR_CHASE"), tick >= familiarChaseReady[ai], roll(&rng) < 20 {
                    let marked = familiarMarkExpiry[ai] >= tick
                    let chase = max(1, actor.attack / 2)
                    let dash = marked && actor.effectIDs.contains("FAMILIAR_DASH_BONUS_6000BP") ? actor.attack * 6 / 10 : 0
                    let extra = chase + dash; foeHP[ti] -= extra; emit(tick, "familiar_chase", actor.id, foe.id, extra, root)
                    if actor.effectIDs.contains("FAMILIAR_CHASE_ICD_1500MS") { familiarChaseReady[ai] = tick + 2 }
                }
            }
            if foeHP.allSatisfy({ $0 <= 0 }) { return result(true, tick) }

            for ei in enemies.indices where foeHP[ei] > 0 {
                let enemy = enemies[ei], root = "enemy:\(enemy.id):\(tick)"
                let living = allyHP.indices.filter { allyHP[$0] > 0 }
                guard !living.isEmpty else { break }
                let actionAttack = tick <= smithWeakenExpiry[ei] ? enemy.attack * 8_800 / 10_000 : enemy.attack
                if enemy.actionPattern == "heavy", tick % 3 == 1 { emit(tick, "telegraph_heavy", enemy.id, party[living[0]].id, actionAttack * 2, root); continue }
                if enemy.actionPattern == "heavy", tick % 3 == 2 { applyHit(actionAttack * 2, target: living[0], enemy: enemy, root: root, tick: tick) }
                else if enemy.actionPattern == "multiHit" {
                    let target = living[0]
                    for hit in 1...3 where allyHP[target] > 0 { applyHit(max(1, actionAttack / 2), target: target, enemy: enemy, root: root, tick: tick, hit: hit) }
                } else if enemy.actionPattern == "dot" {
                    let target = living[0]; applyHit(actionAttack, target: target, enemy: enemy, root: root, tick: tick); allyDot[target] = max(allyDot[target], 3); emit(tick, "dot_applied", enemy.id, party[target].id, 3, root)
                } else if enemy.actionPattern == "aoe" || (enemy.actionPattern == "combined" && tick % 2 == 0) {
                    emit(tick, "telegraph_aoe", enemy.id, "party", actionAttack, root)
                    for target in living { applyHit(max(1, actionAttack / 2), target: target, enemy: enemy, root: root, tick: tick) }
                } else {
                    let target = living[0]; applyHit(actionAttack, target: target, enemy: enemy, root: root, tick: tick)
                }
                if enemy.actionPattern == "support", let weakest = foeHP.indices.filter({ foeHP[$0] > 0 }).min(by: { foeHP[$0] < foeHP[$1] }) {
                    let heal = max(1, enemies[ei].attack / 3); foeHP[weakest] = min(enemies[weakest].maxHP, foeHP[weakest] + heal); emit(tick, "enemy_support", enemy.id, enemies[weakest].id, heal, root)
                }
            }

            // Root healing is one automatic action; its follow-up is depth-one and cannot recurse.
            if tick % 3 == 0, let healer = party.indices.first(where: { party[$0].id == "C_APPRENTICE" && allyHP[$0] > 0 }),
               let target = allyHP.indices.filter({ allyHP[$0] > 0 && allyHP[$0] < party[$0].maxHP }).max(by: { party[$0].maxHP - allyHP[$0] < party[$1].maxHP - allyHP[$1] }) {
                let effective = min(party[target].maxHP - allyHP[target], max(1, party[healer].attack / 2)); allyHP[target] += effective
                let root = "heal:C_APPRENTICE:\(tick)"; emit(tick, "root_heal", party[healer].id, party[target].id, effective, root)
                if party[healer].effectIDs.contains("HEAL_TO_BARRIER") {
                    let barrier = effective / 5; wardHP[target] += barrier; wardExpiry[target] = max(wardExpiry[target], tick + 6); emit(tick, "heal_barrier", party[healer].id, party[target].id, barrier, root)
                }
                if party[healer].effectIDs.contains("HEAL_LINK"), let targetEnemy = foeHP.indices.first(where: { foeHP[$0] > 0 }) {
                    let followup = max(1, party[target].attack / 5); foeHP[targetEnemy] -= followup; emit(tick, "heal_followup", party[target].id, enemies[targetEnemy].id, followup, root)
                }
            }
            if allyHP.allSatisfy({ $0 <= 0 }) { return result(false, tick) }
        }
        return result(false, maxTicks)

        func applyHit(_ rawDamage: Int, target: Int, enemy: Combatant, root: String, tick: Int, hit: Int = 1) {
            guard allyHP[target] > 0 else { return }
            let actor = party[target]
            var damage = max(1, rawDamage - actor.defense)
            let guarded = actor.guardChanceBP > 0 && roll(&rng) * 100 < actor.guardChanceBP
            if guarded {
                damage = max(1, damage * (10_000 - actor.guardReductionBP) / 10_000)
                emit(tick, "guard", enemy.id, actor.id, actor.guardReductionBP, root)
            }
            let guardContact = guarded && damage > 0
            let ward = tick <= wardExpiry[target] ? min(damage, wardHP[target]) : 0
            if ward > 0 { wardHP[target] -= ward; damage -= ward; emit(tick, "barrier_absorb", enemy.id, actor.id, ward, root) }
            allyHP[target] = max(0, allyHP[target] - damage); emit(tick, "enemy_hit", enemy.id, actor.id, damage, root)
            if guardContact, counteredRoots.insert(root).inserted,
               let smith = party.indices.first(where: { party[$0].id == "C_SMITH" && allyHP[$0] > 0 }) {
                let counter = max(1, party[smith].attack * 7_500 / 10_000)
                if let foe = enemies.firstIndex(where: { $0.id == enemy.id }) { foeHP[foe] = max(0, foeHP[foe] - counter) }
                emit(tick, "smith_counter", party[smith].id, enemy.id, counter, root)
                if party[smith].effectIDs.contains("SMITH_PRESSURE") {
                    pressure = min(3, pressure + 1); emit(tick, "smith_pressure", party[smith].id, enemy.id, pressure, root)
                }
            }
            if ward > 0, actor.effectIDs.contains("BARRIER_REFLECT"), tick >= reflectReady[target] {
                let reflected = max(1, ward / 2); if let foe = enemies.firstIndex(where: { $0.id == enemy.id }) { foeHP[foe] -= reflected }
                reflectReady[target] = tick + 3; emit(tick, "barrier_reflect", actor.id, enemy.id, reflected, root)
            }
            _ = hit // Multi-hit contacts share the counter root action.
        }
    }
}
