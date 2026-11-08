import SwiftUI

struct AboutPane: View {
    @State private var copied = false
    @State private var resetCopied: Task<Void, Never>?
    @ObservedObject private var updates = UpdateService.shared

    private static let repo = "https://github.com/prabeshbhetwal/tessera"

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tessera").font(.title.bold())
                        Text("Version \(version)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } footer: {
                Footer("A window manager that fits its grid to each display.")
            }

            Section {
                Button(copied ? "Copied" : "Copy version", action: copyVersion)
                    .help("Copies the version for bug reports")
                Button("Check for Updates…") { updates.checkForUpdates() }.settingAnchor("Check for Updates…")
                    .disabled(!updates.canCheckForUpdates)
            }

            Section {
                Link("Licence (GPL-3.0)", destination: Self.link("/blob/main/LICENSE"))
                Link("Third-party notices", destination: Self.link("/blob/main/THIRD-PARTY-NOTICES.md"))
                Link("Security", destination: Self.link("/blob/main/SECURITY.md"))
                Link("Privacy", destination: Self.link("#privacy"))
            } header: {
                Text("Links")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Footer("No analytics or telemetry. Settings and window snapshots stay on this Mac. Update checks go to GitHub.")
                    Footer(info["NSHumanReadableCopyright"] as? String ?? "")
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func link(_ path: String) -> URL { URL(string: repo + path)! }

    /// Shows "Copied" for about two seconds, then goes back to "Copy version".
    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Tessera \(version)", forType: .string)
        copied = true
        resetCopied?.cancel()
        resetCopied = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

#Preview {
    AboutPane()
}
