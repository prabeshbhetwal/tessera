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
    /// The small picture inside each wedge. Always drawn: without it the ring is a blank donut.
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

    /// Remember how windows were arranged by hand and reapply it the next time the same apps are tiled.
    public var learnSplits = true
    /// Put each app back in the slot it had, rather than keep the current window order with the learned sizes.
    public var splitRestoresOrder = false
    public var splitGapPlacement: SplitGapPlacement = .staysInPlace
    public var splitGapWhenGrowing: SplitGapWhenGrowing = .fixed
    /// After a Tile, resizing or moving one window makes the windows beside it follow its edges, so nothing is left
    /// uncovered or stacked. Needs `learnSplits`, whose watch notices the change.
    public var splitReflowsNeighbours = true
    /// When a window of a side-by-side group closes, the rest cover its space: the learned split for the apps left
    /// when there is one, otherwise the most recently used window beside the space grows into it. Needs `learnSplits`.
    public var splitFillsClosedGap = true
    /// When a new window opens beside a side-by-side group, the group is tiled again with it: the learned split for
    /// the apps now there when there is one, otherwise equal shares. Needs `learnSplits`.
    public var splitTilesNewWindow = true
    /// Which displays `splitTilesNewWindow` acts on.
    public var splitNewWindowScope: SplitNewWindowScope = .tiledDisplays
    /// Oldest first, at most `SplitMemory.capacity`.
    public var learnedSplits: [LearnedSplit] = []
    public var updates = UpdateSettings()
    public var help = HelpSettings()

    public init() {}
    public static let defaults = TesseraSettings()
}
