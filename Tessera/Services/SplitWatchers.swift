import AppKit
import TesseraCore

/// One `SplitWatcher` per display, kept armed so a hand adjustment reflows the neighbours without a Tile first.
/// Once Tessera's moves settle, at launch, after a display change and after a settings change, every display whose
/// windows sit side by side (two or more that `SplitLearner` accepts as a split) is watched. A display already watching
/// that same group keeps its watch, so its baseline and Tile Evenly's no-learn watch survive.
@MainActor
final class SplitWatchers {
    var onLearned: ((String) -> Void)? {
        didSet { for watcher in watchers.values { watcher.onLearned = onLearned } }
    }

    private let windows: WindowService
    private let displays: DisplayService
    private let model: SettingsModel
    /// Keyed by `DisplayID.storageKey`.
    private var watchers: [String: SplitWatcher] = [:]
    private var ownMoves = 0
    private var pendingArm: Task<Void, Never>?
    /// Groups last arranged by Tile Evenly: a re-arm keeps them from learning, so the stored split survives.
    private var noLearn: Set<SplitKey> = []

    init(windows: WindowService, displays: DisplayService, model: SettingsModel) {
        self.windows = windows
        self.displays = displays
        self.model = model
    }

    /// Watches `group` on `display`, replacing that display's watch. `learns` false reflows neighbours but never saves
    /// the arrangement as a split (Tile Evenly).
    func watch(_ group: [(window: WindowRef, frame: CGRect)], display: DisplayContext, learns: Bool = true) {
        let key = SplitKey(group, on: display)
        if learns { noLearn.remove(key) } else { noLearn.insert(key) }
        watcher(for: display).watch(group, display: display, learns: learns)
    }

    func save(_ found: [(window: WindowRef, frame: CGRect)], display: DisplayContext)
        -> Result<(key: SplitKey, changed: Bool), SplitRejection> {
        watcher(for: display).save(found, display: display)
    }

    /// Stops every display's watch and any pending re-arm.
    func stop() {
        pendingArm?.cancel()
        pendingArm = nil
        for watcher in watchers.values { watcher.stop() }
    }

    /// See `SplitWatcher.beginOwnMove`. Every display hears it: a move can cross displays.
    func beginOwnMove() {
        ownMoves += 1
        pendingArm?.cancel()
        for watcher in watchers.values { watcher.beginOwnMove() }
    }

    func endOwnMove() {
        ownMoves -= 1
        for watcher in watchers.values { watcher.endOwnMove() }
        if ownMoves == 0 { armSoon() }
    }

    /// Re-reads every display after `delay` and watches the ones whose windows sit side by side.
    func armSoon(after delay: Duration = SplitWatcher.settle) {
        pendingArm?.cancel()
        pendingArm = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.armAll()
        }
    }

    private func armAll() async {
        guard model.settings.learnSplits, Permissions.isAccessibilityTrusted else { return }
        let excluded = Set(model.settings.excludedBundleIDs)
        for display in displays.displays {
            let found = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                     excluding: excluded)
            // A Tessera move began while reading: its end arms again from settled frames.
            guard !Task.isCancelled, ownMoves == 0 else { return }
            let current = watchers[display.id.storageKey]
            let key = SplitKey(found, on: display)
            // Same group, or a hand adjustment mid-way (a drag can overlap windows for a moment): leave it be.
            if current?.key == key || current?.isBusy == true { continue }
            let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
            let frames = found.map { (bundleID: $0.window.bundleID, frame: $0.frame) }
            guard found.count > 1, case .success = SplitLearner.learn(frames, usable: usable, gap: display.profile.gap)
            else {
                current?.stop()  // stacked or a lone window: nothing to reflow
                continue
            }
            watcher(for: display).watch(found, display: display, learns: !noLearn.contains(key))
        }
    }

    private func watcher(for display: DisplayContext) -> SplitWatcher {
        let id = display.id.storageKey
        if let existing = watchers[id] { return existing }
        let watcher = SplitWatcher(windows: windows, displays: displays, model: model)
        watcher.onLearned = onLearned
        // A window joined, left or closed: watch whatever the display holds now.
        watcher.onEnded = { [weak self] in self?.armSoon() }
        // Moves already in flight count for the new watcher too; `endOwnMove` balances them.
        for _ in 0..<ownMoves { watcher.beginOwnMove() }
        // Created after the moves that called for it: their late notifications still count as Tessera's.
        watcher.beginOwnMove()
        watcher.endOwnMove()
        watchers[id] = watcher
        return watcher
    }
}
