import ServiceManagement
import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

struct GeneralPane: View {
    @Bindable var model: SettingsModel
    @State private var loginError: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var ioMessage: Outcome?
    @State private var cliInstalled = CLIInstaller.isInstalled
    @State private var cliMessage: CLIOutcome?
    /// Read once per appearance; `SMAppService.status` is IPC and must never run in `body`.
    @State private var loginNeedsApproval = false
    @State private var recordingChord = false

    var body: some View {
        Form {
            Section {
                KeycapRow(keys: ModifierKey.names(model.settings.trigger.keyCodes), prominent: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                ChordRecorder(chord: $model.settings.trigger, recording: $recordingChord)
            } header: {
                Text("Trigger")
            } footer: {
                Footer(recordingChord
                    ? "Hold the modifier keys you want, then release them. Esc cancels."
                    : model.settings.trigger.keyCodes.count == 1
                        ? "A single-key chord opens the ring every time you press that key."
                        : "Hold these keys to open the ring; release to snap. Click the chord to record a new one, or select it and press Delete for the default.")
            }

            Section {
                AppearancePicker(selection: $model.settings.appearance)
            } header: {
                Text("Appearance")
            } footer: {
                Footer("Light or dark for Tessera's windows. Match System follows macOS. The on-screen ring has its own colours in Overlay.")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError { Callout(.warning, loginError) }
                if loginNeedsApproval {
                    Callout(.warning, "Approve Tessera in System Settings › General › Login Items.")
                }
            } header: {
                Text("App")
            }

            UpdatesSection(model: model)

            Section {
                Toggle("Show the menu bar icon", isOn: $model.settings.showMenuBarIcon)
                Group {
                    LabeledContent("Icon") {
                        Picker("Icon", selection: $model.settings.menuBarIcon) {
                            ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                                Image(systemName: icon.rawValue)
                                    .accessibilityLabel(icon.displayName)
                                    .help(icon.displayName)
                                    .tag(icon)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle("Status line (how to snap)", isOn: $model.settings.menuBarItems.statusLine)
                    Toggle("Snap Front Window submenu", isOn: $model.settings.menuBarItems.snapSubmenu)
                    Toggle("Columns submenu", isOn: $model.settings.menuBarItems.columnsSubmenu)
                    Toggle("Shortcuts…", isOn: $model.settings.menuBarItems.shortcuts)
                    Toggle("Undo Last Move", isOn: $model.settings.menuBarItems.undo)
                    Toggle("Check for Updates…", isOn: $model.settings.menuBarItems.checkForUpdates)
                }
                .disabled(!model.settings.showMenuBarIcon)
            } header: {
                Text("Menu bar")
            } footer: {
                Footer(model.settings.showMenuBarIcon
                    ? "Choose what the menu shows. Settings… and Quit are always there."
                    : "With the icon hidden, open Tessera from Finder or Spotlight to reach Settings.")
            }

            Section {
                Toggle("Show messages", isOn: $model.settings.showHUD)
                Group {
                    Picker("Position", selection: $model.settings.hudPosition) {
                        ForEach(HUDPosition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    SliderRow(title: "Stays for", value: $model.settings.hudSeconds, range: 0.5...5, step: 0.1,
                              format: { String(format: "%.1f s", $0) })
                }
                .disabled(!model.settings.showHUD)
            } header: {
                Text("Messages")
            } footer: {
                Footer("Shortcut confirmations and short results such as \u{201C}5 columns\u{201D}, shown on the screen under the mouse.")
            }

            Section {
                HStack {
                    Button("Export settings…") { exporting = true }
                        .fileExporter(
                            isPresented: $exporting,
                            document: SettingsDocument(settings: model.settings),
                            contentType: .json,
                            defaultFilename: "Tessera Settings"
                        ) { result in
                            switch result {
                            case .success: ioMessage = .success("Settings exported.")
                            case .failure(let error): ioMessage = .failure("Export failed: \(error.localizedDescription)")
                            }
                        }
                    Button("Import settings…") { importing = true }
                        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                            importSettings(result)
                        }
                }
                if let ioMessage { Callout(ioMessage.kind, ioMessage.text) }
            } header: {
                Text("Import and export")
            } footer: {
                Footer("Import replaces every setting. An invalid file is rejected and nothing changes.")
            }

            Section {
                HStack {
                    Button(cliInstalled ? "Reinstall Command-Line Tool" : "Install Command-Line Tool", action: installCLI)
                    Spacer()
                }
                switch cliMessage {
                case .installed(let folder):
                    Callout(.success, "Installed. If your shell can't find tessera, add \(folder) to your PATH:") {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("export PATH=\"\(folder):$PATH\"", forType: .string)
                        }
                        .controlSize(.small)
                    }
                    Text("export PATH=\"\(folder):$PATH\"")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                case .failed(let reason):
                    Callout(.warning, reason)
                case nil:
                    EmptyView()
                }
            } header: {
                Text("Command line")
            } footer: {
                Footer("Links the tessera command into \(CLIInstaller.linkURL.deletingLastPathComponent().path(percentEncoded: false)) so scripts and terminals can run every Tessera command.")
            }

            ResetSection {
                model.settings.trigger = .default
                model.settings.showMenuBarIcon = true
                model.settings.showHUD = true
                model.settings.hudPosition = .bottom
                model.settings.hudSeconds = TesseraSettings.defaults.hudSeconds
                model.settings.menuBarIcon = .grid
                model.settings.menuBarItems = MenuBarItems()
                model.settings.appearance = .system
                model.settings.snapSeconds = SnapSpeed.instant.seconds
                model.settings.updates = UpdateSettings()
                if model.settings.launchAtLogin { setLaunchAtLogin(false) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The system owns the truth: the user may have removed Tessera from Login Items.
            let status = SMAppService.mainApp.status
            loginNeedsApproval = status == .requiresApproval
            if status == .enabled || status == .notRegistered { model.settings.launchAtLogin = status == .enabled }
        }
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
            cliMessage = .installed(folder: url.deletingLastPathComponent().path(percentEncoded: false))
        case .failure(let error):
            cliMessage = .failed("Couldn't install the command-line tool: \(error.localizedDescription)")
        }
    }

    private func importSettings(_ result: Result<URL, any Error>) {
        do {
            model.settings = try SettingsDocument.importSettings(from: result.get())
            ioMessage = .success("Settings imported.")
        } catch SettingsError.invalid(let problem) {
            ioMessage = .failure("Import rejected: \(problem)")
        } catch {
            ioMessage = .failure("Import rejected: this isn't a Tessera settings file.")
        }
    }
}

/// Outcome shown under a button, so the callout's kind never depends on sniffing the text.
enum Outcome: Equatable {
    case success(String)
    case failure(String)

    var kind: Callout<EmptyView>.Kind { if case .success = self { .success } else { .warning } }
    var text: String {
        switch self {
        case .success(let t), .failure(let t): t
        }
    }
}

private enum CLIOutcome: Equatable {
    case installed(folder: String)
    case failed(String)
}

/// JSON file wrapper for `fileExporter`, plus validated import.
struct SettingsDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var settings: TesseraSettings

    init(settings: TesseraSettings) { self.settings = settings }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        settings = try SettingsStore.decode(data).settings
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(settings))
    }

    /// Same migrate → decode → validate path as the store, so the UI and the CLI accept the same files.
    static func importSettings(from url: URL) throws -> TesseraSettings {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try SettingsStore.decode(Data(contentsOf: url)).settings
    }
}

#Preview {
    GeneralPane(model: SettingsModel())
}
