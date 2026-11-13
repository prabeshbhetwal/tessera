import AppKit
import TesseraCore

/// Keeping the watched group's baseline and mutation context current, reading the group back, and moving its
/// neighbours after a hand adjustment. Kept apart from `SplitWatcher.swift` for its line limit.
extension SplitWatcher {
    /// Updates a known group without a gap in its close/minimise subscriptions.
    func updateBaseline(_ group: [(window: WindowRef, frame: CGRect)], learns: Bool) {
        cancelAdjustment()
        self.learns = learns
        baseline = group
        watchContext = WindowMutationScope.ticket ?? windows.mutationContext.capture()
    }

    func renewContext(_ ticket: WindowMutationContext.Ticket) {
        cancelAdjustment()
        watchContext = ticket
        refreshBaseline()
    }
    func acceptHandContext(_ ticket: WindowMutationContext.Ticket) { watchContext = ticket }

    /// Discards pre-command learning work without dropping lifecycle subscriptions.
    func cancelAdjustment() {
        generation += 1
        pending?.cancel()
        pending = nil
        adjusting = false
        byHand = false
    }

    /// The watched display as it is now (so a gap or padding edited since the watch began counts) and the windows on
    /// it; nil when the display is gone or its windows are no longer the watched group.
    func currentGroup() async -> (display: DisplayContext, visible: [(window: WindowRef, frame: CGRect)])? {
        guard let key, let ticket = watchContext,
              windows.mutationContext.isCurrent(ticket, on: [key.display], refreshSpaces: true),
              let display = displays.displays.first(where: { $0.id.storageKey == key.display }), ticket.topology.contains(display) else { return nil }
        let visible = await windows.visibleWindows(on: display.frame, primaryHeight: ticket.topology.primaryHeight,
                                                   excluding: Set(model.settings.excludedBundleIDs))
        guard windows.mutationContext.isCurrent(ticket, on: [key.display], refreshSpaces: true) else { return nil }
        guard SplitKey(visible, on: display) == key, watches(visible) else { return nil }
        return (display: display, visible: visible)
    }

    /// When the person has changed exactly one window since `baseline`, moves the windows beside it to follow its new
    /// edges (`SplitReflow`) as one undo step, and makes where they landed the baseline: the next pass then sees no
    /// change (so it learns, even if an app refused its size) unless the person adjusts again. True when it moved them,
    /// or when a mouse button is still down (a drag held still); either way the caller tries again later.
    func reflow(_ visible: [(window: WindowRef, frame: CGRect)], display: DisplayContext) async -> Bool {
        let before = visible.compactMap { entry in baseline.first { $0.window == entry.window }?.frame }
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        guard model.settings.splitReflowsNeighbours, baseline.count == visible.count, before.count == visible.count,
              let goals = SplitReflow.frames(before: before, after: visible.map(\.frame), usable: usable,
                                             gap: display.profile.gap) else { return false }
        // Mid-drag: following a still-moving edge would leave the neighbours behind; the adjustment still waits.
        guard NSEvent.pressedMouseButtons == 0 else { adjusting = true; return true }
        let moves = visible.indices.filter { visible[$0].frame != goals[$0] }.map { (index: $0, window: visible[$0].window) }
        let generation = self.generation
        onReflowBegan?()
        defer { onReflowEnded?() }
        let (results, undoMarker) = await windows.moveTogether(  // one ⌃⌥Z puts the neighbours back
            moves.map { (window: $0.window, goal: goals[$0.index]) }, primaryHeight: DisplayService.primaryHeight,
            duration: model.glideSeconds)
        var landed: [Int: CGRect] = [:]
        for (move, frame) in zip(moves, results) { landed[move.index] = frame }
        if generation == self.generation {
            let finals = visible.indices.map { (window: visible[$0].window, frame: landed[$0] ?? visible[$0].frame) }
            baseline = finals
            let moved = Set(moves.map(\.index))
            let changedIndex = visible.indices.first {
                !moved.contains($0) && !CommandExecutor.sameFrame(visible[$0].frame, before[$0])
            }
            let followed = moves.filter { landed[$0.index] != nil }  // a follower whose app refused didn't follow
            if !followed.isEmpty, let changedIndex {
                let kind = HelpEventKind.neighboursFollowed(
                    changed: HelpEvent.appName(visible[changedIndex].window),
                    followers: followed.map { HelpEvent.appName($0.window) })
                onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                                   group: onScreenOrder(finals, portrait: display.range.isPortrait),
                                   split: nil, previous: nil, undoMarker: undoMarker))
            }
        }
        return true
    }
}
