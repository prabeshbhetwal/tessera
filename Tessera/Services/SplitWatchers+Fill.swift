import AppKit
import TesseraCore

/// A window closing in a side-by-side group leaves no hole (`splitFillsClosedGap`): the apps left go back to their
/// learned split on that display when there is one, otherwise the most recently used window beside the space grows
/// into it (`SplitFill`). One ⌃⌥Z puts them back.
extension SplitWatchers {
    /// Waits for the window list to drop the closed window, then fills its space; re-arms the watchers either way.
    /// Each display fills on its own, so an app quitting with windows on two displays fills both. A `minimised` window
    /// left the same way (`minimiseFillsGap`); only the help message differs.
    func fillSoon(_ group: ManagedWindowGroup, displayKey: String, minimised: Bool = false,
                  baselineAt: ContinuousClock.Instant = .now, origin: SplitWorkspaceStore.Key? = nil,
                  topology: WindowTopology? = nil, expectedRevision: UInt64? = nil) {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        let origin = origin ?? activeWorkspaceKeys[displayKey] ?? workspaceKey(displayKey, ticket: ticket)
        guard !Task.isCancelled, windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { return }
        if let expectedRevision, workspaceStore[origin]?.revision != expectedRevision { return }
        if let previous = workspaceStore[origin], baselineAt < previous.baselineAt,
           !(expectedRevision != nil && previous.recovery?.baselineAt == baselineAt) { return }
        let sourceTopology = topology ?? workspaceStore[origin]?.topology ?? ticket.topology
        if workspaceStore[origin]?.recovery == nil { workspaceStore[origin]?.recoveryRetries = 0 }
        let reserved = workspaceStore[origin].map { $0.project($0.reserved, into: sourceTopology) } ?? []
        let unresolved = workspaceStore[origin]?.recovery?.frames(in: sourceTopology) ?? []
        var merged = group
        for entry in reserved + unresolved where !merged.contains(where: { $0.window == entry.window }) { merged.append(entry) }
        workspaceStore.remember(merged, at: origin, topology: sourceTopology, baselineAt: baselineAt)
        workspaceStore[origin]?.recoveryPending = true
        workspaceStore[origin]?.recovery = .init(group: merged, topology: sourceTopology, baselineAt: baselineAt, minimised: minimised)
        workspaceStore[origin]?.pendingMinimised = minimised
        guard currentWorkspaceKeys().contains(origin),
              windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { return }
        let rebased = workspaceStore[origin]!.frames(in: ticket.topology)
        pendingFills[displayKey]?.cancel()
        let fillID = UUID()
        fillIDs[displayKey] = fillID
        fillGroups[displayKey] = merged
        lifecycleLog.notice("Recovery started: \(fillID.uuidString, privacy: .public), members \(group.count), minimised \(minimised)")
        pendingFills[displayKey] = Task { [weak self] in
            var outcome = "timedOut"
            defer {
                self?.lifecycleLog.notice("Recovery finished: \(fillID.uuidString, privacy: .public), outcome \(Task.isCancelled ? "cancelled" : outcome, privacy: .public)")
                if self?.fillIDs[displayKey] == fillID {
                    if !Task.isCancelled, outcome != "recovered" {
                        self?.workspaceStore[origin]?.retryAfter = .now + .seconds(5)
                    }
                    self?.pendingFills[displayKey] = nil
                    self?.fillIDs[displayKey] = nil
                    self?.fillGroups[displayKey] = nil
                }
            }
            await WindowMutationScope.$ticket.withValue(ticket) {
                var group = rebased
                // Window and AX lists can lag a process exit. Retry for up to ten seconds with a bounded backoff. Waiting for
                // another fill's glide (slow snap speeds take seconds) doesn't use them up; `busy` only caps a stuck count.
                var (looks, busy) = (0, 0)
                while looks < 12, busy < 100 {
                    do { try await Task.sleep(for: looks < 3 ? SplitWatcher.settle : .seconds(1)) } catch { return }
                    guard let self else { return }
                    switch await self.fill(group, displayKey: displayKey, minimised: minimised, baselineAt: baselineAt) {
                    case .moved(let finals):
                        outcome = "recovered"
                        self.fillGroups[displayKey] = finals
                        // The watch ended with the close, so a window closed during the glide went unseen: look once more.
                        (group, looks) = (finals, 11)
                    case .constrained(let finals):
                        outcome = "constrained"
                        self.fillGroups[displayKey] = finals
                        (group, looks) = (finals, 11)
                    case .partial(let finals):
                        outcome = "partial"
                        self.fillGroups[displayKey] = finals
                        looks = 12
                    case .suspended:
                        outcome = "suspended"
                        self.fillGroups[displayKey] = []
                        looks = 12
                    case .busy: busy += 1
                    case .notYet: looks += 1
                    case .skipped:
                        if outcome != "recovered" && outcome != "constrained" { outcome = "skipped" }
                        looks = 12
                    }
                }
                if busy >= 100, outcome != "recovered" { outcome = "busyTimeout" }
                self?.armSoon(after: .zero)
            }
        }
    }

    enum FillOutcome {
        /// The windows left, where they ended up.
        case moved([(window: WindowRef, frame: CGRect)])
        case constrained(ManagedWindowGroup), partial(ManagedWindowGroup)
        case busy, notYet, skipped, suspended
    }

    /// `.busy` while Tessera is moving windows; `.notYet` while no window of `group` has left the window list;
    /// `.skipped` when the setting is off, a window joined or wandered onto the display since, or nothing beside the
    /// space can cover it.
    private func fill(_ initialGroup: ManagedWindowGroup, displayKey: String, minimised: Bool, baselineAt: ContinuousClock.Instant) async
        -> FillOutcome {
        let settings = model.settings
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        let origin = workspaceKey(displayKey, ticket: ticket)
        var revision = workspaceStore[origin]?.revision
        let reserved = workspaceStore[origin].map { $0.project($0.reserved, into: ticket.topology) } ?? []
        let group = initialGroup + reserved.filter { entry in !initialGroup.contains { $0.window == entry.window } }
        guard windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true) else { return .skipped }
        guard settings.learnSplits, settings.splitFillsClosedGap, !group.isEmpty,
              let display = displays.displays.first(where: { $0.id.storageKey == displayKey }) else {
            workspaceStore[origin]?.recoveryPending = false
            return .skipped
        }
        guard ticket.topology.contains(display) else { return .notYet }
        guard !group.contains(where: { settings.excludedBundleIDs.contains($0.window.bundleID ?? "") }) else { return .skipped }
        guard ownMoves == 0 else { return .busy }
        // Front-most first, so the most recently used window comes first.
        let left = await windows.visibleWindows(on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                                                excluding: Set(settings.excludedBundleIDs), retaining: group.map(\.window))
        let absent = group.filter { entry in !left.contains { $0.window == entry.window } }
        var closed: [(window: WindowRef, frame: CGRect)] = []
        var miniRefs: [WindowRef] = []
        var protected: ManagedWindowGroup = []
        var protectedMinis: [WindowRef] = []
        var closedRefs: [WindowRef] = []
        for entry in absent {
            let removal = await windows.removalKind(of: entry.window)
            guard !Task.isCancelled, windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true), layoutSettingsMatch(settings, on: displayKey),
                  displays.displays.first(where: { $0.id.storageKey == displayKey }) == display else { return .notYet }
            if let removal {
                if removal, !settings.minimiseFillsGap { protected.append(entry); protectedMinis.append(entry.window) }
                else if !removal, settings.splitOnCloseKeepsRunning == .leaveSpace,
                        NSRunningApplication(processIdentifier: entry.window.pid)?.isTerminated == false {
                    protected.append(entry); closedRefs.append(entry.window)
                } else {
                    closed.append(entry)
                    if removal { miniRefs.append(entry.window) } else { closedRefs.append(entry.window) }
                }
            }
            else {
                // Losing an AX response is not a removal; wait before taking this member's space.
                if NSRunningApplication(processIdentifier: entry.window.pid)?.isHidden == true { protected.append(entry); continue }
                let frame = await windows.frame(of: entry.window)
                guard !Task.isCancelled, windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true), layoutSettingsMatch(settings, on: displayKey),
                      displays.displays.first(where: { $0.id.storageKey == displayKey }) == display else { return .notYet }
                if let frame, !display.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) { return .skipped }
                return .notYet
            }
        }
        for index in closed.indices {
            if let latest = await windows.placement(of: closed[index].window, after: baselineAt,
                                                    primaryHeight: ticket.topology.primaryHeight) {
                closed[index].frame = latest
            }
        }
        for index in protected.indices {
            if let latest = await windows.placement(of: protected[index].window, after: baselineAt,
                                                    primaryHeight: ticket.topology.primaryHeight) { protected[index].frame = latest }
        }
        guard !Task.isCancelled, ownMoves == 0 else { return .busy }
        // Revalidate after the last AX await, before policy-dependent exits as well as moves.
        guard windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true), layoutSettingsMatch(settings, on: displayKey),
              displays.displays.first(where: { $0.id.storageKey == displayKey }) == display,
              workspaceStore[origin]?.revision == revision else { return .notYet }
        workspaceStore.reserve(protected, at: origin)
        for ref in protectedMinis { trackMinimised(ref, others: left.map(\.window), displayKey: displayKey, rejoin: false) }
        for ref in closedRefs where !left.isEmpty {
            if let bundle = ref.bundleID { closedOutOf[bundle, default: [:]][displayKey] = left.map(\.window) }
        }
        guard !closed.isEmpty else {
            if !protected.isEmpty { recoveredWorkspace(left, displayKey: displayKey); return .skipped }
            return .notYet
        }
        if left.isEmpty {
            if protected.isEmpty { recoveredWorkspace([], displayKey: displayKey); return .skipped }
            workspaceStore.remember([], at: origin, topology: ticket.topology, baselineAt: .now)
            workspaceStore[origin]?.recoveryPending = true
            return .suspended
        }
        guard left.allSatisfy({ entry in group.contains { $0.window == entry.window } }) else {
            lifecycleLog.notice("Window recovery skipped: unrelated exposed window")
            return .skipped
        }

        var goals = left.map(\.frame)
        let learned = protected.isEmpty ? settings.learnedFrames(for: left, display: display) : nil
        if let learned {
            goals = learned
        } else if let filled = SplitFill.frames(filling: closed.map(\.frame), frames: goals + protected.map(\.frame), gap: display.profile.gap) {
            goals = Array(filled.prefix(left.count))
        }
        let moves = left.indices.filter { !CommandExecutor.sameFrame(left[$0].frame, goals[$0]) }
        // A minimised window waits to be tiled back in beside the windows left (a closed one can't be watched, so
        // `add` skips it). Taken from what left, not from the event, so one minimised while the watch was down counts.
        if settings.minimiseFillsGap {
            for entry in closed where miniRefs.contains(entry.window) {
                trackMinimised(entry.window, others: left.map(\.window), displayKey: displayKey)
            }
        }
        revision = workspaceStore[origin]?.revision
        if moves.isEmpty {
            workspaceStore.consumeReserved(closed.map(\.window), at: origin)
            recoveredWorkspace(left, displayKey: displayKey)
            watch(left, display: display)
            for entry in closed where !miniRefs.contains(entry.window) {
                if let bundle = entry.window.bundleID { closedOutOf[bundle, default: [:]][displayKey] = left.map(\.window) }
            }
            return .skipped
        }

        beginOwnMove()
        // The whole group, so a window beside one that lands short of its goal (a fixed-size app) can follow it.
        let (landed, undoMarker) = await windows.moveTogether(
            left.indices.map { (window: left[$0].window, goal: goals[$0]) }, primaryHeight: ticket.topology.primaryHeight,
            duration: model.glideSeconds, gap: display.profile.gap)
        endOwnMove()  // re-arms the watchers from where the windows ended up

        guard windows.mutationContext.isCurrent(ticket, on: [displayKey], refreshSpaces: true), !Task.isCancelled,
              layoutSettingsMatch(settings, on: displayKey), workspaceStore[origin]?.revision == revision else { return .skipped }
        var finals = left
        for (index, frame) in landed.enumerated() { if let frame { finals[index].frame = frame } }
        let grew = moves.filter { landed[$0] != nil }.map { HelpEvent.appName(left[$0].window) }
        guard !Task.isCancelled else { return .skipped }
        // A refusal keeps the vacancy on record, so a later event can try again; only a full fill consumes it.
        let refused = moves.contains { landed[$0] == nil }
        if refused {
            workspaceStore.remember(finals, at: origin, topology: ticket.topology, baselineAt: .now)
            workspaceStore[origin]?.recoveryPending = true
        } else {
            workspaceStore.consumeReserved(closed.map(\.window), at: origin)
            recoveredWorkspace(finals, displayKey: displayKey)
        }
        watch(finals, display: display)
        if !minimised {
            for case let bundleID? in closed.filter({ !miniRefs.contains($0.window) }).map(\.window.bundleID) {
                closedOutOf[bundleID, default: [:]][displayKey] = left.map(\.window)
            }
        }
        let exact = moves.map { ($0, landed[$0]) }.filter { index, frame in frame.map { CommandExecutor.sameFrame($0, goals[index]) } ?? false }
        let kind: HelpEventKind = if exact.count == moves.count {
            .gapFilled(closed: closed.map { HelpEvent.appName($0.window) }, filled: grew,
                       usedSplit: learned != nil, minimised: minimised)
        } else {
            .tilePartial(moved: exact.count, total: moves.count,
                         stuck: moves.map { ($0, landed[$0]) }.filter { index, frame in !(frame.map { CommandExecutor.sameFrame($0, goals[index]) } ?? false) }
                            .map { HelpEvent.appName(left[$0.0].window) })
        }
        let split = learned == nil ? nil : SplitMemory.lookup(SplitKey(left, on: display), in: settings.learnedSplits)
        onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                           group: onScreenOrder(finals, portrait: display.range.isPortrait), split: split,
                           previous: nil, undoMarker: undoMarker))
        if refused { return .partial(finals) }
        return exact.count == moves.count ? .moved(finals) : .constrained(finals)
    }
}

extension TesseraSettings {
    /// The frames the learned split for these windows' apps on `display` gives them, in input order; nil when there is
    /// no split for them or it doesn't fit.
    func learnedFrames(for windows: [(window: WindowRef, frame: CGRect)], display: DisplayContext) -> [CGRect]? {
        guard let split = SplitMemory.lookup(SplitKey(windows, on: display), in: learnedSplits) else { return nil }
        return SplitApplier.frames(
            for: split, windows: windows.map { (bundleID: $0.window.bundleID, frame: $0.frame) },
            usable: GridGeometry.usableFrame(display.visibleFrame, profile: display.profile),
            portrait: display.range.isPortrait, restoresOrder: splitRestoresOrder, gapPlacement: splitGapPlacement)
    }
}
