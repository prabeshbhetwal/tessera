/// Modifier keycodes held together to open the ring. Default: Left Control + Left Option + Left Command.
public struct TriggerChord: Codable, Equatable, Sendable {
    public var keyCodes: Set<UInt16>

    public init(keyCodes: Set<UInt16>) { self.keyCodes = keyCodes }
    public static let `default` = TriggerChord(keyCodes: [59, 58, 55])
}

public struct RingSettings: Codable, Equatable, Sendable {
    /// No longer drives selection (the ring's empty middle is the cancel area, see `cancelRadius`).
    /// Kept so settings files keep their shape and validation.
    public var deadZone: Double = 10
    public var flickDistance: Double = 90
    /// 8 wedges, first centred straight up, clockwise.
    public var wedges: [WindowAction] = [
        .maximize, .topRightQuarter, .rightHalf, .bottomRightQuarter,
        .center, .bottomLeftQuarter, .leftHalf, .topLeftQuarter,
    ]
    public var radius: Double = 50
    public var thickness: Double = 22
    public var topBand: Double = 0.30
    public var bottomBand: Double = 0.30
    // Optional so files written before they existed still decode; read and write the computed twins.
    public var boundary: Bool?
    public var columnNumbers: Bool?
    public var pointingHint: Bool?
    /// Pointing sessions that have shown the hint so far; nil = none.
    public var pointingHintsSeen: Int?

    /// Whether the next pointing session should carry the hint.
    public var pointingHintDue: Bool {
        showPointingHint && (pointingHintsSeen ?? 0) < PreviewModel.hintSessions
    }

    /// Circle on screen at `flickDistance`, where pointing starts. Off by default.
    public var showBoundary: Bool {
        get { boundary ?? false }
        set { boundary = newValue }
    }

    /// 1 2 3 … over the grid's columns while pointing.
    public var showColumnNumbers: Bool {
        get { columnNumbers ?? true }
        set { columnNumbers = newValue }
    }

    /// "Col 2 · click to add columns" for the first `PreviewModel.hintSessions` pointing sessions.
    public var showPointingHint: Bool {
        get { pointingHint ?? true }
        set { pointingHint = newValue }
    }

    /// The ring's empty middle: nothing is selected inside it, so releasing there cancels.
    public var cancelRadius: Double { max(radius - thickness / 2, 8) }
    /// Outer edge of the drawn ring.
    public var outerRadius: Double { radius + thickness / 2 }

    // Appearance. Hiding the ring keeps every gesture working; only the drawing goes.
    public var showRing = true
    /// Plain-language selection and input guidance beside the direction dial.
    public var showActionLabels = true
    /// The small picture inside each wedge; `iconStyle` picks which picture.
    public var showGlyphs = true
    public var iconStyle: RingIconStyle = .layouts
    /// The vibrant blur behind the wedges.
    public var frosted = true
    /// Column outlines and band lines while pointing.
    public var showGrid = true

    // Gestures.
    /// A short move picks a wedge. Off: any move past the dead zone points at the grid.
    public var directions = true
    /// A longer move points at a column. Off: the wedges reach any distance.
    public var pointing = true
    public var clickToSpan = true
    public var scrollChangesColumns = true
    /// Pressing and releasing the trigger without moving tiles every visible window on that display.
    public var tapTilesWindows = false

    public init() {}
    public static let `default` = RingSettings()
}

/// What fills the snap preview box.
public enum PreviewStyle: String, Codable, CaseIterable, Sendable {
    /// Accent-tinted box. Instant, needs no permission.
    case tint
    /// Tinted box, then the window's snapshot fades in (needs Screen Recording; stays tinted without it).
    case snapshot
    /// Tinted box with the app's icon in the middle.
    case appIcon

    public var displayName: String {
        switch self {
        case .tint: "Tinted box"
        case .snapshot: "Window snapshot"
        case .appIcon: "App icon"
        }
    }
}

/// What each wedge shows: a picture of its layout, or an arrow pointing its way.
public enum RingIconStyle: String, Codable, CaseIterable, Sendable {
    case layouts, arrows
}

/// The menu bar item's picture. Raw values are SF Symbol names.
public enum MenuBarIcon: String, Codable, CaseIterable, Sendable {
    case grid = "square.grid.3x2"
    case columns = "rectangle.split.3x1"
    case halves = "rectangle.split.2x1"
    case quarters = "square.grid.2x2"
    case window = "macwindow"
    case ring = "circle.dashed"

    public var displayName: String {
        switch self {
        case .grid: "Grid"
        case .columns: "Columns"
        case .halves: "Halves"
        case .quarters: "Quarters"
        case .window: "Window"
        case .ring: "Ring"
        }
    }
}

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

/// Where the short messages appear on the screen under the mouse.
public enum HUDPosition: String, Codable, CaseIterable, Sendable {
    case top, center, bottom

    public var displayName: String {
        switch self {
        case .top: "Top"
        case .center: "Centre"
        case .bottom: "Bottom"
        }
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var displayName: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum LabelPosition: String, Codable, Sendable {
    case center, bottom
}

public struct PreviewSettings: Codable, Equatable, Sendable {
    // Optional so files written before they existed still decode (an old `showThumbnail` key is
    // ignored, so everyone starts on the tinted box); read and write the computed twins.
    public var previewStyle: PreviewStyle?
    public var outlineCurrent: Bool?

    public var style: PreviewStyle {
        get { previewStyle ?? .tint }
        set { previewStyle = newValue }
    }

    /// Dashed outline of the window's current frame. Off by default.
    public var showCurrentOutline: Bool {
        get { outlineCurrent ?? false }
        set { outlineCurrent = newValue }
    }

    public var showLabel = true
    /// What the label says: "1280 × 1047" and "cols 2–3 · top". Both off hides it.
    public var labelShowsSize = true
    public var labelShowsSlot = true
    /// Dim the windows the preview covers.
    public var showNeighbours = true
    /// The preview glides between selections. Off by default: a jump tracks the cursor with no delay.
    public var morph = false
    public var opacity: Double = 0.35
    public var borderWidth: Double = 2
    public var cornerRadius: Double = 10
    public var useWindowCornerRadius = false
    public var labelPosition: LabelPosition = .center
    public var dimStrength: Double = 0.35
    /// Spring response in seconds, 0...0.4. 0 disables the morph.
    public var springResponse: Double = 0.1

    public init() {}
    public static let `default` = PreviewSettings()
}

public struct RingStyle: Codable, Equatable, Sendable {
    public var fillHex: String
    public var strokeHex: String
    public var opacity: Double
    /// Column outlines and band lines while pointing.
    public var gridHex: String

    public init(fillHex: String, strokeHex: String, opacity: Double, gridHex: String = "#FFFFFF") {
        self.fillHex = fillHex
        self.strokeHex = strokeHex
        self.opacity = opacity
        self.gridHex = gridHex
    }
}

/// Visual preset. Never carries behaviour.
public struct Theme: Codable, Equatable, Sendable {
    public var name: String
    public var ring: RingStyle
    public var preview: PreviewSettings
    /// The lit wedge.
    public var accentHex: String
    /// Fill and border of the snap preview.
    public var previewHex: String
    /// The size label: its pill and its text.
    public var labelHex = "#141414"
    public var labelTextHex = "#FFFFFF"
    /// Dashed outline of where the window is now.
    public var outlineHex = "#FFFFFF"
    /// Shade over the windows the preview covers.
    public var dimHex = "#000000"

    public init(name: String, ring: RingStyle, preview: PreviewSettings, accentHex: String, previewHex: String? = nil) {
        self.name = name
        self.ring = ring
        self.preview = preview
        self.accentHex = accentHex
        self.previewHex = previewHex ?? accentHex
    }

    /// The ring is drawn over a vibrant material; `ring.opacity` is the strength of the fill tint on top of it,
    /// and a light `fillHex` selects the light material.
    public static let `default` = Theme(
        name: "Default",
        ring: RingStyle(fillHex: "#1C1C1E", strokeHex: "#FFFFFF", opacity: 0.3),
        preview: .default,
        accentHex: "#0A84FF"
    )

    public static let minimal: Theme = {
        var p = PreviewSettings()
        p.opacity = 0
        return Theme(
            name: "Minimal",
            ring: RingStyle(fillHex: "#000000", strokeHex: "#FFFFFF", opacity: 0.55),
            preview: p,
            accentHex: "#FFFFFF"
        )
    }()

    public static let glass: Theme = {
        var p = PreviewSettings()
        p.opacity = 0.5
        p.useWindowCornerRadius = true
        return Theme(
            name: "Glass",
            ring: RingStyle(fillHex: "#FFFFFF", strokeHex: "#1C1C1E", opacity: 0.2),
            preview: p,
            accentHex: "#0A84FF"
        )
    }()

    public static let builtIn: [Theme] = [.default, .minimal, .glass]
}

/// Single versioned settings model (spec §6.4).
public struct TesseraSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var trigger: TriggerChord = .default
    public var sizing: SizingConstants = .default
    public var defaultGap: Double = 8
    public var defaultPadding: Double = 8
    /// Keyed by `DisplayID.storageKey`.
    public var displayOverrides: [String: DisplayProfile] = [:]
    public var ring: RingSettings = .default
    public var preview: PreviewSettings = .default
    public var themeName = "Default"
    public var customThemes: [Theme] = []
    public var excludedBundleIDs: [String] = []
    public var launchAtLogin = false
    public var showMenuBarIcon = true
    // M2 (schema v2): keyboard + automation.
    public var hotkeys: [HotkeyBinding] = HotkeyBinding.defaults
    public var cycles: [Cycle] = Cycle.defaults
    public var ringKeyNavigation = true
    public var announceSelection = true
    /// Master switch for every global hotkey; each binding keeps its own switch too.
    public var hotkeysEnabled = true
    /// Short messages near the bottom of the screen ("5 columns", "No window to move").
    public var showHUD = true
    public var hudPosition: HUDPosition = .bottom
    /// Seconds a message stays before it fades.
    public var hudSeconds = 1.2
    public var menuBarIcon: MenuBarIcon = .grid
    public var menuBarItems = MenuBarItems()
    /// Light or dark for Tessera's own windows (Settings, setup); `.system` follows macOS.
    public var appearance: AppearanceMode = .system
    /// Seconds a snapped window takes to glide to its new frame; 0 jumps straight there.
    /// Read and write it through `snapSeconds`, which clamps.
    public var snapDuration: Double = 0

    /// `snapDuration` clamped to `0...SnapSpeed.maxSeconds`.
    public var snapSeconds: Double {
        get { snapDuration.isFinite ? min(max(snapDuration, 0), SnapSpeed.maxSeconds) : 0 }
        set { snapDuration = newValue }
    }

    /// Remember how windows were arranged by hand and reapply it the next time the same apps are tiled.
    public var learnSplits = true
    /// Put each app back in the slot it had, rather than keep the current window order with the learned sizes.
    public var splitRestoresOrder = false
    public var splitGapPlacement: SplitGapPlacement = .staysInPlace
    public var splitGapWhenGrowing: SplitGapWhenGrowing = .fixed
    /// Oldest first, at most `SplitMemory.capacity`.
    public var learnedSplits: [LearnedSplit] = []

    public init() {}
    public static let defaults = TesseraSettings()
}
