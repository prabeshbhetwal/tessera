import AppKit
import TesseraCore

/// Puts a coach step on screen: a mouse-transparent dim with spotlight cut-outs (full presentation only) and a
/// clickable card beside the spotlight. One dim panel and one card panel, moved to the event's display each time:
/// the coach shows on one display at a time.
///
/// Shown on its own (`keyable == false`) the card never becomes key and never swallows a key; it reports `onClose`
/// on Esc, on any other key unless the step waits for a drag, when another app activates, or after 12 s untouched on
/// the first step. Opened on request it becomes key, and Esc reports `onClose`. The owner decides when to `dismiss()`.
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
    /// The app that was front before an on-request card took key; re-activated on dismiss.
    private var previousPID: pid_t?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var autoClose: Task<Void, Never>?
    /// Bumped by every present and dismiss, so a fade-out that finishes late never hides a newer presentation.
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
        if !isShowing { previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        isShowing = true
        self.keyable = keyable

        let seam = step.spotlight == .seam
            ? CoachGeometry.seam(event.frames, portrait: event.portrait, gap: CGFloat(display.profile.gap)) : nil
        let holes = (seam.map { [$0] } ?? event.frames)
            .map { $0.insetBy(dx: -CoachGeometry.inset, dy: -CoachGeometry.inset) }
        let target: CGRect
        if presentation == .full {
            target = Self.union(holes) ?? display.visibleFrame
            showDim(holes: holes, seam: seam, display: display, accent: HexColor.cgColor(theme.accentHex))
        } else {
            target = Self.union(event.frames) ?? display.visibleFrame
            dimPanel.orderOut(nil)
        }
        showCard(step: step, index: index, count: count, target: target, display: display)
        if !keyable { watch(step: step, index: index) }
    }

    func dismiss() {
        guard isShowing else { return }
        stopWatching()
        isShowing = false
        generation += 1
        let current = generation
        if keyable, let previousPID { NSRunningApplication(processIdentifier: previousPID)?.activate() }
        previousPID = nil
        let panels: [NSWindow] = [dimPanel, cardPanel].filter(\.isVisible)
        Task { [weak self] in
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    for panel in panels { panel.animator().alphaValue = 0 }
                }
            }
            guard let self, self.generation == current else { return }
            for panel in panels { panel.orderOut(nil) }
        }
    }

    // MARK: Panels

    private func showDim(holes: [CGRect], seam: CGRect?, display: DisplayContext, accent: CGColor) {
        let frame = display.frame
        dimPanel.setFrame(frame, display: false)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let scale = NSScreen.screens.first { $0.frame.contains(center) }?.backingScaleFactor ?? 2
        dimView.update(
            spotlights: holes.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) },
            seamRect: seam?.offsetBy(dx: -frame.minX, dy: -frame.minY),
            outlined: seam == nil, accent: accent, scale: scale)
        fadeIn(dimPanel)
    }

    private func showCard(step: CoachStep, index: Int, count: Int, target: CGRect, display: DisplayContext) {
        let card = CoachCardView(
            step: step, index: index, count: count, keyable: keyable,
            onAction: { [weak self] in self?.onAction?($0) },
            onBrowse: { [weak self] in self?.onBrowse?($0) },
            onDontShow: { [weak self] in self?.onDontShow?() })
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
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    // MARK: Auto-close

    /// Observe-only watchers for a card shown on its own. Nothing here consumes an event.
    private func watch(step: CoachStep, index: Int) {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let escape = event.keyCode == 53
            MainActor.assumeIsolated {
                if escape || !step.waitsForLearn { self?.onClose?() }
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if pid != front { self?.onClose?() }
            }
        }
        guard index == 0 else { return }
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.onClose?()
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
