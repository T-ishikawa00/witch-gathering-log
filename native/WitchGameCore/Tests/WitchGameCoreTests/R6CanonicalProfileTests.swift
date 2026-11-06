import XCTest
@testable import WitchGameCore

final class R6CanonicalProfileTests: XCTestCase {
    func testR6BKeyedRandomLabelAndSourceVector() throws {
        let index = #"["enemy:B_R01_A:1",0]"#
        let label = try R6CanonicalProfile.keyedLabel(domain: "guard.C_WITCH", index: index)
        XCTAssertEqual(label, #"["guard.C_WITCH","[\"enemy:B_R01_A:1\",0]"]"#)
        XCTAssertEqual(try R6CanonicalProfile.keyedInt(seed: "100049", label: label, upperBound: 10_000), 1_058)

        let critLabel = try R6CanonicalProfile.keyedLabel(domain: "crit.C_WITCH", index: "C_WITCH_BASIC:1")
        XCTAssertEqual(try R6CanonicalProfile.keyedInt(seed: "100049", label: critLabel, upperBound: 10_000), 3_699)
        XCTAssertEqual(try R6CanonicalProfile.keyedInt(seed: "100049", label: label, upperBound: 10_000), 1_058, "unrelated draws must not advance a shared RNG stream")
    }

    func testR6FixedPointAdapterPreservesLockedFixtureScale() throws {
        let input = try R6SourceBattleInput(seed: "100049", actors: [
            .init(actorID: "C_WITCH", level: 50, hp: 6_960_945, power: 918_425, defense: 601_720),
            .init(actorID: "C_APPRENTICE", level: 50, hp: 6_940_500, power: 755_860, defense: 640_000),
            .init(actorID: "C_SMITH", level: 50, hp: 10_584_000, power: 630_000, defense: 1_040_000),
            .init(actorID: "C_FAMILIAR", level: 50, hp: 6_000_000, power: 670_000, defense: 580_000)
        ])
        let witch = try XCTUnwrap(input.combatants().first(where: { $0.id == "C_WITCH" }))
        XCTAssertEqual(input.unitScale, 10_000)
        XCTAssertEqual(witch.maxHP, 6_960_945)
        XCTAssertEqual(witch.attack, 918_425)
        XCTAssertEqual(witch.defense, 601_720)
    }

    func testR6FixedPointIncomingDamageMatchesExactRationalVector() throws {
        let input = R6IncomingDamageInput(power: 918_425, coefficientBP: 10_000, defense: 640_000,
                                         attackerLevel: 50, guarded: true, specialReductionBP: 1_500)
        // Python R6 `Fraction` reference: floor(raw * defense/guard/reduction factors).
        XCTAssertEqual(try R6CanonicalProfile.incomingDamage(input), 449_020)
    }

    func testR6NormalAttackTraceMatchesKeyedCritAndFixedPointDefenseVector() throws {
        let trace = try R6CanonicalProfile.normalAttackTrace(.init(seed: "100049", sourceID: "C_WITCH", sourcePower: 918_425,
                                                                    sourceLevel: 50, targetID: "B_R01_A", targetHP: 10_000_000,
                                                                    targetDefense: 1_050_000, rootActionID: "normal:fixture:1",
                                                                    critChanceBP: 500))
        XCTAssertEqual(trace.critRoll, 5_722)
        XCTAssertFalse(trace.critical)
        XCTAssertEqual(trace.rawPower, 918_425)
        XCTAssertEqual(trace.damage, 756_892)
        XCTAssertEqual(trace.hpLoss, 756_892)
        XCTAssertEqual(trace.rootActionID, "normal:fixture:1")
    }

    func testR6SmithRedirectAndApprenticeHealChooserVectors() throws {
        let forecast = R6SmithGuardInput.Telegraph(targetIsAlive: true, isAOE: false,
                                                  impactOffsetsMs: [1_200, 1_600], targetIsDangerousWithoutCover: true,
                                                  redirectedIncomingDamage: [300_000, 200_000])
        let smith = R6SmithGuardInput(nowMs: 8_000, smithHP: 4_000_000, smithMaxHP: 10_584_000,
                                      smithBarrier: 100_000, telegraphs: [forecast])
        XCTAssertTrue(R6CanonicalProfile.smithShouldGuard(smith), "redirected packet is dangerous and nonlethal after Smith barriers")
        XCTAssertFalse(R6CanonicalProfile.smithShouldGuard(.init(nowMs: 8_000, smithHP: 4_000_000, smithMaxHP: 10_584_000,
                                                                  smithBarrier: 100_000, telegraphs: [.init(targetIsAlive: true, isAOE: true, impactOffsetsMs: [100], targetIsDangerousWithoutCover: true, redirectedIncomingDamage: [10])])))

        let candidates = [
            R6HealCandidate(actorID: "C_WITCH", hp: 8_000, maxHP: 10_000, danger: false, projectedHP: 8_000),
            R6HealCandidate(actorID: "C_APPRENTICE", hp: 6_000, maxHP: 10_000, danger: false, projectedHP: 6_000),
            R6HealCandidate(actorID: "C_FAMILIAR", hp: 6_000, maxHP: 10_000, danger: false, projectedHP: 6_000),
            R6HealCandidate(actorID: "C_SMITH", hp: 8_000, maxHP: 10_000, danger: true, projectedHP: 3_000)
        ]
        let target = R6CanonicalProfile.apprenticeHealTarget(candidates)
        XCTAssertEqual(target, "C_FAMILIAR", "equal lowest ratios use Python R6 canonical roster order")
        XCTAssertEqual(R6CanonicalProfile.apprenticeChoice(healTargetID: target, support: .init(healReady: true, wardReady: true, wardTargetID: "C_SMITH", wardIsLethal: true)),
                       R6SupportChoice(skillID: "SK_A_WARD", targetID: "C_SMITH"))
        XCTAssertEqual(R6CanonicalProfile.apprenticeChoice(healTargetID: target, support: .init(healReady: true, wardReady: true, wardTargetID: "C_WITCH", wardIsLethal: false)),
                       R6SupportChoice(skillID: "SK_A_HEAL", targetID: "C_FAMILIAR"))
    }
}
