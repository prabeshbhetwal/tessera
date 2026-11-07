import AppKit
import TesseraCore

/// The menu bar menu shows each item's hotkey at its right edge, as any Mac menu does.
/// The event tap consumes a matched hotkey before the open menu sees the key, so a press never runs twice.
extension NSMenuItem {
    /// Shows the first enabled hotkey bound to `command`. Without one (or with `visible` off), shows `fallback`:
    /// Settings… keeps ⌘, so the open menu still answers it.
    func showShortcut(for command: Command?, in hotkeys: [HotkeyBinding], visible: Bool,
                      fallback: (key: String, modifiers: NSEvent.ModifierFlags) = ("", [])) {
        let bound = visible
            ? command.flatMap { c in hotkeys.lazy.filter { $0.enabled && $0.command == c }.compactMap(\.hotkey.menuKeyEquivalent).first }
            : nil
        let shown = bound ?? fallback
        keyEquivalent = shown.key
        keyEquivalentModifierMask = shown.modifiers
        // The key comes from the current layout already; AppKit must not remap it again.
        allowsAutomaticKeyEquivalentLocalization = false
    }
}

extension Hotkey {
    /// What an `NSMenuItem` draws for this hotkey. Nil for a cleared hotkey or a key the layout gives no character.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard !isNone, let key = Self.menuKey(keyCode) else { return nil }
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.function), !KeyNames.implicitFunction.contains(keyCode) { mask.insert(.function) }
        return (key, mask)
    }

    private static let typed: [UInt16: String] = [36: "\r", 76: "\u{3}", 48: "\t", 49: " ", 51: "\u{8}", 53: "\u{1b}"]
    private static let functionScalars: [UInt16: Int] = [
        123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey, 125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey,
        117: NSDeleteFunctionKey, 115: NSHomeFunctionKey, 119: NSEndFunctionKey, 116: NSPageUpFunctionKey,
        121: NSPageDownFunctionKey, 114: NSHelpFunctionKey,
    ]

    private static func menuKey(_ code: UInt16) -> String? {
        if let typed = typed[code] { return typed }
        let scalar = KeyNames.functionKeyOrder.firstIndex(of: code).map { NSF1FunctionKey + $0 } ?? functionScalars[code]
        if let scalar { return String(utf16CodeUnits: [unichar(scalar)], count: 1) }
        // A character key: the layout's character, lowercased because an uppercase key equivalent adds Shift.
        let name = KeyNames.name(for: code)
        return name.count == 1 ? name.lowercased() : nil
    }
}
