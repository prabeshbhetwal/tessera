import SwiftUI

struct AboutPane: View {
    @State private var copied = false
    @ObservedObject private var updates = UpdateService.shared

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Tessera").font(.title.bold())
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("A window manager that adapts to every display.")
                .foregroundStyle(.secondary)

            Button(copied ? "Copied" : "Copy version") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("Tessera \(version)", forType: .string)
                copied = true
            }
            .controlSize(.small)
            .help("Copies the version for bug reports")

            Button("Check for Updates…") { updates.checkForUpdates() }
                .controlSize(.small)
                .disabled(!updates.canCheckForUpdates)

            Divider().frame(width: 240)

            Text(info["NSHumanReadableCopyright"] as? String ?? "")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutPane()
}
