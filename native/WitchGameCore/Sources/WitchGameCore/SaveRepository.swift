import Foundation
import Darwin

private struct SaveEnvelope: Codable {
    var snapshot: GameSnapshot
    var receipts: [UUID: CommandReceipt]
    enum CodingKeys: String, CodingKey { case snapshot, receipts }
    init(snapshot: GameSnapshot, receipts: [UUID: CommandReceipt]) { self.snapshot = snapshot; self.receipts = receipts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapshot = try c.decode(GameSnapshot.self, forKey: .snapshot)
        receipts = try c.decodeIfPresent([UUID: CommandReceipt].self, forKey: .receipts) ?? [:]
    }
}

/// Serializes mutations and persists a new revision with atomic file replacement.
public actor SaveRepository {
    private let url: URL?
    private var envelope: SaveEnvelope
    public init(initial: GameSnapshot = GameSnapshot(), fileURL: URL? = nil) throws {
        self.url = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        } else { self.envelope = SaveEnvelope(snapshot: initial, receipts: [:]) }
    }
    public func snapshot() -> GameSnapshot { envelope.snapshot }
    public func receipt(for operationID: UUID) -> CommandReceipt? { envelope.receipts[operationID] }

    public func transact(expectedRevision: Int64, operationID: UUID, requestFingerprint: String? = nil, mutation: @Sendable (inout GameSnapshot) throws -> String) throws -> CommandReceipt {
        if let url { return try withFileLock(url) {
            if FileManager.default.fileExists(atPath: url.path) { envelope = try JSONDecoder().decode(SaveEnvelope.self, from: Data(contentsOf: url)) }
            return try apply(expectedRevision: expectedRevision, operationID: operationID, requestFingerprint: requestFingerprint, mutation: mutation)
        } }
        return try apply(expectedRevision: expectedRevision, operationID: operationID, requestFingerprint: requestFingerprint, mutation: mutation)
    }
    private func apply(expectedRevision: Int64, operationID: UUID, requestFingerprint: String?, mutation: @Sendable (inout GameSnapshot) throws -> String) throws -> CommandReceipt {
        if let receipt = envelope.receipts[operationID] {
            guard receipt.requestFingerprint == requestFingerprint else { throw CoreError.duplicateOperation }
            return receipt
        }
        guard envelope.snapshot.revision == expectedRevision else { throw CoreError.revisionConflict(expected: expectedRevision, actual: envelope.snapshot.revision) }
        // Revisions are persisted as signed 64-bit integers. Refuse exhausted or
        // malformed negative revisions before running a command closure; unchecked
        // `+= 1` traps the process and can make an otherwise readable save unusable.
        guard envelope.snapshot.revision >= 0, envelope.snapshot.revision < Int64.max else {
            throw CoreError.invalidCommand("save revision is outside the writable range")
        }
        var candidate = envelope.snapshot
        let result = try mutation(&candidate)
        candidate.revision = envelope.snapshot.revision + 1
        let receipt = CommandReceipt(operationID: operationID, revision: candidate.revision, result: result, requestFingerprint: requestFingerprint)
        var next = envelope; next.snapshot = candidate; next.receipts[operationID] = receipt
        try persist(next); envelope = next
        return receipt
    }
    private func withFileLock<T>(_ url: URL, operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CoreError.invalidCommand("cannot open save lock") }
        guard flock(descriptor, LOCK_EX) == 0 else { close(descriptor); throw CoreError.invalidCommand("cannot lock save file") }
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        return try operation()
    }
    private func persist(_ value: SaveEnvelope) throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
