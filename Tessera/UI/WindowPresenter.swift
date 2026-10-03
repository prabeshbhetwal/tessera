import AppKit
import SwiftUI
import TesseraCore

/// Opens the Settings and Onboarding windows. The app is `.regular` (Dock icon, can take focus)
/// only while one of them is open, and returns to `.accessory` when the last one closes.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private let model: SettingsModel
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
        self.displays = displays
        (settingsWindow?.contentViewController as? NSHostingController<SettingsView>)?.rootView =
            SettingsView(model: model, displays: displays)
    }

    func showSettings() {
        let window = settingsWindow ?? makeWindow(
            title: "Tessera Settings",
            controller: NSHostingController(rootView: SettingsView(model: model, displays: displays))
        )
        settingsWindow = window
        updateDisplays(displays)
        present(window)
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

    private func makeWindow(title: String, controller: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let stillOpen = [settingsWindow, onboardingWindow].contains { $0 !== closing && $0?.isVisible == true }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }
}
