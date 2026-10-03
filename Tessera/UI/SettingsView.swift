import Observation
import SwiftUI
import TesseraCore

/// Settings panes in sidebar order; ⌘1–8 selects them.
enum SettingsPane: Int, CaseIterable, Hashable {
    case general, excludedApps, shortcuts, cycles, displays, ring, overlay, motion, about

    var title: String {
        switch self {
        case .general: "General"
        case .excludedApps: "Excluded Apps"
        case .shortcuts: "Shortcuts"
        case .cycles: "Cycles"
        case .displays: "Displays"
        case .ring: "Ring"
        case .overlay: "Overlay"
        case .motion: "Motion"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .excludedApps: "hand.raised.fill"
        case .shortcuts: "command"
        case .cycles: "arrow.triangle.2.circlepath"
        case .displays: "display"
        case .ring: "smallcircle.filled.circle"
        case .overlay: "circle.lefthalf.filled"
        case .motion: "hare.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .excludedApps: .red
        case .shortcuts: .orange
        case .cycles: .green
        case .displays: .blue
        case .ring: .indigo
        case .overlay: .teal
        case .motion: .mint
        case .about: .gray
        }
    }

    /// One sentence under the pane title: what the pane controls.
    var blurb: String {
        switch self {
        case .general: "The trigger chord, launch behaviour, settings files and the command-line tool."
        case .excludedApps: "Apps in front of which the trigger and hotkeys stay off."
        case .shortcuts: "Global hotkeys and keyboard control of the open ring."
        case .cycles: "Named sequences a hotkey steps through on repeated presses."
        case .displays: "Column count, gap and padding for each connected display."
        case .ring: "What each direction does, where pointing begins, and how big the ring is."
        case .overlay: "How the ring and the snap preview look on screen."
        case .motion: "How fast windows glide into place and the preview animates."
        case .about: ""
        }
    }
}

/// Sidebar groups, in ⌘-number order.
enum SettingsGroup: CaseIterable {
    case setup, control, snapping, about

    var title: String? {
        switch self {
        case .setup: "Setup"
        case .control: "Control"
        case .snapping: "Snapping"
        case .about: nil
        }
    }

    var panes: [SettingsPane] {
        switch self {
        case .setup: [.general, .excludedApps]
        case .control: [.shortcuts, .cycles]
        case .snapping: [.displays, .ring, .overlay, .motion]
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
    /// Fixed window size in content points (smaller only on a screen that can't fit it).
    static let width: CGFloat = 820
    static let height: CGFloat = 720

    @Bindable var model: SettingsModel
    @Bindable var navigation: SettingsNavigation
    var displays: [DisplayContext]

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
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
            // A fixed sidebar that can't be collapsed or dragged, like System Settings.
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var paneView: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .excludedApps: ExcludedAppsPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .cycles: CyclesPane(model: model)
        case .displays: DisplaysPane(model: model, displays: displays)
        case .ring: RingPane(model: model)
        case .overlay: OverlayPane(model: model)
        case .motion: MotionPane(model: model)
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
        HStack(alignment: .center, spacing: 14) {
            PaneIcon(pane: pane, size: 40)
            VStack(alignment: .leading, spacing: 2) {
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
