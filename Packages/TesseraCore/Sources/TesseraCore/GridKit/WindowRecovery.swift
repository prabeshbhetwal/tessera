import CoreGraphics

/// Keeps a remembered frame reachable when its display has disconnected, while preserving intentional placements.
public enum WindowRecovery {
    public static func frame(_ stored: CGRect, displays: [CGRect]) -> CGRect {
        guard !displays.contains(where: { $0.intersects(stored) }),
              let display = displays.filter({ !$0.isEmpty }).min(by: {
                  hypot($0.midX - stored.midX, $0.midY - stored.midY)
                    < hypot($1.midX - stored.midX, $1.midY - stored.midY)
              }) else { return stored }
        let size = CGSize(width: min(stored.width, display.width), height: min(stored.height, display.height))
        return CGRect(x: min(max(stored.minX, display.minX), display.maxX - size.width),
                      y: min(max(stored.minY, display.minY), display.maxY - size.height),
                      width: size.width, height: size.height)
    }

    /// Where a window that kept its own `size` (a minimum size, or it refuses resizing) goes so it still hugs the edges
    /// it was aimed at: the right edge when `goal` sits nearer its display's right than its left, the bottom edge when
    /// nearer the bottom than the top. Top-left origin coordinates (AX), as are `goal` and `display`.
    public static func anchoredOrigin(goal: CGRect, size: CGSize, display: CGRect) -> CGPoint {
        CGPoint(
            x: display.maxX - goal.maxX < goal.minX - display.minX ? max(display.minX, goal.maxX - size.width) : goal.minX,
            y: display.maxY - goal.maxY < goal.minY - display.minY ? max(display.minY, goal.maxY - size.height) : goal.minY)
    }
}
