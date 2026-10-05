import AppKit
import TesseraCore

/// Learned splits (spec: Tile reuses a remembered arrangement): choosing Tile's frames, watching the result for
/// hand adjustments, and the Remember Split command.
extension CommandExecutor {
    /// The display `selector` names and the visible windows on it. `.current` is the front window's display; with
    /// no front window (desktop or Tessera in front) the display under the cursor.
    func windowsOnDisplay(_ selector: DisplaySelector) async throws(Failure)
        -> (display: DisplayContext, found: [(window: WindowRef, frame: CGRect)]) {
        guard Permissions.isAccessibilityTrusted else {
            throw Failure(message: "Tessera needs Accessibility permission to move windows")
        }
        let front = await windows.frontmostWindow()
        let frontFrame: CGRect? = if let front { await windows.frame(of: front) } else { nil }
        let display = try resolve(selector == .current && frontFrame == nil ? .cursor : selector, windowFrame: frontFrame)
        let found = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                 excluding: Set(model.settings.excludedBundleIDs))
        return (display, found)
    }

    /// The frames Tile gives `ordered`: the remembered split for these apps on this display when there is one that
    /// fits, otherwise equal tiles.
    func splitFrames(for ordered: [(window: WindowRef, frame: CGRect)], display: DisplayContext)
        -> (frames: [CGRect], learned: Bool) {
        let settings = model.settings
        if let split = SplitMemory.lookup(splitKey(ordered, display), in: settings.learnedSplits),
           let frames = SplitApplier.frames(
               for: split, windows: ordered.map { (bundleID: $0.window.bundleID, frame: $0.frame) },
               usable: GridGeometry.usableFrame(display.visibleFrame, profile: display.profile),
               portrait: display.range.isPortrait, restoresOrder: settings.splitRestoresOrder,
               gapPlacement: settings.splitGapPlacement) {
            return (frames, true)
        }
        return (GridGeometry.tiles(ordered.count, display: display), false)
    }

    /// Watches `ordered` for hand adjustments, skipping the moves that placed them.
    func watchSplit(_ ordered: [(window: WindowRef, frame: CGRect)], display: DisplayContext) {
        splitWatcher.watch(ordered.map(\.window), key: splitKey(ordered, display), display: display,
                           ignoreUntil: ContinuousClock.now + SplitWatcher.settle)
    }

    /// Saves how the windows on the display are arranged now; Tile reuses it.
    func rememberSplit(_ selector: DisplaySelector) async throws(Failure) -> CommandResult {
        let (display, found) = try await windowsOnDisplay(selector)
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let frames = found.map { (bundleID: $0.window.bundleID, frame: $0.frame) }
        switch SplitLearner.learn(frames, usable: usable, gap: display.profile.gap) {
        case let .failure(rejection):
            throw Failure(message: rejection.message)
        case let .success(slots):
            let key = splitKey(found, display)
            let split = LearnedSplit(key: key, slots: slots, updated: Date())
            model.settings.learnedSplits = SplitMemory.upsert(split, into: model.settings.learnedSplits)
            watchSplit(found, display: display)
            return CommandResult(ok: true, message: "Remembered split · \(SplitLabel.apps(key)) · "
                + SplitLabel.display(key, displays: [display]))
        }
    }

    private func splitKey(_ group: [(window: WindowRef, frame: CGRect)], _ display: DisplayContext) -> SplitKey {
        SplitKey(display: display.id.storageKey, bundleIDs: group.map(\.window.bundleID))
    }
}
