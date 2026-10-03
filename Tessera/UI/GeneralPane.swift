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

    var body: some View {
        Form {
            Section("Trigger") {
                ChordRecorder(chord: $model.settings.trigger)
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError { Caption(loginError) }
                if SMAppService.mainApp.status == .requiresApproval {
                    Caption("Approve Tessera in System Settings › General › Login Items.")
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
                if let ioMessage { Caption(ioMessage) }
            }

            ResetSection {
                model.settings.trigger = .default
                model.settings.showMenuBarIcon = true
                if model.settings.launchAtLogin { setLaunchAtLogin(false) }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.settings.launchAtLogin = on
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
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

/// Records a modifier chord: hold the keys, then release them all.
struct ChordRecorder: View {
    @Binding var chord: TriggerChord
    @State private var recording = false
    @State private var peak: Set<UInt16> = []
    @State private var monitor: Any?

    var body: some View {
        Group {
            LabeledContent("Chord") {
                HStack {
                    Text(recording ? (peak.isEmpty ? "Hold keys…" : ModifierKey.describe(peak)) : ModifierKey.describe(chord.keyCodes))
                        .monospaced()
                    Button(recording ? "Cancel" : "Record") { recording ? stop() : start() }
                }
            }
            if recording {
                Caption("Hold the modifier keys you want, then release them. Esc cancels.")
            } else if chord.keyCodes.count == 1 {
                Caption("A single-key chord opens the ring every time you press that key.")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        peak = []
        recording = true
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
        settings = try JSONDecoder().decode(TesseraSettings.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(settings))
    }

    static func importSettings(from url: URL) throws -> TesseraSettings {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let settings = try JSONDecoder().decode(TesseraSettings.self, from: Data(contentsOf: url))
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
