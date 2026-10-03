import AppKit
import os
import TesseraCore

/// Owns one trigger session at a time and wires services, engine and overlay together (spec §5.3).
@MainActor
final class Coordinator {
    let model: SettingsModel
    let displays: DisplayService
    let presenter: WindowPresenter
    private let store: SettingsStore
    private let windows = WindowService()
    private let thumbnails = ThumbnailService()
    private let overlay = OverlayController()
    private var input: InputService?
    private var engine: SelectionEngine
    private var session: Session?
    private var sessionCounter = 0
    private var saveTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "coordinator")

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
    }

    init(model: SettingsModel, store: SettingsStore) {
        self.model = model
        self.store = store
        self.engine = SelectionEngine(ring: model.settings.ring)
        let displays = DisplayService(settings: { [unowned model] in model.settings })
        self.displays = displays
        self.presenter = WindowPresenter(model: model, displays: displays.displays)
        displays.onChange = { [weak self] in self?.displaysChanged() }
        model.onChange = { [weak self] in self?.settingsChanged($0) }
    }

    /// Starts the event tap. Returns false when Accessibility is missing or the tap can't be created.
    @discardableResult
    func start() -> Bool {
        guard input == nil else { return true }
        guard Permissions.isAccessibilityTrusted else { return false }
        let (stream, continuation) = AsyncStream.makeStream(of: TriggerOutput.self)
        let service = InputService(chord: model.settings.trigger) { continuation.yield($0) }
        service.updatePrimaryHeight(DisplayService.primaryHeight)
        guard service.start() else {
            log.error("event tap could not be created")
            return false
        }
        input = service
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

    // MARK: - Trigger outputs

    private func handle(_ output: TriggerOutput) async {
        switch output {
        case let .open(origin): await open(at: origin)
        case let .move(point):
            session?.cursor = point
            refreshSelection()
        case let .anchor(point):
            guard var s = session else { return }
            s.anchor = engine.anchor(at: point, displays: s.displays)
            s.cursor = point
            session = s
            refreshSelection()
        case let .step(delta): step(delta)
        case .apply: await apply()
        case .cancel: cancelSession()
        }
    }

    private func open(at origin: CGPoint) async {
        cancelSession()
        guard Permissions.isAccessibilityTrusted else { return }
        if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           model.settings.excludedBundleIDs.contains(bundle) { return }
        guard let target = await windows.frontmostWindow() else {
            overlay.showHUD("No window to move")
            return
        }
        let current = await windows.frame(of: target)
        sessionCounter += 1
        let id = sessionCounter
        session = Session(id: id, origin: origin, target: target, current: current,
                          displays: displays.displays, cursor: origin)
        overlay.show(origin: origin, displays: displays.displays, ring: model.settings.ring, theme: model.settings.activeTheme)
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

    private func refreshSelection() {
        guard var s = session else { return }
        let selection = engine.select(origin: s.origin, cursor: s.cursor, displays: s.displays, anchor: s.anchor)
        let frame = targetFrame(for: selection, in: s)
        s.targetFrame = frame
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
        overlay.update(selection: selection, layers: layers, thumbnail: s.thumbnail,
                       displays: s.displays, pointMode: pointMode)
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

    private func step(_ delta: Int) {
        guard let s = session,
              let display = s.displays.display(at: s.cursor) else { return }
        let columns = min(max(display.profile.columns + delta, display.range.minCols), display.range.maxCols)
        guard columns != display.profile.columns else { return }
        var profile = display.profile
        profile.columns = columns
        profile.isUserOverride = true
        // Mutating settings triggers settingsChanged → save + display refresh.
        model.settings.displayOverrides[display.id.storageKey] = profile
        session?.displays = displays.displays
        session?.anchor = nil
        refreshSelection()
    }

    private func apply() async {
        guard let s = session else { return }
        session = nil
        overlay.hide()
        guard let frame = s.targetFrame else { return }
        let fromDisplay = s.current.flatMap { cur in
            s.displays.display(at: CGPoint(x: cur.midX, y: cur.midY))?.id
        }
        let toDisplay = s.displays.first { $0.visibleFrame.intersects(frame) }?.id
        let result = await windows.apply(frame, to: s.target, primaryHeight: DisplayService.primaryHeight,
                                         crossingDisplays: fromDisplay != toDisplay)
        if case let .failed(reason) = result {
            log.notice("apply failed for \(s.target.bundleID ?? "?", privacy: .public): \(reason, privacy: .public)")
            overlay.showHUD("Can't move this window")
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
        input?.updateChord(settings.trigger)
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
