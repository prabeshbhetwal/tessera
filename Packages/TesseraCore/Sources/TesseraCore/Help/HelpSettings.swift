/// State for the in-app help coach.
public struct HelpSettings: Codable, Equatable, Sendable {
    /// Show the coach card by itself after interactive actions.
    public var autoShow = true
    /// Moments whose card has been shown, so each appears once.
    public var seenMoments: Set<String> = []

    public init() {}
}

public enum HelpDefaults {
    /// ⌃⌥/
    public static let explainHotkey = Hotkey(keyCode: 44, modifiers: [.control, .option])

    /// Adds the default Explain binding when no binding has the id or the chord. Callers apply it only to files
    /// that predate help settings, so a binding the person deleted later is never re-added.
    public static func offeringExplainHotkey(_ s: TesseraSettings) -> TesseraSettings {
        guard !s.hotkeys.contains(where: { $0.id == "explain" || $0.hotkey == explainHotkey }) else { return s }
        var out = s
        out.hotkeys.append(HotkeyBinding(id: "explain", hotkey: explainHotkey, command: .explain))
        return out
    }
}
