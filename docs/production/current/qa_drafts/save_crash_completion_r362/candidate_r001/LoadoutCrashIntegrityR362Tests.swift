import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import WitchGameCore

/// Root-run only. Three invocations of this one method: seed, crash-child, verify.
/// All file activity is confined to the caller-provided new R362 evidence directory.
final class LoadoutCrashIntegrityR362Tests: XCTestCase {
    private struct SeedRecord: Codable {
        let schema: String
        let operationID: String
        let requestFingerprint: String
        let revision: Int64
        let snapshot: GameSnapshot
        let saveSHA256: String
        let equippedGearIDs: [String: String]
    }
    private struct StageRecord: Codable {
        let schema: String
        let phase: String
        let pid: Int32
        let processGroupID: Int32
        let parentPID: Int32
        let phaseToken: String
        let markerUnixTime: TimeInterval
        let operationID: String
        let requestFingerprint: String
        let primarySHA256: String
    }

    func testR342LoadoutPayloadCrashBoundary() async throws {
        guard let mode = ProcessInfo.processInfo.environment["WITCH_R362_MODE"],
              ["seed", "crash-child", "verify"].contains(mode),
              let rawRoot = ProcessInfo.processInfo.environment["WITCH_R362_ROOT"],
              rawRoot.hasPrefix("/") else {
            XCTFail("R362 requires one exact mode and a new absolute evidence root")
            return
        }
        let root = URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL
        guard root.resolvingSymlinksInPath().path == root.path,
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              FileManager.default.fileExists(atPath: root.path) else {
            XCTFail("R362 root must be a precreated non-symlink directory")
            return
        }
        let saveURL = root.appendingPathComponent("save.json")
        let previousURL = saveURL.appendingPathExtension("previous")
        let seedURL = root.appendingPathComponent("seed.json")
        let stageURL = root.appendingPathComponent("after-primary-replace.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let runtime = try GameRuntimeConfigurationR098.resolve(growthStrengthBP: 500)
        let seedOperation = try Self.requiredUUID("WITCH_R362_SEED_OPERATION_ID")
        let saveOperation = try Self.requiredUUID("WITCH_R362_SAVE_OPERATION_ID")
        let saveCommand = GameCommand.saveGearLoadoutR342(slot: .first)
        let requestFingerprint = saveCommand.requestFingerprint

        switch mode {
        case "seed":
            guard Self.directoryIsEmpty(root) else { throw Self.failure("seed root is not empty") }
            let initial = try runtime.makeNewSnapshot()
            let saves = try SaveRepository(initial: initial, fileURL: saveURL)
            let engine = try runtime.makeEngine(saves: saves)
            let seedCommand = GameCommand.startExpeditionAt(regionID: "R01", now: Date(timeIntervalSince1970: 1_800_000_000))
            let receipt = try await engine.dispatch(seedCommand, operationID: seedOperation, expectedRevision: 0)
            let state = await saves.snapshot()
            guard receipt.revision == 1, state.revision == 1,
                  state.gearLoadoutsR342 == nil,
                  let bytes = try? Data(contentsOf: saveURL) else { throw Self.failure("seed state mismatch") }
            try Self.writeExclusive(bytes, to: root.appendingPathComponent("seed-save.bytes"))
            let record = SeedRecord(schema: "r362-loadout-crash-seed-v1",
                operationID: seedOperation.uuidString.lowercased(), requestFingerprint: seedCommand.requestFingerprint,
                revision: state.revision, snapshot: state,
                saveSHA256: Self.sha(bytes), equippedGearIDs: Self.stringIDs(state.equippedGearIDs))
            try Self.writeExclusive(try encoder.encode(record), to: seedURL)

        case "crash-child":
            guard let phaseToken = ProcessInfo.processInfo.environment["WITCH_R362_PHASE_TOKEN"],
                  UUID(uuidString: phaseToken) != nil else { throw Self.failure("missing unique crash phase token") }
            let seed = try Self.decode(SeedRecord.self, at: seedURL)
            guard seed.schema == "r362-loadout-crash-seed-v1",
                  seed.operationID == seedOperation.uuidString.lowercased(),
                  saveOperation != seedOperation,
                  !FileManager.default.fileExists(atPath: stageURL.path),
                  let seedBytes = try? Data(contentsOf: saveURL),
                  Self.sha(seedBytes) == seed.saveSHA256 else { throw Self.failure("bad or stale crash-child inputs") }
            let saves = try SaveRepository(initial: GameSnapshot(), fileURL: saveURL, faultInjector: { phase in
                guard phase == .afterPrimaryReplace else { return }
                let bytes = try Data(contentsOf: saveURL)
                let marker = StageRecord(schema: "r362-after-primary-replace-v1", phase: phase.rawValue,
                    pid: getpid(), processGroupID: getpgrp(), parentPID: getppid(), phaseToken: phaseToken, markerUnixTime: Date().timeIntervalSince1970, operationID: saveOperation.uuidString.lowercased(),
                    requestFingerprint: requestFingerprint, primarySHA256: Self.sha(bytes))
                try Self.writeExclusive(try JSONEncoder().encode(marker), to: stageURL)
                // Bounded barrier. The supervisor should kill only this verified XCTest PID.
                let barrierDeadline = ProcessInfo.processInfo.systemUptime + 40
                while ProcessInfo.processInfo.systemUptime < barrierDeadline { usleep(100_000) }
                XCTFail("supervisor did not terminate the validated XCTest child before barrier timeout")
            })
            guard await saves.snapshot() == seed.snapshot,
                  await saves.receipt(for: seedOperation) != nil else { throw Self.failure("crash-child did not open the exact acknowledged seed") }
            let engine = try runtime.makeEngine(saves: saves)
            _ = try await engine.dispatch(saveCommand, operationID: saveOperation, expectedRevision: seed.revision)
            XCTFail("the parent must stop this child at the post-replace/pre-directory-sync barrier")

        case "verify":
            let seed = try Self.decode(SeedRecord.self, at: seedURL)
            let marker = try Self.decode(StageRecord.self, at: stageURL)
            guard seed.schema == "r362-loadout-crash-seed-v1",
                  seed.operationID == seedOperation.uuidString.lowercased(),
                  saveOperation != seedOperation,
                  marker.schema == "r362-after-primary-replace-v1",
                  marker.phase == SaveWritePhase.afterPrimaryReplace.rawValue,
                  marker.operationID == saveOperation.uuidString.lowercased(),
                  marker.requestFingerprint == requestFingerprint,
                  let priorBytes = try? Data(contentsOf: root.appendingPathComponent("seed-save.bytes")),
                  Self.sha(priorBytes) == seed.saveSHA256,
                  let primaryBytes = try? Data(contentsOf: saveURL),
                  Self.sha(primaryBytes) == marker.primarySHA256,
                  let backupBytes = try? Data(contentsOf: previousURL),
                  Self.sha(backupBytes) == seed.saveSHA256 else {
                throw Self.failure("stage/primary/previous generation identity mismatch")
            }
            let baseReopened = try SaveRepository(fileURL: previousURL)
            let baseSnapshot = await baseReopened.snapshot()
            guard baseSnapshot.revision == seed.revision,
                  baseSnapshot == seed.snapshot,
                  await baseReopened.receipt(for: seedOperation) != nil else {
                throw Self.failure("previous generation did not decode to the exact acknowledged seed snapshot")
            }
            let reopened = try SaveRepository(fileURL: saveURL)
            let beforeReplay = await reopened.snapshot()
            let receiptBefore = await reopened.receipt(for: saveOperation)
            guard beforeReplay.revision == seed.revision + 1,
                  beforeReplay.gearLoadoutsR342?.loadout(for: .first)?.gearByActorSlot == beforeReplay.equippedGearIDs,
                  let receiptBefore, receiptBefore.requestFingerprint == requestFingerprint,
                  receiptBefore.revision == seed.revision + 1,
                  (await reopened.recoveryStatus()).source == .primary,
                  try Data(contentsOf: saveURL) == primaryBytes,
                  try Data(contentsOf: previousURL) == backupBytes else {
                throw Self.failure("post-crash loadout payload/receipt did not reopen as one complete commit")
            }
            let engine = try runtime.makeEngine(saves: reopened)
            let replay = try await engine.dispatch(saveCommand, operationID: saveOperation, expectedRevision: seed.revision)
            let afterReplay = await reopened.snapshot()
            guard replay == receiptBefore, afterReplay == beforeReplay,
                  await reopened.receipt(for: saveOperation) == receiptBefore,
                  try Data(contentsOf: saveURL) == primaryBytes,
                  try Data(contentsOf: previousURL) == backupBytes else {
                throw Self.failure("same-command replay changed a committed R342 payload or save bytes")
            }
            let cold = try SaveRepository(fileURL: saveURL)
            let coldState = await cold.snapshot()
            guard coldState == beforeReplay,
                  coldState.gearLoadoutsR342?.loadout(for: .first)?.gearByActorSlot == coldState.equippedGearIDs,
                  await cold.receipt(for: saveOperation) == receiptBefore,
                  try Data(contentsOf: saveURL) == primaryBytes else {
                throw Self.failure("cold reopen changed R342 payload or receipt")
            }
        default: throw Self.failure("unreachable mode")
        }
    }

    private static func requiredUUID(_ name: String) throws -> UUID {
        guard let raw = ProcessInfo.processInfo.environment[name], let value = UUID(uuidString: raw),
              value.uuidString.lowercased() == raw.lowercased() else { throw failure("invalid \(name)") }
        return value
    }
    private static func directoryIsEmpty(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty) == true
    }
    private static func stringIDs(_ input: [String: UUID]) -> [String: String] {
        input.mapValues { $0.uuidString.lowercased() }
    }
    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func writeExclusive(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw failure("exclusive evidence create failed: \(url.lastPathComponent)") }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw failure("evidence write failed") }
                guard count > 0 else { throw failure("evidence write made no progress") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw failure("evidence fsync failed") }
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "R362", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
