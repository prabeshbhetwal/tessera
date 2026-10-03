import Carbon
import SwiftUI
import TesseraCore

extension Notification.Name {
    /// Posted with `userInfo["active": Bool]` when a recorder starts or stops capturing keys,
    /// so global hotkeys and the trigger can be paused while the user types a new shortcut.
    static let tesseraRecorderActive = Notification.Name("TesseraRecorderActive")
    /// Posted by the Overlay pane's "Show on screen" button; the coordinator shows the real overlay briefly.
    static let tesseraPreviewOverlay = Notification.Name("TesseraPreviewOverlay")
}

extension Hotkey {
    /// A cleared binding. No physical key has this code, so it never matches.
    static let none = Hotkey(keyCode: .max, modifiers: [])
    var isNone: Bool { keyCode == .max }

    var displayString: String { isNone ? "None" : modifiers.symbols + KeyNames.name(for: keyCode) }
}

extension Modifiers {
    var symbols: String {
        (contains(.function) ? "fn " : "") + (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

/// Human names for virtual key codes, following the current keyboard layout for character keys.
enum KeyNames {
    static let special: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
        53: "⎋", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 114: "Help",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    /// Keys for which macOS sets the fn flag on its own, so fn is not part of the shortcut.
    static let implicitFunction: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121, 117, 114]
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    static func name(for keyCode: UInt16) -> String {
        special[keyCode] ?? character(for: keyCode) ?? "Key \(keyCode)"
    }

    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text.uppercased()
    }
}

/// Focusable field shared by the chord and hotkey recorders (spec §6):
/// Space or Return starts, Delete clears, click starts. Esc cancelling is handled by the owner's key monitor.
struct RecorderField: View {
    let title: String
    let text: String
    let recording: Bool
    let start: () -> Void
    let clear: () -> Void
    @FocusState private var focused: Bool

    /// A real button: every click starts recording. (It was text marked as an editable focus target, so a
    /// click often went to focusing and selecting the text instead of the tap that starts recording.)
    var body: some View {
        Button { if !recording { start() } } label: {
            Text(text)
                .monospaced()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 110)
                .background(RoundedRectangle(cornerRadius: 5).fill(recording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused || recording ? Color.accentColor : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(keys: [.space, .return]) { _ in
                if !recording { start() }
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                if !recording { clear() }
                return .handled
            }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(recording ? "Recording. Press the new shortcut, or Escape to cancel." : text)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !recording { start() } }
            .accessibilityAction(named: "Clear", clear)
            .help("Space or Return to record, Delete to clear")
    }
}

/// Records one hotkey: a key plus modifiers. Saved when the key is released; Esc cancels; Delete clears.
struct HotkeyRecorder: View {
    let title: String
    @Binding var hotkey: Hotkey
    @State private var recording = false
    @State private var pending: Hotkey?
    @State private var liveModifiers: Modifiers = []
    @State private var rejected = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            RecorderField(title: title, text: text, recording: recording, start: start, clear: { hotkey = .none })
            if rejected {
                Caption("Use ⌃, ⌥ or ⌘, or an F-key.")
            }
        }
        .onDisappear { stop() }
        // Recording pauses Tessera's trigger and hotkeys system-wide; never leave it on when focus goes elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stop() }
    }

    private var text: String {
        guard recording else { return hotkey.displayString }
        if let pending { return pending.displayString }
        return liveModifiers.isEmpty ? "Type shortcut…" : liveModifiers.symbols + "…"
    }

    private func start() {
        pending = nil
        liveModifiers = []
        rejected = false
        recording = true
        NotificationCenter.default.post(name: .tesseraRecorderActive, object: nil, userInfo: ["active": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = Self.modifiers(event.modifierFlags, keyCode: event.keyCode)
        switch event.type {
        case .flagsChanged:
            liveModifiers = modifiers
            return event
        case .keyDown:
            guard pending == nil else { return nil }
            if event.keyCode == 53, modifiers.isEmpty {
                stop()
            } else if [51, 117].contains(event.keyCode), modifiers.isEmpty {
                hotkey = .none
                stop()
            } else if modifiers.isDisjoint(with: [.control, .option, .command]), !KeyNames.functionKeys.contains(event.keyCode) {
                // A bare letter would swallow normal typing system-wide.
                rejected = true
            } else {
                rejected = false
                pending = Hotkey(keyCode: event.keyCode, modifiers: modifiers)
            }
            return nil
        default:
            if let pending, event.keyCode == pending.keyCode {
                hotkey = pending
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if recording {
            NotificationCenter.default.post(name: .tesseraRecorderActive, object: nil, userInfo: ["active": false])
        }
        monitor = nil
        pending = nil
        recording = false
    }

    /// Side-agnostic modifiers as the input service sees them: fn only when physically held.
    static func modifiers(_ flags: NSEvent.ModifierFlags, keyCode: UInt16) -> Modifiers {
        Modifiers(deviceKeyCodes: ModifierKey.pressed(in: flags)).normalized(forKeyCode: keyCode)
    }
}
