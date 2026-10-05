import AppKit
import os
import TesseraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SettingsModel()
    /// Sparkle starts when this is first touched, i.e. as the delegate is created at launch.
    let updates = UpdateService.shared
    private(set) var coordinator: Coordinator?
    private var statusItem: StatusItemController?
    private var permissionObserver: NSObjectProtocol?
    /// URLs that arrive before the coordinator exists (app launched by a `tessera://` link).
    private var pendingURLs: [URL] = []
    /// CLI endpoint; answers "still starting up" until the executor exists.
    private let socketServer = SocketServer()
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !anotherInstanceIsRunning() else {
            NSApp.terminate(nil)
            return
        }
        // After the single-instance guard: start() replaces any existing socket file.
        socketServer.start()
        switch CLIInstaller.repairIfStale() {
        case .success(let link)?: log.info("repointed \(link.path, privacy: .public) at this build")
        case .failure(let error)?: log.error("CLI link repair failed: \(error.localizedDescription, privacy: .public)")
        case nil: break
        }
        statusItem = StatusItemController(
            model: model,
            updates: updates,
            presenter: { [weak self] in self?.coordinator?.presenter },
            run: { [weak self] command in
                guard let coordinator = self?.coordinator else { return }
                Task { await coordinator.run(command) }
            }
        )
        guard let fileURL = Self.settingsURL() else {
            log.fault("no Application Support directory")
            return
        }
        let store = SettingsStore(fileURL: fileURL)
        Task {
            let loaded = await store.load()
            model.settings = loaded.settings
            applyAppSettings(loaded.settings)
            let coordinator = Coordinator(model: model, store: store)
            coordinator.onSettingsChange = { [weak self] in self?.applyAppSettings($0) }
            self.coordinator = coordinator
            CommandBridge.executor = coordinator.executor
            let queued = pendingURLs
            pendingURLs = []
            for url in queued { await handle(url, with: coordinator) }
            if let recovered = loaded.recoveredFrom { showRecoveryAlert(recovered) }
            permissionObserver = Permissions.observeAccessibility { [weak self] granted in
                self?.permissionChanged(granted)
            }
            // Setup interrupted by a relaunch (System Settings' "Quit & Reopen" after a permission grant)
            // picks up at the step it was on.
            let resumeStep = OnboardingView.savedStep
            if Permissions.isAccessibilityTrusted, coordinator.start() {
                statusItem?.accessibilityGranted = true
                if let resumeStep { coordinator.presenter.showOnboarding(startStep: resumeStep) }
            } else {
                statusItem?.accessibilityGranted = false
                coordinator.presenter.showOnboarding(startStep: min(resumeStep ?? 0, OnboardingView.accessibilityStep))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The menu bar icon can be hidden; relaunching the app is the way back to Settings.
        coordinator?.presenter.showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer.stop()
        coordinator?.stop()
    }

    /// `tessera://` URLs (M2 spec §5): fire-and-forget; errors are logged and shown in the HUD.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else {
            pendingURLs += urls
            return
        }
        Task {
            for url in urls { await handle(url, with: coordinator) }
        }
    }

    private func handle(_ url: URL, with coordinator: Coordinator) async {
        let command: Command
        do {
            command = try CommandParser.parse(url: url)
        } catch {
            let message = if case let CommandParseError.invalid(m) = error { m } else { error.localizedDescription }
            log.notice("bad URL \(url.absoluteString, privacy: .public): \(message, privacy: .public)")
            coordinator.showHUD(message)
            return
        }
        // Any web page can open a URL, so file access stays with the CLI and AppleScript.
        switch command {
        case .exportSettings, .importSettings:
            log.notice("refused settings file command from URL")
            coordinator.showHUD("Settings import/export isn't available from URLs")
        default:
            await coordinator.run(command)
        }
    }

    /// App-level settings that live outside the coordinator: the menu bar item, the windows' appearance and updates.
    private func applyAppSettings(_ settings: TesseraSettings) {
        statusItem?.apply(settings)
        updates.apply(settings.updates)
        let appearance: NSAppearance? = switch settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance != appearance { NSApp.appearance = appearance }
    }

    private func permissionChanged(_ granted: Bool) {
        statusItem?.accessibilityGranted = granted
        if granted {
            coordinator?.start()
        } else {
            coordinator?.stop()
            coordinator?.presenter.closeSettings()
            coordinator?.presenter.showOnboarding(startStep: OnboardingView.accessibilityStep)
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
