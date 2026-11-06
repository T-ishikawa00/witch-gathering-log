import Foundation
import XCTest
@testable import WitchGameCore

final class CandidateLatentCombatModifiersR005Tests: XCTestCase {
    func testValidatedProjectionRoundTripsCodableAndKeepsActorBaselineValues() throws {
        let policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
        let slots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_POWER", rawQ: 1000),
            CandidateLatentSlotR003(affixID: "AF_CRIT_DMG", rawQ: 1000),
            CandidateLatentSlotR003(affixID: "AF_WARD", rawQ: 1000)
        ])
        let projected = try policy.projectStatsR004(legacyProjectedValuesBP: [:],
                                                    candidateBaseValuesBP: ["power_pct": 300,
                                                                            "crit_chance_bp": 1_000,
                                                                            "crit_multiplier_bp": 15_000,
                                                                            "barrier_bonus_bp": 9_500],
                                                    candidateSlots: slots, qualityID: "Q3")
        let value = try CandidateLatentCombatModifiersR005(validating: projected)
        XCTAssertEqual(value.powerPercentBP, 900)
        XCTAssertEqual(value.critChanceBP, 1_000)
        XCTAssertEqual(value.critMultiplierBP, 16_000)
        XCTAssertEqual(value.barrierBonusBP, 10_000)
        let bytes = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(CandidateLatentCombatModifiersR005.self, from: bytes), value)
    }

    func testMalformedModifierPayloadsRejectNegativeAboveCapUnknownAndOverflowValues() throws {
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["direct_bonus_bp": -1]))
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["direct_bonus_bp": 6_001]))
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["unregistered_stat": 1]))
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["crit_multiplier_bp": 14_999]))
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: ["hp_pct": Int.max]))

        let value = try CandidateLatentCombatModifiersR005(validating: [:])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["hasteBP"] = Int.max
        let malformed = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(CandidateLatentCombatModifiersR005.self, from: malformed))
    }

    func testLegacyProjectionCannotBeUpcastToCandidateModifiers() throws {
        let policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
        let projection = try policy.projectStatsR004(legacyProjectedValuesBP: ["direct_bonus_bp": 200],
                                                     candidateBaseValuesBP: [:], candidateSlots: nil,
                                                     qualityID: "Q3")
        XCTAssertThrowsError(try CandidateLatentCombatModifiersR005(validating: projection))
    }

    func testSlotPresentationSeparatesStoredRawRollQualityLockAndActorMismatch() throws {
        let policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
        let legacy = try policy.slotPresentation(templateID: "EQ_BODY_01", qualityID: "Q2",
                                                 actorID: "C_SMITH", candidateSlots: nil)
        XCTAssertTrue(legacy.isLegacyUnknown)
        XCTAssertTrue(legacy.slots.isEmpty, "legacy nil must not invent three empty/unknown rolls")

        let slots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_HEAL", rawQ: 300),
            CandidateLatentSlotR003(affixID: "AF_POWER", rawQ: 250),
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 100)
        ])
        let shown = try policy.slotPresentation(templateID: "EQ_BODY_01", qualityID: "Q2",
                                                actorID: "C_SMITH", candidateSlots: slots)
        XCTAssertTrue(shown.payloadPresent)
        XCTAssertEqual(shown.activeSlotCount, 2)
        XCTAssertEqual(shown.slots.map(\.rawQ), [300, 250, 100])
        XCTAssertEqual(shown.slots.map(\.effectiveQ), [300, 250, 100])
        XCTAssertEqual(shown.slots.map(\.valueBP), [650, 375, 330])
        XCTAssertFalse(shown.slots[0].actorCompatible)
        XCTAssertEqual(shown.slots[0].capabilityReason, .requiredActorNotSelected)
        XCTAssertEqual(shown.slots[0].state, .actorIncompatible)
        XCTAssertTrue(shown.slots[1].isActive)
        XCTAssertFalse(shown.slots[2].qualityActive)
        XCTAssertEqual(shown.slots[2].state, .qualityLocked)
    }

    func testActorAggregateAppliesCapOnceAcrossItemsAndReportsOverflow() throws {
        let policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
        let slots = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_DOT", rawQ: 1000),
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 500),
            CandidateLatentSlotR003(affixID: "AF_DEF", rawQ: 500)
        ])
        let items = [0, 1].map { n in
            CandidateLatentEquippedItemR005(id: UUID(uuidString: "30000000-0000-4000-8000-00000000000\(n)")!,
                                            templateID: "EQ_BODY_01", qualityID: "Q1", candidateSlots: slots)
        }
        let result = try policy.projectActorModifiers(actorID: "C_WITCH",
                                                      baseValuesBP: ["dot_bonus_bp": 9_800,
                                                                     "crit_chance_bp": 500,
                                                                     "crit_multiplier_bp": 15_000],
                                                      equippedItems: items)
        XCTAssertEqual(result.uncappedValuesBP["dot_bonus_bp"], 11_800)
        XCTAssertEqual(result.cappedValuesBP["dot_bonus_bp"], 10_000)
        XCTAssertEqual(result.overflowBP["dot_bonus_bp"], 1_800)
        XCTAssertEqual(result.modifiers.dotBonusBP, 10_000)
        XCTAssertEqual(result.modifiers.critChanceBP, 500, "actor baseline is supplied exactly once")
        XCTAssertEqual(result.itemDisplays.count, 2)
    }

    func testActorProjectionRejectsStoredAffixThatTemplateCannotCarry() throws {
        let policy = try CandidateLatentSlotPolicyR003.loadBundledR004()
        let invalid = try CandidateLatentSlotsR003(slots: [
            CandidateLatentSlotR003(affixID: "AF_DOT", rawQ: 800),
            CandidateLatentSlotR003(affixID: "AF_HP", rawQ: 500),
            CandidateLatentSlotR003(affixID: "AF_WARD", rawQ: 500)
        ])
        XCTAssertThrowsError(try policy.projectActorModifiers(actorID: "C_WITCH",
                                                               baseValuesBP: CandidateLatentCombatModifiersR005.baseValuesBP(actorID: "C_WITCH"),
                                                               equippedItems: [CandidateLatentEquippedItemR005(
                                                                id: UUID(), templateID: "EQ_W_01",
                                                                qualityID: "Q4", candidateSlots: invalid)])) {
            XCTAssertEqual($0 as? CandidateLatentPolicyErrorR003, .incompatibleStoredPayload("AF_DOT"))
        }
    }
}
