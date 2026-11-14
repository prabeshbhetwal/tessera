/// How the Settings window's sidebar and preview are drawn. Liquid Glass needs macOS 26 and draws as Frosted before
/// it; Reduce Transparency draws every look as Solid.
public enum WindowMaterial: String, Codable, CaseIterable, Sendable {
    case liquidGlass, frosted, solid

    public var displayName: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .frosted: "Frosted"
        case .solid: "Solid"
        }
    }

    /// An unknown look (a file from a newer build) loads as Liquid Glass rather than setting the file aside.
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .liquidGlass
    }
}
