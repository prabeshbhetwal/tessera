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
        if !window.isVisible { fitSettingsWindow(window) }
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
        // Fixed size, never resized by the user, zoomed or made full screen. Only the position is remembered.
        let window = makeWindow(title: "Tessera Settings", controller: controller)
        window.collectionBehavior.insert(.fullScreenNone)
        window.center()
        window.setFrameAutosaveName("TesseraSettings")
        fitSettingsWindow(window)
        return window
    }

    /// The window's one size for the screen it is on: 820 × 720 points, smaller only when the screen is.
    /// Re-applied on every open, so a frame saved by an older build or on another display can't stick.
    private func fitSettingsWindow(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(SettingsView.width, visible.width - 40),
                          height: min(SettingsView.height, visible.height - 60))
        window.contentMinSize = size
        window.contentMaxSize = size
        if window.contentRect(forFrameRect: window.frame).size != size {
            let top = window.frame.maxY
            window.setContentSize(size)
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
        if !visible.contains(window.frame) {
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(window.frame) }) { return }
            window.center()
        }
    }

    private func makeWindow(title: String, controller: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
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
        // Closing setup (Done, Esc or the close button) ends it; quitting the app does not close windows,
        // so a "Quit & Reopen" keeps the saved step and setup resumes there.
        if closing === onboardingWindow { OnboardingView.saveStep(nil) }
        let stillOpen = [settingsWindow, onboardingWindow].contains { $0 !== closing && $0?.isVisible == true }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }
}
