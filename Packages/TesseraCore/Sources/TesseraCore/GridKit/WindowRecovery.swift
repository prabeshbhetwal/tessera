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
}
