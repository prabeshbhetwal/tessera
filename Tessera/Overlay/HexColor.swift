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
