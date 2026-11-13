import AppKit
import TesseraCore

typealias ManagedWindowGroup = [(window: WindowRef, frame: CGRect)]

/// Runtime ownership, separate from persisted app-multiset layout memory.
@MainActor
final class SplitWorkspaceStore {
    struct Key: Hashable {
        let display: String
        let space: UInt64?
    }
    struct Restore {
        let window: WindowRef
        let others: [WindowRef]
        let rejoin: Bool
        var restored = false
    }
    struct Recovery {
        let group: ManagedWindowGroup
        let topology: WindowTopology
        let baselineAt: ContinuousClock.Instant
        let minimised: Bool
        func frames(in current: WindowTopology) -> ManagedWindowGroup {
            projectManagedFrames(group, from: topology, into: current)
        }
    }
    struct Record {
        var group: ManagedWindowGroup
        var reserved: ManagedWindowGroup = []
        var topology: WindowTopology
        var baselineAt: ContinuousClock.Instant
        var closedOutOf: [String: [WindowRef]] = [:]
        var restores: [Restore] = []
        var recoveryPending = false
        var recovery: Recovery?
        var pendingMinimised = false
        var retryAfter: ContinuousClock.Instant?
        var recoveryRetries = 0
        var revision: UInt64 = 0
        var updated: Date

        var members: ManagedWindowGroup {
            group + reserved.filter { entry in !group.contains { $0.window == entry.window } }
        }

        func frames(in current: WindowTopology) -> ManagedWindowGroup {
            project(members, into: current)
        }
        func project(_ entries: ManagedWindowGroup, into current: WindowTopology) -> ManagedWindowGroup {
            projectManagedFrames(entries, from: topology, into: current)
        }
    }
    private(set) var records: [Key: Record] = [:]
    private let limit: Int
    private let lifetime: TimeInterval
    private var nextRevision: UInt64 = 0
    var onEvicted: ((Record) -> Void)?

    init(limit: Int = 32, lifetime: TimeInterval = 172_800) { self.limit = limit; self.lifetime = lifetime }

    subscript(_ key: Key) -> Record? {
        get { records[key] }
        set {
            guard var value = newValue else { records[key] = nil; return }
            let old = records[key]
            let changed = old.map { $0.topology != value.topology || !sameManagedFrames($0.group, value.group)
                || !sameManagedFrames($0.reserved, value.reserved) } ?? true
            if changed { nextRevision += 1; value.revision = nextRevision }
            else { value.revision = old?.revision ?? 0 }
            records[key] = value
        }
    }

    func remember(_ group: ManagedWindowGroup, at key: Key, topology: WindowTopology,
                  baselineAt: ContinuousClock.Instant, now: Date = Date()) {
        var record = records[key] ?? Record(group: group, topology: topology, baselineAt: baselineAt, updated: now)
        record.reserved = record.project(record.reserved, into: topology)
        record.reserved.removeAll { entry in group.contains { $0.window == entry.window } }
        record.group = group
        record.topology = topology
        record.baselineAt = baselineAt
        record.updated = now
        self[key] = record
    }

    func closedContexts(active: Set<Key>) -> [String: [String: [WindowRef]]] {
        var result: [String: [String: [WindowRef]]] = [:]
        for key in active {
            for (bundle, others) in records[key]?.closedOutOf ?? [:] { result[bundle, default: [:]][key.display] = others }
        }
        return result
    }

    func replaceClosedContexts(_ contexts: [String: [String: [WindowRef]]], active: Set<Key>) {
        for key in active where records[key] != nil {
            records[key]?.closedOutOf = contexts.reduce(into: [:]) { result, item in
                if let others = item.value[key.display] { result[item.key] = others }
            }
        }
    }

    func trackRestore(_ window: WindowRef, others: [WindowRef], at key: Key, rejoin: Bool = true) {
        for origin in Array(records.keys) { records[origin]?.restores.removeAll { $0.window == window } }
        records[key]?.restores.append(Restore(window: window, others: others, rejoin: rejoin))
    }

    func reserve(_ entries: ManagedWindowGroup, at key: Key) {
        guard var record = records[key] else { return }
        for entry in entries {
            record.reserved.removeAll { $0.window == entry.window }
            record.reserved.append(entry)
        }
        self[key] = record
    }

    func consumeReserved(_ windows: [WindowRef], at key: Key) {
        guard var record = records[key] else { return }
        record.reserved.removeAll { windows.contains($0.window) }
        self[key] = record
    }

    func restored(_ window: WindowRef) -> (Key, Restore)? {
        for key in Array(records.keys) {
            if let index = records[key]?.restores.firstIndex(where: { $0.window == window }) {
                records[key]?.restores[index].restored = true
                if let restore = records[key]?.restores[index] { return (key, restore) }
            }
        }
        return nil
    }

    func consumeRestores(_ windows: [WindowRef], at key: Key) {
        records[key]?.restores.removeAll { windows.contains($0.window) }
    }

    func terminated(_ pid: pid_t, retainReopen: Bool) -> Set<Key> {
        var affected: Set<Key> = []
        for key in Array(records.keys) {
            guard var record = records[key] else { continue }
            let leaving = record.members.filter { $0.window.pid == pid }
            let minimised = record.restores.filter { $0.window.pid == pid }
            guard !leaving.isEmpty || !minimised.isEmpty else { continue }
            affected.insert(key)
            record.recoveryPending = record.recoveryPending || !leaving.isEmpty
            if !leaving.isEmpty { record.pendingMinimised = false }
            if retainReopen {
                let others = record.members.map(\.window).filter { $0.pid != pid }
                for ref in leaving.map(\.window) where !others.isEmpty {
                    if let bundle = ref.bundleID { record.closedOutOf[bundle] = others }
                }
                for restore in minimised where !restore.others.isEmpty {
                    if let bundle = restore.window.bundleID { record.closedOutOf[bundle] = restore.others }
                }
            }
            record.restores.removeAll { $0.window.pid == pid }
            record.updated = Date()
            records[key] = record
        }
        return affected
    }

    func discardUnknown(on displays: Set<String>) {
        for key in Array(records.keys) where key.space == nil && displays.contains(key.display) { evict(key) }
    }

    /// Soft total cap: at most max(limit, active.count). Active workspaces are never evicted to satisfy the cap.
    func prune(active: Set<Key>, now: Date = Date()) {
        for key in Array(records.keys) where !active.contains(key)
            && now.timeIntervalSince(records[key]!.updated) > lifetime { evict(key) }
        while records.count > limit,
              let oldest = records.filter({ !active.contains($0.key) }).min(by: { $0.value.updated < $1.value.updated })?.key {
            evict(oldest)
        }
    }

    func removeAll() { for key in Array(records.keys) { evict(key) } }
    func remove(_ key: Key) { evict(key) }
    private func evict(_ key: Key) { if let record = records.removeValue(forKey: key) { onEvicted?(record) } }
}

private func sameManagedFrames(_ a: ManagedWindowGroup, _ b: ManagedWindowGroup) -> Bool {
    a.count == b.count && a.allSatisfy { entry in b.contains { $0.window == entry.window && $0.frame == entry.frame } }
}

private func projectManagedFrames(_ entries: ManagedWindowGroup, from old: WindowTopology, into current: WindowTopology) -> ManagedWindowGroup {
    guard old != current else { return entries }
    return entries.map { entry in
        let ax = CoordinateSpace.toAX(entry.frame, primaryHeight: old.primaryHeight)
        let frame = old.placement(ax).resolved(in: current.recoveryDisplays)
        return (entry.window, CoordinateSpace.fromAX(frame, primaryHeight: current.primaryHeight))
    }
}
