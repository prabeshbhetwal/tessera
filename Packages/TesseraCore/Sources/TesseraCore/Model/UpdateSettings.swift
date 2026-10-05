import Foundation

/// How often Tessera looks for a new version on its own.
public enum UpdateInterval: String, CaseIterable, Codable, Equatable, Sendable {
    case daily, weekly, fortnightly, monthly

    public var seconds: TimeInterval {
        switch self {
        case .daily: 86_400
        case .weekly: 604_800
        case .fortnightly: 1_209_600
        case .monthly: 2_592_000
        }
    }

    public var displayName: String { rawValue.capitalized }
}

/// Update preferences, applied to the updater by the app.
public struct UpdateSettings: Codable, Equatable, Sendable {
    /// The Sparkle channel that carries pre-release builds.
    public static let betaChannel = "beta"

    public var checkAutomatically = true
    public var interval: UpdateInterval = .weekly
    public var installAutomatically = false
    public var includeBetas = false

    /// Channels to accept beyond the default one.
    public var allowedChannels: Set<String> { includeBetas ? [Self.betaChannel] : [] }

    public init() {}
}
