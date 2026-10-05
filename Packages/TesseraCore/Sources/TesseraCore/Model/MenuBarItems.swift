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

    public init() {}
}
