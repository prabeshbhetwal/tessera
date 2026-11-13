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

    /// Channels to accept beyond the default one. Every appcast item is on the beta channel, so a pre-release
    /// build always accepts it: without that, a beta never sees the next beta and a check says up to date.
    public func allowedChannels(runningVersion: String?) -> Set<String> {
        includeBetas || Self.isPrerelease(runningVersion) ? [Self.betaChannel] : []
    }

    /// A version string with a pre-release suffix, such as `0.2.0-beta.25`.
    public static func isPrerelease(_ version: String?) -> Bool { version?.contains("-") == true }

    public init() {}
}
