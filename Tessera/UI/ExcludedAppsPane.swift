import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

struct ExcludedAppsPane: View {
    @Bindable var model: SettingsModel
    @State private var choosing = false

    var body: some View {
        Form {
            Section {
                if model.settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                ForEach(model.settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppIcon(bundleID: bundleID)
                        VStack(alignment: .leading) {
                            Text(Self.name(for: bundleID))
                            Caption(bundleID)
                        }
                        Spacer()
                        Button {
                            model.settings.excludedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(Self.name(for: bundleID))")
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(Self.runningApps(), id: \.bundleID) { app in
                            Button(app.name) { add(app.bundleID) }
                        }
                    }
                    .fixedSize()
                    Button("Choose App…") { choosing = true }
                        .fileImporter(isPresented: $choosing, allowedContentTypes: [.application]) { result in
                            if case .success(let url) = result, let id = Bundle(url: url)?.bundleIdentifier {
                                add(id)
                            }
                        }
                    Spacer()
                }
            } header: {
                Text("Apps")
            } footer: {
                Footer("While one of these apps is in front, the trigger and hotkeys do nothing, so that app's own shortcuts keep working.")
            }

            ResetSection { model.settings.excludedBundleIDs = [] }
        }
        .formStyle(.grouped)
    }

    private func add(_ bundleID: String) {
        guard !model.settings.excludedBundleIDs.contains(bundleID) else { return }
        model.settings.excludedBundleIDs.append(bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func runningApps() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    ExcludedAppsPane(model: SettingsModel())
}
