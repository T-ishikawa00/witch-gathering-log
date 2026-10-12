import Foundation
import XCTest
@testable import WitchGameCore

final class CandidateLatentSlotPolicyR003Tests: XCTestCase {
    private var policy: CandidateLatentSlotPolicyR003!

    override func setUpWithError() throws {
        policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
    }

    func testCandidateCatalogCoversThirtyThreeTemplatesAndTwentyEvolutionEdges() throws {
        XCTAssertEqual(policy.templateIDs.count, 33)
        XCTAssertEqual(policy.familiarProposedTemplateIDs,
                       ["EQ_F_BODY_01", "EQ_F_HAND_01", "EQ_F_FEET_01", "EQ_F_RING_01"])
        XCTAssertEqual(policy.evolutionEdgePairs.count, 20)
        XCTAssertTrue(policy.evolutionEdgePairs.contains("EQ_W_01->EQ_W_G1"))
        XCTAssertTrue(policy.evolutionEdgePairs.contains("EQ_RING_02->EQ_RING_03"))
    }

    func testAcquisitionEligibilityUsesTemplateCapabilityAndAcquisitionParty() throws {
        let openingParty: Set<String> = ["C_WITCH", "C_FAMILIAR"]
        let witchStaff = try policy.acquisitionEligibleAffixIDs(templateID: "EQ_W_01", joinedActorIDs: openingParty)
        XCTAssertFalse(witchStaff.contains("AF_DOT"), "base-staff branch exclusion must match stored policy row")
        XCTAssertTrue(witchStaff.contains("AF_WARD"))
        XCTAssertFalse(witchStaff.contains("AF_CHASE"), "Familiar capability does not transfer to Witch-only staff")

        let sharedAmulet = try policy.acquisitionEligibleAffixIDs(templateID: "EQ_AMU_01", joinedActorIDs: openingParty)
        XCTAssertTrue(sharedAmulet.contains("AF_CHASE"))
        XCTAssertTrue(sharedAmulet.contains("AF_WARD"))
        XCTAssertFalse(sharedAmulet.contains("AF_HEAL"), "Apprentice is not in acquisition roster")

        let smithOnly = try policy.acquisitionEligibleAffixIDs(templateID: "EQ_S_01", joinedActorIDs: ["C_WITCH", "C_FAMILIAR"])
        XCTAssertFalse(smithOnly.contains("AF_COUNTER"), "Smith is not joined")
        let catItem = try policy.acquisitionEligibleAffixIDs(templateID: "EQ_F_BODY_01", joinedActorIDs: openingParty)
        XCTAssertTrue(catItem.contains("AF_CHASE"))
    }

    func testVersionedPayloadRequiresThreeInRangeRecordsAndUniqueGroups() throws {
        XCTAssertThrowsError(try CandidateLatentSlotsR003(slots: [slot("AF_HP", 1), slot("AF_POWER", 2)])) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .slotCount(2))
        }
        XCTAssertThrowsError(try CandidateLatentSlotsR003(slots: [slot("AF_HP", -1), slot("AF_POWER", 2), slot("AF_DEF", 3)])) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .rawQOutOfRange)
        }
        let duplicate = try CandidateLatentSlotsR003(slots: [slot("AF_POWER", 1), slot("AF_POWER", 999), slot("AF_HP", 2)])
        XCTAssertThrowsError(try policy.validateNewInstanceSlots(templateID: "EQ_W_P1", joinedActorIDs: ["C_WITCH"], slots: duplicate)) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .duplicateGroup("AF_POWER"))
        }
    }

    func testCraftFloorAndQualityActivationValueAreEvaluationOnly() throws {
        let rolls = try CandidateLatentSlotsR003(slots: [slot("AF_POWER", 250), slot("AF_HP", 250), slot("AF_DIRECT", 1000)])
        try policy.validateCraftNewCandidate(templateID: "EQ_W_P1", joinedActorIDs: ["C_WITCH"], slots: rolls)
        XCTAssertThrowsError(try policy.validateCraftNewCandidate(templateID: "EQ_W_P1", joinedActorIDs: ["C_WITCH"],
                                                                  slots: CandidateLatentSlotsR003(slots: [slot("AF_POWER", 249), slot("AF_HP", 250), slot("AF_DIRECT", 1000)]))) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .belowMinimumRawQ(minimum: 250))
        }
        XCTAssertEqual(try policy.activeSlotCount(qualityID: "Q0"), 0)
        XCTAssertEqual(try policy.activeSlotCount(qualityID: "Q1"), 1)
        XCTAssertEqual(try policy.activeSlotCount(qualityID: "Q2"), 2)
        XCTAssertEqual(try policy.activeSlotCount(qualityID: "Q3"), 3)
        XCTAssertEqual(try policy.activeSlotCount(qualityID: "Q4"), 3)
        XCTAssertEqual(try policy.effectiveQ(rawQ: 250, qualityID: "Q2"), 250)
        XCTAssertEqual(try policy.effectiveQ(rawQ: 250, qualityID: "Q4"), 600)
        XCTAssertEqual(try policy.valueBP(rawQ: 250, qualityID: "Q2", minimumBP: 300, maximumBP: 600), 375)
        XCTAssertEqual(try policy.valueBP(rawQ: 250, qualityID: "Q4", minimumBP: 300, maximumBP: 600), 480)
        XCTAssertEqual(rolls.slots.map(\.rawQ), [250, 250, 1000], "evaluation must not mutate stored q")
    }

    func testEveryCandidateEvolutionEdgePreservesCompatibleThreeSlots() throws {
        let safeSlots = try CandidateLatentSlotsR003(slots: [slot("AF_HP", 0), slot("AF_POWER", 500), slot("AF_DEF", 1000)])
        let safeEnvelope = CandidateLatentItemEnvelopeR003(latentEffectID: nil, candidateLatentSlots: safeSlots)
        for pair in policy.evolutionEdgePairs {
            let parts = pair.components(separatedBy: "->")
            XCTAssertEqual(parts.count, 2)
            XCTAssertEqual(try policy.validateEvolution(from: parts[0], to: parts[1], legacyEnvelope: safeEnvelope), .candidateSlotsChecked, pair)
        }
    }

    func testWardBranchRejectsPoisonSlotButPoisonBranchPreservesIt() throws {
        let poisonSlots = try CandidateLatentSlotsR003(slots: [slot("AF_DOT", 700), slot("AF_HP", 300), slot("AF_POWER", 800)])
        let item = CandidateLatentItemEnvelopeR003(latentEffectID: nil, candidateLatentSlots: poisonSlots)
        let beforeRejectedEvolution = item
        XCTAssertEqual(try policy.validateEvolution(from: "EQ_W_P1", to: "EQ_W_P2", legacyEnvelope: item), .candidateSlotsChecked)
        XCTAssertThrowsError(try policy.validateEvolution(from: "EQ_W_01", to: "EQ_W_G1", legacyEnvelope: item)) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .incompatibleEvolution("AF_DOT"))
        }
        XCTAssertEqual(item, beforeRejectedEvolution, "pure rejection must not mutate caller-owned instance data")
    }

    func testLegacyMissingOrSingularLatentRemainsUnknownAndUnmapped() throws {
        let absent = try JSONDecoder().decode(CandidateLatentItemEnvelopeR003.self,
                                             from: Data(#"{"definitionID":"EQ_W_01"}"#.utf8))
        XCTAssertTrue(absent.isLegacyUnknown)
        XCTAssertNil(absent.latentEffectID)
        XCTAssertEqual(try policy.validateEvolution(from: "EQ_W_01", to: "EQ_W_G1", legacyEnvelope: absent), .legacyUnknownPreserved)

        let singular = try JSONDecoder().decode(CandidateLatentItemEnvelopeR003.self,
                                                from: Data(#"{"latentEffectID":"LATENT_TEST_01"}"#.utf8))
        XCTAssertTrue(singular.isLegacyUnknown)
        XCTAssertEqual(singular.latentEffectID, "LATENT_TEST_01")
        let roundTrip = try JSONDecoder().decode(CandidateLatentItemEnvelopeR003.self, from: JSONEncoder().encode(singular))
        XCTAssertEqual(roundTrip.latentEffectID, "LATENT_TEST_01")
        XCTAssertNil(roundTrip.candidateLatentSlots)
    }

    func testUnknownVersionAndUnknownEdgeRejectWithoutChangingInputValues() throws {
        XCTAssertThrowsError(try CandidateLatentSlotsR003(version: 2, slots: [slot("AF_HP", 1), slot("AF_POWER", 2), slot("AF_DEF", 3)])) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .unsupportedVersion(2))
        }
        let invalidVersionJSON = Data(#"{"version":2,"slots":[{"affixID":"AF_HP","rawQ":1},{"affixID":"AF_POWER","rawQ":2},{"affixID":"AF_DEF","rawQ":3}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CandidateLatentSlotsR003.self, from: invalidVersionJSON))
        let slots = try CandidateLatentSlotsR003(slots: [slot("AF_HP", 1), slot("AF_POWER", 2), slot("AF_DEF", 3)])
        let before = slots
        XCTAssertThrowsError(try policy.validateEvolution(from: "EQ_W_G2", to: "EQ_W_P1", legacyEnvelope: CandidateLatentItemEnvelopeR003(candidateLatentSlots: slots)))
        XCTAssertEqual(slots, before)
    }

    func testR2SixteenNumericDefinitionsAndCapTargetsMatchPinnedAffixContract() throws {
        let expected: [String: (String, Int, Int, String, Int)] = [
            "AF_HP": ("hp_pct", 300, 600, "hp_pct", 10000),
            "AF_POWER": ("power_pct", 300, 600, "power_pct", 8000),
            "AF_DEF": ("defense_pct", 400, 800, "defense_pct", 10000),
            "AF_CRIT": ("crit_chance_bp", 200, 400, "crit_chance_bp", 6000),
            "AF_CRIT_DMG": ("crit_damage_extra_bp", 500, 1000, "crit_multiplier_bp", 22500),
            "AF_HASTE": ("haste_bp", 200, 500, "haste_bp", 5000),
            "AF_CDR": ("cdr_bp", 100, 300, "cdr_bp", 2500),
            "AF_DIRECT": ("direct_bonus_bp", 400, 800, "direct_bonus_bp", 6000),
            "AF_DOT": ("dot_bonus_bp", 500, 1000, "dot_bonus_bp", 10000),
            "AF_HEAL": ("heal_bonus_bp", 500, 1000, "heal_bonus_bp", 10000),
            "AF_WARD": ("barrier_bonus_bp", 500, 1000, "barrier_bonus_bp", 10000),
            "AF_GUARD": ("guard_chance_bp", 200, 400, "guard_chance_bp", 4500),
            "AF_COUNTER": ("counter_bonus_bp", 500, 1000, "counter_bonus_bp", 10000),
            "AF_CHASE": ("chase_bonus_bp", 500, 1000, "chase_bonus_bp", 10000),
            "AF_STATUS_RESIST": ("debuff_duration_resist_bp", 400, 800, "debuff_duration_resist_bp", 5000),
            "AF_DOT_RESIST": ("periodic_resist_bp", 400, 800, "periodic_resist_bp", 5000)
        ]
        XCTAssertEqual(expected.count, 16)
        for (id, definition) in expected {
            let low = try policy.contribution(affixID: id, rawQ: 0, qualityID: "Q3")
            let high = try policy.contribution(affixID: id, rawQ: 1000, qualityID: "Q3")
            XCTAssertEqual(low.statID.rawValue, definition.0, id)
            XCTAssertEqual(low.valueBP, definition.1, id)
            XCTAssertEqual(high.valueBP, definition.2, id)
            XCTAssertEqual(low.aggregateCapStatID, definition.3, id)
            XCTAssertEqual(low.aggregateCapBP, definition.4, id)
            XCTAssertEqual(high.aggregateCapBP, definition.4, id)
        }
        let qualityFloor = try policy.contribution(affixID: "AF_WARD", rawQ: 0, qualityID: "Q4")
        XCTAssertEqual(qualityFloor.valueBP, 800, "R2 Q4 floor is effective q=600, not a stored-q rewrite")
    }

    func testNewPayloadStatRouteIsExclusiveAndLegacyNilReturnsExactPriorProjection() throws {
        let legacy = ["direct_bonus_bp": 5200, "hp_pct": 1200, "legacy_only": 77]
        let nilRoute = try policy.projectStatsR004(legacyProjectedValuesBP: legacy,
                                                   candidateBaseValuesBP: [:],
                                                   candidateSlots: nil, qualityID: "Q4")
        XCTAssertEqual(nilRoute.route, .legacyUnchanged)
        XCTAssertEqual(nilRoute.valuesBP, legacy)

        let slots = try CandidateLatentSlotsR003(slots: [slot("AF_DIRECT", 1000),
                                                          slot("AF_HP", 500),
                                                          slot("AF_DEF", 500)])
        let newRoute = try policy.projectStatsR004(legacyProjectedValuesBP: legacy,
                                                   candidateBaseValuesBP: ["direct_bonus_bp": 5800, "hp_pct": 900],
                                                   candidateSlots: slots, qualityID: "Q3")
        XCTAssertEqual(newRoute.route, .versionedCandidate)
        XCTAssertEqual(newRoute.valuesBP["direct_bonus_bp"], 6000, "candidate payload adds once and clamps aggregate cap")
        XCTAssertEqual(newRoute.valuesBP["hp_pct"], 1350)
        XCTAssertEqual(newRoute.valuesBP["legacy_only"], nil, "legacy item affix/latent inputs are not combined with new payload")
    }

    func testTypedCombatModifiersExposeAllSixteenBPFieldsAndFinalCritMultiplier() throws {
        let base: [String: Int] = [
            "hp_pct": 100, "power_pct": 200, "defense_pct": 300,
            "crit_chance_bp": 400, "crit_multiplier_bp": 15_000,
            "haste_bp": 500, "cdr_bp": 600, "direct_bonus_bp": 5_500,
            "dot_bonus_bp": 700, "heal_bonus_bp": 800, "barrier_bonus_bp": 900,
            "guard_chance_bp": 1_000, "counter_bonus_bp": 1_100,
            "chase_bonus_bp": 1_200, "debuff_duration_resist_bp": 1_300,
            "periodic_resist_bp": 1_400
        ]
        let slots = try CandidateLatentSlotsR003(slots: [
            slot("AF_DIRECT", 1000), slot("AF_WARD", 1000), slot("AF_CRIT_DMG", 1000)
        ])
        let projection = try policy.projectStatsR004(legacyProjectedValuesBP: [:],
                                                      candidateBaseValuesBP: base,
                                                      candidateSlots: slots, qualityID: "Q3")
        let typed = try XCTUnwrap(projection.combatModifiers)
        XCTAssertEqual(typed.hpPercentBP, 100)
        XCTAssertEqual(typed.powerPercentBP, 200)
        XCTAssertEqual(typed.defensePercentBP, 300)
        XCTAssertEqual(typed.critChanceBP, 400)
        XCTAssertEqual(typed.critMultiplierBP, 16_000)
        XCTAssertEqual(typed.hasteBP, 500)
        XCTAssertEqual(typed.cooldownReductionBP, 600)
        XCTAssertEqual(typed.directBonusBP, 6_000)
        XCTAssertEqual(typed.dotBonusBP, 700)
        XCTAssertEqual(typed.healBonusBP, 800)
        XCTAssertEqual(typed.barrierBonusBP, 1_900)
        XCTAssertEqual(typed.guardChanceBP, 1_000)
        XCTAssertEqual(typed.counterBonusBP, 1_100)
        XCTAssertEqual(typed.chaseBonusBP, 1_200)
        XCTAssertEqual(typed.debuffDurationResistBP, 1_300)
        XCTAssertEqual(typed.periodicResistBP, 1_400)
    }

    private func slot(_ id: String, _ q: Int) -> CandidateLatentSlotR003 {
        CandidateLatentSlotR003(affixID: id, rawQ: q)
    }
}
