import CoreGraphics
import Foundation

/// `#RRGGBB` / `#RRGGBBAA` <-> sRGB `CGColor`. Malformed input falls back to white.
enum HexColor {
    static func cgColor(_ hex: String, alpha: Double = 1) -> CGColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            return CGColor(gray: 1, alpha: alpha)
        }
        let rgba = s.count == 8 ? v : (v << 8) | 0xFF
        func channel(_ shift: UInt64) -> CGFloat { CGFloat((rgba >> shift) & 0xFF) / 255 }
        return CGColor(
            srgbRed: channel(24), green: channel(16), blue: channel(8),
            alpha: channel(0) * CGFloat(alpha)
        )
    }

    /// Perceived brightness above mid-grey. Malformed input counts as light (it falls back to white).
    static func isLight(_ hex: String) -> Bool {
        guard let c = cgColor(hex).components, c.count >= 3 else { return true }
        return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] > 0.5
    }

    /// Choose the ink with the larger WCAG contrast ratio against an opaque accent.
    static func contrastingInk(_ hex: String) -> CGColor {
        let c = cgColor(hex).components ?? [1, 1, 1, 1]
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
        return CGColor(gray: luminance > 0.179 ? 0 : 1, alpha: 1)
    }

    static func hex(_ color: CGColor) -> String {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let c = color.converted(to: space, intent: .defaultIntent, options: nil),
            let comps = c.components, comps.count >= 3
        else { return "#FFFFFF" }
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(comps[0]), byte(comps[1]), byte(comps[2]))
    }
}
