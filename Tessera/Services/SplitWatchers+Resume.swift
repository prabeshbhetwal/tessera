import AppKit
import TesseraCore

extension SplitWatchers {
    /// Two delayed retries complement each recovery's bounded AX polling. Persistent refusals wait for a new event.
    func retryPendingRecoveries() {
        for key in currentWorkspaceKeys() {
            guard let record = workspaceStore[key], record.recoveryPending, record.recoveryRetries < 2,
                  let due = record.retryAfter, due <= .now,
                  pendingFills[key.display] == nil, pendingResumes[key.display] == nil else { continue }
            workspaceStore[key]?.recoveryRetries += 1
            workspaceStore[key]?.retryAfter = nil
            resumeWorkspace(key)
        }
    }

    func resumeWorkspace(_ origin: SplitWorkspaceStore.Key) {
        guard model.settings.learnSplits, workspaceStore[origin] != nil, pendingFills[origin.display] == nil else { return }
        pendingResumes[origin.display]?.cancel()
        let id = UUID(), ticket = windows.mutationContext.capture()
        resumeIDs[origin.display] = id
        pendingResumes[origin.display] = Task { [weak self] in
            defer {
                if self?.resumeIDs[origin.display] == id {
                    self?.pendingResumes[origin.display] = nil
                    self?.resumeIDs[origin.display] = nil
                }
            }
            await WindowMutationScope.$ticket.withValue(ticket) {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                await self?.resume(origin, ticket: ticket)
            }
        }
    }

    private func resume(_ origin: SplitWorkspaceStore.Key, ticket: WindowMutationContext.Ticket) async {
        guard !Task.isCancelled, model.settings.learnSplits, currentWorkspaceKeys().contains(origin),
              windows.mutationContext.isCurrent(ticket, on: [origin.display], refreshSpaces: true),
              let record = workspaceStore[origin],
              let display = displays.displays.first(where: { $0.id.storageKey == origin.display }) else { return }
        guard ticket.topology.contains(display) else { return }
        let group = record.recovery?.frames(in: ticket.topology) ?? record.frames(in: ticket.topology)
        let found = await windows.visibleWindows(on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                                                excluding: Set(model.settings.excludedBundleIDs), retaining: group.map(\.window))
        guard !Task.isCancelled, currentWorkspaceKeys().contains(origin),
              windows.mutationContext.isCurrent(ticket, on: [origin.display], refreshSpaces: true),
              workspaceStore[origin]?.revision == record.revision else { return }
        for entry in record.restores where entry.restored && found.contains(where: { $0.window == entry.window }) {
            if entry.rejoin {
                joinSoon(pid: entry.window.pid, launched: false, createdWindowID: entry.window.windowID,
                         restoring: (others: entry.others, displayKey: origin.display))
            } else {
                workspaceStore.consumeReserved([entry.window], at: origin)
                workspaceStore.consumeRestores([entry.window], at: origin)
                armSoon()
            }
            return
        }
        var removed: [Bool] = []
        var unresolved = false
        for entry in group where !found.contains(where: { $0.window == entry.window }) {
            if let kind = await windows.removalKind(of: entry.window) { removed.append(kind) }
            else { unresolved = true }
        }
        guard !Task.isCancelled, currentWorkspaceKeys().contains(origin),
              windows.mutationContext.isCurrent(ticket, on: [origin.display], refreshSpaces: true),
              workspaceStore[origin]?.revision == record.revision else { return }
        if !removed.isEmpty || record.recoveryPending || unresolved {
            fillSoon(group, displayKey: origin.display, minimised: removed.isEmpty ? record.pendingMinimised : removed.allSatisfy { $0 },
                     baselineAt: record.recovery?.baselineAt ?? record.baselineAt, origin: origin, topology: ticket.topology,
                     expectedRevision: record.revision)
        } else if group.allSatisfy({ entry in found.contains { $0.window == entry.window } }) {
            workspaceStore[origin]?.recoveryPending = false
        }
        armSoon()
    }
}
