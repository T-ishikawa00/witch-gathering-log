import CryptoKit
import Foundation
import XCTest
@testable import WitchGameCore

/// One small earned-inventory comparison. This is a read-only, unapproved
/// development-profile preview, not ordinary-play, balance, or purchase acceptance.
final class EffectBuildComparisonR376Tests: XCTestCase {
    private struct Input: Decodable {
        let schema: String
        let savePath: String
        let saveSHA256: String
        let saveBytes: Int
        let reportPath: String
        let reportSHA256: String
        let directGearID: String
        let poisonGearID: String
        let appIdentityPath: String
        let appIdentitySHA256: String
        let challengeID: String
        let seeds: [UInt64]
        let r368InputManifestSHA256: String
    }

    private struct GearRow: Encodable {
        let id: String
        let definitionID: String
        let ownerID: String?
        let qualityID: String
        let enhancement: Int
        let refinement: Int
        let investmentDust: Int
        let latentSlots: CandidateLatentSlotsR003?
    }

    private struct Outcome: Encodable {
        let seed: UInt64
        let loadoutID: String
        let weapon: GearRow
        let won: Bool
        let ticks: Int
        let initialPartyHP: [String: Int]
        let remainingPartyHP: [String: Int]
        let initialEnemyHP: [String: Int]
        let remainingEnemyHP: [String: Int]
        let eventKindCounts: [String: Int]
        let events: [CombatEvent]
    }

    private struct Report: Encodable {
        let schema: String
        let status: String
        let sourceSaveSHA256: String
        let sourceReportSHA256: String
        let r368InputManifestSHA256: String
        let runtimeBaseProfileID: String
        let runtimeBaseFingerprint: String
        let runtimeEnhancementProfileID: String
        let runtimeEnhancementFingerprint: String
        let partyWorkPolicyFingerprint: String
        let challengeID: String
        let outcomes: [Outcome]
        let interpretation: [String]
    }

    func testEarnedSameQualityDirectVsPoisonWeaponOnR02_01() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let inputPath = env["WITCH_R376_INPUT_MANIFEST"], inputPath.hasPrefix("/"),
              let expectedInputSHA = env["WITCH_R376_INPUT_MANIFEST_SHA256"],
              let worktreePath = env["WITCH_R376_WORKTREE"],
              worktreePath == "/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg",
              let outputPath = env["WITCH_R376_OUTPUT"], outputPath.hasPrefix("/"),
              URL(fileURLWithPath: outputPath).lastPathComponent == "report.json" else {
            throw CoreError.invalidCommand("R376 requires pinned absolute input manifest and fresh report.json output")
        }
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let inputBytes = try Data(contentsOf: inputURL)
        XCTAssertEqual(Self.sha256(inputBytes), expectedInputSHA)
        let input = try JSONDecoder().decode(Input.self, from: inputBytes)
        XCTAssertEqual(input.schema, "effect-build-comparison-r376-input-r001")
        XCTAssertEqual(input.challengeID, "CH_R02_01")
        XCTAssertEqual(input.seeds, [37_601, 37_602, 37_603])
        XCTAssertEqual(input.r368InputManifestSHA256, "47ba83bfa951eaac593cf1059492233caec1064c959cdea6afb928a67fcf8417")

        let worktree = URL(fileURLWithPath: worktreePath, isDirectory: true).standardizedFileURL
        guard inputURL.path.hasPrefix(worktree.path + "/") else {
            throw CoreError.invalidCommand("R376 inputs must remain inside the fixed worktree")
        }
        let saveURL = worktree.appendingPathComponent(input.savePath).standardizedFileURL
        let sourceReportURL = worktree.appendingPathComponent(input.reportPath).standardizedFileURL
        XCTAssertTrue(saveURL.path.hasPrefix(worktree.path + "/"))
        XCTAssertTrue(sourceReportURL.path.hasPrefix(worktree.path + "/"))
        let originalSave = try Data(contentsOf: saveURL)
        let originalReport = try Data(contentsOf: sourceReportURL)
        XCTAssertEqual(originalSave.count, input.saveBytes)
        XCTAssertEqual(Self.sha256(originalSave), input.saveSHA256)
        XCTAssertEqual(Self.sha256(originalReport), input.reportSHA256)
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: originalReport) as? [String: Any])
        XCTAssertEqual(source["caseID"] as? String, "R368-free_no_ad-30-seed100049")
        XCTAssertEqual(source["status"] as? String, "RUNNER_FINISHED_XCTEST_RESULT_SEPARATE")
        XCTAssertEqual(source["baseRuntimeProfileID"] as? String, "app-candidate-r098-v1-growth-500bp")
        XCTAssertEqual(source["runtimeProfileID"] as? String,
                       "app-candidate-r098-v1-growth-500bp-enhancement-r230-v1-r350-r352-r353-test-v1")
        XCTAssertEqual(source["paidSummonDrawCount"] as? Int, 0)
        XCTAssertEqual(source["freeSummonDrawCount"] as? Int, 155)
        XCTAssertEqual((source["syntheticGrantReceipts"] as? [Any])?.count, 0)
        XCTAssertEqual((source["naturalGearAcquisitionRecords"] as? [Any])?.count, 96)
        let identityURL = worktree.appendingPathComponent(input.appIdentityPath).standardizedFileURL
        XCTAssertTrue(identityURL.path.hasPrefix(worktree.path + "/"))
        let identityBytes = try Data(contentsOf: identityURL)
        XCTAssertEqual(Self.sha256(identityBytes), input.appIdentitySHA256)

        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: originalSave) as? [String: Any])
        let snapshotObject = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        let snapshotData = try JSONSerialization.data(withJSONObject: snapshotObject, options: [.sortedKeys, .withoutEscapingSlashes])
        let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: snapshotData)
        XCTAssertTrue(snapshot.completedEncounterIDs.contains("CHALLENGE_CLEAR|CH_R02_01"))
        let directID = try XCTUnwrap(UUID(uuidString: input.directGearID))
        let poisonID = try XCTUnwrap(UUID(uuidString: input.poisonGearID))
        let direct = try XCTUnwrap(snapshot.gear.first(where: { $0.id == directID }))
        let poison = try XCTUnwrap(snapshot.gear.first(where: { $0.id == poisonID }))
        XCTAssertFalse(Set(snapshot.equippedGearIDs.values).contains(directID))
        XCTAssertFalse(Set(snapshot.equippedGearIDs.values).contains(poisonID))
        XCTAssertEqual(direct.definitionID, "EQ_W_01"); XCTAssertEqual(poison.definitionID, "EQ_W_P1")
        XCTAssertEqual(direct.qualityID, "Q0"); XCTAssertEqual(poison.qualityID, "Q0")
        XCTAssertEqual(direct.enhancement, 0); XCTAssertEqual(poison.enhancement, 0)
        XCTAssertEqual(direct.refinement, 0); XCTAssertEqual(poison.refinement, 0)
        XCTAssertEqual(direct.investmentDust, 0); XCTAssertEqual(poison.investmentDust, 0)
        XCTAssertNil(direct.ownerID); XCTAssertNil(poison.ownerID)
        XCTAssertNotEqual(direct.candidateLatentSlots, poison.candidateLatentSlots,
                          "latent slot rolls differ and are retained as a comparison confound")

        let base = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        XCTAssertEqual(base.catalog.gearAttackBonuses["EQ_W_01"], 3)
        XCTAssertEqual(base.catalog.gearAttackBonuses["EQ_W_P1"], 3)
        XCTAssertEqual(base.profileID, source["baseRuntimeProfileID"] as? String)
        XCTAssertEqual(base.configurationFingerprint, source["baseRuntimeConfigurationFingerprint"] as? String)
        let r230 = try GameRuntimeEnhancementProfileR230(base: base)
        XCTAssertEqual(r230.configurationFingerprint, source["runtimeConfigurationFingerprint"] as? String)
        let integrated = GameRuntimeIntegratedEquipmentProfileR355(base: r230)
        let workPolicy = try PartyWorkPolicyR144(baseProfileID: base.profileID,
                                                 baseConfigurationFingerprint: base.configurationFingerprint)
        XCTAssertEqual(workPolicy.policyFingerprint, source["partyWorkPolicyFingerprint"] as? String)
        let store = try SaveRepository(initial: snapshot, fileURL: nil)
        let engine = try integrated.makeEngine(saves: store,
            candidatePartyWorkPolicyR144: workPolicy,
            firstCraftAidCapabilityR179: .enabled)
        let witchWeapon = "C_WITCH|weapon"
        let actualID = try XCTUnwrap(snapshot.equippedGearIDs[witchWeapon])
        let occupied = Set(snapshot.equippedGearIDs.values).subtracting([actualID])
        XCTAssertFalse(occupied.contains(directID)); XCTAssertFalse(occupied.contains(poisonID))
        var directMap = snapshot.equippedGearIDs; directMap[witchWeapon] = directID
        var poisonMap = snapshot.equippedGearIDs; poisonMap[witchWeapon] = poisonID
        let loadouts = [
            OwnedPartyLoadoutR181(id: "same_quality_direct_control", gearByActorSlot: directMap),
            OwnedPartyLoadoutR181(id: "same_quality_poison_effect", gearByActorSlot: poisonMap)
        ]

        var rows: [Outcome] = []
        for seed in input.seeds {
            let previews = try engine.previewChallengeOwnedPartyLoadoutsR181(
                challengeID: input.challengeID, seed: seed, snapshot: snapshot, loadouts: loadouts)
            XCTAssertEqual(previews.map(\.loadoutID), ["same_quality_direct_control", "same_quality_poison_effect"])
            for preview in previews {
                let counts = Dictionary(grouping: preview.result.events.map(\.kind), by: { $0 }).mapValues(\.count)
                let poisonKinds = ["poison_seed", "poison_stack", "poison_tick", "poison_burst", "poison_shatter"]
                if preview.loadoutID == "same_quality_direct_control" {
                    XCTAssertEqual(poisonKinds.reduce(0) { $0 + counts[$1, default: 0] }, 0)
                } else {
                    XCTAssertGreaterThan(counts["poison_seed", default: 0], 0)
                    XCTAssertGreaterThan(counts["poison_tick", default: 0], 0)
                }
                rows.append(Outcome(seed: seed, loadoutID: preview.loadoutID,
                    weapon: GearRow(id: preview.loadoutID == "same_quality_direct_control" ? direct.id.uuidString : poison.id.uuidString,
                        definitionID: preview.loadoutID == "same_quality_direct_control" ? direct.definitionID : poison.definitionID,
                        ownerID: nil, qualityID: "Q0", enhancement: 0, refinement: 0,
                        investmentDust: 0, latentSlots: preview.loadoutID == "same_quality_direct_control" ? direct.candidateLatentSlots : poison.candidateLatentSlots),
                    won: preview.result.won, ticks: preview.result.ticks,
                    initialPartyHP: preview.result.initialPartyHP, remainingPartyHP: preview.result.remainingPartyHP,
                    initialEnemyHP: preview.result.initialEnemyHP, remainingEnemyHP: preview.result.remainingEnemyHP,
                    eventKindCounts: counts, events: preview.result.events))
            }
        }
        XCTAssertEqual(rows.count, 6)
        let after = await store.snapshot()
        XCTAssertEqual(after, snapshot, "read-only previews must not change source snapshot")
        XCTAssertEqual(try Data(contentsOf: saveURL), originalSave, "earned save must remain byte-identical")
        XCTAssertEqual(try Data(contentsOf: sourceReportURL), originalReport)
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        guard output.path.hasPrefix(worktree.path + "/"),
              !FileManager.default.fileExists(atPath: output.path) else {
            throw CoreError.invalidCommand("R376 output must be a new file inside the worktree")
        }
        let report = Report(schema: "effect-build-comparison-r376-v1",
            status: "OBSERVATIONAL_PAIRED_PREVIEWS_NOT_BALANCE_ACCEPTANCE",
            sourceSaveSHA256: input.saveSHA256, sourceReportSHA256: input.reportSHA256,
            r368InputManifestSHA256: input.r368InputManifestSHA256,
            runtimeBaseProfileID: base.profileID, runtimeBaseFingerprint: base.configurationFingerprint,
            runtimeEnhancementProfileID: r230.profileID,
            runtimeEnhancementFingerprint: r230.configurationFingerprint,
            partyWorkPolicyFingerprint: workPolicy.policyFingerprint,
            challengeID: input.challengeID, outcomes: rows,
            interpretation: [
                "One free_no_ad 30-virtual-day R368 generated save, one challenge, three fixed seeds, six no-reward previews.",
                "Both weapon items existed in the archived earned inventory; neither is injected. The paired comparison changes only Witch's weapon UUID in the loadout map.",
                "The two Q0/+0/refinement-I/investment-0 weapons have equal catalog attack +3, but their naturally rolled latent slots differ; report is descriptive, not pure causal proof.",
                "No claims about ordinary human acquisition, optimality, all 15 research designs, fun, paid value, formal approval, or other effect families."
            ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: output, options: .withoutOverwriting)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
