import Foundation
import CryptoKit
import XCTest
@testable import WitchGameCore

final class OwnedPartyLoadoutPreviewR181Tests: XCTestCase {
    private struct EarnedSave: Decodable { let snapshot: GameSnapshot }

    private enum EvidenceError: Error { case missingEvidenceRoot, evidenceRootNotAbsolute, evidenceRootMissingOrNotDirectory, evidenceRootUsesSymlink, runDirectoryCollision }

    private struct CombatMetrics: Encodable {
        let won: Bool
        let ticks: Int
        let eventCount: Int
        let eventKindCounts: [String: Int]
        let initialPartyHP: [String: Int]
        let remainingPartyHP: [String: Int]
        let survivingPartyCount: Int
        let initialEnemyHP: [String: Int]
        let remainingEnemyHP: [String: Int]
        let defeatedEnemyCount: Int

        init(_ result: CombatResult) {
            won = result.won
            ticks = result.ticks
            eventCount = result.events.count
            var kinds: [String: Int] = [:]
            for event in result.events { kinds[event.kind, default: 0] += 1 }
            eventKindCounts = kinds
            initialPartyHP = result.initialPartyHP
            remainingPartyHP = result.remainingPartyHP
            survivingPartyCount = result.remainingPartyHP.values.filter { $0 > 0 }.count
            initialEnemyHP = result.initialEnemyHP
            remainingEnemyHP = result.remainingEnemyHP
            defeatedEnemyCount = result.remainingEnemyHP.values.filter { $0 <= 0 }.count
        }
    }

    private struct LoadoutEvidence: Encodable {
        let loadoutID: String
        let gearByActorSlot: [String: String]
        let result: CombatMetrics
    }

    private struct PreviewPairEvidence: Encodable {
        let sequence: Int
        let challengeID: String
        let seed: UInt64
        let fixtureSHA256: String
        let baselineRevision: Int64
        let runtimeProfileID: String
        let configurationFingerprint: String
        let previews: [LoadoutEvidence]
    }

    private struct RunCompleteEvidence: Encodable {
        let status: String
        let fixtureSHA256: String
        let baselineRevision: Int64
        let runtimeProfileID: String
        let configurationFingerprint: String
        let expectedPreviewCount: Int
        let persistedPairFiles: [String]
    }

    private func requiredEvidenceRoot() throws -> URL {
        guard let raw = ProcessInfo.processInfo.environment["WITCH_R181_EVIDENCE_ROOT"], !raw.isEmpty else {
            throw EvidenceError.missingEvidenceRoot
        }
        guard raw.hasPrefix("/") else { throw EvidenceError.evidenceRootNotAbsolute }
        let root = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
            throw EvidenceError.evidenceRootUsesSymlink
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw EvidenceError.evidenceRootMissingOrNotDirectory
        }
        return root
    }

    private func evidenceData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func earnedFixture() throws -> (GameSnapshot, Data) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("R159_DAY30_SAVE_AFTER_REOPEN.json")
        let bytes = try Data(contentsOf: url)
        return (try JSONDecoder().decode(EarnedSave.self, from: bytes).snapshot, bytes)
    }

    private func twoActualLoadouts(_ snapshot: GameSnapshot) throws -> [OwnedPartyLoadoutR181] {
        let base = snapshot.equippedGearIDs
        XCTAssertEqual(base["C_APPRENTICE|weapon"], UUID(uuidString: "CC7B2DE2-CD14-43BA-92C0-9C047946EBAF"))
        let actualAlternative = try XCTUnwrap(snapshot.gear.first(where: {
            $0.id == UUID(uuidString: "10000000-0000-4000-8000-000000000002")
        }))
        XCTAssertEqual(actualAlternative.definitionID, "EQ_A_03")
        XCTAssertNil(actualAlternative.ownerID)
        var alternative = base
        alternative["C_APPRENTICE|weapon"] = actualAlternative.id
        let familiarAlternative = try XCTUnwrap(snapshot.gear.first(where: {
            $0.id == UUID(uuidString: "3C8AFF0F-A72D-4E80-B8AD-34B998224759")
        }))
        XCTAssertEqual(familiarAlternative.definitionID, "EQ_F_01")
        XCTAssertNil(familiarAlternative.ownerID)
        alternative["C_FAMILIAR|weapon"] = familiarAlternative.id
        return [OwnedPartyLoadoutR181(id: "earned-equipped", gearByActorSlot: base),
                OwnedPartyLoadoutR181(id: "earned-apprentice-weapon-alternative", gearByActorSlot: alternative)]
    }

    func testR159EarnedSaveProvidesTwoCompleteActualFourActorMapsAndPreviewIsReadOnly() async throws {
        let (snapshot, fixtureBytes) = try earnedFixture()
        XCTAssertTrue(snapshot.completedEncounterIDs.contains("B_R05_B"))
        XCTAssertEqual(snapshot.partyActorIDs.count, 4)
        let loadouts = try twoActualLoadouts(snapshot)
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        XCTAssertEqual(profile.configurationFingerprint,
                       "4b556e250948bd35ff31a7bdc9dbbc01a671e358565182f556ab1d8d3bf4efb0")

        // The caller must pre-create a stable, absolute, non-symlink evidence root.
        // This test retains a unique child directory and never cleans it up.
        let fileManager = FileManager.default
        let evidenceRoot = try requiredEvidenceRoot()
        let runDirectory = evidenceRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard !fileManager.fileExists(atPath: runDirectory.path) else { throw EvidenceError.runDirectoryCollision }
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: false)
        print("R181_EVIDENCE_RUN_PATH=\(runDirectory.path)")
        let saveURL = runDirectory.appendingPathComponent("save.json")
        let previousURL = saveURL.appendingPathExtension("previous")
        try fixtureBytes.write(to: saveURL, options: .withoutOverwriting)
        try fixtureBytes.write(to: previousURL, options: .withoutOverwriting)
        let beforePrimary = try Data(contentsOf: saveURL)
        let beforePrevious = try Data(contentsOf: previousURL)
        XCTAssertEqual(beforePrimary, fixtureBytes)
        XCTAssertEqual(beforePrevious, fixtureBytes)
        let beforeEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: beforePrimary) as? [String: Any])
        let beforeReceipts = try XCTUnwrap(beforeEnvelope["receipts"])

        let saves = try SaveRepository(initial: snapshot, fileURL: saveURL)
        let engine = try profile.makeEngine(saves: saves)
        let baseline = await engine.snapshot()
        XCTAssertEqual(baseline, snapshot)

        var previewCount = 0
        for challengeID in ["CH_R01_03", "CH_R02_02", "CH_R03_01"] {
            for seed: UInt64 in [31_001, 31_002, 31_003] {
                let rows = try engine.previewChallengeOwnedPartyLoadoutsR181(
                    challengeID: challengeID, seed: seed, snapshot: baseline, loadouts: loadouts)
                XCTAssertEqual(rows.count, 2)
                XCTAssertTrue(rows.allSatisfy { $0.challengeID == challengeID && $0.seed == seed })
                XCTAssertEqual(rows[0].gearByActorSlot["C_APPRENTICE|weapon"], UUID(uuidString: "CC7B2DE2-CD14-43BA-92C0-9C047946EBAF"))
                XCTAssertEqual(rows[1].gearByActorSlot["C_APPRENTICE|weapon"], UUID(uuidString: "10000000-0000-4000-8000-000000000002"))
                XCTAssertEqual(rows[0].gearByActorSlot["C_FAMILIAR|weapon"], UUID(uuidString: "10000000-0000-4000-8000-000000000004"))
                XCTAssertEqual(rows[1].gearByActorSlot["C_FAMILIAR|weapon"], UUID(uuidString: "3C8AFF0F-A72D-4E80-B8AD-34B998224759"))
                let pairSequence = previewCount / 2
                let pairEvidence = PreviewPairEvidence(
                    sequence: pairSequence,
                    challengeID: challengeID,
                    seed: seed,
                    fixtureSHA256: fixtureBytes.sha256HexR181,
                    baselineRevision: baseline.revision,
                    runtimeProfileID: profile.profileID,
                    configurationFingerprint: profile.configurationFingerprint,
                    previews: rows.map { row in
                        LoadoutEvidence(
                            loadoutID: row.loadoutID,
                            gearByActorSlot: row.gearByActorSlot.mapValues { $0.uuidString },
                            result: CombatMetrics(row.result))
                    })
                let pairName = String(format: "pair_%03d.json", pairSequence)
                let pairURL = runDirectory.appendingPathComponent(pairName)
                guard !fileManager.fileExists(atPath: pairURL.path) else { throw EvidenceError.runDirectoryCollision }
                try evidenceData(pairEvidence).write(to: pairURL, options: .withoutOverwriting)
                for row in pairEvidence.previews {
                    XCTAssertGreaterThan(row.result.ticks, 0)
                    XCTAssertGreaterThan(row.result.eventCount, 0)
                }
                previewCount += rows.count
                let afterPreviewSnapshot = await engine.snapshot()
                XCTAssertEqual(afterPreviewSnapshot, baseline)
                XCTAssertEqual(try Data(contentsOf: saveURL), beforePrimary)
                XCTAssertEqual(try Data(contentsOf: previousURL), beforePrevious)
                let currentEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: saveURL)) as? [String: Any])
                let currentReceipts = try XCTUnwrap(currentEnvelope["receipts"])
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: currentReceipts, options: [.sortedKeys]),
                               try JSONSerialization.data(withJSONObject: beforeReceipts, options: [.sortedKeys]))
            }
        }
        XCTAssertEqual(previewCount, 18)
        let pairFiles = (0..<9).map { String(format: "pair_%03d.json", $0) }
        let completed = RunCompleteEvidence(
            status: "ALL_18_PREVIEWS_RECORDED",
            fixtureSHA256: fixtureBytes.sha256HexR181,
            baselineRevision: baseline.revision,
            runtimeProfileID: profile.profileID,
            configurationFingerprint: profile.configurationFingerprint,
            expectedPreviewCount: previewCount,
            persistedPairFiles: pairFiles)
        let completeURL = runDirectory.appendingPathComponent("RUN_COMPLETE.json")
        guard !fileManager.fileExists(atPath: completeURL.path) else { throw EvidenceError.runDirectoryCollision }
        try evidenceData(completed).write(to: completeURL, options: .withoutOverwriting)

        // Cold reopen from the exact persisted primary, then recheck both state
        // and bytes to ensure the preview did not leave a hidden repository write.
        let reopenedSaves = try SaveRepository(initial: GameSnapshot(), fileURL: saveURL)
        let reopenedEngine = try profile.makeEngine(saves: reopenedSaves)
        let reopenedSnapshot = await reopenedEngine.snapshot()
        XCTAssertEqual(reopenedSnapshot, baseline)
        XCTAssertEqual(try Data(contentsOf: saveURL), beforePrimary)
        XCTAssertEqual(try Data(contentsOf: previousURL), beforePrevious)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("R159_DAY30_SAVE_AFTER_REOPEN.json")), fixtureBytes)
    }

    func testRejectsDuplicateGearUnknownIDWrongSlotAndIncompleteMap() async throws {
        let (snapshot, _) = try earnedFixture()
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let engine = try profile.makeEngine(saves: SaveRepository(initial: snapshot))
        var good = try twoActualLoadouts(snapshot)
        var duplicate = good[1].gearByActorSlot
        duplicate["C_APPRENTICE|weapon"] = good[0].gearByActorSlot["C_WITCH|weapon"]
        let badDuplicate = OwnedPartyLoadoutR181(id: "duplicate", gearByActorSlot: duplicate)
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_R01_03", seed: 31_001, snapshot: snapshot,
            loadouts: [good[0], badDuplicate])) { error in
                XCTAssertEqual(error as? OwnedPartyLoadoutPreviewErrorR181,
                               .duplicateGearAssignment(UUID(uuidString: "10000000-0000-4000-8000-000000000001")!))
            }
        var missingID = good[1].gearByActorSlot
        missingID["C_APPRENTICE|weapon"] = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_R01_03", seed: 31_001, snapshot: snapshot,
            loadouts: [good[0], OwnedPartyLoadoutR181(id: "unknown", gearByActorSlot: missingID)])) { error in
                XCTAssertEqual(error as? OwnedPartyLoadoutPreviewErrorR181,
                               .missingOrDuplicateGear(UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!))
            }
        var wrongSlot = good[1].gearByActorSlot
        let witchWeapon = wrongSlot["C_WITCH|weapon"]
        wrongSlot["C_WITCH|weapon"] = wrongSlot["C_WITCH|body"]
        wrongSlot["C_WITCH|body"] = witchWeapon
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_R01_03", seed: 31_001, snapshot: snapshot,
            loadouts: [good[0], OwnedPartyLoadoutR181(id: "wrong-slot", gearByActorSlot: wrongSlot)])) { error in
                guard let typed = error as? OwnedPartyLoadoutPreviewErrorR181,
                      case .wrongGearSlot = typed else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        var incomplete = good[1].gearByActorSlot
        incomplete.removeValue(forKey: "C_SMITH|weapon")
        good[1] = OwnedPartyLoadoutR181(id: "incomplete", gearByActorSlot: incomplete)
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_R01_03", seed: 31_001, snapshot: snapshot, loadouts: good)) { error in
                XCTAssertEqual(error as? OwnedPartyLoadoutPreviewErrorR181, .occupiedSlotSetMismatch)
            }
    }

    func testRejectsWrongActorOwnershipAndLockedChallenge() async throws {
        let (snapshot, _) = try earnedFixture()
        let profile = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let engine = try profile.makeEngine(saves: SaveRepository(initial: snapshot))
        let loadouts = try twoActualLoadouts(snapshot)
        var foreign = loadouts[1].gearByActorSlot
        // Move the actual Apprentice-owned weapon into Familiar's slot while
        // assigning the actual unowned familiar weapon to Apprentice. UUIDs stay unique.
        // Keep the actual valid Apprentice alternative but place the Apprentice-owned
        // actual EQ_A_01 UUID in Familiar's slot to exercise the owner boundary.
        foreign["C_FAMILIAR|weapon"] = UUID(uuidString: "CC7B2DE2-CD14-43BA-92C0-9C047946EBAF")
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_R01_03", seed: 31_001, snapshot: snapshot,
            loadouts: [loadouts[0], OwnedPartyLoadoutR181(id: "foreign", gearByActorSlot: foreign)])) { error in
                XCTAssertEqual(error as? OwnedPartyLoadoutPreviewErrorR181,
                               .wrongGearOwner(UUID(uuidString: "CC7B2DE2-CD14-43BA-92C0-9C047946EBAF")!))
            }
        var locked = snapshot
        locked.completedEncounterIDs.remove("B_R05_B")
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_R01_03", seed: 31_001, snapshot: locked, loadouts: loadouts)) { error in
                XCTAssertEqual(error as? OwnedPartyLoadoutPreviewErrorR181, .challengeLocked)
            }
        XCTAssertThrowsError(try engine.previewChallengeOwnedPartyLoadoutsR181(
            challengeID: "CH_UNKNOWN", seed: 31_001, snapshot: snapshot, loadouts: loadouts)) { error in
                XCTAssertEqual(error as? OwnedPartyLoadoutPreviewErrorR181, .unknownChallenge)
            }
    }
}

private extension Data {
    var sha256HexR181: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
