import AppKit
import TesseraCore

/// A window closing in a side-by-side group leaves no hole (`splitFillsClosedGap`): the apps left go back to their
/// learned split on that display when there is one, otherwise the most recently used window beside the space grows
/// into it (`SplitFill`). One ⌃⌥Z puts them back.
extension SplitWatchers {
    /// Waits for the window list to drop the closed window, then fills its space; re-arms the watchers either way.
    /// Each display fills on its own, so an app quitting with windows on two displays fills both. A `minimised` window
    /// left the same way (`minimiseFillsGap`); only the help message differs.
    func fillSoon(_ group: [(window: WindowRef, frame: CGRect)], displayKey: String, minimised: Bool = false) {
        pendingFills[displayKey]?.cancel()
        pendingFills[displayKey] = Task { [weak self] in
            var group = group
            // Up to 3 looks for the closed window to leave the window list, which can lag the close. Waiting for
            // another fill's glide (slow snap speeds take seconds) doesn't use them up; `busy` only caps a stuck count.
            var (looks, busy) = (0, 0)
            while looks < 3, busy < 100 {
                do { try await Task.sleep(for: SplitWatcher.settle) } catch { return }
                guard let self else { return }
                switch await self.fill(group, displayKey: displayKey, minimised: minimised) {
                case .moved(let finals):
                    // The watch ended with the close, so a window closed during the glide went unseen: look once more.
                    (group, looks) = (finals, 2)
                case .busy: busy += 1
                case .notYet: looks += 1
                case .skipped: looks = 3
                }
            }
            self?.armSoon(after: .zero)
        }
    }

    enum FillOutcome {
        /// The windows left, where they ended up.
        case moved([(window: WindowRef, frame: CGRect)])
        case busy, notYet, skipped
    }

    /// `.busy` while Tessera is moving windows; `.notYet` while no window of `group` has left the window list;
    /// `.skipped` when the setting is off, a window joined or wandered onto the display since, or nothing beside the
    /// space can cover it.
    private func fill(_ group: [(window: WindowRef, frame: CGRect)], displayKey: String, minimised: Bool) async
        -> FillOutcome {
        let settings = model.settings
        guard settings.learnSplits, settings.splitFillsClosedGap, group.count > 1,
              let display = displays.displays.first(where: { $0.id.storageKey == displayKey }) else { return .skipped }
        guard ownMoves == 0 else { return .busy }
        // Front-most first, so the most recently used window comes first.
        let left = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                excluding: Set(settings.excludedBundleIDs))
        let closed = group.filter { entry in !left.contains { $0.window == entry.window } }
        guard !Task.isCancelled, ownMoves == 0 else { return .busy }
        guard !closed.isEmpty else { return .notYet }
        guard !left.isEmpty, left.allSatisfy({ entry in group.contains { $0.window == entry.window } })
        else { return .skipped }

        var goals = left.map(\.frame)
        let learned = settings.learnedFrames(for: left, display: display)
        if let learned {
            goals = learned
        } else if let filled = SplitFill.frames(filling: closed.map(\.frame), frames: goals, gap: display.profile.gap) {
            goals = filled
        }
        let moves = left.indices.filter { !CommandExecutor.sameFrame(left[$0].frame, goals[$0]) }
        guard !moves.isEmpty else { return .skipped }
        // A minimised window waits to be tiled back in beside the windows left (a closed one can't be watched, so
        // `add` skips it). Taken from what left, not from the event, so one minimised while the watch was down counts.
        if settings.minimiseFillsGap {
            for entry in closed {
                minimisedWindows.add(entry.window, others: left.map(\.window), displayKey: displayKey)
            }
        }

        beginOwnMove()
        let (landed, undoMarker) = await windows.moveTogether(
            moves.map { (window: left[$0].window, goal: goals[$0]) }, primaryHeight: DisplayService.primaryHeight,
            duration: model.glideSeconds)
        endOwnMove()  // re-arms the watchers from where the windows ended up

        var finals = left
        for (index, frame) in zip(moves, landed) { if let frame { finals[index].frame = frame } }
        let grew = zip(moves, landed).filter { $0.1 != nil }.map { HelpEvent.appName(left[$0.0].window) }
        guard !grew.isEmpty else { return .skipped }
        let kind = HelpEventKind.gapFilled(closed: closed.map { HelpEvent.appName($0.window) }, filled: grew,
                                           usedSplit: learned != nil, minimised: minimised)
        let split = learned == nil ? nil : SplitMemory.lookup(SplitKey(left, on: display), in: settings.learnedSplits)
        onHelpEvent?(.make(kind: kind, source: .hand, display: display,
                           group: onScreenOrder(finals, portrait: display.range.isPortrait), split: split,
                           previous: nil, undoMarker: undoMarker))
        return .moved(finals)
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
