import SwiftUI

struct AboutPane: View {
    @State private var copied = false

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.3x2.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.tint))
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

            Divider().frame(width: 240)

            VStack(spacing: 6) {
                Text(info["NSHumanReadableCopyright"] as? String ?? "")
                    .multilineTextAlignment(.center)
                if let loop = URL(string: "https://github.com/MrKai77/Loop") {
                    Link("Loop by MrKai77", destination: loop)
                }
            }
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
