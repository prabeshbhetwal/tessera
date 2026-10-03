/// Exact-match lookup of enabled hotkey bindings (M2 spec §4).
public struct HotkeyTable: Sendable {
    private let commands: [Hotkey: Command]

    /// Disabled bindings are dropped. When two enabled bindings share a hotkey, the first one wins.
    public init(_ bindings: [HotkeyBinding]) {
        var table: [Hotkey: Command] = [:]
        for b in bindings where b.enabled && table[b.hotkey] == nil { table[b.hotkey] = b.command }
        commands = table
    }

    /// Modifiers must be equal, not a superset: ⌃⌥⇧← never triggers a ⌃⌥← binding.
    public func match(keyCode: UInt16, modifiers: Modifiers) -> Command? {
        commands[Hotkey(keyCode: keyCode, modifiers: modifiers)]
    }

    /// Warnings for the Shortcuts pane, keyed by binding id. Only enabled bindings are checked:
    /// duplicates, a match with an enabled system shortcut, and the trigger chord used as a hotkey.
    public static func conflicts(
        _ bindings: [HotkeyBinding], chord: TriggerChord, systemHotkeys: Set<Hotkey>
    ) -> [String: String] {
        let enabled = bindings.filter(\.enabled)
        let chordModifiers = Modifiers(deviceKeyCodes: chord.keyCodes)
        var result: [String: String] = [:]

        for b in enabled {
            var messages: [String] = []
            let twins = enabled.filter { $0.id != b.id && $0.hotkey == b.hotkey }.map(\.id)
            if !twins.isEmpty { messages.append("Same shortcut as \(twins.joined(separator: ", ")).") }
            if systemHotkeys.contains(b.hotkey) { messages.append("Matches a system shortcut.") }
            // "Chord with no key": a modifier keycode carrying exactly the chord's modifiers. Pressing a
            // real key with those modifiers is fine (it fires through the open ring, e.g. ⌃⌥⌘,).
            if modifierKeyCodes.contains(b.hotkey.keyCode), !chordModifiers.isEmpty, b.hotkey.modifiers == chordModifiers {
                messages.append("Same as the trigger chord, which opens the ring.")
            }
            if !messages.isEmpty { result[b.id] = messages.joined(separator: " ") }
        }
        return result
    }

    /// Cmd 54/55, Shift 56/60, Caps Lock 57, Option 58/61, Control 59/62, Fn 63.
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}
