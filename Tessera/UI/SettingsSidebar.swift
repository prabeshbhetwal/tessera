import AppKit
import SwiftUI

/// Settings sidebar: the pane list, grouped. Search results drop down from the title bar's field instead
/// (`SearchResultsPanel`), so the list stays put while searching.
struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        List(selection: $navigation.pane) {
            ForEach(SettingsGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(group.panes, id: \.self) { pane in
                        Label { Text(pane.title) } icon: { PaneIcon(pane: pane) }
                            .tag(pane)
                    }
                } header: {
                    if let title = group.title { Text(title) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

/// The sidebar's foot, now the title bar holds search instead of a title: Tessera's icon over its name and version,
/// or the icon alone over the icon rail. Opens About.
struct SidebarBrand: View {
    @Bindable var navigation: SettingsNavigation
    let compact: Bool

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    var body: some View {
        Button { navigation.pane = .about } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                if !compact {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tessera").font(.headline)
                        Text(Self.version).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(.leading, compact ? 0 : 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        // Not a keyboard stop: About is in the pane list, and as the window's first stop it wore a focus ring.
        .focusable(false)
        .help("About Tessera")
        .accessibilityLabel("About Tessera, version \(Self.version)")
    }
}
