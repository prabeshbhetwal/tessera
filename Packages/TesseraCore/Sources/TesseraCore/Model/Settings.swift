/// Modifier keycodes held together to open the ring. Default: Left Control + Left Option + Left Command.
public struct TriggerChord: Codable, Equatable, Sendable {
    public var keyCodes: Set<UInt16>

    public init(keyCodes: Set<UInt16>) { self.keyCodes = keyCodes }
    public static let `default` = TriggerChord(keyCodes: [59, 58, 55])
}

public struct RingSettings: Codable, Equatable, Sendable {
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

    public init() {}
    public static let `default` = RingSettings()
}

public enum LabelPosition: String, Codable, Sendable {
    case center, bottom
}

public struct PreviewSettings: Codable, Equatable, Sendable {
    public var showThumbnail = true
    public var showLabel = true
    public var showNeighbours = true
    public var morph = true
    public var opacity: Double = 0.35
    public var borderWidth: Double = 2
    public var cornerRadius: Double = 10
    public var useWindowCornerRadius = false
    public var labelPosition: LabelPosition = .center
    public var dimStrength: Double = 0.35
    /// Spring response in seconds, 0...0.4. 0 disables the morph.
    public var springResponse: Double = 0.18

    public init() {}
    public static let `default` = PreviewSettings()
}

public struct RingStyle: Codable, Equatable, Sendable {
    public var fillHex: String
    public var strokeHex: String
    public var opacity: Double

    public init(fillHex: String, strokeHex: String, opacity: Double) {
        self.fillHex = fillHex
        self.strokeHex = strokeHex
        self.opacity = opacity
    }
}

/// Visual preset. Never carries behaviour.
public struct Theme: Codable, Equatable, Sendable {
    public var name: String
    public var ring: RingStyle
    public var preview: PreviewSettings
    public var accentHex: String

    public init(name: String, ring: RingStyle, preview: PreviewSettings, accentHex: String) {
        self.name = name
        self.ring = ring
        self.preview = preview
        self.accentHex = accentHex
    }

    public static let `default` = Theme(
        name: "Default",
        ring: RingStyle(fillHex: "#1C1C1E", strokeHex: "#FFFFFF", opacity: 0.85),
        preview: .default,
        accentHex: "#0A84FF"
    )

    public static let minimal: Theme = {
        var p = PreviewSettings()
        p.showThumbnail = false
        p.opacity = 0
        return Theme(
            name: "Minimal",
            ring: RingStyle(fillHex: "#000000", strokeHex: "#FFFFFF", opacity: 0.6),
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
            ring: RingStyle(fillHex: "#FFFFFF", strokeHex: "#FFFFFF", opacity: 0.25),
            preview: p,
            accentHex: "#64D2FF"
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
    /// Seconds a snapped window takes to glide to its new frame. Optional so files written before
    /// it existed still decode (no schema bump); read and write it through `snapSeconds`.
    public var snapDuration: Double?

    /// `snapDuration` clamped to `0...SnapSpeed.maxSeconds`; 0 (the default) jumps straight there.
    public var snapSeconds: Double {
        get {
            guard let d = snapDuration, d.isFinite else { return 0 }
            return min(max(d, 0), SnapSpeed.maxSeconds)
        }
        set { snapDuration = newValue }
    }

    public init() {}
    public static let defaults = TesseraSettings()
}

/// Named snap speeds. Only the seconds are stored, so any value between them is a valid custom speed.
public enum SnapSpeed: String, CaseIterable, Sendable {
    case instant, snappy, smooth, fluid, relaxed

    public static let maxSeconds = 1.0

    public var seconds: Double {
        switch self {
        case .instant: 0
        case .snappy: 0.12
        case .smooth: 0.2
        case .fluid: 0.3
        case .relaxed: 0.45
        }
    }

    public var displayName: String { rawValue.capitalized }

    /// The preset whose duration is `seconds`, or nil for a custom value.
    public init?(seconds: Double) {
        guard let match = Self.allCases.first(where: { abs($0.seconds - seconds) < 0.005 }) else { return nil }
        self = match
    }
}
