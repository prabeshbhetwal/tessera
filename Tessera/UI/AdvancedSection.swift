import os
import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

/// General › Advanced: settings export and import, and the command-line tool.
/// Failures show a plain sentence with a way to retry; the raw error goes to the log, never to the user.
struct AdvancedSection: View {
    @Bindable var model: SettingsModel
    @State private var exporting = false
    @State private var importing = false
    /// A decoded file waiting for the person to confirm it replaces every setting, and what decoding fixed in it.
    @State private var pendingImport: (settings: TesseraSettings, repairs: [String])?
    @State private var confirmingImport = false
    @State private var ioMessage: Outcome?
    @State private var cliInstalled = CLIInstaller.isInstalled
    @State private var cliMessage: CLIOutcome?

    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "settings-ui")

    var body: some View {
        Section {
            DisclosureGroup {
                HStack {
                    Button("Export Settings…") { exporting = true }
                        .fileExporter(
                            isPresented: $exporting,
                            document: SettingsDocument(settings: model.settings),
                            contentType: .json,
                            defaultFilename: "Tessera Settings"
                        ) { result in exported(result) }
                    Button("Import Settings…") { importing = true }
                        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                            importSettings(result)
                        }
                }
                .confirmationDialog("Replace all settings with this file?", isPresented: $confirmingImport,
                                    titleVisibility: .visible, presenting: pendingImport) { imported in
                    Button("Replace Settings", role: .destructive) {
                        model.settings = imported.settings
                        pendingImport = nil
                        ioMessage = .success("Settings imported.")
                    }
                    Button("Cancel", role: .cancel) { pendingImport = nil }
                } message: { imported in
                    Text(Self.importMessage(repairs: imported.repairs))
                }
                if let ioMessage { ioCallout(ioMessage) }

                HStack {
                    Button(cliInstalled ? "Reinstall Command-Line Tool" : "Install Command-Line Tool", action: installCLI)
                    Spacer()
                }
                switch cliMessage {
                case .installed(let folder):
                    let exportLine = "export PATH=\"\(folder):$PATH\""
                    Callout(.success, "Installed. If your shell can’t find tessera, add \(folder) to your PATH:")
                    // The copy action sits on the line it copies.
                    HStack(spacing: 6) {
                        Text(exportLine)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        CopyButton(text: exportLine, label: "Copy command")
                        Spacer(minLength: 0)
                    }
                case .failed(let reason):
                    Callout(.warning, reason) {
                        Button("Try Again", action: installCLI).controlSize(.small)
                    }
                case nil:
                    EmptyView()
                }
            } label: {
                InfoHeader("Advanced", info: "Export or import all your settings as a file. Importing replaces everything; an invalid file changes nothing. The command-line tool lets scripts run any Tessera command.")
            }
            .settingAnchor("Advanced")
        }
    }

    @ViewBuilder private func ioCallout(_ outcome: Outcome) -> some View {
        switch outcome {
        case .success(let text):
            Callout(.success, text)
        case .failure(let text, let retry):
            Callout(.warning, text) {
                Button(retry == .export ? "Try Again" : "Choose Another File…") {
                    if retry == .export { exporting = true } else { importing = true }
                }
                .controlSize(.small)
            }
        }
    }

    /// The warning, then what the file needed fixing (the same bullets as the launch notice), so nothing is dropped silently.
    private static func importMessage(repairs: [String]) -> String {
        let warning = "This replaces every setting, including shortcuts and cycles. Export first to keep a copy."
        guard !repairs.isEmpty else { return warning }
        let what = repairs.count == 1 ? "1 setting" : "\(repairs.count) settings"
        return warning + "\n\nTessera fixed \(what) in this file that it couldn’t use and kept everything else."
            + SettingsStore.LoadResult.repairList(repairs)
    }

    private func exported(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            ioMessage = .success("Settings exported.")
        case .failure(let error):
            guard !Self.cancelled(error) else { return }
            Self.log.error("Settings export failed: \(error.localizedDescription, privacy: .private)")
            ioMessage = .failure("Couldn’t export the settings. Choose another folder and try again.", retry: .export)
        }
    }

    private func importSettings(_ result: Result<URL, any Error>) {
        do {
            // Decoded and validated now, applied only once confirmed: an invalid file never reaches the dialog.
            pendingImport = try SettingsDocument.importSettings(from: result.get())
            ioMessage = nil
            confirmingImport = true
        } catch SettingsError.invalid(let problem) {
            ioMessage = .failure("Import rejected: \(problem)", retry: .importing)
        } catch {
            guard !Self.cancelled(error) else { return }
            Self.log.error("Settings import failed: \(error.localizedDescription, privacy: .private)")
            ioMessage = .failure("Couldn’t read that file as Tessera settings. Choose a file exported from Tessera.",
                                 retry: .importing)
        }
    }

    private func installCLI() {
        switch CLIInstaller.install() {
        case .success(let url):
            cliInstalled = true
            cliMessage = .installed(folder: url.deletingLastPathComponent().path(percentEncoded: false))
        case .failure(let error):
            Self.log.error("Command-line tool install failed: \(error.localizedDescription, privacy: .private)")
            cliMessage = .failed(cliFailure(error))
        }
    }

    private func cliFailure(_ error: Error) -> String {
        switch error as? CLIInstaller.InstallError {
        case .missingBinary: "The command-line tool is missing from this copy of Tessera. Reinstall Tessera, then try again."
        case .occupied: "Another file named tessera is already in that folder. Remove or rename it, then try again."
        case nil: "Couldn’t install the command-line tool. Check that the folder is writable, then try again."
        }
    }

    private static func cancelled(_ error: Error) -> Bool { (error as? CocoaError)?.code == .userCancelled }
}

/// Outcome shown under a button, so the callout's kind never depends on sniffing the text.
enum Outcome: Equatable {
    enum Retry { case export, importing }

    case success(String)
    case failure(String, retry: Retry)
}

enum CLIOutcome: Equatable {
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
    static func importSettings(from url: URL) throws -> (settings: TesseraSettings, repairs: [String]) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let decoded = try SettingsStore.decode(Data(contentsOf: url))
        return (decoded.settings, decoded.repairs)
    }
}
