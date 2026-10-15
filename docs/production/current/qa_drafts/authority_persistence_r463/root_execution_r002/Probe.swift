import Foundation
import WitchGameCore

@main
struct AuthorityStoreProbeR463 {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else { throw NSError(domain: "R463ProbeArguments", code: 1) }
        let binding = String(repeating: "a", count: 64)
        let store = try FileBackedAuthorityStoreR463(rehearsalDirectory: URL(fileURLWithPath: args[1]), accountBindingSHA256: binding)
        let operationID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let pending = try PendingPurchaseOperationR461(operationID: operationID, signedTransactionJWS: "e30.e30.AA")
        func observation(_ revision: Int, status: String = "active", debt: Int = 0) throws -> AuthorityObservationR461 {
            let bytes = try JSONSerialization.data(withJSONObject: ["accountBindingSHA256": binding, "revision": revision, "status": status, "ticketBalance": 0, "ticketDebt": debt])
            return try JSONDecoder().decode(AuthorityObservationR461.self, from: bytes)
        }
        var result: [String: Any] = ["mode": args[2], "pid": ProcessInfo.processInfo.processIdentifier]
        switch args[2] {
        case "write":
            try await store.registerIfAbsent(pending)
            result["saved"] = try await store.compareAndSave(observation(5), expectedPreviousRevision: nil)
        case "read":
            result["pendingEqual"] = try await store.loadPending(operationID: operationID) == pending
            result["revision"] = try await store.load(accountBindingSHA256: binding)?.revision
        case "race":
            guard args.count == 5, let revision = Int(args[3]), let barrier = TimeInterval(args[4]) else { throw NSError(domain: "R463ProbeArguments", code: 2) }
            // Synchronize two independent executables without using shared store state as a barrier.
            while Date().timeIntervalSince1970 < barrier { try await Task.sleep(nanoseconds: 5_000_000) }
            result["saved"] = try await store.compareAndSave(observation(revision), expectedPreviousRevision: 5)
            result["proposedRevision"] = revision
        case "refund":
            let previous = try await store.load(accountBindingSHA256: binding)
            result["saved"] = try await store.compareAndSave(observation(10, status: "refunded", debt: 2), expectedPreviousRevision: previous?.revision)
        case "stale":
            result["acceptedStale"] = try await store.compareAndSave(observation(5), expectedPreviousRevision: 10)
            result["revision"] = try await store.load(accountBindingSHA256: binding)?.revision
            result["debt"] = try await store.load(accountBindingSHA256: binding)?.ticketDebt
        default: throw NSError(domain: "R463ProbeArguments", code: 3)
        }
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
    }
}
