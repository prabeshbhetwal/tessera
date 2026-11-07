import AppKit
import TesseraCore

/// Puts a coach step on screen: a mouse-transparent dim with spotlight cut-outs (full presentation only) and a
/// clickable card beside the spotlight. One dim panel and one card panel, moved to the event's display each time:
/// the coach shows on one display at a time.
///
/// Shown on its own (`keyable == false`) the card never becomes key and never swallows a key; it reports `onClose`
/// on Esc, on any other key unless the step waits for a drag, when another app activates, or after 12 s untouched on
/// the first step. Opened on request it becomes key, and Esc or another app activating reports `onClose`. On a step
/// that waits for a drag only Esc closes it (besides its buttons): the drag itself may activate another app. The owner
/// decides when to `dismiss()`. Fades stay under Reduce Motion (a cross-fade isn't motion); the seam's pulse doesn't.
@MainActor
final class CoachController {
    var onAction: ((CoachAction) -> Void)?
    var onClose: (() -> Void)?
    /// -1 earlier, +1 later.
    var onBrowse: ((Int) -> Void)?
    var onDontShow: (() -> Void)?
    private(set) var isShowing = false

    private let dimView = CoachDimView(frame: .zero)
    private let dimPanel: NSPanel
    private let cardPanel = CoachCardPanel()
    private var hosting: CoachHostingView?
    private var keyable = false
    /// The app that was front before an on-request card took key; given the keyboard back on dismiss.
    private var previousPID: pid_t?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var autoClose: Task<Void, Never>?
    /// Bumped by every present and dismiss, so a late fade-out or watcher never acts on a newer presentation.
    private var generation = 0

    init() {
        dimPanel = OverlayController.makePanel(frame: .zero)
        dimPanel.level = .statusBar
        dimPanel.contentView = dimView
        cardPanel.onCancel = { [weak self] in self?.onClose?() }
        cardPanel.onHover = { [weak self] in
            self?.autoClose?.cancel()
            self?.autoClose = nil
        }
    }

    func present(step: CoachStep, index: Int, count: Int, event: HelpEvent, display: DisplayContext,
                 presentation: CoachPresentation, keyable: Bool, theme: Theme) {
        stopWatching()
        generation += 1
        if isShowing, self.keyable, !keyable {
            // On request → on its own: drop key and give the keyboard back before the card stops being keyable.
            cardPanel.orderOut(nil)
            restoreFocus()
        }
        if keyable, let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           front != ProcessInfo.processInfo.processIdentifier {
            previousPID = front
        }
        isShowing = true
        self.keyable = keyable

        let seam = step.spotlight == .seam
            ? CoachGeometry.seam(event.frames, portrait: event.portrait, gap: CGFloat(display.profile.gap)) : nil
        let holes = (seam.map { [$0] } ?? event.frames)
            .map { $0.insetBy(dx: -CoachGeometry.inset, dy: -CoachGeometry.inset) }
        let target: CGRect
        if presentation == .full {
            target = Self.union(holes) ?? display.visibleFrame
            showDim(holes: holes, seam: seam, display: display, theme: theme)
        } else {
            target = Self.union(event.frames) ?? display.visibleFrame
            dimPanel.orderOut(nil)
        }
        showCard(step: step, index: index, count: count, target: target, display: display)
        if !keyable {
            // The card never takes key, so VoiceOver would not notice it: announce it instead.
            NSAccessibility.post(element: cardPanel, notification: .announcementRequested, userInfo: [
                .announcement: "\(step.title). \(step.body)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
        watch(step: step, index: index)
    }

    func dismiss() {
        guard isShowing else { return }
        stopWatching()
        isShowing = false
        generation += 1
        let current = generation
        if keyable { restoreFocus() }
        cardPanel.ignoresMouseEvents = true  // a fading card takes no clicks
        let panels: [NSWindow] = [dimPanel, cardPanel].filter { $0.isVisible }
        Task { [weak self] in
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                for panel in panels { panel.animator().alphaValue = 0 }
            }
            guard let self, self.generation == current else { return }
            for panel in panels { panel.orderOut(nil) }
        }
    }

    // MARK: Panels

    private func showDim(holes: [CGRect], seam: CGRect?, display: DisplayContext, theme: Theme) {
        let frame = display.frame
        dimPanel.setFrame(frame, display: false)
        dimView.update(
            spotlights: holes.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) },
            seamRect: seam?.offsetBy(dx: -frame.minX, dy: -frame.minY), outlined: seam == nil,
            dimColor: HexColor.cgColor(theme.dimHex, alpha: theme.preview.dimStrength),
            accent: HexColor.cgColor(theme.accentHex))
        fadeIn(dimPanel)
    }

    private func showCard(step: CoachStep, index: Int, count: Int, target: CGRect, display: DisplayContext) {
        let card = CoachCardView(
            step: step, index: index, count: count, keyable: keyable,
            onAction: { [weak self] in self?.onAction?($0) },
            onBrowse: { [weak self] in self?.onBrowse?($0) },
            onDontShow: { [weak self] in self?.onDontShow?() },
            onClose: { [weak self] in self?.onClose?() })
        let hosting: CoachHostingView
        if let existing = self.hosting {
            existing.rootView = card
            hosting = existing
        } else {
            hosting = CoachHostingView(rootView: card)
            cardPanel.contentView?.addSubview(hosting)
            self.hosting = hosting
        }
        let size = hosting.fittingSize
        let origin = CoachGeometry.cardOrigin(size: size, target: target, screen: display.visibleFrame)
        cardPanel.keyable = keyable
        cardPanel.ignoresMouseEvents = false
        cardPanel.setAccessibilityLabel(step.title)
        cardPanel.setFrame(CGRect(origin: origin, size: size), display: true)
        hosting.frame = CGRect(origin: .zero, size: size)
        cardPanel.invalidateShadow()
        fadeIn(cardPanel)
    }

    /// Orders the panel front (making the card key when opened on request) and fades it in unless already shown.
    private func fadeIn(_ panel: NSWindow) {
        if !panel.isVisible { panel.alphaValue = 0 }
        if panel === cardPanel, keyable {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    /// Re-activates the app an on-request card took key from, unless the person has since moved to another app.
    private func restoreFocus() {
        defer { previousPID = nil }
        guard let previousPID else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == previousPID || front == ProcessInfo.processInfo.processIdentifier else { return }
        NSRunningApplication(processIdentifier: previousPID)?.activate()
    }

    // MARK: Auto-close

    /// Observe-only watchers; nothing here consumes an event. Each closes only the presentation it was made for, and
    /// ignores the first 300 ms so the key or activation that brought the card up can't close it.
    private func watch(step: CoachStep, index: Int) {
        let current = generation
        let start = ContinuousClock.now
        let close: @MainActor () -> Void = { [weak self] in
            guard let self, self.isShowing, self.generation == current else { return }
            self.onClose?()
        }
        let settled: @MainActor () -> Bool = { ContinuousClock.now - start >= .milliseconds(300) }
        // A "try it" step waits for a drag, and clicking the window to drag can activate its app: only Esc, Skip or
        // the card's buttons close it. Esc is watched even on a card opened on request, which loses key on that click.
        let waits = step.waitsForLearn
        if !waits {
            // Opened on request: Tessera or the app it came from may be front. On its own: only the app that was front.
            let stays: Set<pid_t?> = keyable
                ? [ProcessInfo.processInfo.processIdentifier, previousPID]
                : [NSWorkspace.shared.frontmostApplication?.processIdentifier]
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    if settled(), !stays.contains(pid) { close() }
                }
            }
        }
        guard !keyable || waits else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let escape = event.keyCode == KeyCodes.escape, repeated = event.isARepeat
            MainActor.assumeIsolated {
                if settled(), !repeated, escape || !waits { close() }
            }
        }
        guard index == 0 else { return }
        autoClose = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            close()
        }
    }

    private func stopWatching() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        autoClose?.cancel()
        autoClose = nil
    }

    private static func union(_ rects: [CGRect]) -> CGRect? {
        rects.isEmpty ? nil : rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    }
}
