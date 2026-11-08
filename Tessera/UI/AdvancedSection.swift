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
    @State private var ioMessage: Outcome?
    @State private var cliInstalled = CLIInstaller.isInstalled
    @State private var cliMessage: CLIOutcome?

    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "settings-ui")

    var body: some View {
        Section {
            DisclosureGroup("Advanced") {
                HStack {
                    Button("Export settings…") { exporting = true }
                        .fileExporter(
                            isPresented: $exporting,
                            document: SettingsDocument(settings: model.settings),
                            contentType: .json,
                            defaultFilename: "Tessera Settings"
                        ) { result in exported(result) }
                    Button("Import settings…") { importing = true }
                        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                            importSettings(result)
                        }
                }
                if let ioMessage { ioCallout(ioMessage) }

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
                    Callout(.warning, reason) {
                        Button("Try Again", action: installCLI).controlSize(.small)
                    }
                case nil:
                    EmptyView()
                }
            }
        } footer: {
            Footer("Import replaces every setting; an invalid file changes nothing. The command-line tool links tessera into \(CLIInstaller.linkURL.deletingLastPathComponent().path(percentEncoded: false)) so scripts can run every Tessera command.")
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

    private func exported(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            ioMessage = .success("Settings exported.")
        case .failure(let error):
            guard !Self.cancelled(error) else { return }
            Self.log.error("Settings export failed: \(error.localizedDescription, privacy: .private)")
            ioMessage = .failure("Couldn't export the settings. Choose another folder and try again.", retry: .export)
        }
    }

    private func importSettings(_ result: Result<URL, any Error>) {
        do {
            model.settings = try SettingsDocument.importSettings(from: result.get())
            ioMessage = .success("Settings imported.")
        } catch SettingsError.invalid(let problem) {
            ioMessage = .failure("Import rejected: \(problem)", retry: .importing)
        } catch {
            guard !Self.cancelled(error) else { return }
            Self.log.error("Settings import failed: \(error.localizedDescription, privacy: .private)")
            ioMessage = .failure("Couldn't read that file as Tessera settings. Choose a file exported from Tessera.",
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
        case nil: "Couldn't install the command-line tool. Check that the folder is writable, then try again."
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
    static func importSettings(from url: URL) throws -> TesseraSettings {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try SettingsStore.decode(Data(contentsOf: url)).settings
    }
}
