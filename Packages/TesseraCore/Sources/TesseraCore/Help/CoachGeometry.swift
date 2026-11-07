import CoreGraphics

/// Pure geometry for the coach spotlight and its card. AppKit global coordinates (origin bottom-left, y up).
public enum CoachGeometry {
    /// The spotlight grows by this around each window.
    public static let inset: CGFloat = 4
    static let seamThickness: CGFloat = 8
    static let margin: CGFloat = 12

    /// The shared edge between frames[0] and frames[1] in on-screen order, as an 8 pt wide (tall on portrait) rect;
    /// nil when they don't face each other within `gap + 2`.
    public static func seam(_ frames: [CGRect], portrait: Bool, gap: CGFloat) -> CGRect? {
        guard frames.count >= 2 else { return nil }
        let (a, b) = (frames[0], frames[1])
        let tolerance = gap + 2
        if portrait {
            let distance = a.minY - b.maxY
            let lo = max(a.minX, b.minX), hi = min(a.maxX, b.maxX)
            guard abs(distance) <= tolerance, hi > lo else { return nil }
            let mid = (a.minY + b.maxY) / 2
            return CGRect(x: lo, y: mid - seamThickness / 2, width: hi - lo, height: seamThickness)
        }
        let distance = b.minX - a.maxX
        let lo = max(a.minY, b.minY), hi = min(a.maxY, b.maxY)
        guard abs(distance) <= tolerance, hi > lo else { return nil }
        let mid = (a.maxX + b.minX) / 2
        return CGRect(x: mid - seamThickness / 2, y: lo, width: seamThickness, height: hi - lo)
    }

    /// Card origin (AppKit, bottom-left) beside `target`: below it if it fits, else above, else right, else left,
    /// then clamped so the card sits ≥ 12 pt inside `screen`.
    public static func cardOrigin(size: CGSize, target: CGRect, screen: CGRect) -> CGPoint {
        let bounds = screen.insetBy(dx: margin, dy: margin)
        let candidates = [
            CGPoint(x: target.midX - size.width / 2, y: target.minY - margin - size.height),
            CGPoint(x: target.midX - size.width / 2, y: target.maxY + margin),
            CGPoint(x: target.maxX + margin, y: target.midY - size.height / 2),
            CGPoint(x: target.minX - margin - size.width, y: target.midY - size.height / 2)
        ]
        let fits = candidates.first { bounds.contains(CGRect(origin: $0, size: size)) } ?? candidates[0]
        return CGPoint(
            x: min(max(fits.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(fits.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }
}
