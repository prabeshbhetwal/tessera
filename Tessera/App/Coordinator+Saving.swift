import os
import TesseraCore

/// Settings writes: debounced while the person edits, flushed when the app quits (see `AppDelegate`).
extension Coordinator {
    private static let saveLog = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "coordinator")

    /// Writes `settings` once edits pause for 300 ms; a newer change replaces it.
    func scheduleSave(_ settings: TesseraSettings) {
        saveTask?.cancel()
        unsavedSettings = settings
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.writeUnsaved()
        }
    }

    /// Writes any change still waiting on the debounce, after a write already under way finishes.
    func flushSave() async {
        let pending = saveTask
        pending?.cancel()
        await pending?.value
        await writeUnsaved()
    }

    private func writeUnsaved() async {
        guard let settings = unsavedSettings else { return }
        unsavedSettings = nil
        do {
            try await store.save(settings)
            saveFailing = false
        } catch let refusal as SettingsStore.SaveRefusal {
            // The launch alert already said changes aren't saved this run (the file on disk is being kept);
            // a HUD per edit would only repeat it. Logged once.
            if !saveFailing { Self.saveLog.notice("settings not saved this run: \(String(describing: refusal), privacy: .public)") }
            saveFailing = true
        } catch {
            Self.saveLog.error("settings save failed: \(error.localizedDescription, privacy: .public)")
            // Once per run of failures, even with messages turned off: the change would be lost silently otherwise.
            if !saveFailing { showHUD("Couldn’t save settings", always: true) }
            saveFailing = true
        }
    }
}
