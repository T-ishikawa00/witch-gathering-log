import Foundation
import Darwin

/// Durable local persistence for the explicit R459 rehearsal only.
/// It stores pending request bytes and the latest correlated authority observation;
/// it is not wired to app production flows and never mutates gameplay saves.
public final class FileBackedAuthorityStoreR463: AuthorityObservationStoreR461,
                                                   PendingPurchaseOperationStoreR461,
                                                   @unchecked Sendable {
    static let namespacePrefix = "r461-account-"
    static let pendingFileName = "pending-operations-v1.json"
    static let observationFileName = "authority-observation-v1.json"
    static let lockFileName = ".r461-store.lock"
    static let pendingTempName = ".pending-operations-v1.tmp"
    static let observationTempName = ".authority-observation-v1.tmp"
    private static let maxPendingRecords = 256
    private static let maxPendingFileBytes = 18 * 1_048_576
    private static let maxObservationFileBytes = 16_384

    private struct PendingEnvelope: Codable, Equatable {
        let schemaVersion: Int
        let accountBindingSHA256: String
        let operations: [PendingPurchaseOperationR461]
    }

    private struct ObservationEnvelope: Codable, Equatable {
        let schemaVersion: Int
        let accountBindingSHA256: String
        let observation: AuthorityObservationR461
    }

    private let rehearsalPath: String
    private let namespaceName: String
    private let accountBindingSHA256: String
    private let rootFD: Int32
    private let namespaceFD: Int32
    private let lockFD: Int32
    private let rootDevice: dev_t
    private let rootInode: ino_t
    private let namespaceDevice: dev_t
    private let namespaceInode: ino_t
    private let processLock = NSLock()

    public init(rehearsalDirectory: URL, accountBindingSHA256: String) throws {
        guard Self.isSHA256(accountBindingSHA256) else { throw Self.invalid("invalid account binding namespace") }
        let standardized = rehearsalDirectory.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard standardized.path == resolved.path,
              standardized.lastPathComponent == "r459-sandbox-rehearsal" else {
            throw Self.invalid("store must be inside the canonical R459 rehearsal directory")
        }
        var rootStat = stat()
        guard lstat(standardized.path, &rootStat) == 0,
              (rootStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              rootStat.st_uid == geteuid(), (rootStat.st_mode & 0o077) == 0 else {
            throw Self.invalid("rehearsal directory must be private, owned, and nonsymlink")
        }
        let rootHandle = Darwin.open(standardized.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootHandle >= 0 else { throw Self.io("open rehearsal directory") }
        do {
            try Self.validateMarker(rootFD: rootHandle)
            let child = Self.namespacePrefix + accountBindingSHA256
            let namespaceCreated = mkdirat(rootHandle, child, mode_t(0o700)) == 0
            if !namespaceCreated && errno != EEXIST { throw Self.io("create account namespace") }
            if namespaceCreated && fsync(rootHandle) != 0 { throw Self.io("sync account namespace creation") }
            let childFD = openat(rootHandle, child, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard childFD >= 0 else { throw Self.io("open account namespace") }
            var childStat = stat()
            guard fstat(childFD, &childStat) == 0,
                  (childStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  childStat.st_uid == geteuid(), (childStat.st_mode & 0o077) == 0 else {
                Darwin.close(childFD)
                throw Self.invalid("account namespace must be private and owned")
            }
            let lockHandle = openat(childFD, Self.lockFileName,
                                    O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard lockHandle >= 0 else {
                Darwin.close(childFD)
                throw Self.io("open storage lock")
            }
            do {
                try Self.validateRegularOwnedFile(lockHandle, allowReadOnly: false)
                if fsync(childFD) != 0 { throw Self.io("sync storage lock creation") }
            } catch { Darwin.close(lockHandle); Darwin.close(childFD); throw error }
            self.rehearsalPath = standardized.path
            self.namespaceName = child
            self.accountBindingSHA256 = accountBindingSHA256
            self.rootFD = rootHandle
            self.namespaceFD = childFD
            self.lockFD = lockHandle
            self.rootDevice = rootStat.st_dev
            self.rootInode = rootStat.st_ino
            self.namespaceDevice = childStat.st_dev
            self.namespaceInode = childStat.st_ino
        } catch {
            Darwin.close(rootHandle)
            throw error
        }
    }

    deinit {
        Darwin.close(lockFD)
        Darwin.close(namespaceFD)
        Darwin.close(rootFD)
    }

    /// Read a saved retry request after relaunch. The operation UUID is the key;
    /// a caller must resubmit the returned identical request, never rebuild it.
    public func loadPending(operationID: UUID) async throws -> PendingPurchaseOperationR461? {
        try withExclusiveLock {
            let envelope = try loadPendingEnvelope()
            return envelope.operations.first { $0.request.operationID == operationID.uuidString.lowercased() }
        }
    }

    public func registerIfAbsent(_ pending: PendingPurchaseOperationR461) async throws {
        try pending.validate()
        try withExclusiveLock {
            var envelope = try loadPendingEnvelope()
            let id = pending.request.operationID
            if let old = envelope.operations.first(where: { $0.request.operationID == id }) {
                guard old == pending else { throw Self.invalid("operation UUID is already bound to different request bytes") }
                return
            }
            guard envelope.operations.count < Self.maxPendingRecords else { throw Self.invalid("pending operation capacity reached") }
            envelope.operations.append(pending)
            envelope.operations.sort { $0.request.operationID < $1.request.operationID }
            try writeEnvelope(envelope, target: Self.pendingFileName, temp: Self.pendingTempName,
                             maximumBytes: Self.maxPendingFileBytes)
        }
    }

    public func load(accountBindingSHA256 requestedBinding: String) async throws -> AuthorityObservationR461? {
        guard requestedBinding == accountBindingSHA256 else { throw Self.invalid("account binding namespace mismatch") }
        return try withExclusiveLock {
            try loadObservationEnvelope()?.observation
        }
    }

    public func compareAndSave(_ observation: AuthorityObservationR461,
                               expectedPreviousRevision: Int64?) async throws -> Bool {
        guard observation.accountBindingSHA256 == accountBindingSHA256,
              observation.revision >= 0, observation.ticketBalance >= 0, observation.ticketDebt >= 0,
              expectedPreviousRevision.map({ $0 >= 0 }) ?? true else {
            throw Self.invalid("invalid observation or revision precondition")
        }
        return try withExclusiveLock {
            let old = try loadObservationEnvelope()?.observation
            guard old?.revision == expectedPreviousRevision else { return false }
            if let old {
                guard observation.revision >= old.revision else { return false }
                if observation.revision == old.revision, observation != old { return false }
            }
            try writeEnvelope(ObservationEnvelope(schemaVersion: 1,
                accountBindingSHA256: accountBindingSHA256, observation: observation),
                target: Self.observationFileName, temp: Self.observationTempName,
                maximumBytes: Self.maxObservationFileBytes)
            return true
        }
    }

    // MARK: Private storage

    private func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        processLock.lock()
        defer { processLock.unlock() }
        try validateRootStillBound()
        guard flock(lockFD, LOCK_EX) == 0 else { throw Self.io("lock local store") }
        defer { _ = flock(lockFD, LOCK_UN) }
        try validateRootStillBound()
        try recoverOwnedTemporary(Self.pendingTempName)
        try recoverOwnedTemporary(Self.observationTempName)
        return try body()
    }

    private func validateRootStillBound() throws {
        var pathStat = stat()
        guard lstat(rehearsalPath, &pathStat) == 0,
              pathStat.st_dev == rootDevice, pathStat.st_ino == rootInode,
              (pathStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              pathStat.st_uid == geteuid(), (pathStat.st_mode & 0o077) == 0 else {
            throw Self.invalid("rehearsal root identity changed")
        }
        try Self.validateMarker(rootFD: rootFD)
        var childStat = stat()
        guard fstatat(rootFD, namespaceName, &childStat, AT_SYMLINK_NOFOLLOW) == 0,
              childStat.st_dev == namespaceDevice, childStat.st_ino == namespaceInode,
              (childStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              childStat.st_uid == geteuid(), (childStat.st_mode & 0o077) == 0 else {
            throw Self.invalid("account namespace identity changed")
        }
    }

    private static func validateMarker(rootFD: Int32) throws {
        let fd = openat(rootFD, "R459_LOCAL_REHEARSAL_ONLY", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.invalid("R459 rehearsal marker missing") }
        defer { Darwin.close(fd) }
        try validateRegularOwnedFile(fd, allowReadOnly: true)
        var data = Data(count: 128)
        let count = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return Darwin.read(fd, base, buffer.count)
        }
        guard count == 30 else { throw Self.invalid("invalid R459 rehearsal marker") }
        data.removeSubrange(count..<data.endIndex)
        guard data == Data("NOT_AUTHORIZED_FOR_PRODUCTION\n".utf8) else {
            throw Self.invalid("invalid R459 rehearsal marker")
        }
    }

    private func loadPendingEnvelope() throws -> PendingEnvelope {
        guard let data = try readRegularFile(Self.pendingFileName, maximumBytes: Self.maxPendingFileBytes) else {
            return PendingEnvelope(schemaVersion: 1, accountBindingSHA256: accountBindingSHA256, operations: [])
        }
        let envelope: PendingEnvelope = try decodeCanonical(data)
        guard envelope.schemaVersion == 1, envelope.accountBindingSHA256 == accountBindingSHA256,
              envelope.operations.count <= Self.maxPendingRecords else { throw Self.invalid("pending store schema/namespace invalid") }
        var seen = Set<String>()
        for operation in envelope.operations {
            try operation.validate()
            let id = operation.request.operationID
            guard UUID(uuidString: id)?.uuidString.lowercased() == id, seen.insert(id).inserted else {
                throw Self.invalid("pending operation IDs are duplicate or noncanonical")
            }
        }
        guard envelope.operations.map({ $0.request.operationID }) == envelope.operations.map({ $0.request.operationID }).sorted() else {
            throw Self.invalid("pending operations are not in canonical order")
        }
        return envelope
    }

    private func loadObservationEnvelope() throws -> ObservationEnvelope? {
        guard let data = try readRegularFile(Self.observationFileName, maximumBytes: Self.maxObservationFileBytes) else { return nil }
        let envelope: ObservationEnvelope = try decodeCanonical(data)
        let value = envelope.observation
        guard envelope.schemaVersion == 1, envelope.accountBindingSHA256 == accountBindingSHA256,
              value.accountBindingSHA256 == accountBindingSHA256, value.revision >= 0,
              value.ticketBalance >= 0, value.ticketDebt >= 0 else { throw Self.invalid("observation store schema/namespace invalid") }
        return envelope
    }

    private func readRegularFile(_ name: String, maximumBytes: Int) throws -> Data? {
        let fd = openat(namespaceFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Self.io("open stored file")
        }
        defer { Darwin.close(fd) }
        try Self.validateRegularOwnedFile(fd, allowReadOnly: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0, info.st_size <= maximumBytes else {
            throw Self.invalid("stored file size is invalid")
        }
        var data = Data(count: Int(info.st_size))
        var offset = 0
        while offset < data.count {
            let readCount = data.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.read(fd, base.advanced(by: offset), buffer.count - offset)
            }
            guard readCount > 0 else { throw Self.invalid("stored file ended unexpectedly") }
            offset += readCount
        }
        var extra: UInt8 = 0
        guard Darwin.read(fd, &extra, 1) == 0 else { throw Self.invalid("stored file changed while reading") }
        return data
    }

    private func writeEnvelope<T: Encodable>(_ value: T, target: String, temp: String,
                                             maximumBytes: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(value)
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw Self.invalid("encoded store exceeds size bound") }
        try ensureSafeExistingTarget(target)
        try recoverOwnedTemporary(temp)
        let fd = openat(namespaceFD, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw Self.io("create atomic temporary file") }
        var keepTemp = true
        defer { Darwin.close(fd); if keepTemp { /* retained partial file is recovered on next locked access */ } }
        do {
            try Self.validateRegularOwnedFile(fd, allowReadOnly: false)
            var offset = 0
            while offset < bytes.count {
                let wrote = bytes.withUnsafeBytes { buffer -> Int in
                    guard let base = buffer.baseAddress else { return -1 }
                    return Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                }
                guard wrote > 0 else { throw Self.io("write atomic temporary file") }
                offset += wrote
            }
            guard fsync(fd) == 0 else { throw Self.io("sync atomic temporary file") }
            try ensureSafeExistingTarget(target)
            guard renameat(namespaceFD, temp, namespaceFD, target) == 0 else { throw Self.io("replace stored file") }
            keepTemp = false
            guard fsync(namespaceFD) == 0 else { throw Self.io("sync account namespace") }
        } catch {
            // Leave only this exact owned temp path; next locked read validates and removes it.
            throw error
        }
    }

    private func ensureSafeExistingTarget(_ name: String) throws {
        let fd = openat(namespaceFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return }
            throw Self.io("inspect target file")
        }
        defer { Darwin.close(fd) }
        try Self.validateRegularOwnedFile(fd, allowReadOnly: true)
    }

    private func recoverOwnedTemporary(_ name: String) throws {
        let fd = openat(namespaceFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return }
            throw Self.io("inspect interrupted-write temporary")
        }
        defer { Darwin.close(fd) }
        try Self.validateRegularOwnedFile(fd, allowReadOnly: true)
        guard unlinkat(namespaceFD, name, 0) == 0, fsync(namespaceFD) == 0 else {
            throw Self.io("recover interrupted-write temporary")
        }
    }

    private func decodeCanonical<T: Decodable & Encodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(T.self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(decoded) == data else { throw Self.invalid("stored JSON is noncanonical, unknown, or duplicated") }
        return decoded
    }

    private static func validateRegularOwnedFile(_ fd: Int32, allowReadOnly: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_uid == geteuid(), (info.st_mode & 0o077) == 0 else {
            throw Self.invalid("storage file must be private, owned, regular, and single-link")
        }
        if !allowReadOnly && (info.st_mode & 0o200) == 0 { throw Self.invalid("storage file is not writable") }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func invalid(_ message: String) -> CoreError { .invalidCommand("R463 local store: " + message) }
    private static func io(_ operation: String) -> CoreError {
        .invalidCommand("R463 local store failed to " + operation + " (errno " + String(errno) + ")")
    }
}
