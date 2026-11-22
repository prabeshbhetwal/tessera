import AppKit
import TesseraCore

/// One look of `joinSoon` at every display, and the move it leads to. Kept apart from `SplitWatchers+Join.swift` for
/// its line limit.
extension SplitWatchers {
    /// `.tiled` once a group was tiled, or the setting went off. `holds` leaves a window whose group has no learned split
    /// untiled and answers `.held` with it (see `splitNewWindowWait`); a hold anywhere wins, so it is looked at again.
    /// `waiting` (after the wait) tiles only where a window that waited (`now`) is still open, and leaves out any window
    /// the app opened since (not in `allowed`), answering `.held` with those so they wait their own turn. The string
    /// says why nothing was tiled, for the decision log.
    func join(_ request: JoinRequest) async -> (JoinLook, String) {
        let settings = model.settings, pid = request.pid
        guard settings.learnSplits, settings.splitTilesNewWindow || request.restoringMinimised else { return (.stopped, "settingOff") }
        guard Permissions.isAccessibilityTrusted else { return (.stopped, "noAccessibility") }
        guard ownMoves == 0 else { return (.notFound, "tesseraMoving") }
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        let startsHere = request.startsGroups && settings.splitNewWindowScope != .tiledDisplays
        var done = false, held: [WindowRef] = [], reason = "noWindowYet", settleOnly = true
        for display in displays.displays {
            let key = display.id.storageKey
            if let only = request.displaysOnly, !only.contains(key) { continue }
            // The event's own Space: a look never follows the user to another one.
            guard ticket.topology.contains(display), windows.mutationContext.isCurrent(ticket, on: [key], refreshSpaces: true),
                  request.origin.workspaces[key] == ticket.workspaces[key] else { reason = "spaceChanged"; continue }
            // A Tile, a placement or a hand change since the event is the newer word on this display.
            guard request.origin.layoutEpochs[key, default: 0] == ticket.layoutEpochs[key, default: 0] else {
                reason = "newerLayout"; continue
            }
            // A recovery moves this display's own windows: joining now would have both move them.
            guard pendingFills[key] == nil, pendingResumes[key] == nil else { reason = "recoveryRunning"; continue }
            let group = request.groups[key] ?? []
            guard !group.isEmpty || startsHere else { continue }
            // With no group here the newcomer often opens over the only other window: keep covered windows in the read.
            let read = await windows.visibleWindowsCounted(
                on: display.frame, primaryHeight: ticket.topology.primaryHeight, excluding: Set(settings.excludedBundleIDs),
                retaining: group, includingNewWindowsOf: pid, existingWindowIDs: request.existing,
                keepingCoveredByNewcomer: group.isEmpty, patient: true)
            guard !Task.isCancelled, ownMoves == 0 else { return (.notFound, "tesseraMoving") }
            guard windows.mutationContext.isCurrent(ticket, on: [key], refreshSpaces: true),
                  displays.displays.contains(display) else { reason = "spaceChanged"; continue }
            guard pendingFills[key] == nil, pendingResumes[key] == nil else { reason = "recoveryRunning"; continue }
            // An app on this display that did not answer in time has windows this look cannot see: decide on a full
            // list. The last retry goes ahead with what it has rather than leave the window untiled for a hung app.
            guard read.skipped == 0 || request.lastAttempt else { reason = "appNotAnswering"; continue }
            // A group starts on a partial read only where no unread app's window lies over the windows to be tiled.
            if read.skipped > 0, group.isEmpty, read.found.contains(where: { entry in read.unread.contains { $0.intersects(entry.frame) } }) {
                reason = "appNotAnswering"; continue
            }
            var found = read.found
            // A window that can't zoom (Finder's Copy progress) can't take a column's height and is usually gone in
            // seconds: tiling it in would only squeeze the group, then leave a gap when it closes. System Settings zooms.
            found.removeAll { AX.element($0.window.element, kAXZoomButtonAttribute).flatMap { AX.bool($0, kAXEnabledAttribute) } == false }
            let known = request.known[key] ?? []
            var joined = found.filter { $0.window.pid == pid && !known.contains($0.window)
                && !($0.window.windowID.map { request.existing.contains($0) } ?? false) }
            if let waiting = request.waiting, !joined.isEmpty {
                let newcomers = joined.map(\.window).filter { !waiting.allowed.contains($0) }
                held += newcomers
                guard joined.contains(where: { waiting.now.contains($0.window) }) else { continue }
                found.removeAll { newcomers.contains($0.window) }
                joined.removeAll { newcomers.contains($0.window) }
            }
            let members = group.filter { window in !joined.contains { $0.window == window } }
            let present = members.filter { window in found.contains { $0.window == window } }
            let ordered = onScreenOrder(found, portrait: display.range.isPortrait)
            let learned = settings.learnedFrames(for: ordered, display: display)
            let facts = JoinFacts(
                scope: settings.splitNewWindowScope, startsGroups: request.startsGroups, watched: members.count,
                present: present.count, found: found.count, joined: joined.count,
                apps: Set(found.map { $0.window.bundleID ?? "pid \($0.window.pid)" }).count, maxColumns: display.range.maxCols,
                freshApp: request.freshApp, restored: request.restored, hasLearnedSplit: learned != nil, holds: request.holds)
            switch JoinDecision.decide(facts) {
            case .skip(let why): reason = why.rawValue
            case .hold: held += joined.map(\.window); settleOnly = false
            // A first sighting on a display with no group waits a moment: a splash or sign-in window is gone by then.
            case .tile where members.isEmpty && request.settles: held += joined.map(\.window)
            case .tile:
                let goals = learned ?? GridGeometry.tiles(ordered.count, display: display)
                if await tileIn(ordered, goals: goals, joined: joined, display: display, usedSplit: learned != nil,
                                restored: request.restored, settings: settings) { done = true } else { reason = "moveRefused" }
            }
        }
        if !held.isEmpty { return (.held(held), settleOnly ? "settle" : "wait") }
        return (done ? .tiled : .notFound, done ? "tiled" : reason)
    }

    private func tileIn(_ ordered: [(window: WindowRef, frame: CGRect)], goals: [CGRect],
                        joined: [(window: WindowRef, frame: CGRect)], display: DisplayContext, usedSplit: Bool,
                        restored: Bool, settings: TesseraSettings) async -> Bool {
        let ticket = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        guard windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
              ticket.topology.contains(display), displays.displays.contains(display) else { return false }
        let moves = ordered.indices.filter { !CommandExecutor.sameFrame(ordered[$0].frame, goals[$0]) }
        // Already in its place (an app reopening a window where it was last tiled): nothing moves, so no move's end
        // re-arms the watchers. Re-arm here, or the group is watched without it and its close leaves a gap.
        guard !moves.isEmpty else {
            watch(ordered, display: display)
            consumeJoinContext(joined.map(\.window), displayKey: display.id.storageKey)
            armSoon(after: .zero)
            return true
        }

        beginOwnMove()
        // The whole group, so the windows beside one that lands short of its goal (System Settings is a fixed width)
        // follow its real edge instead of leaving a hole beside it.
        // A window still loading can refuse its first move: it is asked again in the same undo step rather than left
        // floating over the group that just made room for it.
        let newcomers = Set(ordered.indices.filter { index in joined.contains { $0.window == ordered[index].window } })
        let (landed, undoMarker) = await windows.moveTogether(
            ordered.indices.map { (window: ordered[$0].window, goal: goals[$0]) },
            primaryHeight: ticket.topology.primaryHeight, duration: model.glideSeconds, gap: display.profile.gap,
            retrying: newcomers, undoingIfRefused: ordered.map(\.frame))
        // Watched only once the newcomer is in, and Undo has not taken the move back meanwhile: a group that went back
        // must not be watched at its goals.
        let undone = windows.mutationContext.capture().layoutEpochs[display.id.storageKey, default: 0]
            != ticket.layoutEpochs[display.id.storageKey, default: 0]
        let accepted = !undone && newcomers.allSatisfy { !moves.contains($0) || landed[$0] != nil }
        if accepted { watch(Array(zip(ordered.map(\.window), goals)), display: display) }
        endOwnMove()  // re-arms the watchers, which then watch the new group
        guard !Task.isCancelled, windows.mutationContext.isCurrent(ticket, on: [display.id.storageKey], refreshSpaces: true),
              displays.displays.contains(display) else { return false }

        var finals = ordered
        for (index, frame) in landed.enumerated() { if let frame { finals[index].frame = frame } }
        let exact = moves.filter { index in landed[index].map { CommandExecutor.sameFrame($0, goals[index]) } ?? false }
        if watchers[display.id.storageKey]?.watches(finals) == true {
            watch(finals, display: display)
        }
        // Only a join every moving window accepted uses up the reopen context; a refusal leaves it for a retry.
        if moves.allSatisfy({ landed[$0] != nil }) {
            consumeJoinContext(joined.map(\.window), displayKey: display.id.storageKey)
        }
        // The newcomer never landed: the rest went back in the same undo step, and the look tries again later.
        guard accepted, moves.contains(where: { landed[$0] != nil }) else { return false }
        let kind: HelpEventKind = if exact.count < moves.count {
            .tilePartial(moved: exact.count, total: moves.count,
                         stuck: moves.filter { !exact.contains($0) }.map { HelpEvent.appName(ordered[$0].window) })
        } else {
            .windowJoined(joined: joined.map { HelpEvent.appName($0.window) }, usedSplit: usedSplit, restored: restored)
        }
        let split = usedSplit ? SplitMemory.lookup(SplitKey(ordered, on: display), in: settings.learnedSplits) : nil
        onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                           group: onScreenOrder(finals, portrait: display.range.isPortrait), split: split,
                           previous: nil, undoMarker: undoMarker))
        return true
    }
}
