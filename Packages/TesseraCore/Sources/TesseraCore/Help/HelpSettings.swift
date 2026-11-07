/// State for the in-app help coach.
public struct HelpSettings: Codable, Equatable, Sendable {
    /// Show the coach card by itself after interactive actions.
    public var autoShow = true
    /// Moments whose card has been shown, so each appears once.
    public var seenMoments: Set<String> = []
    /// The ⌃⌥/ default has been offered once. Stops it returning after the person removes it.
    public var explainHotkeyOffered = false

    public init() {}
}

public enum HelpDefaults {
    /// ⌃⌥/
    public static let explainHotkey = Hotkey(keyCode: 44, modifiers: [.control, .option])

    /// Adds the default Explain binding to a file written before it existed, once, and only when its chord is free.
    public static func offeringExplainHotkey(_ s: TesseraSettings) -> TesseraSettings {
        // Already bound (fresh defaults): nothing to offer, and leaving the flag alone keeps defaults round-trip equal.
        guard !s.help.explainHotkeyOffered, !s.hotkeys.contains(where: { $0.id == "explain" }) else { return s }
        var out = s
        out.help.explainHotkeyOffered = true
        if !out.hotkeys.contains(where: { $0.hotkey == explainHotkey }) {
            out.hotkeys.append(HotkeyBinding(id: "explain", hotkey: explainHotkey, command: .explain))
        }
        return out
    }
}
