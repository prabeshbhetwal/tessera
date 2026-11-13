import Foundation
import os

/// Shared by producers and the window actor. Locks protect small snapshots, never an AX call or suspension.
final class WindowMutationContext: @unchecked Sendable {
    struct Ticket: Sendable {
        let topology: WindowTopology
        let topologyVersion: UInt64
        let workspaceVersions: [String: UInt64]
        let workspaces: [String: UInt64]
    }
    struct Change {
        let topology: Bool
        let displays: Set<String>
        let workspaces: [String: UInt64]
    }
    private struct State {
        var topology: WindowTopology
        var topologyVersion: UInt64 = 0
        var workspaceVersions: [String: UInt64] = [:]
        var workspaces: [String: UInt64]
        var trustworthySpaces: Bool
        var pendingTopology = false
        var pendingDisplays: Set<String> = []
    }
    private let state: OSAllocatedUnfairLock<State>
    private let sampling = OSAllocatedUnfairLock(initialState: ())
    private let topologyReader: @Sendable () -> WindowTopology
    private let workspaceReader: @Sendable () -> [String: UInt64]?

    init(topology: @escaping @Sendable () -> WindowTopology = WindowTopology.system,
         workspaces: @escaping @Sendable () -> [String: UInt64]? = SPI.activeWorkspaceIDs) {
        topologyReader = topology
        workspaceReader = workspaces
        let first = topology(), spaces = workspaces()
        state = OSAllocatedUnfairLock(initialState: State(topology: first, workspaces: spaces ?? [:],
            trustworthySpaces: spaces.map { first.keys.isSubset(of: Set($0.keys)) } ?? false))
    }

    func capture() -> Ticket {
        refresh(spaces: true)
        return state.withLock { Ticket(topology: $0.topology, topologyVersion: $0.topologyVersion,
                                      workspaceVersions: $0.workspaceVersions, workspaces: $0.workspaces) }
    }

    func isCurrent(_ ticket: Ticket, on displays: Set<String>, refreshSpaces: Bool = false) -> Bool {
        refresh(spaces: refreshSpaces)
        return state.withLock { state in
            ticket.topologyVersion == state.topologyVersion
                && displays.allSatisfy { state.topology.keys.contains($0)
                    && ticket.workspaceVersions[$0, default: 0] == state.workspaceVersions[$0, default: 0] }
        }
    }

    /// A real notification invalidates work conservatively when Space identity is unavailable.
    func consumeChanges(spaceNotification: Bool) -> Change {
        refresh(spaces: true)
        return state.withLock { state in
            if spaceNotification, !state.trustworthySpaces {
                for key in state.topology.keys { state.workspaceVersions[key, default: 0] += 1 }
                state.pendingDisplays.formUnion(state.topology.keys)
            }
            let change = Change(topology: state.pendingTopology, displays: state.pendingDisplays,
                                workspaces: state.workspaces)
            state.pendingTopology = false
            state.pendingDisplays = []
            return change
        }
    }

    func invalidateLayouts(on displays: Set<String>) {
        state.withLock { state in
            for key in displays { state.workspaceVersions[key, default: 0] += 1 }
        }
    }

    /// An explicit layout command supersedes older automatic work on those displays only.
    func overridingLayouts(_ ticket: Ticket, on displays: Set<String>, validating relevant: Set<String>? = nil) -> Ticket? {
        refresh(spaces: true)
        return state.withLock { state in
            let keys = relevant ?? displays
            guard ticket.topologyVersion == state.topologyVersion,
                  keys.allSatisfy({ state.topology.keys.contains($0)
                    && ticket.workspaceVersions[$0, default: 0] == state.workspaceVersions[$0, default: 0] }) else { return nil }
            var versions = ticket.workspaceVersions
            for key in displays {
                state.workspaceVersions[key, default: 0] += 1
                versions[key] = state.workspaceVersions[key]
            }
            return Ticket(topology: ticket.topology, topologyVersion: ticket.topologyVersion,
                          workspaceVersions: versions, workspaces: ticket.workspaces)
        }
    }

    /// A column change made inside the current gesture accepts its new layout version, not a new Space/topology.
    func acceptingLayoutChange(_ ticket: Ticket, on displays: Set<String>) -> Ticket? {
        refresh(spaces: true)
        return state.withLock { state in
            guard ticket.topologyVersion == state.topologyVersion,
                  displays.allSatisfy({ ticket.workspaces[$0] == state.workspaces[$0] }) else { return nil }
            var versions = ticket.workspaceVersions
            for key in displays { versions[key] = state.workspaceVersions[key, default: 0] }
            return Ticket(topology: ticket.topology, topologyVersion: ticket.topologyVersion,
                          workspaceVersions: versions, workspaces: ticket.workspaces)
        }
    }

    private func refresh(spaces: Bool) {
        // Serial sampling prevents an older concurrent sample from replacing a newer one.
        sampling.withLock { _ in
            let topology = topologyReader()
            let workspaceIDs = spaces ? workspaceReader() : nil
            state.withLock { state in
                if topology != state.topology {
                    state.pendingDisplays.formUnion(state.topology.keys.union(topology.keys))
                    state.topology = topology
                    state.topologyVersion += 1
                    state.pendingTopology = true
                }
                if spaces {
                    let next = workspaceIDs ?? [:]
                    for key in Set(state.workspaces.keys).union(next.keys) where state.workspaces[key] != next[key] {
                        state.workspaceVersions[key, default: 0] += 1
                        state.pendingDisplays.insert(key)
                    }
                    state.workspaces = next
                    state.trustworthySpaces = workspaceIDs.map { topology.keys.isSubset(of: Set($0.keys)) } ?? false
                }
            }
        }
    }
}

enum WindowMutationScope {
    @TaskLocal static var ticket: WindowMutationContext.Ticket?
}
