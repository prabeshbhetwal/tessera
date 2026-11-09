import SwiftUI
import TesseraCore

/// Which pane is showing, and the title bar's settings search. Owned by `WindowPresenter` so menu items can open
/// a specific pane.
@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
    /// Id of the row a search result revealed; it is drawn highlighted until cleared.
    var highlight: String?
    /// Bumped on every reveal, so revealing the same row again scrolls to it again.
    private(set) var reveals = 0
    /// Bumped by ⌘F to focus the title bar's search field.
    private(set) var searchFocusRequests = 0
    /// What is typed in the title bar's search field. While it holds text the sidebar lists the matching settings,
    /// showing over icons only until the search is cleared.
    var query = ""
    /// ↑ ↓ and Return pressed in the search field, for the sidebar's results to act on.
    private(set) var searchKey = SearchKey()
    /// The sidebar shows only pane icons. Remembered between launches.
    var compactSidebar = UserDefaults.standard.bool(forKey: "SettingsCompactSidebar") {
        didSet { UserDefaults.standard.set(compactSidebar, forKey: "SettingsCompactSidebar") }
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The icon rail is showing: icons only, with no search results to list.
    var showsRail: Bool { compactSidebar && !isSearching }

    func focusSearch() { searchFocusRequests += 1 }

    /// `step` is −1 for ↑, 1 for ↓ and 0 for Return.
    func pressSearchKey(_ step: Int) { searchKey = SearchKey(step: step, serial: searchKey.serial + 1) }

    /// Opens the entry's pane and asks the pane to scroll to its row and highlight it.
    func reveal(_ entry: SettingsEntry) {
        if let target = SettingsPane(key: entry.pane) { pane = target }
        highlight = entry.anchor.map { "\(entry.pane)/\($0)" }
        reveals += 1
        // The highlight is visual; VoiceOver hears where it went.
        AccessibilityNotification.Announcement("\(entry.title), \(pane.title)").post()
    }
}

/// One key press in the search field; `serial` makes pressing the same key twice a change.
struct SearchKey: Equatable {
    var step = 0
    var serial = 0
}
