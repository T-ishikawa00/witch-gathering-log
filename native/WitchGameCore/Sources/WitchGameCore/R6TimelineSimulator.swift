import Foundation

/// Integer-millisecond event scheduler port of the R6-B battle loop. Data IDs and
/// values remain candidate overlay inputs; this is deliberately separate from
/// the compatibility tick simulator until differential contracts pass.
public enum R6TimelineSimulator {
    private enum Kind {
        case decide(Int)
        case commit(Int, String, Int, String)
        case enemyTell(Int, Int)
        case magnetStrikeStart(Int, String)
        case enemyHit(Int, String, Int, Int)
        case enemySupport(Int, Int, String, String)
        case reflectProjectile(Int, Int, Int, String)
        case poisonTick(Int)
        case allyDot(Int, String)
        case reaction(String, Int, String, String)
        case expireMark(Int)
        case expirePoison(Int)
    }
    private struct Entry { let at: Int; let priority: Int; let seq: Int; let kind: Kind }
    private struct ActorState {
        var hp: Int
        var basicAt: Int
        var busyUntil = 0
        var casting = false
        var castingAction: String?
        var castingRoot: String?
        var castingFinishAt = 0
        var castSlowUntil = 0
        var ready: [String: Int] = [:]
        var sequence: [String: Int] = [:]
        var shields: [(amount: Int, expiry: Int, source: String)] = []
        var guardUntil = 0
        var coverCharges = 0
        var coverRoots = Set<String>()
        var counterAt = 0
        var counterRoots = Set<String>()
        var chaseAt = 0
        var chaseRoots = Set<String>()
        var smithCoverBarrierReadyAt = 0
        var echoExpiry = 0
        var echoCharges = 0
        var echoReadyAt = 0
        var echoBonusBP = 1_500
        var reflectReadyAt = 0
        var dotStacks = 0
        var dotNext = 0
        var slowUntil = 0
        var weakenedUntil = 0
    }
    private struct EnemyState {
        var hp: Int
        var phase = 1
        var buffUntil = 0
        var supportBuffBP = 0
        var supportBuffUntil = 0
        var guardUntil = 0
        var mirrorUntil = 0
        var openingUntil = 0
        var armorUntil = 0
        var followupReadyAt = 0
        var followupTriggerRoots: Set<String> = []
        var heatStored = false
        var poison = 0
        var poisonNext: Int?
        var poisonExpiry = 0
        var poisonPower = 0
        var markExpiry = 0
        var weakenExpiry = 0
        var actionCount = 0
        var telegraphs: [String: (target: Int?, hits: [Int], processed: Int, pattern: String, action: EnemyActionDefinition?)] = [:]
    }

    private static let actorOrder = ["C_WITCH", "C_FAMILIAR", "C_APPRENTICE", "C_SMITH"]
    /// R4-only, unapproved candidate formation. Kept separate from renderer coordinates
    /// and from the immutable R6 source profile. See the candidate formation contract.
    private static let candidateFrontRowIDs: Set<String> = ["C_SMITH", "C_FAMILIAR"]
    private static let intervals = ["C_WITCH": 1_800, "C_APPRENTICE": 2_000, "C_SMITH": 2_200, "C_FAMILIAR": 1_400]
    private static let windups = ["basic": 250, "seed": 400, "burst": 450, "mark": 200, "dash": 200, "heal": 300, "ward": 250, "guard": 150, "hammer": 500]
    private static let recoveries = ["basic": 250, "seed": 300, "burst": 300, "mark": 200, "dash": 300, "heal": 250, "ward": 200, "guard": 250, "hammer": 400]
    private static let cooldowns = ["seed": 6_000, "burst": 7_000, "mark": 8_000, "dash": 6_000, "heal": 6_000, "ward": 10_000, "guard": 10_000, "hammer": 8_000]

    /// F03's campaign candidate ICD is gear-specific. The immutable R6 source
    /// profile deliberately retains its verified 2,000 ms reaction interval.
    static func familiarChaseCooldownMs(effectIDs: Set<String>, sourceProfile: Bool) -> Int {
        sourceProfile ? 2_000 : (effectIDs.contains("FAMILIAR_CHASE_ICD_1500MS") ? 1_500 : 2_000)
    }

    private static func sourceSkillID(_ actorID: String, _ action: String) -> String {
        if action == "basic" { return "\(actorID)_BASIC" }
        let skills: [String: String] = ["seed": "SK_W_SEED", "burst": "SK_W_BURST", "mark": "SK_F_MARK", "dash": "SK_F_DASH", "heal": "SK_A_HEAL", "ward": "SK_A_WARD", "guard": "SK_S_GUARD", "hammer": "SK_S_HAMMER"]
        return skills[action] ?? action
    }

    private static func checkedScaleBP(_ value: Int, _ basisPoints: Int) throws -> Int {
        guard value >= 0, basisPoints >= 0 else { throw CoreError.invalidCommand("candidate scale requires nonnegative input") }
        let wholeProduct = (value / 10_000).multipliedReportingOverflow(by: basisPoints)
        let remainderProduct = (value % 10_000).multipliedReportingOverflow(by: basisPoints)
        guard !wholeProduct.overflow, !remainderProduct.overflow else { throw CoreError.invalidCommand("candidate damage scale overflow") }
        let combined = wholeProduct.partialValue.addingReportingOverflow(remainderProduct.partialValue / 10_000)
        guard !combined.overflow else { throw CoreError.invalidCommand("candidate damage scale overflow") }
        return combined.partialValue
    }

    /// R2 time scaling uses a ceiling so a fractional millisecond does not
    /// shorten an authored interval. Inputs are small authored durations, but
    /// checked arithmetic keeps malformed candidate values from trapping.
    private static func ceilScale(_ value: Int, numerator: Int, denominator: Int) throws -> Int {
        guard value >= 0, numerator >= 0, denominator > 0 else {
            throw CoreError.invalidCommand("invalid candidate time scale")
        }
        let product = value.multipliedReportingOverflow(by: numerator)
        guard !product.overflow else { throw CoreError.invalidCommand("candidate time scale overflow") }
        let quotient = product.partialValue / denominator
        let remainder = product.partialValue % denominator
        if remainder == 0 { return quotient }
        let rounded = quotient.addingReportingOverflow(1)
        guard !rounded.overflow else { throw CoreError.invalidCommand("candidate time scale overflow") }
        return rounded.partialValue
    }

    private static func candidateModifiersAreValid(_ value: CandidateLatentCombatModifiersR005) -> Bool {
        (0...10_000).contains(value.hpPercentBP) && (0...8_000).contains(value.powerPercentBP)
            && (0...10_000).contains(value.defensePercentBP) && (0...6_000).contains(value.critChanceBP)
            && (15_000...22_500).contains(value.critMultiplierBP) && (0...5_000).contains(value.hasteBP)
            && (0...2_500).contains(value.cooldownReductionBP) && (0...6_000).contains(value.directBonusBP)
            && (0...10_000).contains(value.dotBonusBP) && (0...10_000).contains(value.healBonusBP)
            && (0...10_000).contains(value.barrierBonusBP) && (0...4_500).contains(value.guardChanceBP)
            && (0...10_000).contains(value.counterBonusBP) && (0...10_000).contains(value.chaseBonusBP)
            && (0...5_000).contains(value.debuffDurationResistBP) && (0...5_000).contains(value.periodicResistBP)
    }

    private static func candidateDuration(_ baseMs: Int, resistanceBP: Int) throws -> Int {
        let bounded = max(0, min(5_000, resistanceBP))
        return max(1, try ceilScale(baseMs, numerator: 10_000 - bounded, denominator: 10_000))
    }

    public static func run(party: [Combatant], enemies: [Combatant], seed: UInt64, maxDurationMs: Int = 600_000, challengeID: String? = nil, entityPresentation: [String: CombatEntityPresentation] = [:], sourceProfileSeed: String? = nil, initialBarriers: [String: (amount: Int, expiryMs: Int)] = [:], candidateMagnetParameters: MagnetMechanicParameters? = nil) throws -> CombatResult {
        let candidateLatentInputsValid = sourceProfileSeed != nil || (party + enemies).allSatisfy {
            $0.candidateLatentModifiersR004.map(candidateModifiersAreValid) ?? true
        }
        let hasCandidateLatentModifiers = sourceProfileSeed == nil && (party + enemies).contains { $0.candidateLatentModifiersR004 != nil }
        let candidateNumericInputsValid = !hasCandidateLatentModifiers || (
            maxDurationMs <= 86_400_000 && (party + enemies).allSatisfy {
                // The candidate timeline contains a few legacy integer products
                // (e.g. attack * authored coefficient before /10,000 and maxHP
                // percentage thresholds). Keep inputs inside the largest fixed
                // BP products used by this experiment; canonical/nil paths keep
                // their existing acceptance surface.
                $0.maxHP <= Int.max / 10_000 && $0.attack <= Int.max / 100_000 && $0.defense <= Int.max / 10_000
                    && ($0.enemyActions ?? []).allSatisfy { action in
                        (0...100_000).contains(action.coefficientBP)
                            && action.windupMs >= 0 && action.recoveryMs >= 0 && action.restMs >= 0
                            && !action.hitOffsetsMs.isEmpty && action.hitOffsetsMs.allSatisfy { $0 >= 0 }
                    }
            }
        )
        guard party.count == 4, !enemies.isEmpty, maxDurationMs > 0,
              Set(party.map(\.id)) == Set(actorOrder), (party + enemies).allSatisfy({ $0.maxHP > 0 && $0.attack >= 0 && $0.defense >= 0 }),
              candidateLatentInputsValid, candidateNumericInputsValid,
              candidateMagnetParameters.map(\.isValidForExperiment) ?? true,
              candidateMagnetParameters == nil || maxDurationMs <= 86_400_000,
              candidateMagnetParameters == nil || (party + enemies).allSatisfy({ $0.maxHP <= Int.max / 10_000 }),
              candidateMagnetParameters == nil || enemies.filter({ $0.actionPattern == "magnetMarkStrike" }).allSatisfy({ $0.attack <= Int.max / 10_000 }),
              sourceProfileSeed == nil || candidateMagnetParameters == nil,
              !enemies.contains(where: { $0.actionPattern == "magnetMarkStrike" }) || (candidateMagnetParameters != nil && sourceProfileSeed == nil) else {
            throw CoreError.invalidCommand("invalid timeline input or isolated magnet parameters required")
        }
        let partyByID = Dictionary(uniqueKeysWithValues: party.map { ($0.id, $0) })
        let orderedParty = actorOrder.compactMap { partyByID[$0] }
        var candidateIntervals = intervals
        if sourceProfileSeed == nil {
            for actor in orderedParty {
                if let modifiers = actor.candidateLatentModifiersR004, modifiers.hasteBP > 0 {
                    candidateIntervals[actor.id] = max(500, try ceilScale(intervals[actor.id] ?? 1_800,
                                                                         numerator: 10_000,
                                                                         denominator: 10_000 + min(5_000, modifiers.hasteBP)))
                }
            }
        }
        var allies = orderedParty.map { ActorState(hp: $0.maxHP, basicAt: max(0, (candidateIntervals[$0.id] ?? 1_800) - 250)) }
        var foes = enemies.map { EnemyState(hp: $0.maxHP) }
        var events: [CombatEvent] = [], queue: [Entry] = [], now = 0, seq = 0, randomState = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        var pressure = 0
        var generatedFollowupRoots: Set<String> = []
        var outcome: Bool? = nil
        func roll(_ state: inout UInt64, _ range: Int, domain: String, index: String) throws -> Int {
            if let sourceProfileSeed {
                return try R6CanonicalProfile.keyedInt(seed: sourceProfileSeed,
                                                       label: R6CanonicalProfile.keyedLabel(domain: domain, index: index),
                                                       upperBound: range)
            }
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(max(1, range)))
        }
        func rollInt(_ state: inout UInt64, _ range: Int, domain: String, index: Int) throws -> Int {
            if let sourceProfileSeed {
                return try R6CanonicalProfile.keyedInt(seed: sourceProfileSeed,
                                                       label: R6CanonicalProfile.keyedLabel(domain: domain, index: index),
                                                       upperBound: range)
            }
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Int(state % UInt64(max(1, range)))
        }
        func push(_ at: Int, _ priority: Int, _ kind: Kind) {
            let aiOrder: Int
            if case .decide(let ai) = kind {
                let actorID = actorOrder[ai]
                aiOrder = actorID == "C_SMITH" ? 0 : actorID == "C_APPRENTICE" ? 1 : actorID == "C_WITCH" ? 2 : 3
            } else { aiOrder = 0 }
            seq += 1; queue.append(Entry(at: max(now, at), priority: priority * 10 + aiOrder, seq: seq, kind: kind))
        }
        func emit(_ at: Int, _ kind: String, _ source: String, _ target: String, _ amount: Int = 0, _ root: String? = nil, diagnostics: [String: Int]? = nil) {
            events.append(CombatEvent(tick: at / 1_000, kind: kind, sourceID: source, targetID: target, amount: amount, rootActionID: root, timestampMs: at, diagnostics: diagnostics))
        }
        for ai in allies.indices {
            if let shield = initialBarriers[orderedParty[ai].id], shield.amount > 0, shield.expiryMs > 0 {
                allies[ai].shields.append((shield.amount, shield.expiryMs, orderedParty[ai].id))
                emit(0, "barrier", orderedParty[ai].id, orderedParty[ai].id, shield.amount)
            }
        }
        func livingEnemy() -> Int? { foes.indices.first(where: { foes[$0].hp > 0 }) }
        func livingAlly() -> Int? { allies.indices.first(where: { allies[$0].hp > 0 }) }
        func projectedThreat(until deadline: Int, target: Int) -> Int {
            var total = 0
            for ei in foes.indices where foes[ei].hp > 0 {
                for tele in foes[ei].telegraphs.values {
                    guard tele.hits.contains(where: { $0 > now && $0 <= deadline }) else { continue }
                    let isAOE = tele.target == nil
                    guard isAOE || tele.target == target else { continue }
                    if sourceProfileSeed != nil, let action = tele.action, let attackerLevel = enemies[ei].level {
                        for hitAt in tele.hits where hitAt > now && hitAt <= deadline {
                            var raw = enemies[ei].attack * action.coefficientBP / 10_000
                            if foes[ei].weakenExpiry > hitAt { raw = raw * 8_800 / 10_000 }
                            let hitDamage = (try? R6CanonicalProfile.incomingDamage(.init(power: raw,
                                                                                          coefficientBP: 10_000,
                                                                                          defense: orderedParty[target].defense,
                                                                                          attackerLevel: attackerLevel))) ?? max(1, raw)
                            total += hitDamage
                        }
                        continue
                    }
                    var hitDamage = max(1, enemies[ei].attack - orderedParty[target].defense)
                    if foes[ei].supportBuffUntil > now {
                        hitDamage = hitDamage * (10_000 + foes[ei].supportBuffBP) / 10_000
                    }
                    if tele.pattern == "heavy" { hitDamage *= 2 }
                    if tele.pattern == "multiHit" { hitDamage = max(1, hitDamage / 2) }
                    total += hitDamage * tele.hits.filter { $0 > now && $0 <= deadline }.count
                }
            }
            return total
        }
        func sourceShouldGuard(now: Int, smithIndex: Int, party: [Combatant], allies: [ActorState],
                               enemies: [Combatant], foes: [EnemyState]) throws -> Bool {
            let smith = party[smithIndex], smithState = allies[smithIndex]
            guard smithState.hp * 10_000 > smith.maxHP * 3_500,
                  !(smithState.guardUntil > now && smithState.coverCharges > 0) else { return false }
            for enemyIndex in foes.indices where foes[enemyIndex].hp > 0 {
                for tele in foes[enemyIndex].telegraphs.values {
                    guard let targetIndex = tele.target,
                          tele.action?.aoe == false, !(tele.processed > 0),
                          let action = tele.action else { continue }
                    let hits = tele.hits.filter { $0 > now }
                    guard let firstHit = hits.first, firstHit <= now + 1_500,
                          now + (windups["guard"] ?? 150) < firstHit else { continue }
                    func damage(_ actor: Combatant, redirected: Bool = false) throws -> Int {
                        var raw = enemies[enemyIndex].attack * action.coefficientBP / 10_000
                        if foes[enemyIndex].weakenExpiry > now { raw = raw * 8_800 / 10_000 }
                        return try R6CanonicalProfile.incomingDamage(.init(power: raw,
                                                                            coefficientBP: 10_000,
                                                                            defense: actor.defense,
                                                                            attackerLevel: enemies[enemyIndex].level ?? 1,
                                                                            specialReductionBP: redirected ? 1_500 : 0))
                    }
                    let targetIncoming = try damage(party[targetIndex])
                    var targetShield = allies[targetIndex].shields.filter { $0.expiry > firstHit }.reduce(0) { $0 + $1.amount }
                    var targetLoss = 0, singleHitLoss = 0
                    for _ in hits {
                        let effective = max(0, targetIncoming - targetShield)
                        targetShield = max(0, targetShield - targetIncoming)
                        targetLoss += effective; singleHitLoss = max(singleHitLoss, effective)
                    }
                    let targetProjectedHP = allies[targetIndex].hp - targetLoss
                    let targetIsDangerous = singleHitLoss * 10_000 >= party[targetIndex].maxHP * 2_000 ||
                        targetProjectedHP * 10_000 <= party[targetIndex].maxHP * 3_500
                    guard targetIsDangerous else { continue }
                    let smithIncoming = try damage(smith, redirected: true)
                    let smithBarrier = smithState.shields.filter { $0.expiry > firstHit }.reduce(0) { $0 + $1.amount }
                    let redirectedDamage = smithIncoming * hits.count
                    if max(0, redirectedDamage - smithBarrier) < smithState.hp { return true }
                }
            }
            return false
        }
        func winCheck() -> Bool? {
            if foes.allSatisfy({ $0.hp <= 0 }) { return true }
            if allies.allSatisfy({ $0.hp <= 0 }) { return false }
            return nil
        }
        for ai in allies.indices { push(0, 4, .decide(ai)) }
        for ei in foes.indices { push(enemies[ei].firstTelegraphMs ?? 2_500, 2, .enemyTell(ei, 0)) }

        while !queue.isEmpty && outcome == nil {
            queue.sort { ($0.at, $0.priority, $0.seq) < ($1.at, $1.priority, $1.seq) }
            let entry = queue.removeFirst(); now = entry.at
            if now > maxDurationMs { outcome = false; break }
            switch entry.kind {
            case .decide(let ai):
                guard allies[ai].hp > 0, !allies[ai].casting else { continue }
                if allies[ai].slowUntil > now { push(allies[ai].slowUntil, 4, .decide(ai)); continue }
                if allies[ai].busyUntil > now { push(allies[ai].busyUntil, 4, .decide(ai)); continue }
                guard let ei = livingEnemy() else { outcome = true; break }
                let actor = orderedParty[ai], effects = actor.effectIDs
                let poisonStacks = foes[ei].poison, markExpiry = foes[ei].markExpiry
                var skill: String? = nil, target = ei
                if actor.id == "C_WITCH" {
                    if effects.contains("BARRIER_WARD"), allies[ai].ready["ward", default: 0] <= now,
                       let threatened = allies.indices.filter({ allies[$0].hp > 0 && projectedThreat(until: now + 6_000, target: $0) > 0 })
                            .max(by: { projectedThreat(until: now + 6_000, target: $0) < projectedThreat(until: now + 6_000, target: $1) }),
                       projectedThreat(until: now + 6_000, target: threatened) > allies[threatened].shields.filter({ $0.expiry > now }).reduce(0, { $0 + $1.amount }) {
                        skill = "ward"; target = threatened
                    } else if effects.contains("POISON_STACK"), !effects.contains("WARD_REPLACES_SEED"), allies[ai].ready["seed", default: 0] <= now,
                              poisonStacks == 0 || foes[ei].poisonExpiry - now <= 2_000 || poisonStacks < (effects.contains("POISON_STACK_CAP_2") ? 7 : 5) {
                        skill = "seed"
                    } else if allies[ai].ready["burst", default: 0] <= now { skill = "burst" }
                } else if actor.id == "C_FAMILIAR" {
                    if allies[ai].ready["mark", default: 0] <= now, markExpiry <= now + 1_000 { skill = "mark" }
                    else if allies[ai].ready["dash", default: 0] <= now { skill = "dash" }
                } else if actor.id == "C_APPRENTICE" {
                    let sourceHealNominal = try {
                        guard sourceProfileSeed != nil else { return 0 }
                        let stats = actor.r6SourceStats
                        return try R6CanonicalProfile.multiplyDivideFloor(base: actor.attack,
                                                                           numeratorFactors: [22_000, 10_000 + (stats?.healBonusBP ?? 0)],
                                                                           denominatorFactors: [10_000, 10_000])
                    }()
                    let injured = allies.indices.filter { index in
                        guard allies[index].hp > 0 else { return false }
                        if sourceProfileSeed != nil {
                            let deficit = orderedParty[index].maxHP - allies[index].hp
                            return deficit > 0 && deficit * 10_000 >= sourceHealNominal * 5_000
                        }
                        return allies[index].hp * 10_000 / orderedParty[index].maxHP <= 7_000
                    }
                    let lethalWardTarget = allies.indices.filter { allies[$0].hp > 0 && projectedThreat(until: now + 1_500, target: $0) >= allies[$0].hp }
                        .min(by: { allies[$0].hp < allies[$1].hp })
                    let sourceWardTarget = try { () -> Int? in
                        guard sourceProfileSeed != nil, allies[ai].ready["ward", default: 0] <= now else { return nil }
                        let nominal = try R6CanonicalProfile.multiplyDivideFloor(base: actor.attack,
                                                                                  numeratorFactors: [15_000, 10_000 + (actor.r6SourceStats?.barrierBonusBP ?? 0)],
                                                                                  denominatorFactors: [10_000, 10_000])
                        let candidates = allies.indices.compactMap { target -> (Int, Int, Int)? in
                            guard allies[target].hp > 0,
                                  projectedThreat(until: now + 3_000, target: target) > 0 else { return nil }
                            let futureDamage = projectedThreat(until: now + 3_000, target: target)
                            let existing = allies[target].shields.filter { $0.expiry > now + 250 }.reduce(0) { $0 + $1.amount }
                            let cap = max(0, orderedParty[target].maxHP * 35 / 100 - existing)
                            let grant = min(cap, nominal)
                            let effective = min(futureDamage, grant)
                            let projected = allies[target].hp - futureDamage
                            guard grant > 0, projected < allies[target].hp, effective * 10_000 >= nominal * 5_000 else { return nil }
                            return (projected <= 0 ? 0 : 1, -effective, target)
                        }
                        return candidates.min { lhs, rhs in
                            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                            return actorOrder.firstIndex(of: orderedParty[lhs.2].id)! < actorOrder.firstIndex(of: orderedParty[rhs.2].id)!
                        }?.2
                    }()
                    if let lethal = lethalWardTarget, allies[ai].ready["ward", default: 0] <= now, projectedThreat(until: now + 1_500, target: lethal) > 0 {
                        target = lethal; skill = "ward"
                    } else if !injured.isEmpty, allies[ai].ready["heal", default: 0] <= now {
                        target = injured.min(by: { allies[$0].hp * 10_000 / orderedParty[$0].maxHP < allies[$1].hp * 10_000 / orderedParty[$1].maxHP })!; skill = "heal"
                    } else if let candidate = sourceWardTarget {
                        target = candidate; skill = "ward"
                    } else if allies[ai].ready["ward", default: 0] <= now {
                        let candidate = allies.indices.filter { allies[$0].hp > 0 }.filter { target in
                            let threat = projectedThreat(until: now + 1_500, target: target)
                            return threat * 10_000 >= orderedParty[target].maxHP * 2_000 ||
                                (sourceProfileSeed == nil && allies[target].hp * 10_000 <= orderedParty[target].maxHP * 5_000)
                        }.min(by: { allies[$0].hp * 10_000 / orderedParty[$0].maxHP < allies[$1].hp * 10_000 / orderedParty[$1].maxHP })
                        if let candidate { target = candidate; skill = "ward" }
                    }
                } else if actor.id == "C_SMITH" {
                    let urgent: Bool
                    if sourceProfileSeed != nil {
                        urgent = try sourceShouldGuard(now: now, smithIndex: ai, party: orderedParty, allies: allies,
                                                       enemies: enemies, foes: foes)
                    } else {
                        urgent = foes.indices.contains { fi in
                            foes[fi].telegraphs.values.contains { tele in
                                guard let ti = tele.target, tele.hits.contains(where: { $0 > now && $0 <= now + 1_500 }) else { return false }
                                var forecast = max(1, enemies[fi].attack - orderedParty[ti].defense)
                                if tele.pattern == "heavy" { forecast *= 2 }
                                if tele.pattern == "multiHit" { forecast = max(1, forecast / 2) }
                                return forecast * 10_000 >= orderedParty[ti].maxHP * 2_000 ||
                                    (allies[ti].hp - forecast) * 10_000 <= orderedParty[ti].maxHP * 3_500
                            }
                        }
                    }
                    if urgent, allies[ai].ready["guard", default: 0] <= now { skill = "guard"; target = ai }
                    else if allies[ai].ready["hammer", default: 0] <= now { skill = "hammer" }
                }
                let useBasic = skill == nil && allies[ai].basicAt <= now
                if sourceProfileSeed != nil, actor.id == "C_APPRENTICE" {
                    var diagnostic = [String: Int]()
                    for index in allies.indices {
                        let id = orderedParty[index].id
                        diagnostic["\(id).hp"] = allies[index].hp
                        diagnostic["\(id).maxHP"] = orderedParty[index].maxHP
                        diagnostic["\(id).threat1500"] = projectedThreat(until: now + 1_500, target: index)
                        diagnostic["\(id).threat3000"] = projectedThreat(until: now + 3_000, target: index)
                        diagnostic["\(id).busyUntil"] = allies[index].busyUntil
                    }
                    diagnostic["wardReadyAt"] = allies[ai].ready["ward", default: 0]
                    diagnostic["healReadyAt"] = allies[ai].ready["heal", default: 0]
                    let selectedTarget = (skill == "ward" || skill == "heal") && target >= 0 && target < orderedParty.count ? orderedParty[target].id : "boss"
                    emit(now, "support_decision", actor.id, "\(skill ?? (useBasic ? "basic" : "none"))|\(selectedTarget)", 0,
                         diagnostics: diagnostic)
                }
                if sourceProfileSeed != nil, actor.id == "C_SMITH" {
                    // The locked Python support trace records Smith's decision
                    // immediately before the corresponding cast (or no-op).
                    // Keep this diagnostic source-profile-only; campaign events
                    // and actor scheduling are unaffected.
                    let selectedAction = skill ?? (useBasic ? "basic" : nil)
                    let selectedTarget = skill == "guard" ? actor.id : "boss"
                    let selectedSkillID = selectedAction.map { sourceSkillID(actor.id, $0) } ?? "none"
                    emit(now, "support_decision", actor.id, "\(selectedSkillID)|\(selectedTarget)")
                }
                guard let action = skill ?? (useBasic ? "basic" : nil) else {
                    let wake = min(allies[ai].basicAt, allies[ai].ready.values.filter { $0 > now }.min() ?? Int.max)
                    if wake != Int.max { push(wake, 4, .decide(ai)) }
                    continue
                }
                allies[ai].sequence[action, default: 0] += 1
                let actionSequence = allies[ai].sequence[action]!
                let root = sourceProfileSeed.map { _ in "\(actor.id):\(Self.sourceSkillID(actor.id, action)):\(actionSequence)" }
                    ?? "\(actor.id):\(action):\(actionSequence)"
                allies[ai].casting = true
                allies[ai].castingAction = action
                allies[ai].castingRoot = root
                let time = now + (windups[action] ?? 250) + (allies[ai].castSlowUntil > now ? 500 : 0)
                allies[ai].castingFinishAt = time
                push(time, 2, .commit(ai, action, target, root))
                emit(now, "cast_start", actor.id, action, 0, root)

            case .commit(let ai, let action, let target, let root):
                guard allies[ai].hp > 0, allies[ai].casting, allies[ai].castingAction == action,
                      allies[ai].castingRoot == root, allies[ai].castingFinishAt == now, let ei = livingEnemy() else { continue }
                let actor = orderedParty[ai]; allies[ai].casting = false; allies[ai].castingAction = nil; allies[ai].castingRoot = nil; allies[ai].castingFinishAt = 0
                var successful = true
                switch action {
                case "basic", "burst", "dash", "hammer", "seed":
                    var bp = action == "burst" ? 24_000 : action == "hammer" ? 16_000 : action == "dash" ? 16_000 : action == "seed" ? 2_500 : 10_000
                    let poisonBurstBonus = action == "burst" && actor.effectIDs.contains("POISON_SHATTER") && actor.effectIDs.contains("POISON_BURST_25_AT_5") && foes[ei].poison >= 5
                    if poisonBurstBonus { bp += 2_500 }
                    if action == "hammer", effectsHas(orderedParty, id: "C_SMITH", effect: "SMITH_PRESSURE"), pressure > 0 {
                        bp += 2_000 * pressure; pressure = 0
                    }
                    if action == "dash", foes[ei].markExpiry > now || foes[ei].poison > 0 { bp += 4_000 }
                    if action == "dash", actor.effectIDs.contains("FAMILIAR_DASH_BONUS_6000BP"), (foes[ei].markExpiry > now || foes[ei].poison > 0) { bp += 6_000 }
                    let bonus = action != "basic" && allies[ai].echoCharges > 0 && allies[ai].echoExpiry > now ? allies[ai].echoBonusBP : 0
                    if bonus > 0 { allies[ai].echoCharges = 0; emit(now, "echo_consume", actor.id, actor.id, bonus, root) }
                    let legacyCritBP = actor.id == "C_FAMILIAR" ? 1_000 : 500
                    let outgoingBP = allies[ai].weakenedUntil > now ? 8_500 : 10_000
                    let critAllowed = action == "basic" || action == "burst" || action == "dash" || action == "hammer"
                    let sourceStats = actor.r6SourceStats
                    let latentStats = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004 : nil
                    let actualCritBP = sourceStats?.critChanceBP ?? latentStats?.critChanceBP ?? legacyCritBP
                    let crit: Bool
                    if critAllowed {
                        crit = try roll(&randomState, 10_000, domain: "crit.\(actor.id)", index: root) < actualCritBP
                    } else {
                        crit = false
                    }
                    var damage: Int
                    if sourceProfileSeed != nil {
                        var factors = [outgoingBP, bp]
                        if sourceStats != nil {
                            var totalDirect = sourceStats!.directBonusBP
                            if actor.id == "C_WITCH", foes[ei].markExpiry > now { totalDirect += 800 }
                            if bonus > 0 { totalDirect += bonus }
                            if action == "chase" { totalDirect += sourceStats!.chaseBonusBP }
                            factors.append(10_000 + totalDirect)
                        } else if bonus > 0 { factors.append(10_000 + bonus) }
                        var divisors = [10_000, 10_000]
                        if sourceStats != nil || bonus > 0 { divisors.append(10_000) }
                        if crit { factors.append(sourceStats?.critMultiplierBP ?? 15_000); divisors.append(10_000) }
                        if foes[ei].markExpiry > now { factors.append(10_600); divisors.append(10_000) }
                        damage = try R6CanonicalProfile.multiplyDivideFloor(base: actor.attack, numeratorFactors: factors, denominatorFactors: divisors)
                        damage = try R6CanonicalProfile.incomingDamage(.init(power: damage, coefficientBP: 10_000, defense: enemies[ei].defense, attackerLevel: actor.level ?? 1))
                    } else if let latentStats,
                              latentStats.directBonusBP > 0 || actualCritBP != legacyCritBP || latentStats.critMultiplierBP != 15_000 {
                        // R004 normal-campaign candidate math: direct bonus and
                        // crit are folded into the raw hit before target defense.
                        var numerator = [outgoingBP, 10_000 + bonus, bp, 10_000 + latentStats.directBonusBP]
                        var denominator = [10_000, 10_000, 10_000, 10_000]
                        if crit { numerator.append(latentStats.critMultiplierBP); denominator.append(10_000) }
                        if foes[ei].markExpiry > now { numerator.append(10_600); denominator.append(10_000) }
                        let raw = try R6CanonicalProfile.multiplyDivideFloor(base: actor.attack,
                                                                             numeratorFactors: numerator,
                                                                             denominatorFactors: denominator)
                        damage = max(1, raw - enemies[ei].defense)
                    } else {
                        damage = actor.attack * outgoingBP / 10_000 * (10_000 + bonus) / 10_000 * bp / 10_000
                        if crit { damage = damage * 15_000 / 10_000 }
                        if foes[ei].markExpiry > now { damage = damage * 10_600 / 10_000 }
                        damage = max(1, damage - enemies[ei].defense)
                    }
                    damage = min(foes[ei].hp, max(1, damage))
                    if sourceProfileSeed == nil, (enemies[ei].actionPattern == "mirrorCycle" || enemies[ei].actionPattern == "heatCycle" || enemies[ei].actionPattern == "pruningCycle" || enemies[ei].actionPattern == "cliffCharge"), foes[ei].openingUntil > now {
                        damage = min(foes[ei].hp, damage * 12_000 / 10_000)
                    }
                    let isPincerShell = enemies[ei].id == "E_R03_01"
                    let directionalPincerBlock = isPincerShell
                        && (actor.candidateAttackSide ?? .front) == .front
                        && now % 10_000 < 6_000
                    let genericArmorWindow = !isPincerShell
                        && (enemies[ei].actionPattern == "armor" || challengeID == "CH_R02_02")
                        && now % 10_000 < 6_000
                    let candidateArmorActive = sourceProfileSeed == nil
                        && (directionalPincerBlock || genericArmorWindow
                            || enemies[ei].actionPattern == "shellHeavy" && foes[ei].armorUntil > now)
                    if candidateArmorActive {
                        let beforeArmor = damage
                        damage = max(1, damage / 2)
                        let prevented = beforeArmor - damage
                        if prevented > 0 { emit(now, "enemy_armor", enemies[ei].id, actor.id, prevented, root) }
                    } else if sourceProfileSeed != nil, enemies[ei].actionPattern == "armor", now % 10_000 < 6_000 {
                        // Preserve immutable R6 profile behavior exactly.
                        damage = max(1, damage / 2)
                    }
                    if sourceProfileSeed == nil, (enemies[ei].actionPattern == "guardAlternating" || enemies[ei].actionPattern == "seedGuardUltimate"), foes[ei].guardUntil > now {
                        let reduced = max(1, damage / 2)
                        emit(now, "enemy_guard_absorb", enemies[ei].id, actor.id, damage - reduced, root)
                        damage = reduced
                    }
                    foes[ei].hp = max(0, foes[ei].hp - damage)
                    emit(now, action == "hammer" ? "smith_hammer" : action == "seed" ? "poison_seed" : "direct", actor.id, enemies[ei].id, damage, root)
                    if sourceProfileSeed == nil, (enemies[ei].actionPattern == "reflect" || (enemies[ei].actionPattern == "mirrorCycle" && foes[ei].mirrorUntil > now)), damage > 0 {
                        let reflected = max(1, damage * 3_000 / 10_000)
                        push(now + 500, 2, .reflectProjectile(ei, ai, reflected, root))
                    }
                    if challengeID == "CH_R03_02", foes[ei].hp > 0, foes[ei].phase == 1, foes[ei].hp * 2 <= enemies[ei].maxHP {
                        foes[ei].phase = 2; emit(now, "enemy_phase_shift", enemies[ei].id, "phase_2", 2, root)
                    }
                    if challengeID == "CH_R03_03", let cast = foes[ei].telegraphs.first(where: { $0.value.hits.first.map { $0 > now } ?? false }) {
                        foes[ei].telegraphs.removeValue(forKey: cast.key)
                        emit(now, "cast_interrupt", actor.id, enemies[ei].id, 1, cast.key)
                    }
                    if poisonBurstBonus { emit(now, "poison_burst", actor.id, enemies[ei].id, damage, root) }
                    if action == "seed" {
                        let cap = actor.effectIDs.contains("POISON_STACK_CAP_2") ? 7 : 5
                        if foes[ei].poison == 0 { foes[ei].poisonNext = now + 1_000; push(now + 1_000, 0, .poisonTick(ei)) }
                        foes[ei].poison = min(cap, foes[ei].poison + 2); foes[ei].poisonPower = actor.attack; foes[ei].poisonExpiry = now + 9_000
                        push(foes[ei].poisonExpiry, 1, .expirePoison(ei)); emit(now, "poison_stack", actor.id, enemies[ei].id, foes[ei].poison, root)
                    } else if action == "hammer" { foes[ei].weakenExpiry = now + 6_000; emit(now, "enemy_weaken", actor.id, enemies[ei].id, 1_200, root) }
                    else if action == "dash" { /* direct skill only */ }
                    if action != "basic", (sourceProfileSeed != nil || (action != "seed" && action != "hammer")), damage > 0,
                       actor.id != "C_FAMILIAR", orderedParty.indices.contains(where: { orderedParty[$0].id == "C_FAMILIAR" && orderedParty[$0].effectIDs.contains("FAMILIAR_CHASE") }),
                       (foes[ei].markExpiry > now || foes[ei].poison > 0) {
                        if let ci = orderedParty.firstIndex(where: { $0.id == "C_FAMILIAR" }), allies[ci].chaseAt <= now, allies[ci].chaseRoots.insert(root).inserted {
                            allies[ci].chaseAt = now + familiarChaseCooldownMs(effectIDs: orderedParty[ci].effectIDs,
                                                                               sourceProfile: sourceProfileSeed != nil)
                            push(now, 3, .reaction("C_FAMILIAR", ei, root, "chase"))
                        }
                    }
                case "mark":
                    let duration = actor.effectIDs.contains("FAMILIAR_MARK_10S") ? 10_000 : 8_000
                    foes[ei].markExpiry = now + duration; push(now + duration, 1, .expireMark(ei)); emit(now, "mark", actor.id, enemies[ei].id, duration, root)
                case "heal":
                    let t = allies.indices.contains(target) ? target : ai
                    let nominalHeal: Int
                    if sourceProfileSeed != nil, let stats = actor.r6SourceStats {
                        nominalHeal = try R6CanonicalProfile.multiplyDivideFloor(base: actor.attack,
                                                                                  numeratorFactors: [22_000, 10_000 + stats.healBonusBP],
                                                                                  denominatorFactors: [10_000, 10_000])
                    } else {
                        nominalHeal = actor.attack * 22_000 / 10_000
                    }
                    let candidateHeal = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004 : nil
                    let candidateNominal = try candidateHeal.map {
                        try Self.checkedScaleBP(nominalHeal, 10_000 + $0.healBonusBP)
                    } ?? nominalHeal
                    let amount = min(orderedParty[t].maxHP - allies[t].hp, candidateNominal)
                    allies[t].hp += amount; successful = amount > 0; emit(now, "heal", actor.id, orderedParty[t].id, amount, root)
                    if successful, actor.effectIDs.contains("HEAL_TO_BARRIER") {
                        let baseBarrier = amount * 2_000 / 10_000
                        let barrier = try candidateHeal.map {
                            try Self.checkedScaleBP(baseBarrier, 10_000 + $0.barrierBonusBP)
                        } ?? baseBarrier
                        if barrier > 0 { allies[t].shields.append((barrier, now + 6_000, "heal:\(actor.id)")); emit(now, "heal_barrier", actor.id, orderedParty[t].id, barrier, root) }
                    }
                    if successful, actor.effectIDs.contains("HEAL_LINK"), let targetEnemy = livingEnemy() {
                        let followup = max(1, orderedParty[t].attack / 5 - enemies[targetEnemy].defense)
                        foes[targetEnemy].hp = max(0, foes[targetEnemy].hp - followup); emit(now, "heal_followup", orderedParty[t].id, enemies[targetEnemy].id, followup, root)
                    }
                    if successful, amount * 20 >= orderedParty[t].maxHP, allies[ai].echoReadyAt <= now {
                        let candidates = allies.indices.filter { $0 != ai && allies[$0].hp > 0 }
                        let witch = actorOrder.firstIndex(of: "C_WITCH").flatMap { candidates.contains($0) ? $0 : nil }
                        if let receiver = witch ?? candidates.max(by: { orderedParty[$0].attack < orderedParty[$1].attack }) {
                            allies[receiver].echoExpiry = now + 8_000; allies[receiver].echoCharges = 1
                            allies[receiver].echoBonusBP = actor.effectIDs.contains("ECHO_BONUS_2000BP") ? 2_000 : 1_500
                            allies[ai].echoReadyAt = now + 6_000
                            emit(now, "echo_grant", actor.id, orderedParty[receiver].id, allies[receiver].echoBonusBP, root)
                        }
                    }
                case "ward":
                    let t = allies.indices.contains(target) ? target : ai
                    let baseNominal = max(0, actor.attack * (actor.id == "C_WITCH" ? 20_000 : 15_000) / 10_000)
                    let barrierStats = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004 : nil
                    let nominal = try barrierStats.map {
                        try Self.checkedScaleBP(baseNominal, 10_000 + $0.barrierBonusBP)
                    } ?? baseNominal
                    let existing = allies[t].shields.filter { $0.expiry > now }.reduce(0) { $0 + $1.amount }
                    let shield = min(nominal, max(0, orderedParty[t].maxHP * 35 / 100 - existing))
                    allies[t].shields.append((shield, now + 6_000, actor.id)); successful = shield > 0
                    emit(now, "barrier", actor.id, orderedParty[t].id, shield, root)
                case "guard":
                    allies[ai].guardUntil = now + 4_000; allies[ai].coverCharges = 2; emit(now, "cover_stance", actor.id, actor.id, 2, root)
                    if actor.id == "C_SMITH", actor.effectIDs.contains("SMITH_COVER_BARRIER"),
                       allies[ai].smithCoverBarrierReadyAt <= now {
                        let baseBarrier = max(0, actor.attack * 4_000 / 10_000)
                        let coverStats = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004 : nil
                        let barrier = try coverStats.map {
                            try Self.checkedScaleBP(baseBarrier, 10_000 + $0.barrierBonusBP)
                        } ?? baseBarrier
                        if barrier > 0 {
                            allies[ai].shields.append((barrier, now + 4_000, actor.id))
                            emit(now, "smith_cover_barrier", actor.id, actor.id, barrier, root)
                            allies[ai].smithCoverBarrierReadyAt = now + 3_000
                        }
                    }
                default: break
                }
                if action != "basic", successful {
                    let baseCooldown = cooldowns[action] ?? 0
                    let candidateCDR = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004?.cooldownReductionBP ?? 0 : 0
                    let cooldown = candidateCDR > 0
                        ? max(1_000, try Self.ceilScale(baseCooldown, numerator: 10_000 - min(2_500, candidateCDR), denominator: 10_000))
                        : baseCooldown
                    allies[ai].ready[action] = now + cooldown
                }
                if action == "basic" { allies[ai].basicAt = now + (candidateIntervals[actor.id] ?? 1_800) - 250 }
                allies[ai].busyUntil = now + (recoveries[action] ?? 250); push(allies[ai].busyUntil, 4, .decide(ai))
                if sourceProfileSeed != nil {
                    for other in allies.indices { push(now, 4, .decide(other)) }
                }

            case .enemyTell(let ei, let count):
                guard foes[ei].hp > 0 else { continue }
                let enemy = enemies[ei]; foes[ei].actionCount = count + 1
                if enemy.actionPattern == "stationary" { continue }
                let candidateRootIndex: Int
                if sourceProfileSeed == nil && (enemy.actionPattern == "rootChargeCycle" || enemy.actionPattern == "cliffCharge") {
                    candidateRootIndex = count / 3 + 1
                } else if sourceProfileSeed == nil && enemy.actionPattern == "shellHeavy" {
                    candidateRootIndex = count / 2 + 1
                } else {
                    candidateRootIndex = count + 1
                }
                let candidateRoot = "enemy:\(enemy.id):\(candidateRootIndex)"
                if sourceProfileSeed == nil, enemy.actionPattern == "rootChargeCycle", count % 3 == 0 {
                    emit(now, "enemy_scrape", enemy.id, enemy.id, 800, candidateRoot)
                    push(now + 800, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "rootChargeCycle", count % 3 == 2 {
                    emit(now, "enemy_exhausted", enemy.id, enemy.id, 2_800, candidateRoot)
                    push(now + 2_800, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "cliffCharge", count % 3 == 0 {
                    emit(now, "enemy_wind_gather", enemy.id, enemy.id, 1_100, candidateRoot)
                    push(now + 1_100, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "cliffCharge", count % 3 == 2 {
                    foes[ei].openingUntil = now + 3_500
                    emit(now, "enemy_cliff_opening", enemy.id, enemy.id, 3_500, candidateRoot)
                    push(now + 3_500, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "shellHeavy", count % 2 == 0 {
                    foes[ei].armorUntil = now + 5_000
                    emit(now, "enemy_shell_close", enemy.id, enemy.id, 5_000, candidateRoot)
                    push(now + 1_800, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "iceBreathCycle", count % 3 == 0 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    for ai in allies.indices where allies[ai].hp > 0 {
                        allies[ai].slowUntil = max(allies[ai].slowUntil, now + 1_800)
                        emit(now, "party_frost_slow", enemy.id, orderedParty[ai].id, 1_800, root)
                    }
                    emit(now, "enemy_cold_wave", enemy.id, "party", 1_800, root)
                    push(now + 1_800, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "iceBreathCycle", count % 3 == 1 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    emit(now, "enemy_breath_inhale", enemy.id, enemy.id, 1_200, root)
                    push(now + 1_200, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "pruningCycle", count % 3 == 1 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    foes[ei].openingUntil = now + 3_000
                    emit(now, "enemy_ring_opening", enemy.id, enemy.id, 3_000, root)
                    push(now + 2_000, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "seedGuardUltimate", count % 3 == 0 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    for ai in allies.indices where allies[ai].hp > 0 {
                        allies[ai].dotStacks = max(allies[ai].dotStacks, 3)
                        allies[ai].dotNext = now + 1_000
                        push(now + 1_000, 0, .allyDot(ai, root))
                        emit(now, "dot_applied", enemy.id, orderedParty[ai].id, 3, root)
                    }
                    emit(now, "enemy_seed_pressure", enemy.id, "party", 3, root)
                    push(now + 3_000, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "seedGuardUltimate", count % 3 == 1 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    foes[ei].guardUntil = now + 2_500
                    emit(now, "enemy_guard_stance", enemy.id, enemy.id, 2_500, root)
                    push(now + 2_500, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "heatCycle", count % 3 == 0 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    foes[ei].openingUntil = now + 3_500
                    emit(now, "enemy_vent", enemy.id, enemy.id, 3_500, root)
                    push(now + 3_500, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "heatCycle", count % 3 == 1 {
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    foes[ei].heatStored = true
                    emit(now, "enemy_heat_store", enemy.id, enemy.id, 1_500, root)
                    push(now + 1_500, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "mirrorCycle", count % 2 == 0 {
                    foes[ei].mirrorUntil = now + 2_500
                    let root = "enemy:\(enemy.id):\(count + 1)"
                    emit(now, "enemy_reflect_stance", enemy.id, enemy.id, 2_500, root)
                    push(now + 2_500, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                if sourceProfileSeed == nil, enemy.actionPattern == "guardAlternating", count % 2 == 0 {
                    foes[ei].guardUntil = now + 2_500
                    emit(now, "enemy_guard_stance", enemy.id, enemy.id, 2_500, "enemy:\(enemy.id):\(count + 1)")
                    push(now + 2_500, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                let authored = enemy.enemyActions.flatMap { $0.isEmpty ? nil : $0[count % $0.count] }
                let root = sourceProfileSeed == nil ? candidateRoot : "enemy:\(count)"
                if sourceProfileSeed == nil, (enemy.actionPattern == "magicSupport" || enemy.actionPattern == "lightTransfer") {
                    let allyIndex = foes.indices.first(where: { $0 != ei && abs($0 - ei) == 1 && foes[$0].hp > 0 })
                    let targetIndex: Int?
                    if enemy.actionPattern == "magicSupport" {
                        targetIndex = allyIndex ?? ei // Single-enemy encounters use a self-buff fallback.
                    } else {
                        targetIndex = allyIndex
                    }
                    if let targetIndex {
                        let eventKind = enemy.actionPattern == "magicSupport" ? "enemy_magic_support" : "enemy_light_transfer"
                        emit(now, "enemy_telegraph", enemy.id, enemies[targetIndex].id, 1, root)
                        push(now + 1_000, 2, .enemySupport(ei, targetIndex, root, eventKind))
                        for ai in allies.indices { push(now, 4, .decide(ai)) }
                        continue
                    }
                    // A lone light-transfer unit has nobody adjacent to receive energy;
                    // it falls back to its ordinary single strike instead of looping forever.
                }
                if challengeID == "CH_R03_02", foes[ei].phase == 1 { emit(now, "phase_heat", enemy.id, "phase_1", min(3, count + 1), root) }
                if challengeID == "CH_R04_02", count % 3 == 2 { foes[ei].buffUntil = now + 5_000; emit(now, "enemy_buff", enemy.id, enemy.id, 2_000, root) }
                let isAOE: Bool
                if challengeID == "CH_R04_03" { isAOE = count % 2 == 1 }
                else if challengeID == "CH_R05_03" { isAOE = count % 4 == 2 }
                else if challengeID == "CH_R01_03" { isAOE = false }
                else if enemy.actionPattern == "rootBranchCycle" { isAOE = count % 2 == 1 }
                else if challengeID == "CH_R03_02", foes[ei].phase == 2 { isAOE = count % 2 == 1 }
                else {
                    let bossPatternAOE = sourceProfileSeed == nil &&
                        (enemy.actionPattern == "heatCycle" || enemy.actionPattern == "iceBreathCycle" || enemy.actionPattern == "pruningCycle" || enemy.actionPattern == "seedGuardUltimate") && count % 3 == 2
                    isAOE = authored?.aoe ?? (enemy.actionPattern == "aoe" || enemy.actionPattern == "drowse" || enemy.actionPattern == "sporeRest" ||
                        (enemy.actionPattern == "mirrorCycle" && count % 2 == 1) || bossPatternAOE || (enemy.actionPattern == "combined" && count % 2 == 1))
                }
                let isCandidate = sourceProfileSeed == nil
                let frontRowAction = isCandidate && !isAOE && (
                    enemy.id == "E_R01_01"
                    || (enemy.actionPattern == "rootChargeCycle" && count % 3 == 1)
                )
                var target: Int? = nil
                if !isAOE {
                    let livingIndices = allies.indices.filter { allies[$0].hp > 0 }
                    let frontIndices = livingIndices.filter { candidateFrontRowIDs.contains(orderedParty[$0].id) }
                    let selectedIndices = frontRowAction && !frontIndices.isEmpty ? frontIndices : livingIndices
                    let weights = selectedIndices.map { index -> (Int, Int) in
                        let id = orderedParty[index].id
                        return (index, id == "C_SMITH" ? 60 : id == "C_WITCH" ? 15 : id == "C_APPRENTICE" ? 10 : 15)
                    }
                    let total = weights.reduce(0) { $0 + $1.1 }
                    var pick = try rollInt(&randomState, total, domain: "enemy-target", index: count)
                    for (index, weight) in weights {
                        if pick < weight { target = index; break }
                        pick -= weight
                    }
                }
                let rootBranchCycle = isCandidate && enemy.actionPattern == "rootBranchCycle"
                if isCandidate, enemy.actionPattern == "magnetMarkStrike" {
                    guard let params = candidateMagnetParameters, let target else {
                        throw CoreError.invalidCommand("magnet candidate requires a living locked target")
                    }
                    let markDeadline = now.addingReportingOverflow(params.markWindowMs)
                    let strikeDeadline = markDeadline.partialValue.addingReportingOverflow(params.strikeWindupMs)
                    let recoveryDeadline = strikeDeadline.partialValue.addingReportingOverflow(1_500)
                    guard !markDeadline.overflow, !strikeDeadline.overflow, !recoveryDeadline.overflow else {
                        throw CoreError.invalidCommand("magnet candidate deadline overflow")
                    }
                    let strikeAt = strikeDeadline.partialValue
                    foes[ei].telegraphs[root] = (target, [strikeAt], 0, "magnetMarkStrike", nil)
                    emit(now, "enemy_magnet_mark", enemy.id, orderedParty[target].id, params.markWindowMs, root)
                    push(markDeadline.partialValue, 1, .magnetStrikeStart(ei, root))
                    push(strikeAt, 2, .enemyHit(ei, root, 0, count))
                    push(recoveryDeadline.partialValue, 2, .enemyTell(ei, count + 1))
                    for ai in allies.indices { push(now, 4, .decide(ai)) }
                    continue
                }
                let useMultiHit = challengeID == "CH_R01_03" || challengeID == "CH_R03_01" ? count % 2 == 0 : challengeID == "CH_R05_03" ? count % 4 == 0 : enemy.actionPattern == "multiHit" || enemy.actionPattern == "multiHitRest" || (rootBranchCycle && isCandidate && count % 2 == 0) || (isCandidate && enemy.actionPattern == "hammerCombo" && count % 2 == 0) || (isCandidate && enemy.actionPattern == "pruningCycle" && count % 3 == 0)
                let legacyHeavyAlias = !isCandidate && (enemy.actionPattern == "rootChargeCycle" || enemy.actionPattern == "cliffCharge" || enemy.actionPattern == "shellHeavy")
                let useHeavy = challengeID == "CH_R01_01" || challengeID == "CH_R05_01" ? true : challengeID == "CH_R01_03" ? count % 2 == 1 : challengeID == "CH_R04_01" ? count % 2 == 0 : challengeID == "CH_R03_02" && foes[ei].phase == 2 ? count % 2 == 0 : challengeID == "CH_R03_01" ? count % 2 == 1 : enemy.actionPattern == "heavy" || enemy.actionPattern == "frontRowCharge" || legacyHeavyAlias || (isCandidate && enemy.actionPattern == "shellHeavy") || (isCandidate && enemy.actionPattern == "rootChargeCycle" && count % 3 == 1) || (isCandidate && enemy.actionPattern == "cliffCharge" && count % 3 == 1) || (rootBranchCycle && count % 2 == 1) || (isCandidate && enemy.actionPattern == "alternating" && count % 2 == 1) || (isCandidate && enemy.actionPattern == "hammerCombo" && count % 2 == 1) || (isCandidate && (enemy.actionPattern == "heatCycle" || enemy.actionPattern == "iceBreathCycle" || enemy.actionPattern == "seedGuardUltimate") && count % 3 == 2)
                let offsets = authored?.hitOffsetsMs ?? (enemy.actionPattern == "multiHitRest" ? [0, 350, 700] : rootBranchCycle && count % 2 == 0 ? [0, 350, 700] : useMultiHit ? [0, 400, 800] : [0])
                let windup = authored?.windupMs ?? (isCandidate && enemy.actionPattern == "cliffCharge" && count % 3 == 1 ? 1_800 : isCandidate && rootBranchCycle && count % 2 == 1 ? 2_200 : isCandidate && enemy.actionPattern == "rootChargeCycle" && count % 3 == 1 ? 1_700 : isCandidate && enemy.actionPattern == "shellHeavy" ? 2_500 : useHeavy ? (challengeID == "CH_R05_01" ? 1_800 : challengeID == "CH_R03_02" && foes[ei].phase == 2 ? 800 : enemy.actionPattern == "iceBreathCycle" ? 2_500 : enemy.actionPattern == "seedGuardUltimate" ? 2_800 : 2_000) : enemy.actionPattern == "sporeRest" ? 1_800 : 1_000)
                let actionPattern = authored?.heavy == true || useHeavy ? "heavy" : isAOE ? "aoe" : useMultiHit ? "multiHit" : enemy.actionPattern
                if challengeID == "CH_R05_03", useMultiHit || isAOE { emit(now, "challenge_combo", enemy.id, useMultiHit ? "multi_hit" : "aoe", count + 1, root) }
                guard !offsets.isEmpty, offsets.allSatisfy({ $0 >= 0 }) else { throw CoreError.invalidCommand("authored enemy action has invalid hit offsets") }
                let hitTimes = offsets.map { now + windup + $0 }
                foes[ei].telegraphs[root] = (target, hitTimes, 0, actionPattern, authored)
                let telegraphKind = rootBranchCycle && count % 2 == 1 ? "telegraph_aoe" : authored?.heavy == true || useHeavy ? "telegraph_heavy" : isAOE ? "telegraph_aoe" : "enemy_telegraph"
                emit(now, telegraphKind, enemy.id, target.map { orderedParty[$0].id } ?? "party", hitTimes.count, root)
                for (hi, hitAt) in hitTimes.enumerated() { push(hitAt, 2, .enemyHit(ei, root, hi, count)) }
                let recovery = authored.map { $0.recoveryMs + $0.restMs } ?? (isCandidate && rootBranchCycle ? (count % 2 == 0 ? 2_500 : 2_800) : isCandidate && enemy.actionPattern == "rootChargeCycle" ? 400 : isCandidate && enemy.actionPattern == "cliffCharge" ? 500 : isCandidate && enemy.actionPattern == "allyFollowup" ? 2_000 : isCandidate && enemy.actionPattern == "shellHeavy" ? 2_500 : isCandidate && enemy.actionPattern == "hammerCombo" ? (count % 2 == 0 ? 500 : 3_500) : isCandidate && enemy.actionPattern == "heatCycle" ? 3_500 : isCandidate && enemy.actionPattern == "pruningCycle" ? (count % 3 == 0 ? 700 : 3_000) : isCandidate && enemy.actionPattern == "seedGuardUltimate" ? 4_000 : isCandidate && enemy.actionPattern == "iceBreathCycle" ? 2_500 : enemy.actionPattern == "multiHitRest" ? 3_300 : enemy.actionPattern == "sporeRest" || enemy.actionPattern == "mirrorCycle" ? 3_500 : challengeID == "CH_R01_01" ? 4_500 : challengeID == "CH_R05_01" ? 2_500 : 1_500)
                if challengeID == "CH_R03_03" { emit(now, "enemy_cast_start", enemy.id, root, windup, root) }
                push(hitTimes.last! + recovery, 2, .enemyTell(ei, count + 1))
                for ai in allies.indices { push(now, 4, .decide(ai)) }

            case .magnetStrikeStart(let ei, let root):
                guard foes[ei].hp > 0, let tele = foes[ei].telegraphs[root],
                      let target = tele.target, tele.pattern == "magnetMarkStrike",
                      tele.hits.first.map({ $0 > now }) == true else { continue }
                guard allies.indices.contains(target), allies[target].hp > 0 else {
                    foes[ei].telegraphs.removeValue(forKey: root)
                    emit(now, "enemy_magnet_target_lost", enemies[ei].id,
                         target >= 0 && target < orderedParty.count ? orderedParty[target].id : "unknown", 0, root)
                    continue
                }
                emit(now, "telegraph_heavy", enemies[ei].id, orderedParty[target].id, 1, root)

            case .enemyHit(let ei, let root, let hit, let actionCount):
                guard foes[ei].hp > 0, var tele = foes[ei].telegraphs[root], let original = tele.target ?? livingAlly() else { continue }
                if tele.pattern == "magnetMarkStrike", (original < 0 || original >= allies.count || allies[original].hp <= 0) {
                    foes[ei].telegraphs.removeValue(forKey: root)
                    emit(now, "enemy_magnet_target_lost", enemies[ei].id,
                         original >= 0 && original < orderedParty.count ? orderedParty[original].id : "unknown", 0, root)
                    continue
                }
                var target = tele.target == nil ? -1 : original
                if target >= 0, let smith = orderedParty.firstIndex(where: { $0.id == "C_SMITH" }), smith != target,
                   allies[smith].hp > 0, allies[smith].guardUntil > now, allies[smith].hp * 10_000 > orderedParty[smith].maxHP * 3_500 {
                    if allies[smith].coverRoots.contains(root) {
                        target = smith
                    } else if allies[smith].coverCharges > 0 {
                        allies[smith].coverRoots.insert(root); allies[smith].coverCharges -= 1
                        target = smith; emit(now, "cover_redirect", orderedParty[smith].id, orderedParty[original].id, 1, root)
                    }
                }
                let redirected = target >= 0 && target != original
                let targets = target < 0 ? allies.indices.filter { allies[$0].hp > 0 } : [target]
                for ti in targets where allies[ti].hp > 0 {
                    let actor = orderedParty[ti]
                    let guardChance = min(4_500, actor.guardChanceBP + (allies[ti].guardUntil > now ? 1_500 : 0))
                    let guardIndex = "[\"\(root)\",\(hit)]"
                    let guarded = try roll(&randomState, 10_000, domain: "guard.\(actor.id)", index: guardIndex) < guardChance
                    var incoming: Int
                    if let action = tele.action, let attackerLevel = enemies[ei].level, (1...60).contains(attackerLevel) {
                        if sourceProfileSeed != nil {
                            var raw = enemies[ei].attack * action.coefficientBP / 10_000
                            if foes[ei].weakenExpiry > now { raw = raw * 8_800 / 10_000 }
                            incoming = try R6CanonicalProfile.incomingDamage(.init(power: raw, coefficientBP: 10_000,
                                                                                    defense: actor.defense, attackerLevel: attackerLevel,
                                                                                    guarded: guarded, specialReductionBP: redirected ? 1_500 : 0))
                        } else {
                            var raw = enemies[ei].attack * action.coefficientBP / 10_000
                            if foes[ei].supportBuffUntil > now { raw = raw * (10_000 + foes[ei].supportBuffBP) / 10_000 }
                            let k = (100 + 8 * (attackerLevel - 1)) * 10_000
                            let defenseReductionBP = min(7_000, actor.defense * 10_000 / max(1, actor.defense + k))
                            incoming = max(1, raw * (10_000 - defenseReductionBP) / 10_000)
                        }
                    } else {
                        var raw = enemies[ei].attack
                        if sourceProfileSeed == nil, tele.pattern == "magnetMarkStrike",
                           let params = candidateMagnetParameters {
                            raw = try Self.checkedScaleBP(raw, params.strikeCoefficientBP)
                        }
                        if foes[ei].supportBuffUntil > now { raw = raw * (10_000 + foes[ei].supportBuffBP) / 10_000 }
                        incoming = max(1, raw - actor.defense)
                    }
                    if foes[ei].buffUntil > now { incoming = incoming * 12_000 / 10_000 }
                    // Source action coefficients already encode authored AoE damage.
                    // The legacy campaign telegraph synthesizes AoE by halving a single-target hit.
                    if sourceProfileSeed == nil, tele.target == nil { incoming = max(1, incoming / 2) }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "heatCycle", foes[ei].heatStored { incoming = incoming * 30_000 / 10_000 }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "iceBreathCycle", actionCount % 3 == 2 { incoming = incoming * 25_000 / 10_000 }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "seedGuardUltimate", actionCount % 3 == 2 { incoming = incoming * 30_000 / 10_000 }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "hammerCombo", actionCount % 2 == 1 { incoming = incoming * 2 }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "pruningCycle", actionCount % 3 == 2 { incoming = incoming * 3 }
                    if sourceProfileSeed == nil, foes[ei].weakenExpiry > now { incoming = incoming * 8_800 / 10_000 }
                    // The canonical source-profile branch retains its locked input behavior.
                    // Candidate shell/membrane armor only reduces damage dealt TO the enemy;
                    // it does not weaken the enemy's outgoing attack.
                    let sourceProfileArmor = sourceProfileSeed != nil
                        && enemies[ei].actionPattern == "armor" && now % 10_000 < 6_000
                    if sourceProfileArmor { incoming = max(1, incoming / 2); emit(now, "enemy_armor", enemies[ei].id, actor.id, 5_000, root) }
                    if guarded {
                        if sourceProfileSeed == nil { incoming = incoming * 6_500 / 10_000 }
                        emit(now, "guard", enemies[ei].id, actor.id, 3_500, root)
                    }
                    var remaining = incoming, absorbed = 0, ownWardAbsorbed = 0
                    for si in allies[ti].shields.indices where allies[ti].shields[si].expiry > now && remaining > 0 {
                        let take = min(remaining, allies[ti].shields[si].amount)
                        if allies[ti].shields[si].source == "C_WITCH" { ownWardAbsorbed += take }
                        allies[ti].shields[si].amount -= take; remaining -= take; absorbed += take
                    }
                    let hpBeforeHit = allies[ti].hp
                    allies[ti].hp = max(0, hpBeforeHit - remaining)
                    // The canonical source logs effective HP loss, capped at remaining HP.
                    emit(now, "enemy_hit", enemies[ei].id, actor.id, min(hpBeforeHit, remaining), root,
                         diagnostics: tele.pattern == "magnetMarkStrike"
                            ? ["candidateMagnetCoefficientBP": candidateMagnetParameters?.strikeCoefficientBP ?? 0]
                            : nil)
                    if sourceProfileSeed == nil, remaining > 0, !generatedFollowupRoots.contains(root) {
                        for followerIndex in enemies.indices where followerIndex != ei
                            && enemies[followerIndex].actionPattern == "allyFollowup"
                            && foes[followerIndex].hp > 0
                            && foes[followerIndex].followupReadyAt <= now
                            && foes[followerIndex].followupTriggerRoots.insert(root).inserted {
                            let followupRoot = "enemy:\(enemies[followerIndex].id):followup:\(root)"
                            generatedFollowupRoots.insert(followupRoot)
                            foes[followerIndex].followupReadyAt = now + 2_500
                            let followupAt = now + 350
                            foes[followerIndex].telegraphs[followupRoot] = (ti, [followupAt], 0, "followup", nil)
                            emit(now, "enemy_telegraph", enemies[followerIndex].id, actor.id, 1, followupRoot)
                            emit(now, "enemy_followup", enemies[followerIndex].id, actor.id, 1, followupRoot)
                            push(followupAt, 2, .enemyHit(followerIndex, followupRoot, 0, foes[followerIndex].actionCount))
                        }
                    }
                    if (sourceProfileSeed == nil && enemies[ei].actionPattern == "slow") || challengeID == "CH_R01_02", remaining > 0 {
                        let resistance = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004?.debuffDurationResistBP ?? 0 : 0
                        let duration = try Self.candidateDuration(1_500, resistanceBP: resistance)
                        allies[ti].slowUntil = max(allies[ti].slowUntil, now + duration)
                        emit(now, "party_slow", enemies[ei].id, actor.id, duration, root)
                    }
                    if sourceProfileSeed == nil, (enemies[ei].actionPattern == "drowse" || enemies[ei].actionPattern == "sporeRest"), remaining > 0 {
                        let duration = try Self.candidateDuration(2_000, resistanceBP: actor.candidateLatentModifiersR004?.debuffDurationResistBP ?? 0)
                        allies[ti].slowUntil = max(allies[ti].slowUntil, now + duration)
                        emit(now, "party_drowse", enemies[ei].id, actor.id, duration, root)
                    }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "interrupt", remaining > 0,
                       allies[ti].casting, allies[ti].castingRoot != nil {
                        allies[ti].casting = false; allies[ti].castingAction = nil; allies[ti].castingRoot = nil; allies[ti].castingFinishAt = 0
                        allies[ti].busyUntil = max(allies[ti].busyUntil, now + 1_000)
                        push(now + 1_000, 4, .decide(ti))
                        emit(now, "cast_interrupt", enemies[ei].id, actor.id, 1_000, root)
                    }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "castingSlow", remaining > 0 {
                        let duration = try Self.candidateDuration(5_000, resistanceBP: actor.candidateLatentModifiersR004?.debuffDurationResistBP ?? 0)
                        allies[ti].castSlowUntil = max(allies[ti].castSlowUntil, now + duration)
                        if allies[ti].casting, allies[ti].castingFinishAt > now,
                           let action = allies[ti].castingAction, let castRoot = allies[ti].castingRoot {
                            allies[ti].castingFinishAt += 500
                            push(allies[ti].castingFinishAt, 2, .commit(ti, action, 0, castRoot))
                        }
                        emit(now, "party_cast_slow", enemies[ei].id, actor.id, duration, root)
                    }
                    if sourceProfileSeed == nil, enemies[ei].actionPattern == "supportDisrupt", remaining > 0 {
                        var shortened = false
                        for shieldIndex in allies[ti].shields.indices where allies[ti].shields[shieldIndex].expiry > now {
                            allies[ti].shields[shieldIndex].expiry = max(now, allies[ti].shields[shieldIndex].expiry - 1_000)
                            shortened = true
                        }
                        if allies[ti].echoExpiry > now {
                            allies[ti].echoExpiry = max(now, allies[ti].echoExpiry - 1_000)
                            shortened = true
                        }
                        if shortened { emit(now, "support_duration_reduced", enemies[ei].id, actor.id, 1_000, root) }
                    }
                    if challengeID == "CH_R04_02", remaining > 0 {
                        let resistance = sourceProfileSeed == nil ? actor.candidateLatentModifiersR004?.debuffDurationResistBP ?? 0 : 0
                        let duration = try Self.candidateDuration(5_000, resistanceBP: resistance)
                        allies[ti].weakenedUntil = max(allies[ti].weakenedUntil, now + duration)
                        emit(now, "party_weaken", enemies[ei].id, actor.id, duration, root)
                    }
                    if absorbed > 0 { emit(now, "barrier_absorb", enemies[ei].id, actor.id, absorbed, root) }
                    if ownWardAbsorbed > 0, let witch = actorOrder.firstIndex(of: "C_WITCH"),
                       orderedParty[witch].effectIDs.contains("BARRIER_REFLECT"), allies[witch].reflectReadyAt <= now {
                        allies[witch].reflectReadyAt = now + 3_000
                        push(now, 3, .reaction("C_WITCH", ei, "reflect:\(root)", "reflect"))
                    }
                    if (tele.action == nil && (enemies[ei].actionPattern == "dot" || enemies[ei].actionPattern == "regenPoison") ||
                        sourceProfileSeed != nil && tele.action?.id == "candidate_dot"), hit == 0 {
                        allies[ti].dotStacks = max(allies[ti].dotStacks, 3); allies[ti].dotNext = now + 1_000
                        push(now + 1_000, 0, .allyDot(ti, root)); emit(now, "dot_applied", enemies[ei].id, actor.id, 3, root)
                    }
                    if ti == actorOrder.firstIndex(of: "C_SMITH"), (guarded || (target >= 0 && target != original)), remaining + absorbed > 0, allies[ti].hp > 0, allies[ti].counterAt <= now, allies[ti].counterRoots.insert(root).inserted {
                        allies[ti].counterAt = now + 1_500; push(now, 3, .reaction(actor.id, ei, root, "counter"))
                        if actor.effectIDs.contains("SMITH_PRESSURE") { pressure = min(3, pressure + 1); emit(now, "smith_pressure", actor.id, enemies[ei].id, pressure, root) }
                    }
                }
                if sourceProfileSeed != nil {
                    for actorIndex in allies.indices { push(now, 4, .decide(actorIndex)) }
                }
                tele.processed = hit + 1; foes[ei].telegraphs[root] = tele
                if hit == tele.hits.count - 1, enemies[ei].actionPattern == "support",
                   let weakest = foes.indices.filter({ foes[$0].hp > 0 }).min(by: { foes[$0].hp < foes[$1].hp }) {
                    let heal = max(1, enemies[ei].attack / 3); foes[weakest].hp = min(enemies[weakest].maxHP, foes[weakest].hp + heal)
                    emit(now, "enemy_support", enemies[ei].id, enemies[weakest].id, heal, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "regenPoison", foes[ei].hp > 0 {
                    let heal = min(enemies[ei].maxHP - foes[ei].hp, max(1, enemies[ei].maxHP / 100))
                    if heal > 0 { foes[ei].hp += heal; emit(now, "enemy_regen", enemies[ei].id, enemies[ei].id, heal, root) }
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "sporeRest" {
                    emit(now, "enemy_rest", enemies[ei].id, enemies[ei].id, 3_500, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "hammerCombo", actionCount % 2 == 1 {
                    emit(now, "enemy_rest", enemies[ei].id, enemies[ei].id, 3_500, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "mirrorCycle", actionCount % 2 == 1 {
                    foes[ei].openingUntil = now + 3_500
                    emit(now, "enemy_scale_opening", enemies[ei].id, enemies[ei].id, 3_500, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "heatCycle", foes[ei].heatStored {
                    foes[ei].heatStored = false
                    emit(now, "enemy_heat_release", enemies[ei].id, enemies[ei].id, 1, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "iceBreathCycle", actionCount % 3 == 2 {
                    emit(now, "enemy_breath_release", enemies[ei].id, "party", 1, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "seedGuardUltimate", actionCount % 3 == 2 {
                    emit(now, "enemy_ultimate_release", enemies[ei].id, "party", 1, root)
                }
                if sourceProfileSeed == nil, hit == tele.hits.count - 1,
                   enemies[ei].actionPattern == "pruningCycle", actionCount % 3 == 2 {
                    emit(now, "enemy_ring_sweep", enemies[ei].id, "party", 1, root)
                }
                if hit == tele.hits.count - 1, challengeID == "CH_R02_01", let weakest = allies.indices.filter({ allies[$0].hp > 0 }).min(by: { allies[$0].hp < allies[$1].hp }) {
                    let heal = min(orderedParty[weakest].maxHP - allies[weakest].hp, max(1, enemies[ei].attack / 4))
                    allies[weakest].hp += heal; emit(now, "enemy_heal_cycle", enemies[ei].id, orderedParty[weakest].id, heal, root)
                }
                if hit == tele.hits.count - 1, challengeID == "CH_R05_02", let lamp = enemies.firstIndex(where: { $0.id.hasPrefix("LAMP_VESSEL") }), foes[lamp].hp > 0,
                   let guardian = enemies.indices.first(where: { $0 != lamp && foes[$0].hp > 0 }) {
                    let heal = min(enemies[guardian].maxHP - foes[guardian].hp, max(1, enemies[guardian].maxHP / 100))
                    if heal > 0 { foes[guardian].hp += heal; emit(now, "lamp_support", enemies[lamp].id, enemies[guardian].id, heal, root) }
                }

            case .enemySupport(let sourceIndex, let targetIndex, let root, let eventKind):
                guard foes[sourceIndex].hp > 0, foes[targetIndex].hp > 0 else { continue }
                let candidateBuffBP = 1_500
                let candidateDurationMs = 5_000
                foes[targetIndex].supportBuffBP = max(foes[targetIndex].supportBuffBP, candidateBuffBP)
                foes[targetIndex].supportBuffUntil = now + candidateDurationMs
                emit(now, eventKind, enemies[sourceIndex].id, enemies[targetIndex].id, candidateBuffBP, root,
                     diagnostics: ["duration_ms": candidateDurationMs])
                push(now + 2_500, 2, .enemyTell(sourceIndex, foes[sourceIndex].actionCount))

            case .reflectProjectile(let enemyIndex, let actorIndex, let damage, let root):
                guard foes[enemyIndex].hp > 0, allies[actorIndex].hp > 0 else { continue }
                var remaining = max(0, damage)
                var absorbed = 0
                for shieldIndex in allies[actorIndex].shields.indices where allies[actorIndex].shields[shieldIndex].expiry > now && remaining > 0 {
                    let take = min(remaining, max(0, allies[actorIndex].shields[shieldIndex].amount))
                    allies[actorIndex].shields[shieldIndex].amount -= take
                    remaining -= take
                    absorbed += take
                }
                if absorbed > 0 {
                    emit(now, "barrier_absorb", enemies[enemyIndex].id, orderedParty[actorIndex].id, absorbed, root)
                }
                let hpDamage = min(allies[actorIndex].hp, remaining)
                allies[actorIndex].hp -= hpDamage
                emit(now, "enemy_reflect_projectile", enemies[enemyIndex].id, orderedParty[actorIndex].id, hpDamage, root)

            case .poisonTick(let ei):
                guard foes[ei].poisonNext == now, foes[ei].poison > 0, foes[ei].poisonExpiry >= now, foes[ei].hp > 0 else { continue }
                let rawDamage: Int
                if sourceProfileSeed != nil, let witch = orderedParty.first(where: { $0.id == "C_WITCH" }) {
                    rawDamage = try R6CanonicalProfile.multiplyDivideFloor(base: foes[ei].poisonPower,
                                                                            numeratorFactors: [600, foes[ei].poison, 10_000 + (witch.r6SourceStats?.dotBonusBP ?? 0)],
                                                                            denominatorFactors: [10_000, 10_000])
                } else if sourceProfileSeed == nil,
                          let witch = orderedParty.first(where: { $0.id == "C_WITCH" }),
                          let modifiers = witch.candidateLatentModifiersR004, modifiers.dotBonusBP > 0 {
                    rawDamage = try R6CanonicalProfile.multiplyDivideFloor(base: foes[ei].poisonPower,
                                                                            numeratorFactors: [600, foes[ei].poison, 10_000 + modifiers.dotBonusBP],
                                                                            denominatorFactors: [10_000, 10_000])
                } else {
                    rawDamage = max(0, foes[ei].poisonPower * 600 * foes[ei].poison / 10_000)
                }
                let damage = min(foes[ei].hp, rawDamage)
                foes[ei].hp = max(0, foes[ei].hp - damage); emit(now, "poison_tick", "C_WITCH", enemies[ei].id, damage, "poison:\(now)")
                if challengeID == "CH_R03_02", foes[ei].hp > 0, foes[ei].phase == 1, foes[ei].hp * 2 <= enemies[ei].maxHP {
                    foes[ei].phase = 2; emit(now, "enemy_phase_shift", enemies[ei].id, "phase_2", 2, "poison:\(now)")
                }
                foes[ei].poisonNext = now + 1_000; push(now + 1_000, 0, .poisonTick(ei))
            case .allyDot(let ai, let root):
                guard allies[ai].hp > 0, allies[ai].dotStacks > 0, allies[ai].dotNext == now else { continue }
                let baseDamage = max(1, orderedParty[ai].maxHP / 100)
                let resistance = sourceProfileSeed == nil ? orderedParty[ai].candidateLatentModifiersR004?.periodicResistBP ?? 0 : 0
                let reduced = resistance > 0 ? try Self.checkedScaleBP(baseDamage, 10_000 - resistance) : baseDamage
                let damage = min(allies[ai].hp, max(1, reduced))
                allies[ai].hp -= damage; allies[ai].dotStacks -= 1; emit(now, "dot_tick", "enemy", orderedParty[ai].id, damage, root)
                if allies[ai].dotStacks > 0 { allies[ai].dotNext = now + 1_000; push(now + 1_000, 0, .allyDot(ai, root)) }
            case .expireMark(let ei): if foes[ei].markExpiry <= now { foes[ei].markExpiry = 0 }
            case .expirePoison(let ei): if foes[ei].poisonExpiry <= now { foes[ei].poison = 0; foes[ei].poisonNext = nil; emit(now, "poison_expire", "C_WITCH", enemies[ei].id) }
            case .reaction(let actorID, let ei, let root, let kind):
                guard let ai = orderedParty.firstIndex(where: { $0.id == actorID }), allies[ai].hp > 0, foes[ei].hp > 0 else { continue }
                let coef = kind == "counter" ? 7_500 : kind == "reflect" ? 5_000 : 4_000
                let damage: Int
                if sourceProfileSeed != nil, kind == "chase", let stats = orderedParty[ai].r6SourceStats {
                    var factors = [coef, 10_000 + stats.directBonusBP + stats.chaseBonusBP]
                    var divisors = [10_000, 10_000]
                    if foes[ei].markExpiry > now { factors.append(10_600); divisors.append(10_000) }
                    let raw = try R6CanonicalProfile.multiplyDivideFloor(base: orderedParty[ai].attack, numeratorFactors: factors, denominatorFactors: divisors)
                    damage = max(1, min(foes[ei].hp, try R6CanonicalProfile.incomingDamage(.init(power: raw, coefficientBP: 10_000, defense: enemies[ei].defense, attackerLevel: orderedParty[ai].level ?? 1))))
                } else if sourceProfileSeed != nil, kind == "counter" {
                    // The source counter is a direct 75% attack, so active familiar mark applies
                    // its ordinary +6% direct multiplier before target defense.
                    let stats = orderedParty[ai].r6SourceStats
                    var factors = [coef, 10_000 + (stats?.directBonusBP ?? 0)]
                    var divisors = [10_000, 10_000]
                    if foes[ei].markExpiry > now { factors.append(10_600); divisors.append(10_000) }
                    let raw = try R6CanonicalProfile.multiplyDivideFloor(base: orderedParty[ai].attack,
                                                                          numeratorFactors: factors,
                                                                          denominatorFactors: divisors)
                    damage = max(1, min(foes[ei].hp, try R6CanonicalProfile.incomingDamage(.init(power: raw,
                                                                                                    coefficientBP: 10_000,
                                                                                                    defense: enemies[ei].defense,
                                                                                                    attackerLevel: orderedParty[ai].level ?? 1))))
                } else if sourceProfileSeed == nil,
                          let modifiers = orderedParty[ai].candidateLatentModifiersR004,
                          kind == "counter" || kind == "chase" {
                    let specific = kind == "counter" ? modifiers.counterBonusBP : modifiers.chaseBonusBP
                    var numerator = [coef, 10_000 + modifiers.directBonusBP + specific]
                    var denominator = [10_000, 10_000]
                    if foes[ei].markExpiry > now { numerator.append(10_600); denominator.append(10_000) }
                    let raw = try R6CanonicalProfile.multiplyDivideFloor(base: orderedParty[ai].attack,
                                                                          numeratorFactors: numerator,
                                                                          denominatorFactors: denominator)
                    damage = max(1, min(foes[ei].hp, raw - enemies[ei].defense))
                } else {
                    damage = max(1, orderedParty[ai].attack * coef / 10_000 - enemies[ei].defense)
                }
                foes[ei].hp = max(0, foes[ei].hp - damage); emit(now, kind, actorID, enemies[ei].id, damage, root)
            }
            outcome = winCheck()
        }
        let elapsed = min(maxDurationMs, now)
        var presentation = Dictionary(uniqueKeysWithValues: enemies.map { enemy in
            (enemy.id, CombatEntityPresentation(entityID: enemy.id, kind: "enemy", catalogID: enemy.id, label: enemy.id, assetKey: enemy.id))
        })
        for (entityID, mapping) in entityPresentation { presentation[entityID] = mapping }
        for actor in orderedParty where presentation[actor.id] == nil {
            presentation[actor.id] = CombatEntityPresentation(entityID: actor.id, kind: "actor", catalogID: actor.id, label: actor.id, assetKey: actor.id)
        }
        return CombatResult(won: outcome ?? false, ticks: elapsed / 1_000, events: events,
                            remainingPartyHP: Dictionary(uniqueKeysWithValues: orderedParty.indices.map { (orderedParty[$0].id, allies[$0].hp) }),
                            initialPartyHP: Dictionary(uniqueKeysWithValues: orderedParty.map { ($0.id, $0.maxHP) }),
                            initialEnemyHP: Dictionary(uniqueKeysWithValues: enemies.map { ($0.id, $0.maxHP) }),
                            remainingEnemyHP: Dictionary(uniqueKeysWithValues: enemies.indices.map { (enemies[$0].id, foes[$0].hp) }),
                            entityPresentation: presentation)
    }

    private static func effectsHas(_ party: [Combatant], id: String, effect: String) -> Bool {
        party.first(where: { $0.id == id })?.effectIDs.contains(effect) ?? false
    }
}
