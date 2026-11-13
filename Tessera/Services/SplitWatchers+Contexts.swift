import AppKit
import TesseraCore

extension SplitWatchers {
    func workspaceKey(_ display: String, ticket: WindowMutationContext.Ticket? = nil) -> SplitWorkspaceStore.Key {
        let snapshot = ticket ?? windows.mutationContext.capture()
        return .init(display: display, space: snapshot.workspaces[display])
    }

    func currentWorkspaceKeys() -> Set<SplitWorkspaceStore.Key> {
        let ticket = windows.mutationContext.capture()
        return Set(displays.displays.map { workspaceKey($0.id.storageKey, ticket: ticket) })
    }
    func scopedWorkspaceKeys() -> Set<SplitWorkspaceStore.Key> {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        return Set(ticket.topology.keys.map { workspaceKey($0, ticket: ticket) })
    }

    func rememberWorkspace(_ group: ManagedWindowGroup, display: DisplayContext) -> Bool {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture(), displayKey = display.id.storageKey
        guard ticket.topology.contains(display), windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { return false }
        let next = workspaceKey(displayKey, ticket: ticket)
        if let old = activeWorkspaceKeys[displayKey], old != next,
           let snapshot = watchers[displayKey]?.settledGroup, !snapshot.group.isEmpty,
           let record = workspaceStore[old] {
            workspaceStore.remember(snapshot.group, at: old, topology: record.topology, baselineAt: snapshot.at)
        }
        activeWorkspaceKeys[displayKey] = next
        watchedDisplays[displayKey] = display
        workspaceStore.remember(group, at: next, topology: ticket.topology, baselineAt: .now)
        workspaceStore[next]?.reserved.removeAll { model.settings.excludedBundleIDs.contains($0.window.bundleID ?? "") }
        workspaceStore.prune(active: currentWorkspaceKeys())
        return true
    }

    func snapshotActiveWorkspaces() {
        for (display, key) in activeWorkspaceKeys {
            guard let old = workspaceStore[key] else { continue }
            if let group = fillGroups[display], !group.isEmpty {
                workspaceStore.remember(group, at: key, topology: old.topology, baselineAt: old.baselineAt)
                workspaceStore[key]?.recoveryPending = true
            } else if let snapshot = watchers[display]?.settledGroup, !snapshot.group.isEmpty {
                workspaceStore.remember(snapshot.group, at: key, topology: old.topology, baselineAt: snapshot.at)
            }
        }
    }

    func contextsChanged(spaceNotification: Bool) {
        snapshotActiveWorkspaces()
        displays.refresh()
        let change = windows.mutationContext.consumeChanges(spaceNotification: spaceNotification)
        let ticket = windows.mutationContext.capture()
        // Two identical monitors without a UUID share a key: keep the first rather than trap.
        let current = Dictionary(displays.displays.map { ($0.id.storageKey, $0) }, uniquingKeysWith: { first, _ in first })
        var affected = Set(watchedDisplays.keys.filter { watchedDisplays[$0] != current[$0] })
        affected.formUnion(current.filter { !ticket.topology.contains($0.value) }.keys)
        if !change.topology { windows.mutationContext.invalidateLayouts(on: affected) }
        for (key, previous) in activeWorkspaceKeys where previous != workspaceKey(key, ticket: ticket) { affected.insert(key) }
        if !change.topology { affected.formUnion(change.displays) }

        if change.topology {
            startupRestore?.cancel()
            cancelPendingWork()
        } else {
            for key in affected {
                pendingFills[key]?.cancel(); pendingFills[key] = nil
                fillIDs[key] = nil; fillGroups[key] = nil
                pendingResumes[key]?.cancel(); pendingResumes[key] = nil; resumeIDs[key] = nil
            }
        }
        for key in affected { watchers[key]?.stop() }
        for key in Array(watchers.keys) where current[key] == nil { retireWatcher(key) }
        if spaceNotification || change.topology { workspaceStore.discardUnknown(on: affected.union(change.displays)) }
        for (key, display) in current {
            activeWorkspaceKeys[key] = workspaceKey(key, ticket: ticket)
            if watchedDisplays[key] != nil { watchedDisplays[key] = display }
            if change.topology, !affected.contains(key), ticket.topology.contains(display) { watchers[key]?.renewContext(ticket) }
        }
        noLearn = noLearn.filter { current[$0.display] != nil }
        let resume = change.topology ? Set(current.keys) : affected
        for key in resume {
            guard let origin = activeWorkspaceKeys[key], origin.space != nil else { continue }
            resumeWorkspace(origin)
        }
        workspaceStore.prune(active: currentWorkspaceKeys())
        reconcileTopologyWhenReady()
        armSoon(after: .seconds(1))
    }

    func trackMinimised(_ window: WindowRef, others: [WindowRef], displayKey: String, rejoin: Bool = true) {
        let key = activeWorkspaceKeys[displayKey] ?? workspaceKey(displayKey)
        workspaceStore.trackRestore(window, others: others, at: key, rejoin: rejoin)
        minimisedWindows.add(window, others: others, displayKey: displayKey)
    }

    func restoredWindow(_ window: WindowRef) {
        guard let (origin, entry) = workspaceStore.restored(window), currentWorkspaceKeys().contains(origin) else { return }
        if entry.rejoin {
            joinSoon(pid: window.pid, launched: false, createdWindowID: window.windowID,
                     restoring: (others: entry.others, displayKey: origin.display))
        } else {
            workspaceStore.consumeReserved([window], at: origin)
            workspaceStore.consumeRestores([window], at: origin)
            if workspaceStore[origin]?.recoveryPending == true { resumeWorkspace(origin) }
            else { armSoon() }
        }
    }

    func reserveMembers(_ refs: [WindowRef], on displayKey: String, minimised: Bool) async {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        let key = activeWorkspaceKeys[displayKey] ?? workspaceKey(displayKey, ticket: ticket)
        guard let record = workspaceStore[key] else { return }
        var entries = record.frames(in: ticket.topology).filter { refs.contains($0.window) }
        for index in entries.indices {
            if let frame = await windows.placement(of: entries[index].window, after: record.baselineAt,
                                                   primaryHeight: ticket.topology.primaryHeight) { entries[index].frame = frame }
        }
        guard !Task.isCancelled, windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true),
              workspaceStore[key]?.revision == record.revision else { return }
        workspaceStore.reserve(entries, at: key)
        if minimised {
            let others = record.members.map(\.window).filter { !refs.contains($0) }
            for ref in refs { trackMinimised(ref, others: others, displayKey: displayKey, rejoin: false) }
        }
    }

    func recoveredWorkspace(_ group: ManagedWindowGroup, displayKey: String) {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture(), key = workspaceKey(displayKey, ticket: ticket)
        guard windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { return }
        workspaceStore.remember(group, at: key, topology: ticket.topology, baselineAt: .now)
        workspaceStore[key]?.recoveryPending = false
        workspaceStore[key]?.recovery = nil
        workspaceStore[key]?.retryAfter = nil
    }

    func consumeJoinContext(_ joined: [WindowRef], displayKey: String) {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        guard windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { return }
        let key = workspaceKey(displayKey, ticket: ticket)
        for window in joined {
            if let bundle = window.bundleID { workspaceStore[key]?.closedOutOf[bundle] = nil }
        }
        workspaceStore.consumeRestores(joined, at: key)
        workspaceStore[key]?.recoveryPending = false
        workspaceStore[key]?.recovery = nil
        workspaceStore[key]?.retryAfter = nil
    }

    func unhiddenApp(_ pid: pid_t) {
        unhidden[pid] = Date()
        for (key, record) in workspaceStore.records where currentWorkspaceKeys().contains(key)
            && record.recoveryPending && record.members.contains(where: { $0.window.pid == pid }) {
            workspaceStore[key]?.retryAfter = nil
            resumeWorkspace(key)
        }
        armSoon()
    }
}
