/// How the Settings window is drawn: frosted (the desktop blurred through it) or solid. Reduce Transparency and
/// Increase Contrast draw it solid.
public enum WindowMaterial: String, Codable, CaseIterable, Sendable {
    case frosted, solid

    public var displayName: String {
        switch self {
        case .frosted: "Frosted"
        case .solid: "Solid"
        }
    }

    /// "liquidGlass" (0.2.0-beta.30, since withdrawn) and any unknown look load as Frosted rather than setting the
    /// file aside.
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .frosted
    }
}
