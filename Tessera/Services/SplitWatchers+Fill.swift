import AppKit
import TesseraCore

/// A window closing in a side-by-side group leaves no hole (`splitFillsClosedGap`): the apps left go back to their
/// learned split on that display when there is one, otherwise the most recently used window beside the space grows
/// into it (`SplitFill`). One ⌃⌥Z puts them back.
extension SplitWatchers {
    /// Waits for the window list to drop the closed window, then fills its space; re-arms the watchers either way.
    /// Each display fills on its own, so an app quitting with windows on two displays fills both.
    func fillSoon(_ group: [(window: WindowRef, frame: CGRect)], displayKey: String) {
        pendingFills[displayKey]?.cancel()
        pendingFills[displayKey] = Task { [weak self] in
            // A few tries: the window list can lag the close, and another display's fill may be moving windows.
            for _ in 0..<3 {
                do { try await Task.sleep(for: SplitWatcher.settle) } catch { return }
                guard let self else { return }
                switch await self.fill(group, displayKey: displayKey) {
                case .moved: return  // the moves' end re-arms
                case .later: continue
                case .skipped: break
                }
                break
            }
            self?.armSoon(after: .zero)
        }
    }

    enum FillOutcome { case moved, later, skipped }

    /// `.later` while Tessera is moving windows or the closed window is still listed; `.skipped` when the setting is
    /// off, a window joined or wandered onto the display since, or nothing beside the space can cover it.
    private func fill(_ group: [(window: WindowRef, frame: CGRect)], displayKey: String) async -> FillOutcome {
        let settings = model.settings
        guard settings.learnSplits, settings.splitFillsClosedGap, group.count > 1,
              let display = displays.displays.first(where: { $0.id.storageKey == displayKey }) else { return .skipped }
        guard ownMoves == 0 else { return .later }
        // Front-most first, so the most recently used window comes first.
        let left = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                excluding: Set(settings.excludedBundleIDs))
        let closed = group.filter { entry in !left.contains { $0.window == entry.window } }
        guard !Task.isCancelled, ownMoves == 0, !closed.isEmpty else { return .later }
        guard !left.isEmpty, left.allSatisfy({ entry in group.contains { $0.window == entry.window } })
        else { return .skipped }

        var goals = left.map(\.frame)
        let learned = settings.learnedFrames(for: left, display: display)
        if let learned {
            goals = learned
        } else {
            for hole in closed.map(\.frame) {
                if let next = SplitFill.frames(filling: hole, frames: goals, gap: display.profile.gap) { goals = next }
            }
        }
        let moves = left.indices.filter { !CommandExecutor.sameFrame(left[$0].frame, goals[$0]) }
        guard !moves.isEmpty else { return .skipped }

        beginOwnMove()
        let (landed, undoMarker) = await windows.moveTogether(
            moves.map { (window: left[$0].window, goal: goals[$0]) }, primaryHeight: DisplayService.primaryHeight,
            duration: model.glideSeconds)
        endOwnMove()  // re-arms the watchers from where the windows ended up

        var finals = left
        for (index, frame) in zip(moves, landed) { if let frame { finals[index].frame = frame } }
        let grew = zip(moves, landed).filter { $0.1 != nil }.map { HelpEvent.appName(left[$0.0].window) }
        guard !grew.isEmpty else { return .moved }
        let kind = HelpEventKind.gapFilled(closed: closed.map { HelpEvent.appName($0.window) }, filled: grew,
                                           usedSplit: learned != nil)
        let split = learned == nil ? nil : SplitMemory.lookup(SplitKey(left, on: display), in: settings.learnedSplits)
        onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                           group: onScreenOrder(finals, portrait: display.range.isPortrait), split: split,
                           previous: nil, undoMarker: undoMarker))
        return .moved
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
