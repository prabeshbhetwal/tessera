import AppKit
import TesseraCore

/// Runs every `Command` (M2 spec §2). All surfaces reach it through `CommandBridge`.
@MainActor
final class CommandExecutor: CommandExecuting {
    /// Tessera can't move its own windows, so say what to do instead of just "no window".
    static var noWindowMessage: String {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? "Click the window you want to move first"
            : "No window to move"
    }

    private struct Failure: Error {
        let message: String
    }

    private let model: SettingsModel
    private let displays: DisplayService
    private let windows: WindowService
    private let presenter: WindowPresenter
    private let store: SettingsStore
    private var cycles = CycleTracker()

    init(model: SettingsModel, displays: DisplayService, windows: WindowService,
         presenter: WindowPresenter, store: SettingsStore) {
        self.model = model
        self.displays = displays
        self.windows = windows
        self.presenter = presenter
        self.store = store
    }

    func execute(_ command: Command) async -> CommandResult {
        do {
            return try await run(command)
        } catch {
            return .failure(error.message)
        }
    }

    // MARK: - Shared with Coordinator

    /// Moves `window` to `goal`, using the cross-display write order when the window changes display.
    func place(_ window: WindowRef, current: CGRect?, goal: CGRect) async -> ApplyResult {
        let list = displays.displays
        let from = current.flatMap { list.display(at: CGPoint(x: $0.midX, y: $0.midY))?.id }
        let to = list.first { $0.visibleFrame.intersects(goal) }?.id
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : model.settings.snapSeconds
        return await windows.apply(goal, to: window, primaryHeight: DisplayService.primaryHeight,
                                   crossingDisplays: from != to, duration: duration)
    }

    /// Changes `display`'s column count, clamped to its range, and saves it as an override.
    /// Returns the new count, or nil when nothing changed.
    @discardableResult
    func setColumns(_ change: ColumnChange, on display: DisplayContext) -> Int? {
        let wanted = switch change {
        case let .set(n): n
        case let .delta(d): display.profile.columns + d
        }
        let columns = min(max(wanted, display.range.minCols), display.range.maxCols)
        guard columns != display.profile.columns else { return nil }
        var profile = display.profile
        profile.columns = columns
        profile.isUserOverride = true
        // Mutating settings triggers Coordinator.settingsChanged → save + display refresh.
        model.settings.displayOverrides[display.id.storageKey] = profile
        return columns
    }

    // MARK: - Commands

    private func run(_ command: Command) async throws(Failure) -> CommandResult {
        switch command {
        case let .apply(target, selector):
            let (window, frame) = try await frontmost()
            let display = try resolve(selector, windowFrame: frame)
            try await move(window, from: frame, to: TargetResolver.frame(for: target, display: display, current: frame))
            return .success
        case let .cycle(name):
            return try await cycle(name)
        case let .columns(change, selector):
            let frame = try? await frontmost().frame
            let display = try resolve(selector, windowFrame: frame)
            let columns = setColumns(change, on: display) ?? display.profile.columns
            return CommandResult(ok: true, message: "\(columns) columns")
        case let .moveToDisplay(step):
            return try await moveToDisplay(step)
        case let .tileWindows(selector):
            return try await tile(selector)
        case .undo:
            guard await windows.undoLast() else { throw Failure(message: "Nothing to undo") }
            return .success
        case .openSettings:
            presenter.showSettings()
            return .success
        case .listDisplays:
            return CommandResult(ok: true, displays: displayInfos())
        case .describeWindow:
            return try await describeWindow()
        case let .exportSettings(path):
            let url = try fileURL(path)
            guard url.pathExtension.lowercased() == "json" else { throw Failure(message: "Export path must end in .json") }
            do { try await store.export(model.settings, to: url) } catch { throw Self.failure(error) }
            return CommandResult(ok: true, message: "Exported to \(url.path)")
        case let .importSettings(path):
            let url = try fileURL(path)
            do { model.settings = try await store.importSettings(from: url) } catch { throw Self.failure(error) }
            return CommandResult(ok: true, message: "Imported \(url.lastPathComponent)")
        }
    }

    /// Next step of a named cycle; steps that would not change the window are skipped (one pass at most).
    private func cycle(_ name: String) async throws(Failure) -> CommandResult {
        guard let cycle = model.settings.cycles.first(where: { $0.name == name }), !cycle.steps.isEmpty else {
            throw Failure(message: "No cycle named \u{201C}\(name)\u{201D}")
        }
        let (window, frame) = try await frontmost()
        let display = try resolve(cycle.display, windowFrame: frame)
        let key = window.windowID.map { "w\($0)" } ?? "p\(window.pid)-\(CFHash(window.element))"
        for _ in cycle.steps.indices {
            let index = cycles.step(cycle: name, windowKey: key, stepCount: cycle.steps.count, now: Date())
            guard cycle.steps.indices.contains(index) else { break }
            let goal = TargetResolver.frame(for: cycle.steps[index], display: display, current: frame)
            if !Self.sameFrame(goal, frame) {
                try await move(window, from: frame, to: goal)
                return .success
            }
        }
        return CommandResult(ok: true, message: "Window already fits every step")
    }

    /// Keeps the window's grid span (scaled to the new column count), or its proportional frame when off-grid.
    /// Every visible window on the display, side by side in equal shares: 3 windows get a third each. Windows
    /// keep their left-to-right order (top-to-bottom on a portrait display). Each move can be undone.
    private func tile(_ selector: DisplaySelector) async throws(Failure) -> CommandResult {
        guard Permissions.isAccessibilityTrusted else {
            throw Failure(message: "Tessera needs Accessibility permission to move windows")
        }
        // `.current` is the front window's display; with no front window (desktop or Tessera in front) the
        // display under the cursor.
        let front = await windows.frontmostWindow()
        let frontFrame: CGRect? = if let front { await windows.frame(of: front) } else { nil }
        let display = try resolve(selector == .current && frontFrame == nil ? .cursor : selector, windowFrame: frontFrame)
        let found = await windows.visibleWindows(on: display.frame, primaryHeight: DisplayService.primaryHeight,
                                                 excluding: Set(model.settings.excludedBundleIDs))
        guard !found.isEmpty else { throw Failure(message: "No windows to tile on this display") }
        let portrait = display.range.isPortrait
        let ordered = found.sorted { portrait ? $0.frame.midY > $1.frame.midY : $0.frame.minX < $1.frame.minX }
        let slots = GridGeometry.tiles(ordered.count, display: display)
        // All at once, so with a snap speed set the windows glide together instead of one after another.
        let moved = await withTaskGroup(of: Bool.self) { group in
            for (entry, slot) in zip(ordered, slots) {
                group.addTask {
                    if case .applied = await self.place(entry.window, current: entry.frame, goal: slot) { return true }
                    return false
                }
            }
            var count = 0
            for await ok in group where ok { count += 1 }
            return count
        }
        await windows.mergeLastMoves(moved)  // one ⌃⌥Z puts every tiled window back
        let n = ordered.count
        return CommandResult(ok: moved > 0, message: moved == n ? "Tiled \(n) window\(n == 1 ? "" : "s")" : "Tiled \(moved) of \(n) windows")
    }

    private func moveToDisplay(_ step: DisplayStep) async throws(Failure) -> CommandResult {
        let (window, frame) = try await frontmost()
        let from = try resolve(.current, windowFrame: frame)
        guard let to = DisplayResolver.step(step, from: from, displays: displays.displays) else {
            throw Failure(message: "No such display")
        }
        guard to.id != from.id else { return CommandResult(ok: true, message: "Already on that display") }
        let goal: CGRect
        if let span = Self.nearestSpan(to: frame, on: from) {
            goal = GridGeometry.frame(for: TargetResolver.relocate(span: span, from: from, to: to), display: to)
        } else {
            goal = Self.scale(frame, from: from.visibleFrame, to: to.visibleFrame)
        }
        try await move(window, from: frame, to: goal)
        return .success
    }

    private func describeWindow() async throws(Failure) -> CommandResult {
        let (window, frame) = try await frontmost()
        let ordered = DisplayResolver.ordered(displays.displays)
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let index = ordered.firstIndex { $0.frame.contains(centre) }.map { $0 + 1 }
        let app = NSRunningApplication(processIdentifier: window.pid)?.localizedName
        return CommandResult(ok: true, window: WindowInfo(app: app, bundleID: window.bundleID, frame: frame, displayIndex: index))
    }

    private func displayInfos() -> [DisplayInfo] {
        DisplayResolver.ordered(displays.displays).enumerated().map { i, d in
            let name = NSScreen.screens.first { $0.frame == d.frame }?.localizedName
            return DisplayInfo(index: i + 1, id: d.id.storageKey, name: name, frame: d.frame,
                               columns: d.profile.columns, minColumns: d.range.minCols, maxColumns: d.range.maxCols)
        }
    }

    // MARK: - Helpers

    private func frontmost() async throws(Failure) -> (window: WindowRef, frame: CGRect) {
        guard Permissions.isAccessibilityTrusted else {
            throw Failure(message: "Tessera needs Accessibility permission to move windows")
        }
        guard let window = await windows.frontmostWindow(), let frame = await windows.frame(of: window) else {
            throw Failure(message: Self.noWindowMessage)
        }
        if let bundle = window.bundleID, model.settings.excludedBundleIDs.contains(bundle) {
            throw Failure(message: "This app is excluded in Tessera settings")
        }
        return (window, frame)
    }

    private func resolve(_ selector: DisplaySelector, windowFrame: CGRect?) throws(Failure) -> DisplayContext {
        guard let display = DisplayResolver.resolve(selector, displays: displays.displays,
                                                    windowFrame: windowFrame, cursor: NSEvent.mouseLocation) else {
            throw Failure(message: "No such display")
        }
        return display
    }

    private func move(_ window: WindowRef, from current: CGRect, to goal: CGRect) async throws(Failure) {
        if case let .failed(reason) = await place(window, current: current, goal: goal) {
            throw Failure(message: reason)
        }
    }

    /// Automation paths must be absolute (the CLI resolves relative ones); `~` is expanded.
    private func fileURL(_ path: String) throws(Failure) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw Failure(message: "Path must be absolute: \(path)") }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private static func failure(_ error: any Error) -> Failure {
        if case let SettingsError.invalid(message) = error { return Failure(message: message) }
        return Failure(message: error.localizedDescription)
    }

    static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        edgeDistance(a, b) <= 1
    }

    private static func edgeDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX - b.minX), abs(a.maxX - b.maxX), abs(a.minY - b.minY), abs(a.maxY - b.maxY))
    }

    /// The grid span whose frame is closest to `frame`, if within `tolerance` on every edge.
    // ponytail: brute force over every span × band (≤ 8 columns → ≤ 108 frames); fine per keypress.
    static func nearestSpan(to frame: CGRect, on display: DisplayContext, tolerance: CGFloat = 10) -> ColumnSpan? {
        let n = max(display.profile.columns, 1)
        var best: (span: ColumnSpan, distance: CGFloat)?
        for lo in 0..<n {
            for hi in lo..<n {
                for band in [Band.full, .top, .bottom] {
                    let span = ColumnSpan(columns: lo...hi, band: band)
                    let d = edgeDistance(GridGeometry.frame(for: span, display: display), frame)
                    if d < (best?.distance ?? .infinity) { best = (span, d) }
                }
            }
        }
        guard let best, best.distance <= tolerance else { return nil }
        return best.span
    }

    static func scale(_ frame: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
        guard a.width > 0, a.height > 0 else { return CGRect(origin: b.origin, size: frame.size) }
        let sx = b.width / a.width, sy = b.height / a.height
        return CGRect(x: b.minX + (frame.minX - a.minX) * sx, y: b.minY + (frame.minY - a.minY) * sy,
                      width: frame.width * sx, height: frame.height * sy)
    }
}
