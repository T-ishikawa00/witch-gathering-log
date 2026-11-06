import Foundation

/// Deterministic, main-actor LRU with caller-supplied nonnegative byte costs.
/// Limits apply only to values retained by this dictionary, not to external owners.
@MainActor
final class CostBoundedCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
    }

    let maximumCost: Int
    let maximumEntryCount: Int

    private var entries: [Key: Entry] = [:]
    /// Oldest key first; bounded entry count keeps this simple order deterministic.
    private var leastToMostRecent: [Key] = []
    private var retainedCost = 0
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var evictions = 0

    init(maximumCost: Int, maximumEntryCount: Int) {
        self.maximumCost = max(0, maximumCost)
        self.maximumEntryCount = max(0, maximumEntryCount)
    }

    var count: Int { entries.count }
    var estimatedCost: Int { retainedCost }

    func value(forKey key: Key) -> Value? {
        guard let entry = entries[key] else {
            misses = Self.incremented(misses)
            return nil
        }
        hits = Self.incremented(hits)
        markMostRecent(key)
        return entry.value
    }

    /// Stores a value when its cost is positive and fits the cache limits.
    /// A rejected positive oversize replacement removes an older value for the
    /// same key, preventing a stale result from being returned later. The caller
    /// still owns and may immediately use the newly-created value.
    @discardableResult
    func insert(_ value: Value, forKey key: Key, cost: Int) -> Bool {
        guard cost > 0 else { return false }
        guard maximumCost > 0, maximumEntryCount > 0 else { return false }
        guard cost <= maximumCost else {
            removeEntry(forKey: key)
            return false
        }

        removeEntry(forKey: key)
        // Subtracting only after checking cost <= maximumCost avoids overflow.
        let costAvailableAfterInsert = maximumCost - cost
        while entries.count >= maximumEntryCount || retainedCost > costAvailableAfterInsert {
            guard let oldest = leastToMostRecent.first else { break }
            evict(oldest)
        }

        // The loop guarantees this addition is bounded by maximumCost.
        guard retainedCost <= maximumCost - cost else { return false }
        entries[key] = Entry(value: value, cost: cost)
        leastToMostRecent.append(key)
        retainedCost += cost
        return true
    }

    @discardableResult
    func removeValue(forKey key: Key) -> Value? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        retainedCost -= entry.cost
        leastToMostRecent.removeAll { $0 == key }
        return entry.value
    }

    /// Clears retained values and resets diagnostic counters.
    func clear() {
        entries.removeAll(keepingCapacity: false)
        leastToMostRecent.removeAll(keepingCapacity: false)
        retainedCost = 0
        hits = 0
        misses = 0
        evictions = 0
    }

    func snapshot() -> [String: Int] {
        [
            "entries": count,
            "estimatedBytes": estimatedCost,
            "byteLimit": maximumCost,
            "entryLimit": maximumEntryCount,
            "hits": hits,
            "misses": misses,
            "evictions": evictions
        ]
    }

    private func markMostRecent(_ key: Key) {
        leastToMostRecent.removeAll { $0 == key }
        leastToMostRecent.append(key)
    }

    private func evict(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else {
            leastToMostRecent.removeAll { $0 == key }
            return
        }
        retainedCost -= entry.cost
        leastToMostRecent.removeAll { $0 == key }
        evictions = Self.incremented(evictions)
    }

    private func removeEntry(forKey key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        retainedCost -= entry.cost
        leastToMostRecent.removeAll { $0 == key }
    }

    private static func incremented(_ value: Int) -> Int {
        value == Int.max ? Int.max : value + 1
    }
}
