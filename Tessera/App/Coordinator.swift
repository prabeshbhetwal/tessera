import AppKit
import os
import TesseraCore

/// Owns one trigger session at a time and wires services, engine and overlay together (spec §5.3).
@MainActor
final class Coordinator {
    let model: SettingsModel
    let displays: DisplayService
    let presenter: WindowPresenter
    let executor: CommandExecutor
    private let store: SettingsStore
    private let windows: WindowService
    private let thumbnails = ThumbnailService()
    private let overlay = OverlayController()
    private var input: InputService?
    private var engine: SelectionEngine
    private var session: Session?
    private var sessionCounter = 0
    private var saveTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "coordinator")

    /// A mouse move this far from the last nav key hands selection back to the cursor (M2 spec §3).
    private static let navReleaseDistance: CGFloat = 10

    private struct Session {
        let id: Int
        let origin: CGPoint
        let target: WindowRef
        let current: CGRect?
        var displays: [DisplayContext]
        var cursor: CGPoint
        var anchor: SpanAnchor?
        var neighbours: [CGRect] = []
        var thumbnail: CGImage?
        var targetFrame: CGRect?
        /// Keyboard selection; overrides the cursor while set.
        var nav: NavState?
        /// Cursor position at the last nav key.
        var navCursor: CGPoint?
        /// Last label posted to VoiceOver, so unchanged selections aren't re-announced.
        var announced: String?
        /// The cursor selection was a grid span last time (boundary hysteresis).
        var pointing = false
    }

    init(model: SettingsModel, store: SettingsStore) {
        self.model = model
        self.store = store
        self.engine = SelectionEngine(ring: model.settings.ring)
        let displays = DisplayService(settings: { [unowned model] in model.settings })
        self.displays = displays
        let presenter = WindowPresenter(model: model, displays: displays.displays)
        self.presenter = presenter
        let windows = WindowService()
        self.windows = windows
        self.executor = CommandExecutor(model: model, displays: displays, windows: windows,
                                        presenter: presenter, store: store)
        displays.onChange = { [weak self] in self?.displaysChanged() }
        model.onChange = { [weak self] in self?.settingsChanged($0) }
        // Shortcut recorders need raw keys: pause the trigger and hotkeys while one is recording.
        recorderObserver = NotificationCenter.default.addObserver(
            forName: .tesseraRecorderActive, object: nil, queue: .main
        ) { [weak self] note in
            let active = note.userInfo?["active"] as? Bool ?? false
            MainActor.assumeIsolated { self?.setRecording(active) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrontmostExcluded() }
        }
    }

    private var recorderObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var isRecording = false

    /// Excluded apps get their keys untouched: the tap neither opens the ring nor fires hotkeys there.
    private func updateFrontmostExcluded() {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        input?.setFrontmostExcluded(bundle.map(model.settings.excludedBundleIDs.contains) ?? false)
    }

    private func setRecording(_ active: Bool) {
        isRecording = active
        if active { cancelSession() }
        applyInputConfig()
    }

    /// Pushes trigger + hotkeys to the tap; an empty chord never opens while a recorder is active.
    private func applyInputConfig() {
        let s = model.settings
        input?.updateChord(isRecording ? TriggerChord(keyCodes: []) : s.trigger)
        input?.updateHotkeys(isRecording ? [] : s.hotkeys, ringKeyNavigation: s.ringKeyNavigation)
        updateFrontmostExcluded()
    }

    /// Starts the event tap. Returns false when Accessibility is missing or the tap can't be created.
    @discardableResult
    func start() -> Bool {
        guard input == nil else { return true }
        guard Permissions.isAccessibilityTrusted else { return false }
        let (stream, continuation) = AsyncStream.makeStream(of: TriggerOutput.self)
        let service = InputService(chord: model.settings.trigger) { continuation.yield($0) }
        service.updatePrimaryHeight(DisplayService.primaryHeight)
        service.updateHotkeys(model.settings.hotkeys, ringKeyNavigation: model.settings.ringKeyNavigation)
        guard service.start() else {
            log.error("event tap could not be created")
            return false
        }
        input = service
        updateFrontmostExcluded()
        // One consumer keeps outputs strictly ordered even across awaits.
        Task { [weak self] in
            for await output in stream { await self?.handle(output) }
        }
        return true
    }

    func stop() {
        input?.stop()
        input = nil
        cancelSession()
    }

    func undoLast() {
        Task { _ = await windows.undoLast() }
    }

    /// Runs a command through the bridge; a failure is shown in the HUD.
    func run(_ command: Command) async {
        let result = await CommandBridge.execute(command)
        if !result.ok {
            let message = result.message ?? "Command failed"
            log.notice("command failed: \(message, privacy: .public)")
            overlay.showHUD(message)
        }
    }

    func showHUD(_ text: String) {
        overlay.showHUD(text)
    }

    // MARK: - Trigger outputs

    private func handle(_ output: TriggerOutput) async {
        switch output {
        case let .open(origin): await open(at: origin)
        case let .move(point):
            guard var s = session else { return }
            s.cursor = point
            if let from = s.navCursor, hypot(point.x - from.x, point.y - from.y) >= Self.navReleaseDistance {
                s.nav = nil
                s.navCursor = nil
            }
            session = s
            refreshSelection()
        case let .anchor(point):
            guard var s = session else { return }
            s.anchor = engine.anchor(at: point, displays: s.displays)
            s.cursor = point
            s.nav = nil
            s.navCursor = nil
            session = s
            refreshSelection()
        case let .step(delta): step(delta)
        case .apply: await apply()
        case .cancel: cancelSession()
        case let .nav(key): await navigate(key)
        case let .command(command): await run(command)
        }
    }

    private func open(at origin: CGPoint) async {
        cancelSession()
        // Every early return closes the tap's ring too, so nav keys and clicks aren't swallowed invisibly.
        guard Permissions.isAccessibilityTrusted else { input?.abortSession(); return }
        if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           model.settings.excludedBundleIDs.contains(bundle) { input?.abortSession(); return }
        guard let target = await windows.frontmostWindow() else {
            input?.abortSession()
            overlay.showHUD(CommandExecutor.noWindowMessage)
            return
        }
        let current = await windows.frame(of: target)
        sessionCounter += 1
        let id = sessionCounter
        session = Session(id: id, origin: origin, target: target, current: current,
                          displays: displays.displays, cursor: origin)
        overlay.show(origin: origin, displays: displays.displays, ring: model.settings.ring, theme: model.settings.activeTheme)
        refreshSelection() // the cursor starts in the middle: show the cancel mark lit
        loadContext(for: id, target: target)
    }

    /// Neighbour frames and the thumbnail load concurrently; late results are dropped if the session changed.
    private func loadContext(for id: Int, target: WindowRef) {
        let preview = model.settings.preview
        let height = DisplayService.primaryHeight
        if preview.showNeighbours {
            Task {
                let frames = await windows.neighbourFrames(excluding: target, primaryHeight: height)
                guard session?.id == id else { return }
                session?.neighbours = frames
                refreshSelection()
            }
        }
        if preview.showThumbnail, Permissions.isScreenCaptureAllowed, let windowID = target.windowID {
            Task {
                let image = await thumbnails.snapshot(windowID: windowID)
                guard session?.id == id else { return }
                session?.thumbnail = image
                refreshSelection()
            }
        }
    }

    /// Ring keyboard navigation (M2 spec §3). The first nav key starts at the window's display and column.
    private func navigate(_ key: NavKey) async {
        guard var s = session else { return }
        if key == .apply {
            await apply()
            return
        }
        if s.nav == nil { s.nav = KeyNavigator.start(windowFrame: s.current, displays: s.displays) }
        s.navCursor = s.cursor
        session = s
        switch key {
        case .columnsPlus: step(1)
        case .columnsMinus: step(-1)
        default:
            if let nav = s.nav { session?.nav = KeyNavigator.reduce(nav, key, displays: s.displays) }
        }
        refreshSelection()
    }

    private func refreshSelection() {
        guard var s = session else { return }
        let selection: Selection
        if let nav = s.nav {
            selection = KeyNavigator.selection(nav, displays: s.displays)
        } else {
            selection = engine.select(origin: s.origin, cursor: s.cursor, displays: s.displays,
                                      anchor: s.anchor, pointing: s.pointing)
            if case .span = selection { s.pointing = true } else { s.pointing = false }
        }
        let frame = targetFrame(for: selection, in: s)
        s.targetFrame = frame
        if model.settings.announceSelection,
           let label = frame.flatMap({ PreviewModel.label(for: selection, frame: $0) }), label != s.announced {
            s.announced = label
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                .announcement: label,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
        session = s
        let layers = frame.map {
            PreviewModel.layers(
                PreviewInput(target: $0, current: s.current, neighbours: s.neighbours, selection: selection,
                             reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
                settings: model.settings.preview
            )
        }
        var pointMode = false
        if case .span = selection { pointMode = true }
        let cancelling = s.nav == nil
            && hypot(s.cursor.x - s.origin.x, s.cursor.y - s.origin.y) < model.settings.ring.cancelRadius
        overlay.update(selection: selection, layers: layers, thumbnail: s.thumbnail,
                       displays: s.displays, pointMode: pointMode, cancelling: cancelling)
    }

    private func targetFrame(for selection: Selection, in s: Session) -> CGRect? {
        switch selection {
        case .none:
            return nil
        case let .wedge(_, action):
            // Flicks act on the display where the ring opened.
            guard let display = s.displays.display(at: s.origin)
                ?? s.displays.first else { return nil }
            return GridGeometry.frame(for: action, display: display, current: s.current ?? .zero)
        case let .span(id, span):
            guard let display = s.displays.first(where: { $0.id == id }) else { return nil }
            return GridGeometry.frame(for: span, display: display)
        }
    }

    /// Column count ±1 on the keyboard-selected display, else the one under the cursor.
    private func step(_ delta: Int) {
        guard let s = session else { return }
        let ordered = DisplayResolver.ordered(s.displays)
        let navDisplay = s.nav.flatMap { ordered.indices.contains($0.displayIndex) ? ordered[$0.displayIndex] : nil }
        guard let display = navDisplay ?? s.displays.display(at: s.cursor),
              executor.setColumns(.delta(delta), on: display) != nil else { return }
        // setColumns mutated settings → settingsChanged already refreshed `displays`.
        session?.displays = displays.displays
        session?.anchor = nil
        if let nav = s.nav {
            session?.nav = KeyNavigator.reduce(nav, delta > 0 ? .columnsPlus : .columnsMinus, displays: displays.displays)
        }
        refreshSelection()
    }

    private func apply() async {
        guard let s = session else { return }
        session = nil
        overlay.hide()
        guard let frame = s.targetFrame else { return }
        // Not awaited: a glide must never hold up the next ring or hotkey.
        Task {
            let result = await executor.place(s.target, current: s.current, goal: frame)
            if case let .failed(reason) = result {
                log.notice("apply failed for \(s.target.bundleID ?? "?", privacy: .public): \(reason, privacy: .public)")
                overlay.showHUD("Can't move this window")
            }
        }
    }

    private func cancelSession() {
        guard session != nil else { return }
        session = nil
        overlay.hide()
    }

    // MARK: - Changes

    private func displaysChanged() {
        input?.updatePrimaryHeight(DisplayService.primaryHeight)
        presenter.updateDisplays(displays.displays)
        cancelSession() // spec §7: display unplugged mid-session
    }

    private func settingsChanged(_ settings: TesseraSettings) {
        engine = SelectionEngine(ring: settings.ring)
        applyInputConfig()
        displays.refresh()
        presenter.updateDisplays(displays.displays)
        saveTask?.cancel()
        saveTask = Task { [store, log] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do { try await store.save(settings) } catch {
                log.error("settings save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
