import CoreGraphics

/// Which display a command acts on (M2 spec §2).
public enum DisplaySelector: Codable, Equatable, Hashable, Sendable {
    /// Display containing the frontmost window's centre.
    case current
    case cursor
    /// 1-based, displays sorted by frame.minX then frame.minY.
    case index(Int)
    /// `DisplayID.storageKey`.
    case id(String)
}

public enum DisplayStep: Codable, Equatable, Sendable {
    case next, previous
    case index(Int)
}

public enum ColumnChange: Codable, Equatable, Sendable {
    case set(Int)
    case delta(Int)
}

/// Where a window should go. Span columns are 1-based; negatives count from the right (-1 = last).
public enum Target: Codable, Equatable, Sendable {
    case action(WindowAction)
    case span(columns: ClosedRange<Int>, band: Band)
}

/// The single command language every input surface produces.
public enum Command: Codable, Equatable, Sendable {
    case apply(Target, display: DisplaySelector)
    case cycle(name: String)
    case columns(ColumnChange, display: DisplaySelector)
    case moveToDisplay(DisplayStep)
    case undo
    case openSettings
    case listDisplays
    case describeWindow
    case exportSettings(path: String)
    case importSettings(path: String)
}

public struct DisplayInfo: Codable, Equatable, Sendable {
    public let index: Int
    public let id: String
    public let name: String?
    public let frame: CGRect
    public let columns: Int
    public let minColumns: Int
    public let maxColumns: Int

    public init(index: Int, id: String, name: String?, frame: CGRect, columns: Int, minColumns: Int, maxColumns: Int) {
        self.index = index
        self.id = id
        self.name = name
        self.frame = frame
        self.columns = columns
        self.minColumns = minColumns
        self.maxColumns = maxColumns
    }
}

public struct WindowInfo: Codable, Equatable, Sendable {
    public let app: String?
    public let bundleID: String?
    public let frame: CGRect
    public let displayIndex: Int?

    public init(app: String?, bundleID: String?, frame: CGRect, displayIndex: Int?) {
        self.app = app
        self.bundleID = bundleID
        self.frame = frame
        self.displayIndex = displayIndex
    }
}

/// Result returned to every surface. Queries fill `displays` / `window`.
public struct CommandResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let message: String?
    public let displays: [DisplayInfo]?
    public let window: WindowInfo?

    public init(ok: Bool, message: String? = nil, displays: [DisplayInfo]? = nil, window: WindowInfo? = nil) {
        self.ok = ok
        self.message = message
        self.displays = displays
        self.window = window
    }

    public static func failure(_ message: String) -> CommandResult { CommandResult(ok: false, message: message) }
    public static let success = CommandResult(ok: true)
}

/// Named sequence of targets advanced by repeated presses (M2 spec §4).
public struct Cycle: Codable, Equatable, Sendable {
    public var name: String
    public var steps: [Target]
    public var display: DisplaySelector

    public init(name: String, steps: [Target], display: DisplaySelector = .current) {
        self.name = name
        self.steps = steps
        self.display = display
    }

    public static let defaults: [Cycle] = [
        Cycle(name: "left", steps: [.action(.leftHalf), .span(columns: 1...1, band: .full), .span(columns: 1...2, band: .full)]),
        Cycle(name: "right", steps: [.action(.rightHalf), .span(columns: -1 ... -1, band: .full), .span(columns: -2 ... -1, band: .full)]),
    ]
}

/// Side-agnostic modifiers used by hotkeys.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let command = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    /// From device-specific modifier keycodes (see `InputEvent.flagsChanged`).
    public init(deviceKeyCodes: Set<UInt16>) {
        var m: Modifiers = []
        if !deviceKeyCodes.isDisjoint(with: [59, 62]) { m.insert(.control) }
        if !deviceKeyCodes.isDisjoint(with: [58, 61]) { m.insert(.option) }
        if !deviceKeyCodes.isDisjoint(with: [55, 54]) { m.insert(.command) }
        if !deviceKeyCodes.isDisjoint(with: [56, 60]) { m.insert(.shift) }
        if deviceKeyCodes.contains(63) { m.insert(.function) }
        self = m
    }
}

public struct Hotkey: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct HotkeyBinding: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var hotkey: Hotkey
    public var command: Command
    public var enabled: Bool

    public init(id: String, hotkey: Hotkey, command: Command, enabled: Bool = true) {
        self.id = id
        self.hotkey = hotkey
        self.command = command
        self.enabled = enabled
    }

    /// Defaults from M2 spec §4. Ids are stable so "restore defaults" can match them.
    public static let defaults: [HotkeyBinding] = {
        let co: Modifiers = [.control, .option]
        var list: [HotkeyBinding] = [
            HotkeyBinding(id: "cycle-left", hotkey: Hotkey(keyCode: 123, modifiers: co), command: .cycle(name: "left")),
            HotkeyBinding(id: "cycle-right", hotkey: Hotkey(keyCode: 124, modifiers: co), command: .cycle(name: "right")),
            HotkeyBinding(id: "maximize", hotkey: Hotkey(keyCode: 126, modifiers: co),
                          command: .apply(.action(.maximize), display: .current)),
            HotkeyBinding(id: "center", hotkey: Hotkey(keyCode: 125, modifiers: co),
                          command: .apply(.action(.center), display: .current)),
            HotkeyBinding(id: "columns-plus", hotkey: Hotkey(keyCode: 24, modifiers: co),
                          command: .columns(.delta(1), display: .current)),
            HotkeyBinding(id: "columns-minus", hotkey: Hotkey(keyCode: 27, modifiers: co),
                          command: .columns(.delta(-1), display: .current)),
            HotkeyBinding(id: "display-next", hotkey: Hotkey(keyCode: 45, modifiers: co), command: .moveToDisplay(.next)),
            HotkeyBinding(id: "display-previous", hotkey: Hotkey(keyCode: 35, modifiers: co), command: .moveToDisplay(.previous)),
            HotkeyBinding(id: "undo", hotkey: Hotkey(keyCode: 6, modifiers: co), command: .undo),
            HotkeyBinding(id: "open-settings", hotkey: Hotkey(keyCode: 43, modifiers: [.control, .option, .command]),
                          command: .openSettings),
        ]
        // ⌃⌥1 … ⌃⌥9 → column n on the current display.
        let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (i, code) in digitKeyCodes.enumerated() {
            let n = i + 1
            list.append(HotkeyBinding(id: "column-\(n)", hotkey: Hotkey(keyCode: code, modifiers: co),
                                      command: .apply(.span(columns: n...n, band: .full), display: .current)))
        }
        return list
    }()
}

/// Keys that drive the open ring (M2 spec §3).
public enum NavKey: Equatable, Sendable {
    case left, right
    case extendLeft, extendRight
    case bandUp, bandDown
    case column(Int)
    case columnsPlus, columnsMinus
    case nextDisplay, previousDisplay
    case apply
}
