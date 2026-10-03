import Carbon
import TesseraCore

/// Enabled macOS keyboard shortcuts (System Settings › Keyboard › Keyboard Shortcuts), for conflict badges.
enum SystemHotkeys {
    static func enabled() -> Set<Hotkey> {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result = Set<Hotkey>()
        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue,
                  let carbon = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.intValue,
                  let keyCode = UInt16(exactly: code), keyCode != UInt16.max else { continue }
            result.insert(Hotkey(keyCode: keyCode, modifiers: modifiers(carbon: carbon)))
        }
        return result
    }

    /// Carbon modifier bits as returned by `CopySymbolicHotKeys`; fn is bit 17.
    static func modifiers(carbon: Int) -> Modifiers {
        var m: Modifiers = []
        if carbon & controlKey != 0 { m.insert(.control) }
        if carbon & optionKey != 0 { m.insert(.option) }
        if carbon & cmdKey != 0 { m.insert(.command) }
        if carbon & shiftKey != 0 { m.insert(.shift) }
        if carbon & (1 << 17) != 0 { m.insert(.function) }
        return m
    }
}
