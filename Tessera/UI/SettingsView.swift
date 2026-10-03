import Observation
import SwiftUI
import TesseraCore

/// Settings panes in sidebar order; ⌘1–9 selects them.
///
/// One question per pane, so a setting has exactly one home:
/// Ring = how the ring *behaves*, Preview = what the preview *shows*,
/// Appearance = how both *look*, Motion = how fast anything *moves*.
enum SettingsPane: Int, CaseIterable, Hashable {
    case general, shortcuts, displays, ring, preview, appearance, motion, excludedApps, about

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .displays: "Displays"
        case .ring: "Ring"
        case .preview: "Preview"
        case .appearance: "Appearance"
        case .motion: "Motion"
        case .excludedApps: "Excluded Apps"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .displays: "display"
        case .ring: "smallcircle.filled.circle"
        case .preview: "rectangle.lefthalf.filled"
        case .appearance: "paintpalette.fill"
        case .motion: "hare.fill"
        case .excludedApps: "hand.raised.fill"
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
        case .motion: .green
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
        case .ring: "Where directions end and pointing begins, what each direction does, and how pointing splits rows."
        case .preview: "What the snap preview shows while you hold the trigger."
        case .appearance: "Themes, colours and sizes for the ring and preview."
        case .motion: "How fast windows glide into place and the preview animates."
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
        case .customise: [.appearance, .motion, .excludedApps]
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
    /// Fixed window width (content points); only the height is user-adjustable.
    static let width: CGFloat = 820

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
            // idealHeight 0: the split view sizes itself from the detail's *ideal* height, which for a grouped
            // Form is its full content (up to ~1100 pt). That made the split taller than the window and AppKit
            // centred it, hiding the sidebar top and pane header under the title bar. Now it fills the window
            // and the Form scrolls.
            .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity, alignment: .top)
        }
        .background {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                KeyCommand(KeyEquivalent(Character("\(pane.rawValue + 1)"))) { navigation.pane = pane }
            }
        }
        .frame(width: Self.width)
        .frame(minHeight: 540, idealHeight: 640)
    }

    @ViewBuilder private var paneView: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .displays: DisplaysPane(model: model, displays: displays)
        case .ring: RingPane(model: model)
        case .preview: PreviewPane(model: model)
        case .appearance: AppearancePane(model: model)
        case .motion: MotionPane(model: model)
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
        let tile = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        // Fit every glyph into the same box so wide and tall symbols read at the same size.
        Image(systemName: pane.symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.2), radius: size * 0.02, y: size * 0.02)
            .frame(width: size * 0.58, height: size * 0.58)
            .frame(width: size, height: size)
            .background(tile.fill(pane.tint.gradient))
            .overlay(tile.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
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
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    SettingsView(model: SettingsModel(), navigation: SettingsNavigation(), displays: [])
}
