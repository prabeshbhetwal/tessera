import ServiceManagement
import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

struct GeneralPane: View {
    @Bindable var model: SettingsModel
    @State private var loginError: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var ioMessage: String?
    @State private var cliInstalled = CLIInstaller.isInstalled
    @State private var cliMessage: String?
    /// Read once per appearance; `SMAppService.status` is IPC and must never run in `body`.
    @State private var loginNeedsApproval = false

    var body: some View {
        Form {
            Section("Trigger") {
                VStack(spacing: 10) {
                    KeycapRow(keys: ModifierKey.names(model.settings.trigger.keyCodes), prominent: true)
                    Text("Hold these keys together to open the ring. Release any of them to snap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                ChordRecorder(chord: $model.settings.trigger)
            }

            SnapSpeedSection(model: model)

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError { Callout(.warning, loginError) }
                if loginNeedsApproval {
                    Callout(.warning, "Approve Tessera in System Settings › General › Login Items.")
                }
                Toggle("Show menu bar icon", isOn: $model.settings.showMenuBarIcon)
                if !model.settings.showMenuBarIcon {
                    Caption("With the icon hidden, open Tessera again from Finder or Spotlight to reach Settings.")
                }
            }

            Section("Import and export") {
                HStack {
                    Button("Export settings…") { exporting = true }
                        .fileExporter(
                            isPresented: $exporting,
                            document: SettingsDocument(settings: model.settings),
                            contentType: .json,
                            defaultFilename: "Tessera Settings"
                        ) { result in
                            switch result {
                            case .success: ioMessage = "Settings exported."
                            case .failure(let error): ioMessage = "Export failed: \(error.localizedDescription)"
                            }
                        }
                    Button("Import settings…") { importing = true }
                        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                            importSettings(result)
                        }
                }
                Caption("Import replaces every setting. An invalid file is rejected and nothing changes.")
                if let ioMessage { Callout(ioMessage.hasPrefix("Settings") ? .success : .warning, ioMessage) }
            }

            Section("Command line") {
                HStack {
                    Button(cliInstalled ? "Reinstall command-line tool" : "Install command-line tool", action: installCLI)
                    Spacer()
                }
                if let cliMessage {
                    Callout(cliMessage.hasPrefix("Installed") ? .success : .warning, cliMessage)
                } else {
                    Caption("Links the tessera command to \(CLIInstaller.linkURL.path(percentEncoded: false)) so scripts and terminals can run every Tessera command.")
                }
            }

            ResetSection {
                model.settings.trigger = .default
                model.settings.showMenuBarIcon = true
                if model.settings.launchAtLogin { setLaunchAtLogin(false) }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.settings.launchAtLogin = on
            loginError = nil
            loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
    }

    private func installCLI() {
        switch CLIInstaller.install() {
        case .success(let url):
            cliInstalled = true
            let folder = url.deletingLastPathComponent().path(percentEncoded: false)
            cliMessage = "Installed at \(url.path(percentEncoded: false)). \(folder) must be on your PATH; if your shell can't find tessera, add this line to ~/.zshrc: export PATH=\"\(folder):$PATH\""
        case .failure(let error):
            cliMessage = "Couldn't install the command-line tool: \(error.localizedDescription)"
        }
    }

    private func importSettings(_ result: Result<URL, any Error>) {
        do {
            model.settings = try SettingsDocument.importSettings(from: result.get())
            ioMessage = "Settings imported."
        } catch SettingsError.invalid(let problem) {
            ioMessage = "Import rejected: \(problem)"
        } catch {
            ioMessage = "Import rejected: this isn't a Tessera settings file."
        }
    }
}

/// Preset speeds plus a seconds slider; both edit the one stored duration.
private struct SnapSpeedSection: View {
    @Bindable var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let seconds = model.settings.snapSeconds
        Section("Snap speed") {
            Picker("Speed", selection: Binding(
                get: { SnapSpeed(seconds: seconds) },
                set: { if let speed = $0 { model.settings.snapSeconds = speed.seconds } }
            )) {
                ForEach(SnapSpeed.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            SliderRow(title: "Duration", value: $model.settings.snapSeconds, range: 0...SnapSpeed.maxSeconds,
                      step: 0.01, format: { $0 == 0 ? "Instant" : String(format: "%.2f s", $0) })
            if reduceMotion, seconds > 0 {
                Caption("Reduce Motion is on in System Settings, so windows jump instead of gliding.")
            } else {
                Caption(SnapSpeed(seconds: seconds) == nil
                    ? "Custom speed. Pick a preset above or drag to any duration."
                    : "How long a window takes to glide into place, for the ring and shortcuts alike. Instant jumps straight there.")
            }
        }
    }
}

/// Records a modifier chord: hold the keys, then release them all.
struct ChordRecorder: View {
    @Binding var chord: TriggerChord
    @State private var recording = false
    @State private var peak: Set<UInt16> = []
    @State private var monitor: Any?

    var body: some View {
        Group {
            LabeledContent("Chord") {
                RecorderField(
                    title: "Trigger chord",
                    text: recording ? (peak.isEmpty ? "Hold keys…" : ModifierKey.describe(peak)) : ModifierKey.describe(chord.keyCodes),
                    recording: recording,
                    start: start,
                    clear: { chord = .default }
                )
            }
            if recording {
                Caption("Hold the modifier keys you want, then release them. Esc cancels.")
            } else if chord.keyCodes.count == 1 {
                Caption("A single-key chord opens the ring every time you press that key.")
            } else {
                Caption("Select the chord and press Space or Return to record. Delete restores the default.")
            }
        }
        .onDisappear { stop() }
        // Recording pauses Tessera's trigger and hotkeys system-wide; never leave it on when focus goes elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stop() }
    }

    private func start() {
        peak = []
        recording = true
        NotificationCenter.default.post(name: .tesseraRecorderActive, object: nil, userInfo: ["active": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { stop() }
                return nil
            }
            let held = ModifierKey.pressed(in: event.modifierFlags)
            peak.formUnion(held)
            if held.isEmpty, !peak.isEmpty {
                chord = TriggerChord(keyCodes: peak)
                stop()
            }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if recording {
            NotificationCenter.default.post(name: .tesseraRecorderActive, object: nil, userInfo: ["active": false])
        }
        monitor = nil
        recording = false
    }
}

/// JSON file wrapper for `fileExporter`, plus validated import.
struct SettingsDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var settings: TesseraSettings

    init(settings: TesseraSettings) { self.settings = settings }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        settings = try JSONDecoder().decode(TesseraSettings.self, from: SettingsMigration.migrate(data).data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(settings))
    }

    static func importSettings(from url: URL) throws -> TesseraSettings {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // M1 exports are schema v1: migrate before decoding, exactly like SettingsStore does.
        let migrated = try SettingsMigration.migrate(Data(contentsOf: url)).data
        let settings = try JSONDecoder().decode(TesseraSettings.self, from: migrated)
        guard settings.schemaVersion <= TesseraSettings.defaults.schemaVersion else {
            throw SettingsError.invalid("the file is from a newer version of Tessera")
        }
        try SettingsValidation.validate(settings)
        return settings
    }
}

#Preview {
    GeneralPane(model: SettingsModel())
}
