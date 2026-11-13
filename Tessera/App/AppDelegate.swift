import AppKit
import os
import TesseraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SettingsModel()
    /// Sparkle starts once the loaded settings are first applied to it.
    let updates = UpdateService.shared
    private(set) var coordinator: Coordinator?
    private var statusItem: StatusItemController?
    private var helpCenter: HelpCenter?
    private var permissionObserver: NSObjectProtocol?
    /// URLs that arrive before the coordinator exists (app launched by a `tessera://` link).
    private var pendingURLs: [URL] = []
    /// CLI endpoint; answers "still starting up" until the executor exists.
    private let socketServer = SocketServer()
    private let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "app")
    /// Quit is held for the settings flush (see `applicationShouldTerminate`).
    private var awaitingSave = false
    /// The event tap failed and the alert has shown; it shows again only after a start succeeds or the grant is lost.
    private var tapFailing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SettingsSnapshots.runIfRequested() { return }
        #endif
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
                Task { await coordinator.run(command, source: .menu) }
            },
            currentDisplay: { [weak self] in await self?.coordinator?.executor.currentDisplay() }
        )
        guard let fileURL = Self.settingsURL() else {
            // Without it every command would answer "still starting up" for good: say so and quit instead.
            log.fault("no Application Support directory")
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Tessera can’t store its settings"
            alert.informativeText = "macOS didn’t give Tessera an Application Support folder, so it can’t save "
                + "or load settings. Tessera will quit."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let store = SettingsStore(fileURL: fileURL)
        // Sparkle's alert can change "install automatically"; the write saves like a Settings edit, and the
        // re-apply that follows matches what Sparkle already holds, so it never echoes back.
        updates.onInstallAutomaticallyChange = { [weak self] in self?.model.settings.updates.installAutomatically = $0 }
        // Weak here too, or the strong capture makes every `[weak self]` stored below meaningless.
        Task { [weak self] in
            guard let self else { return }
            let loaded = await store.load()
            model.settings = loaded.settings
            applyAppSettings(loaded.settings)
            let coordinator = Coordinator(model: model, store: store)
            coordinator.onSettingsChange = { [weak self] in self?.applyAppSettings($0) }
            self.coordinator = coordinator
            wireHelp(coordinator)
            CommandBridge.executor = coordinator.executor
            let queued = pendingURLs
            pendingURLs = []
            for url in queued { await handle(url, with: coordinator) }
            if let notice = loaded.notice { showSettingsNotice(notice) }
            permissionObserver = Permissions.observeAccessibility { [weak self] granted in
                self?.permissionChanged(granted)
            }
            // Setup interrupted by a relaunch (System Settings' "Quit & Reopen" after a permission grant)
            // picks up at the step it was on.
            let resumeStep = OnboardingView.savedStep
            if Permissions.isAccessibilityTrusted, coordinator.start() {
                tapRecovered()
                statusItem?.accessibilityGranted = true
                if let resumeStep { coordinator.presenter.showOnboarding(startStep: resumeStep) }
            } else if Permissions.isAccessibilityTrusted {
                tapFailed()
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

    /// Writes a settings change still waiting on its debounce (an edit just before Quit or a Sparkle relaunch).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        awaitingSave = true
        Task {
            await coordinator.flushSave()
            replyToTerminate()
        }
        // A stuck disk must never stop Tessera quitting.
        Task {
            try? await Task.sleep(for: .seconds(2))
            replyToTerminate()
        }
        return .terminateLater
    }

    private func replyToTerminate() {
        guard awaitingSave else { return }
        awaitingSave = false
        NSApp.reply(toApplicationShouldTerminate: true)
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
            coordinator.showHUD("Settings import/export isn’t available from URLs")
        default:
            await coordinator.run(command, source: .automation)
        }
    }

    /// The coach hears every command result, split watcher event and What Just Happened? request.
    private func wireHelp(_ coordinator: Coordinator) {
        let help = HelpCenter(
            model: model, displays: coordinator.displays, executor: coordinator.executor,
            presenter: coordinator.presenter,
            showHUD: { [weak coordinator] in coordinator?.showHUD($0) },
            isRingOpen: { [weak coordinator] in coordinator?.isRingOpen ?? false })
        helpCenter = help
        coordinator.executor.onEvent = { [weak help] in help?.record($0) }
        coordinator.executor.splitWatcher.onHelpEvent = { [weak help] in help?.record($0) }
        coordinator.executor.onExplain = { [weak help] in help?.explainLatest() }
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
            if coordinator?.start() == false { tapFailed() } else { tapRecovered() }
        } else {
            tapRecovered()
            coordinator?.stop()
            coordinator?.presenter.closeSettings()
            coordinator?.presenter.showOnboarding(startStep: OnboardingView.accessibilityStep)
        }
    }

    /// Accessibility reads as granted but macOS refused the event tap. The known cause is a stale Accessibility entry
    /// from an older (differently signed) build, which onboarding can't detect because it shows the grant as done.
    private func tapFailed() {
        log.error("Accessibility is granted but the event tap could not be created; stale permission entry?")
        statusItem?.accessibilityGranted = false
        statusItem?.tapFailed = true
        OnboardingView.tapFailed = true
        // Every Accessibility change notification lands here while the failure lasts: alert once per streak.
        guard !tapFailing else { return }
        tapFailing = true
        let alert = NSAlert()
        alert.messageText = "Tessera can’t read the trigger"
        alert.informativeText = "Accessibility is allowed, but macOS won’t let Tessera watch the keyboard and mouse. "
            + "An older Tessera build may hold a stale entry. Open System Settings, remove Tessera from "
            + "Accessibility, then grant it again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { Permissions.openPrivacyPane("Privacy_Accessibility") }
    }

    /// The tap works again (or the grant is gone, which setup handles): clear the tap-failed state.
    private func tapRecovered() {
        tapFailing = false
        statusItem?.tapFailed = false
        OnboardingView.tapFailed = false
    }

    private func anotherInstanceIsRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        // A dying instance (a relaunch racing its quit) doesn't count, or neither would be left running.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        others.first?.activate()
        return !others.isEmpty
    }

    /// What load did to the settings file: reset, repaired, or left alone with saving off for this run.
    private func showSettingsNotice(_ notice: (title: String, message: String)) {
        let alert = NSAlert()
        alert.messageText = notice.title
        alert.informativeText = notice.message
        alert.runModal()
    }

    static func settingsURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tessera", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
