import AppKit
import Observation
import os
import TesseraCore

/// App-wide state the menu bar reads.
@MainActor @Observable
final class AppState {
    var accessibilityGranted = Permissions.isAccessibilityTrusted
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SettingsModel()
    let state = AppState()
    private(set) var coordinator: Coordinator?
    private var permissionObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !anotherInstanceIsRunning() else {
            NSApp.terminate(nil)
            return
        }
        guard let fileURL = Self.settingsURL() else {
            log.fault("no Application Support directory")
            return
        }
        let store = SettingsStore(fileURL: fileURL)
        Task {
            let loaded = await store.load()
            model.settings = loaded.settings
            let coordinator = Coordinator(model: model, store: store)
            self.coordinator = coordinator
            if let recovered = loaded.recoveredFrom { showRecoveryAlert(recovered) }
            permissionObserver = Permissions.observeAccessibility { [weak self] granted in
                self?.permissionChanged(granted)
            }
            if Permissions.isAccessibilityTrusted, coordinator.start() {
                state.accessibilityGranted = true
            } else {
                state.accessibilityGranted = false
                coordinator.presenter.showOnboarding()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The menu bar icon can be hidden; relaunching the app is the way back to Settings.
        coordinator?.presenter.showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    private func permissionChanged(_ granted: Bool) {
        state.accessibilityGranted = granted
        if granted {
            coordinator?.start()
        } else {
            coordinator?.stop()
        }
    }

    private func anotherInstanceIsRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me }
        others.first?.activate()
        return !others.isEmpty
    }

    private func showRecoveryAlert(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Settings were reset"
        alert.informativeText = "Tessera couldn't read its settings file, so it started with defaults. "
            + "The old file was kept at \(url.path)."
        alert.runModal()
    }

    static func settingsURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tessera", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
