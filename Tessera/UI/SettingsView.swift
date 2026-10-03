import Observation
import SwiftUI
import TesseraCore

/// Settings panes in sidebar order; ⌘1–8 selects them.
enum SettingsPane: Int, CaseIterable, Hashable {
    case general, shortcuts, displays, ring, preview, appearance, excludedApps, about

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .displays: "Displays"
        case .ring: "Ring"
        case .preview: "Preview"
        case .appearance: "Appearance"
        case .excludedApps: "Excluded Apps"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .displays: "display.2"
        case .ring: "circle.dashed"
        case .preview: "rectangle.dashed"
        case .appearance: "paintpalette.fill"
        case .excludedApps: "nosign"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .shortcuts: .orange
        case .displays: .blue
        case .ring: .indigo
        case .preview: .teal
        case .appearance: .pink
        case .excludedApps: .red
        case .about: .gray
        }
    }

    var group: SettingsGroup { SettingsGroup.allCases.first { $0.panes.contains(self) } ?? .about }

    /// One sentence under the pane title: what the pane controls.
    var blurb: String {
        switch self {
        case .general: "The trigger chord, launch behaviour, settings files and the command-line tool."
        case .shortcuts: "Global hotkeys, named cycles and keyboard control of the open ring."
        case .displays: "Column count, gap and padding for each connected display."
        case .ring: "How far you flick before pointing, and what each direction does."
        case .preview: "What the snap preview shows while you hold the trigger."
        case .appearance: "Themes and colours for the ring and preview."
        case .excludedApps: "Apps in front of which the trigger stays off."
        case .about: ""
        }
    }
}

/// Sidebar groups, in ⌘-number order.
enum SettingsGroup: CaseIterable {
    case setup, snapping, customise, about

    var title: String? {
        switch self {
        case .setup: "Setup"
        case .snapping: "Snapping"
        case .customise: "Customise"
        case .about: nil
        }
    }

    var panes: [SettingsPane] {
        switch self {
        case .setup: [.general, .shortcuts]
        case .snapping: [.displays, .ring, .preview]
        case .customise: [.appearance, .excludedApps]
        case .about: [.about]
        }
    }
}

/// Which pane is showing. Owned by `WindowPresenter` so menu items can open a specific pane.
@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
}

/// Settings window root: sidebar of panes, grouped form on the right (spec §6.1, M2 §6).
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Bindable var navigation: SettingsNavigation
    var displays: [DisplayContext]

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                ForEach(SettingsGroup.allCases, id: \.self) { group in
                    Section {
                        ForEach(group.panes, id: \.self) { pane in
                            Label {
                                Text(pane.title)
                            } icon: {
                                PaneIcon(pane: pane)
                            }
                            .tag(pane)
                        }
                    } header: {
                        if let title = group.title { Text(title) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if navigation.pane != .about { PaneHeader(pane: navigation.pane) }
                paneView
            }
            .navigationTitle(navigation.pane.title)
        }
        .background {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                KeyCommand(KeyEquivalent(Character("\(pane.rawValue + 1)"))) { navigation.pane = pane }
            }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 640)
    }

    @ViewBuilder private var paneView: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .displays: DisplaysPane(model: model, displays: displays)
        case .ring: RingPane(model: model)
        case .preview: PreviewPane(model: model)
        case .appearance: AppearancePane(model: model)
        case .excludedApps: ExcludedAppsPane(model: model)
        case .about: AboutPane()
        }
    }
}

/// Rounded, tinted tile with a white symbol: sidebar rows and pane headers.
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(pane.tint))
            .accessibilityHidden(true)
    }
}

/// Title and purpose at the top of a pane, above its form.
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PaneIcon(pane: pane, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow = pane.group.title {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                Text(pane.title).font(.title2.weight(.semibold))
                Text(pane.blurb)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    SettingsView(model: SettingsModel(), navigation: SettingsNavigation(), displays: [])
}
