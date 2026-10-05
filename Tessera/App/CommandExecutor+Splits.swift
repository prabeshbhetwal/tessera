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
        if let split = SplitMemory.lookup(SplitKey(ordered, on: display), in: settings.learnedSplits),
           let frames = SplitApplier.frames(
               for: split, windows: ordered.map { (bundleID: $0.window.bundleID, frame: $0.frame) },
               usable: GridGeometry.usableFrame(display.visibleFrame, profile: display.profile),
               portrait: display.range.isPortrait, restoresOrder: settings.splitRestoresOrder,
               gapPlacement: settings.splitGapPlacement) {
            return (frames, true)
        }
        return (GridGeometry.tiles(ordered.count, display: display), false)
    }

    /// Saves how the windows on the display are arranged now, then watches them; Tile reuses the split.
    func rememberSplit(_ selector: DisplaySelector) async throws(Failure) -> CommandResult {
        let (display, found) = try await windowsOnDisplay(selector)
        switch splitWatcher.save(found, display: display) {
        case let .failure(rejection):
            throw Failure(message: rejection.message)
        case let .success((key, _)):
            splitWatcher.watch(found, display: display)
            return CommandResult(ok: true, message: "Remembered split · \(SplitLabel.apps(key)) · "
                + SplitLabel.display(key, displays: [display]))
        }
    }
}
