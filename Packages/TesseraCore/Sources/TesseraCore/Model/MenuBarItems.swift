/// Which optional items the menu bar menu shows. Settings… and Quit are always there.
public struct MenuBarItems: Codable, Equatable, Sendable {
    /// "Hold ⌃⌥⌘ to snap" at the top.
    public var statusLine = true
    /// Snap the front window to any layout.
    public var snapSubmenu = true
    /// Column count of the front window's display.
    public var columnsSubmenu = true
    public var shortcuts = true
    public var undo = true
    /// "Check for Updates…". It still shows while an update waits, so the person can reach it.
    public var checkForUpdates = true
    /// "Explain", which opens the help coach.
    public var explain = true
    /// Each item's hotkey at its right edge, as in any Mac menu.
    public var shortcutKeys = true

    public init() {}
}
