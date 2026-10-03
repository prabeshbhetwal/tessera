import CoreGraphics

/// Stable identity of a physical display, survives re-docking.
public struct DisplayID: Hashable, Codable, Sendable {
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32
    public let uuid: String?

    public init(vendor: UInt32, model: UInt32, serial: UInt32, uuid: String?) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.uuid = uuid
    }

    /// Key used for per-display overrides in settings.
    public var storageKey: String {
        serial != 0 ? "\(vendor)-\(model)-\(serial)" : "uuid:\(uuid ?? "\(vendor)-\(model)")"
    }
}

/// Tunable constants for the sizing rule (spec §3.2).
public struct SizingConstants: Codable, Equatable, Sendable {
    public var idealColumnWidth: Double = 768
    public var minColumnWidth: Double = 640
    public var maxColumnWidth: Double = 1280
    public var minRowHeight: Double = 440
    public var maxColumns: Int = 8

    public init() {}
    public static let `default` = SizingConstants()
}

/// Output of the sizing rule. For portrait displays the "cols" fields mean rows.
public struct ColumnRange: Equatable, Sendable {
    public let minCols: Int
    public let maxCols: Int
    public let defaultCols: Int
    public let maxRows: Int
    public let isPortrait: Bool

    public init(minCols: Int, maxCols: Int, defaultCols: Int, maxRows: Int, isPortrait: Bool) {
        self.minCols = minCols
        self.maxCols = maxCols
        self.defaultCols = defaultCols
        self.maxRows = maxRows
        self.isPortrait = isPortrait
    }
}

/// Per-display grid choice. Only user overrides are persisted.
public struct DisplayProfile: Codable, Equatable, Sendable {
    public var columns: Int
    public var gap: Double
    public var padding: Double
    public var isUserOverride: Bool

    public init(columns: Int, gap: Double = 8, padding: Double = 8, isUserOverride: Bool = false) {
        self.columns = columns
        self.gap = gap
        self.padding = padding
        self.isUserOverride = isUserOverride
    }
}

/// A display as seen by the engine. Frames are AppKit global coords; `visibleFrame` is before padding.
public struct DisplayContext: Equatable, Sendable {
    public let id: DisplayID
    /// Whole screen including menu bar and Dock strips. Used for hit-testing the cursor.
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let range: ColumnRange
    public let profile: DisplayProfile

    public init(id: DisplayID, frame: CGRect? = nil, visibleFrame: CGRect, range: ColumnRange, profile: DisplayProfile) {
        self.id = id
        self.frame = frame ?? visibleFrame
        self.visibleFrame = visibleFrame
        self.range = range
        self.profile = profile
    }
}

extension Collection where Element == DisplayContext {
    /// The display whose whole screen contains `point`. The menu bar and Dock strips count, so the cursor
    /// never falls into a dead zone; points outside every screen return nil.
    public func display(at point: CGPoint) -> DisplayContext? {
        first { $0.frame.contains(point) }
    }
}
