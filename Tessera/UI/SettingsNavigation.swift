import AppKit
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
    /// What is typed in the title bar's search field. While it holds text the matching settings drop down under it.
    var query = ""
    /// The results under the search field are showing. Typing opens them; picking one, clicking elsewhere or
    /// clearing the search closes them. Focusing the field, ↓ or Return brings them back while text remains.
    var resultsOpen = false
    /// ↑ ↓ and Return pressed in the search field, for the open results to act on.
    private(set) var searchKey = SearchKey()
    /// The sidebar shows only pane icons. Remembered between launches.
    var compactSidebar = UserDefaults.standard.bool(forKey: "SettingsCompactSidebar") {
        didSet { UserDefaults.standard.set(compactSidebar, forKey: "SettingsCompactSidebar") }
    }
    /// The pane list's width as last dragged; 0 until the sidebar's edge is first dragged. Remembered between launches.
    var sidebarWidth = CGFloat(UserDefaults.standard.double(forKey: "SettingsSidebarWidth")) {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: "SettingsSidebarWidth") }
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var showsResults: Bool { resultsOpen && isSearching }

    func focusSearch() { searchFocusRequests += 1 }

    /// ↑ ↓, Return or ⌥Return in the search field: acted on by the open results, or reopens them.
    func pressSearchKey(_ action: SearchKey.Action) {
        if showsResults { searchKey = SearchKey(action: action, serial: searchKey.serial + 1) } else { reopenResults() }
    }

    /// Brings back results folded away by a pick or a click elsewhere, while the search still holds text.
    func reopenResults() {
        if isSearching { resultsOpen = true }
    }

    /// Folds the results away, keeping the search text, and takes the keyboard from the field so a click back
    /// into it reopens them.
    func closeResults() {
        resultsOpen = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

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
    enum Action: Equatable {
        /// ↑ is −1, ↓ is 1.
        case move(Int)
        /// Return: open the selected result.
        case open
        /// ⌥Return: flip the selected result's switch.
        case flip
    }

    var action = Action.open
    var serial = 0
}
