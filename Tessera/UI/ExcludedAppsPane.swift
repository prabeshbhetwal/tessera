import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

struct ExcludedAppsPane: View {
    @Bindable var model: SettingsModel
    @State private var choosing = false
    @State private var query = ""

    /// The excluded apps whose name contains the search text; all of them while it is empty.
    private var shown: [String] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return model.settings.excludedBundleIDs }
        return model.settings.excludedBundleIDs.filter { Self.name(for: $0).localizedCaseInsensitiveContains(text) }
    }

    /// Running apps not already excluded.
    private var addable: [(bundleID: String, name: String)] {
        Self.runningApps().filter { !model.settings.excludedBundleIDs.contains($0.bundleID) }
    }

    var body: some View {
        Form {
            Section {
                // Inline rather than `.searchable`: a toolbar search field made this pane's title bar taller
                // than every other pane's, and switching panes left the sidebar clipped under the title bar.
                if !model.settings.excludedBundleIDs.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter excluded apps", text: $query)
                            .textFieldStyle(.plain)
                            .labelsHidden()
                    }
                }
                if shown.isEmpty {
                    Text(model.settings.excludedBundleIDs.isEmpty ? "No excluded apps. Add one below." : "No apps match \u{201C}\(query)\u{201D}")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                ForEach(shown, id: \.self) { bundleID in
                    HStack {
                        AppIcon(bundleID: bundleID)
                        Text(Self.name(for: bundleID))
                        Spacer()
                        Button {
                            model.settings.excludedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(Self.name(for: bundleID))")
                        .help("Remove from excluded apps")
                    }
                    // The bundle identifier is for the curious, not for every row.
                    .help(bundleID)
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(addable, id: \.bundleID) { app in
                            Button(app.name) { add(app.bundleID) }
                        }
                    }
                    .disabled(addable.isEmpty)
                    .fixedSize()
                    Button("Choose App…") { choosing = true }
                        .fileImporter(isPresented: $choosing, allowedContentTypes: [.application]) { result in
                            if case .success(let url) = result, let id = Bundle(url: url)?.bundleIdentifier {
                                add(id)
                            }
                        }
                    Spacer()
                }
                .settingAnchor("Apps")
            } header: {
                InfoHeader("Apps", info: "While one of these apps is in front, the ring trigger and your hotkeys do nothing, so the app’s own shortcuts keep working.")
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
        // Finder's display name keeps ".app" when the user shows extensions; the app's name doesn't include it.
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
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
