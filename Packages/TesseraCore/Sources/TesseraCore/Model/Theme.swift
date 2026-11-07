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
