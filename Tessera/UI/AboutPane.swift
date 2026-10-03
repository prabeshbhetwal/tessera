import SwiftUI

struct AboutPane: View {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.3x2")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Tessera").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text(info["NSHumanReadableCopyright"] as? String ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutPane()
}
