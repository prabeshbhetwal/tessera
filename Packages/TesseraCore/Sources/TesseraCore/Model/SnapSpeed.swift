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
