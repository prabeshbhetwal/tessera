import CoreGraphics

/// The only place that converts between AppKit global coordinates (bottom-left origin, y up) and the
/// top-left, y-down space used by Accessibility and CGEvent. Both are relative to the primary screen,
/// so the flip depends only on the primary screen's height.
///
/// Note: SwiftUI also declares a `CoordinateSpace`; files that import both modules should write
/// `TesseraCore.CoordinateSpace`.
public enum CoordinateSpace {
    /// AppKit rect -> AX rect: `y' = primaryHeight - (y + height)`.
    public static func toAX(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(r, primaryHeight: primaryHeight)
    }

    /// AX rect -> AppKit rect. The flip is its own inverse.
    public static func fromAX(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(r, primaryHeight: primaryHeight)
    }

    /// CGEvent (top-left) point -> AppKit point: `y' = primaryHeight - y`.
    public static func pointFromCG(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - (r.origin.y + r.size.height), width: r.size.width, height: r.size.height)
    }
}
