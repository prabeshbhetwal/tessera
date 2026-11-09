import Observation
import SwiftUI
import TesseraCore

/// Settings panes in sidebar order; ⌘1–9 select all but Updates and ⌘0 selects About.
/// `overlay` is shown as "Appearance"; its key stays `overlay` so search anchors and saved links keep working.
enum SettingsPane: CaseIterable, Hashable {
    case general, ring, shortcuts, cycles, excludedApps, displays, splits, overlay, motion, updates, about

    /// Case name, the pane key `SettingsCatalog` uses.
    var key: String { "\(self)" }

    init?(key: String) {
        guard let pane = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = pane
    }

    /// The ⌘-digit that selects this pane, in sidebar order. Updates, rarely opened, has none.
    var shortcutKey: Character? {
        switch self {
        case .general: "1"
        case .ring: "2"
        case .shortcuts: "3"
        case .cycles: "4"
        case .excludedApps: "5"
        case .displays: "6"
        case .splits: "7"
        case .overlay: "8"
        case .motion: "9"
        case .updates: nil
        case .about: "0"
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .updates: "Updates"
        case .excludedApps: "Excluded Apps"
        case .shortcuts: "Shortcuts"
        case .cycles: "Cycles"
        case .splits: "Splits"
        case .displays: "Displays"
        case .ring: "Ring"
        case .overlay: "Appearance"
        case .motion: "Motion"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .updates: "arrow.down.circle.fill"
        case .excludedApps: "hand.raised.fill"
        case .shortcuts: "command"
        case .cycles: "arrow.triangle.2.circlepath"
        case .splits: "rectangle.split.3x1"
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
        case .updates: .cyan
        case .excludedApps: .red
        case .shortcuts: .orange
        case .cycles: .green
        case .splits: .purple
        case .displays: .blue
        case .ring: .indigo
        case .overlay: .teal
        case .motion: .mint
        case .about: .pink
        }
    }

    /// One short line under the pane title (at most 8 words): what the pane is for, in plain words.
    var blurb: String {
        switch self {
        case .general: "Startup, menu bar, messages and tips."
        case .updates: "Get new versions of Tessera."
        case .excludedApps: "Apps where Tessera stays out of the way."
        case .shortcuts: "Keyboard shortcuts for every action."
        case .cycles: "One shortcut that steps through several layouts."
        case .splits: "Window layouts Tessera remembers for your apps."
        case .displays: "Columns and spacing for each screen."
        case .ring: "How you open the ring and pick layouts."
        case .overlay: "How the ring and snap preview look."
        case .motion: "How fast windows move into place."
        case .about: ""
        }
    }
}

/// Sidebar groups, by task, in ⌘-number order. The first and last have no title.
enum SettingsGroup: CaseIterable {
    case app, controls, windows, look, info

    var title: String? {
        switch self {
        case .app, .info: nil
        case .controls: "Controls"
        case .windows: "Windows"
        case .look: "Look"
        }
    }

    var panes: [SettingsPane] {
        switch self {
        case .app: [.general]
        case .controls: [.ring, .shortcuts, .cycles, .excludedApps]
        case .windows: [.displays, .splits]
        case .look: [.overlay, .motion]
        case .info: [.updates, .about]
        }
    }
}

/// Which pane is showing. Owned by `WindowPresenter` so menu items can open a specific pane.
@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
    /// Id of the row a search result revealed; it is drawn highlighted until cleared.
    var highlight: String?
    /// Bumped on every reveal, so revealing the same row again scrolls to it again.
    private(set) var reveals = 0
    /// Bumped by ⌘F to focus the sidebar's search field.
    var searchFocusRequests = 0

    /// Opens the entry's pane and asks the pane to scroll to its row and highlight it.
    func reveal(_ entry: SettingsEntry) {
        if let target = SettingsPane(key: entry.pane) { pane = target }
        highlight = entry.anchor.map { "\(entry.pane)/\($0)" }
        reveals += 1
        // The highlight is visual; VoiceOver hears where it went.
        AccessibilityNotification.Announcement("\(entry.title), \(pane.title)").post()
    }
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
            SettingsSidebar(navigation: navigation, usesAppleIntelligence: model.settings.searchUsesAppleIntelligence)
            // A sidebar that can't be collapsed, like System Settings. Narrower, the search field cut off the
            // first letter of its "Search settings" placeholder, so it never gets narrower than 220 pt. It can
            // widen to 280 pt, which still leaves the detail 540 pt. The column width alone was ignored (the
            // sidebar opened at ~140 pt); the frame's minimum is what holds it.
            .frame(minWidth: 220)
            .navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if navigation.pane != .about { PaneHeader(pane: navigation.pane) }
                    paneView
                }
                .environment(\.settingsPaneKey, navigation.pane.key)
                .environment(\.settingsHighlight, navigation.highlight)
                .task(id: navigation.reveals) { await scrollToHighlight(proxy) }
            }
            // idealHeight 0: the split view sizes itself from the detail's *ideal* height, which for a grouped
            // Form is its full content (up to ~1100 pt). That made the split taller than the window and AppKit
            // centred it, hiding the sidebar top and pane header under the title bar. Now it fills the window
            // and the Form scrolls.
            .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity, alignment: .top)
        }
        .background {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                if let key = pane.shortcutKey {
                    KeyCommand(KeyEquivalent(key)) { navigation.pane = pane }
                }
            }
            KeyCommand("f") { navigation.searchFocusRequests += 1 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// After a search reveal: let the new pane lay out, bring the row to the middle, then fade the highlight.
    private func scrollToHighlight(_ proxy: ScrollViewProxy) async {
        guard let id = navigation.highlight else { return }
        // Twice: a pane that takes longer to lay out than the first wait misses the first scroll.
        for wait in [80, 250] {
            try? await Task.sleep(for: .milliseconds(wait))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, navigation.highlight == id else { return }
        navigation.highlight = nil
    }

    @ViewBuilder private var paneView: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .updates: UpdatesPane(model: model)
        case .excludedApps: ExcludedAppsPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .cycles: CyclesPane(model: model)
        case .splits: SplitsPane(model: model, displays: displays)
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
            .frame(width: size * 0.58, height: size * 0.58)
            .frame(width: size, height: size)
            .background(tile.fill(pane.tint))
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
