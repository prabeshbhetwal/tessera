import SwiftUI

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
