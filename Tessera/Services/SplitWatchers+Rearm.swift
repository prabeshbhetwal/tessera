import AppKit
import TesseraCore

extension SplitWatchers {
    func readAndArm(_ display: DisplayContext) async {
        guard pendingResumes[display.id.storageKey] == nil else { return }
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        guard ticket.topology.contains(display) else { return }
        let origin = workspaceKey(display.id.storageKey, ticket: ticket)
        if pendingFills[origin.display] == nil, let record = workspaceStore[origin], record.recoveryPending {
            if record.retryAfter.map({ $0 <= .now }) ?? true { resumeWorkspace(origin) }
            return
        }
        let current = watchers[display.id.storageKey]
        let revision = current?.revision
        let found = await windows.visibleWindows(on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                                                excluding: Set(model.settings.excludedBundleIDs))
        guard !Task.isCancelled, watchers[display.id.storageKey] === current,
              current?.revision == revision, displays.displays.contains(display),
              windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true) else { return }
        await arm(found, on: display)
    }

    /// Reconciles one display snapshot before replacing its managed window group.
    func arm(_ found: [(window: WindowRef, frame: CGRect)], on display: DisplayContext) async {
        // A Tessera move began while reading: its end arms again from settled frames.
        guard !Task.isCancelled, ownMoves == 0 else { return }
        guard pendingFills[display.id.storageKey] == nil, pendingResumes[display.id.storageKey] == nil else { return }
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        guard ticket.topology.contains(display), windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true) else { return }
        let current = watchers[display.id.storageKey]
        let revision = current?.revision
        let key = SplitKey(found, on: display)
        if let current {
            let missing = current.watched.filter { window in !found.contains { $0.window == window } }
            if missing.isEmpty { missingAttempts[display.id.storageKey] = nil }
            var removed: [Bool] = []
            var protectedMinimised: [WindowRef] = []
            for window in missing {
                if model.settings.excludedBundleIDs.contains(window.bundleID ?? "") { continue }
                if let kind = await windows.removalKind(of: window) {
                    if kind, !model.settings.minimiseFillsGap { protectedMinimised.append(window) }
                    else { removed.append(kind) }
                }
            }
            guard !Task.isCancelled, ownMoves == 0, current.revision == revision,
                  windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true) else { return }
            if !protectedMinimised.isEmpty { await reserveMembers(protectedMinimised, on: display.id.storageKey, minimised: true) }
            let hiddenMembers = missing.filter { NSRunningApplication(processIdentifier: $0.pid)?.isHidden == true }
            if !hiddenMembers.isEmpty { await reserveMembers(hiddenMembers, on: display.id.storageKey, minimised: false) }
            guard !Task.isCancelled, current.revision == revision else { return }
            if !removed.isEmpty {
                lifecycleLog.notice("Reconciled window removal during re-arm")
                current.closed(minimised: removed.allSatisfy { $0 })
                return
            }
            let hidden = missing.allSatisfy { NSRunningApplication(processIdentifier: $0.pid)?.isHidden == true }
            if !missing.isEmpty, !hidden {
                var unresolved = false
                for window in missing where NSRunningApplication(processIdentifier: window.pid)?.isHidden != true {
                    if model.settings.excludedBundleIDs.contains(window.bundleID ?? "") { continue }
                    if protectedMinimised.contains(window) { continue }
                    // A verified move onto another display detaches a member. An unavailable AX response does not.
                    if let frame = await windows.frame(of: window),
                       !display.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) { continue }
                    unresolved = true
                }
                guard !Task.isCancelled, ownMoves == 0, current.revision == revision,
                  windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true) else { return }
                if unresolved {
                    if missingAttempts[display.id.storageKey, default: 0] < 3 {
                        missingAttempts[display.id.storageKey, default: 0] += 1
                        armSoon(after: .milliseconds(200))
                    }
                    // Fast retries may end; ownership must survive until a removal or departure is confirmed.
                    // The identity timer and Workspace termination handler continue from this same group.
                    return
                }
            }
        }
        // Same windows, or a hand adjustment mid-way (a drag can overlap windows for a moment): leave it be.
        if current?.watches(found) == true || current?.isBusy == true { return }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let frames = found.map { (bundleID: $0.window.bundleID, frame: $0.frame) }
        guard found.count > 1, case .success = SplitLearner.learn(frames, usable: usable, gap: display.profile.gap)
        else {
            current?.stop()  // stacked or a lone window: nothing to reflow
            return
        }
        missingAttempts[display.id.storageKey] = nil
        watch(found, display: display, learns: !noLearn.contains(key))
    }
}
