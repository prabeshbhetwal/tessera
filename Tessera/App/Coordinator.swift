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
    /// Called after every settings change has been applied (the app delegate updates the menu bar item).
    var onSettingsChange: ((TesseraSettings) -> Void)?
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "coordinator")

    /// A mouse move this far from the last nav key hands selection back to the cursor (M2 spec §3).
    private static let navReleaseDistance: CGFloat = 10

    /// The front window and its frame, looked up while the ring is already on screen.
    private typealias FrontWindow = (window: WindowRef, frame: CGRect?)

    private struct Session {
        let id: Int
        let origin: CGPoint
        /// Nil until the lookup finishes (Accessibility round trip to the front app).
        var target: WindowRef?
        var current: CGRect?
        let lookup: Task<FrontWindow?, Never>
        /// Read once per session; it is an IPC-backed system setting, too slow for every mouse move.
        let reduceMotion: Bool
        var selection: Selection = .none
        /// Something was selected at some point: releasing back in the middle then cancels, it isn't a tap.
        var leftDeadZone = false
        var displays: [DisplayContext]
        var cursor: CGPoint
        var anchor: SpanAnchor?
        var neighbours: [CGRect] = []
        /// Window snapshot or app icon, per `PreviewSettings.style`.
        var image: CGImage?
        /// Pointing labels carry the "click to add columns" hint this session.
        let hint: Bool
        /// The cursor reached the grid at least once (counts toward the hint's limit).
        var pointed = false
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
        previewObserver = NotificationCenter.default.addObserver(
            forName: .tesseraPreviewOverlay, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showOverlaySample() }
        }
    }

    private var recorderObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var previewObserver: NSObjectProtocol?
    private var isRecording = false
    private var sampleTask: Task<Void, Never>?

    /// Shows the real overlay for a few seconds on the display under the mouse, with the right half
    /// selected, so a theme can be judged on screen without holding the trigger. A real session wins.
    private func showOverlaySample() {
        guard session == nil else { return }
        let all = displays.displays
        guard let display = all.display(at: NSEvent.mouseLocation) ?? all.first else { return }
        let origin = CGPoint(x: display.visibleFrame.midX, y: display.visibleFrame.midY)
        let settings = model.settings
        overlay.show(origin: origin, displays: all, ring: settings.ring, theme: settings.activeTheme)
        let selection = Selection.wedge(index: 2, action: .rightHalf)
        let target = GridGeometry.frame(for: .rightHalf, display: display, current: .zero)
        let current = GridGeometry.frame(for: .leftHalf, display: display, current: .zero).insetBy(dx: 60, dy: 80)
        let layers = PreviewModel.layers(
            PreviewInput(target: target, current: current, neighbours: [], selection: selection,
                         reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
            settings: settings.preview)
        overlay.update(selection: selection, layers: layers, image: nil, displays: all, pointMode: false, cancelling: false)
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.session == nil else { return }
            self.overlay.hide()
        }
    }

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
        input?.updateHotkeys(isRecording || !s.hotkeysEnabled ? [] : s.hotkeys, ringKeyNavigation: s.ringKeyNavigation)
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
        service.updateHotkeys(model.settings.hotkeysEnabled ? model.settings.hotkeys : [], ringKeyNavigation: model.settings.ringKeyNavigation)
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
        Task { await run(.undo) }
    }

    /// Runs a command through the bridge. The HUD shows a failure, and any message a success carries
    /// ("5 columns", "Already on that display"): a hotkey has no other way to tell the user what happened.
    func run(_ command: Command) async {
        let result = await CommandBridge.execute(command)
        if !result.ok { log.notice("command failed: \(result.message ?? "?", privacy: .public)") }
        if let message = result.ok ? result.message : (result.message ?? "Command failed") {
            showHUD(message)
        }
    }

    /// Every HUD message goes through here, so the "Show messages" switch covers them all.
    func showHUD(_ text: String) {
        let s = model.settings
        guard s.showHUD else { return }
        overlay.showHUD(text, position: s.hudPosition, seconds: s.hudSeconds)
    }

    // MARK: - Trigger outputs

    private func handle(_ output: TriggerOutput) async {
        switch output {
        case let .open(origin): await open(at: origin)
        case let .move(point):
            guard var s = session else { return }
            s.cursor = point
            // The mouse takes selection back only when it can select something itself.
            let ring = model.settings.ring
            if ring.directions || ring.pointing, let from = s.navCursor,
               hypot(point.x - from.x, point.y - from.y) >= Self.navReleaseDistance {
                s.nav = nil
                s.navCursor = nil
            }
            session = s
            refreshSelection()
        case let .anchor(point):
            // The tap still swallows the click while the ring is open, so a disabled gesture clicks nothing.
            guard model.settings.ring.clickToSpan, model.settings.ring.pointing, var s = session else { return }
            s.anchor = engine.anchor(at: point, displays: s.displays)
            s.cursor = point
            s.nav = nil
            s.navCursor = nil
            session = s
            refreshSelection()
        case let .step(delta):
            // Scroll only; the ring's = and − keys go through `navigate` and stay available.
            if model.settings.ring.scrollChangesColumns { step(delta) }
        case .apply: await apply()
        case .cancel: cancelSession()
        case let .nav(key): await navigate(key)
        case let .command(command):
            // Not awaited: a command can glide a window for up to a second, and this loop is the only
            // consumer of trigger outputs. Awaiting it would hold up the next ring open or hotkey.
            Task { await run(command) }
        }
    }

    /// Draws the ring the moment the trigger fires. The front window is looked up in parallel: an
    /// Accessibility round trip to the front app can take tens of milliseconds, and nothing on screen, nor any
    /// mouse move, waits for it.
    private func open(at origin: CGPoint) async {
        // A running sample is left to its own timer: after a successful open it finds a session and does
        // nothing; after an aborted open it still hides the sample panels.
        cancelSession()
        // Every early return closes the tap's ring too, so nav keys and clicks aren't swallowed invisibly.
        guard Permissions.isAccessibilityTrusted else { input?.abortSession(); return }
        if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           model.settings.excludedBundleIDs.contains(bundle) { input?.abortSession(); return }
        sessionCounter += 1
        let id = sessionCounter
        let lookup = Task { [windows] () -> FrontWindow? in
            guard let window = await windows.frontmostWindow() else { return nil }
            return (window, await windows.frame(of: window))
        }
        let all = displays.displays
        session = Session(id: id, origin: origin, lookup: lookup,
                          reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                          displays: all, cursor: origin, hint: model.settings.ring.pointingHintDue)
        overlay.show(origin: origin, displays: all, ring: model.settings.ring, theme: model.settings.activeTheme)
        refreshSelection()  // the cursor starts in the middle: show the cancel mark lit
        Task {
            let found = await lookup.value
            guard session?.id == id else { return }
            guard let found else {
                cancelSession()
                input?.abortSession()
                showHUD(CommandExecutor.noWindowMessage)
                return
            }
            session?.target = found.window
            session?.current = found.frame
            refreshSelection()  // the centre layout and the "from" outline need the window's frame
            loadContext(for: id, target: found.window)
        }
    }

    /// Neighbour frames and the snapshot load concurrently; late results are dropped if the session changed.
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
        switch preview.style {
        case .tint:
            break
        case .appIcon:
            // A nil rect picks the 32 pt representation, which blurs at preview size.
            var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
            session?.image = NSRunningApplication(processIdentifier: target.pid)?.icon?
                .cgImage(forProposedRect: &rect, context: nil, hints: nil)
        case .snapshot:
            guard Permissions.isScreenCaptureAllowed, let windowID = target.windowID else { break }
            Task {
                let image = await thumbnails.snapshot(windowID: windowID)
                guard session?.id == id else { return }
                session?.image = image
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
            if s.pointing { s.pointed = true }
        }
        let frame = targetFrame(for: selection, in: s)
        s.targetFrame = frame
        s.selection = selection
        if selection != .none { s.leftDeadZone = true }
        // Announcing is an accessibility round trip; only do it when someone can hear it.
        if model.settings.announceSelection, NSWorkspace.shared.isVoiceOverEnabled,
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
                             reduceMotion: s.reduceMotion),
                settings: model.settings.preview, hint: s.hint && s.nav == nil // clicks span columns; keys don't
            )
        }
        var pointMode = false
        if case .span = selection { pointMode = true }
        let cancelling = s.nav == nil
            && hypot(s.cursor.x - s.origin.x, s.cursor.y - s.origin.y) < model.settings.ring.cancelRadius
        overlay.update(selection: selection, layers: layers, image: s.image,
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
        end(s)
        // A tap: pressed and released without ever leaving the middle.
        if s.selection == .none, !s.leftDeadZone, model.settings.ring.tapTilesWindows {
            s.lookup.cancel()
            Task { await run(.tileWindows(display: .cursor)) }
            return
        }
        guard s.targetFrame != nil else { s.lookup.cancel(); return }
        // Not awaited: a glide must never hold up the next ring or hotkey.
        Task {
            // Released before the lookup finished: wait for it rather than guess the window.
            var resolved = s
            if resolved.target == nil, let found = await s.lookup.value {
                resolved.target = found.window
                resolved.current = found.frame
                resolved.targetFrame = targetFrame(for: s.selection, in: resolved)  // centre needs the size
            }
            guard let target = resolved.target, let frame = resolved.targetFrame else {
                showHUD(CommandExecutor.noWindowMessage)
                return
            }
            let result = await executor.place(target, current: resolved.current, goal: frame)
            if case let .failed(reason) = result {
                log.notice("apply failed for \(target.bundleID ?? "?", privacy: .public): \(reason, privacy: .public)")
                showHUD("Can't move this window")
            }
        }
    }

    private func cancelSession() {
        guard let s = session else { return }
        s.lookup.cancel()
        end(s)
    }

    /// Closes the session. Doesn't cancel the window lookup: `apply` may still need its result.
    private func end(_ s: Session) {
        session = nil
        overlay.hide()
        if s.hint, s.pointed {
            model.settings.ring.pointingHintsSeen = (model.settings.ring.pointingHintsSeen ?? 0) + 1
        }
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
        onSettingsChange?(settings)
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
