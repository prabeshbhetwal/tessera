import AppKit
import TesseraCore

/// Moving one window: what every command and the ring end in. Kept apart from `CommandExecutor.swift` for its line limit.
extension CommandExecutor {
    /// Moves `window` to `goal`, using the cross-display write order when the window changes display. `batch` tags the
    /// undo step (`WindowService.newBatch`).
    /// A `manual` move (a hotkey or the ring, not a Tile slot) supersedes automatic split work on the displays it
    /// touches, and takes the window out of any split it leaves.
    func place(_ window: WindowRef, current: CGRect?, goal: CGRect, batch: Int? = nil, manual: Bool = true) async -> ApplyResult {
        let original = WindowMutationScope.ticket ?? windows.mutationContext.capture()
        var ticket = original
        if manual {
            let overrides = splitWatcher.manualOverrides(window, goal: goal, ticket: original)
            let height = original.topology.primaryHeight
            var relevant = overrides
            for frame in [current, goal].compactMap({ $0 }) {
                if let key = original.topology.key(containing: CoordinateSpace.toAX(frame, primaryHeight: height)) {
                    relevant.insert(key)
                }
            }
            guard let next = windows.mutationContext.overridingLayouts(original, on: relevant) else {
                return .failed(WindowService.changedMessage)
            }
            ticket = next
            splitWatcher.explicitLayout(on: relevant, ticket: next)
            if !overrides.isEmpty { splitWatcher.relinquish(overrides, windows: [window]) }
        }
        return await WindowMutationScope.$ticket.withValue(ticket) {
            await placeScoped(window, current: current, goal: goal, batch: batch)
        }
    }

    private func placeScoped(_ window: WindowRef, current: CGRect?, goal: CGRect, batch: Int?) async -> ApplyResult {
        // Tessera's own moves must not teach a split: the watcher ignores them until they settle, and keeps watching.
        splitWatcher.beginOwnMove()
        defer { splitWatcher.endOwnMove() }
        let list = displays.displays
        let from = current.flatMap { list.display(at: CGPoint(x: $0.midX, y: $0.midY))?.id }
        let to = list.first { $0.visibleFrame.intersects(goal) }?.id
        return await windows.apply(goal, to: window, primaryHeight: DisplayService.primaryHeight,
                                   crossingDisplays: from != to, duration: model.glideSeconds, batch: batch)
    }
}
