import AppKit
import SwiftUI
import TesseraCore

/// Opens the Settings and Onboarding windows. The app is `.regular` (Dock icon, can take focus)
/// only while one of them is open, and returns to `.accessory` when the last one closes.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    let navigation = SettingsNavigation()
    private var displays: [DisplayContext]
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(model: SettingsModel, displays: [DisplayContext] = []) {
        self.model = model
        self.displays = displays
        super.init()
    }

    /// Call when `DisplayService` reports a change so the Displays pane lists the current screens.
    func updateDisplays(_ displays: [DisplayContext]) {
        guard displays != self.displays else { return }
        self.displays = displays
        (settingsWindow?.contentViewController as? NSHostingController<SettingsView>)?.rootView =
            SettingsView(model: model, navigation: navigation, displays: displays)
    }

    /// Opens Settings, optionally on a specific pane (the menu's "Shortcuts…" item passes `.shortcuts`).
    func showSettings(pane: SettingsPane? = nil) {
        // Every route to Settings (menu, reopen, hotkey, CLI, Shortcuts) lands here: finish setup first.
        guard Permissions.isAccessibilityTrusted else {
            showOnboarding(startStep: OnboardingView.accessibilityStep)
            return
        }
        if let pane { navigation.pane = pane }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        (window.contentViewController as? NSHostingController<SettingsView>)?.rootView =
            SettingsView(model: model, navigation: navigation, displays: displays)
        present(window)
    }

    /// Closes Settings, e.g. when Accessibility is revoked and setup has to be finished again.
    func closeSettings() {
        settingsWindow?.close()
    }

    /// `startStep` 1 jumps straight to the Accessibility step (used when permission is missing).
    func showOnboarding(startStep: Int = 0) {
        let view = OnboardingView(startStep: startStep, chord: model.settings.trigger) { [weak self] in
            self?.onboardingWindow?.close()
        }
        let controller = NSHostingController(rootView: view)
        if let window = onboardingWindow {
            window.contentViewController = controller
            present(window)
        } else {
            let window = makeWindow(title: "Welcome to Tessera", controller: controller)
            onboardingWindow = window
            present(window)
        }
    }

    private func makeSettingsWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model, navigation: navigation, displays: displays))
        // The split view reports its tallest pane as intrinsic height, taller than the screen. AppKit then keeps
        // the oversized view bottom-anchored and the top (sidebar, pane header) is clipped under the title bar.
        // Size the window here and let the view fill it instead.
        controller.sizingOptions = []
        let window = makeWindow(title: "Tessera Settings", controller: controller, resizable: true)
        // Like System Settings: fixed width, height adjustable for long panes, never zoomed or full screen.
        let width = SettingsView.width
        window.setContentSize(NSSize(width: width, height: 640))
        window.contentMinSize = NSSize(width: width, height: 540)
        window.contentMaxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.center()
        // Restores the last size and position (saved by AppKit on every move/resize) and keeps saving them.
        window.setFrameAutosaveName("TesseraSettings")
        // A saved frame can predate the fixed width, or sit on a display that's gone.
        let content = window.contentRect(forFrameRect: window.frame)
        if content.width != width {
            window.setContentSize(NSSize(width: width, height: max(content.height, window.contentMinSize.height)))
        }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        return window
    }

    private func makeWindow(title: String, controller: NSViewController, resizable: Bool = false) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        // Autosaved windows reopen where the user left them.
        if !window.isVisible, window.frameAutosaveName.isEmpty { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // Plain activate() is "cooperative" on macOS 14+ and is often ignored for a background agent,
        // which left the setup window hidden behind other apps.
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let stillOpen = [settingsWindow, onboardingWindow].contains { $0 !== closing && $0?.isVisible == true }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }
}
