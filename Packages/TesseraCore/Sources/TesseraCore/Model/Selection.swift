/// Vertical band within a column (point mode).
public enum Band: String, Codable, Sendable {
    case full, top, bottom
}

/// Inclusive 0-based column range plus a vertical band.
public struct ColumnSpan: Equatable, Sendable {
    public let columns: ClosedRange<Int>
    public let band: Band

    public init(columns: ClosedRange<Int>, band: Band) {
        self.columns = columns
        self.band = band
    }
}

/// Display-relative actions assignable to ring wedges.
public enum WindowAction: String, Codable, CaseIterable, Sendable {
    case maximize, center
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter

    public var displayName: String {
        switch self {
        case .maximize: "Maximise"
        case .center: "Centre"
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeftQuarter: "Top-left quarter"
        case .topRightQuarter: "Top-right quarter"
        case .bottomLeftQuarter: "Bottom-left quarter"
        case .bottomRightQuarter: "Bottom-right quarter"
        }
    }
}

/// What the user is currently pointing at.
public enum Selection: Equatable, Sendable {
    case none
    case wedge(index: Int, action: WindowAction)
    case span(display: DisplayID, span: ColumnSpan)
}
