import CoreGraphics

/// Selects windows with exposed content, in front-to-back order. Several foreground windows can jointly cover one.
public enum WindowVisibility {
    public static func exposedIndices(_ frames: [CGRect]) -> [Int] {
        var covering: [CGRect] = []
        var exposed: [Int] = []
        for (index, frame) in frames.enumerated() {
            var pieces = [frame]
            for cover in covering {
                pieces = pieces.flatMap { subtract(cover, from: $0) }
                if pieces.isEmpty { break }
            }
            if pieces.contains(where: { $0.width > 1 && $0.height > 1 }) { exposed.append(index) }
            covering.append(frame)
        }
        return exposed
    }

    /// The windows a Tile or split may use, front to back: resizable, and exposed or `forced` (a split's own member, a
    /// joining app's new window). Every frame still covers the ones behind it, so a fixed-size window (an alert, an
    /// About box) hides what it covers without ever being picked itself.
    public static func selectedIndices(_ frames: [CGRect], resizable: [Bool], forced: [Bool]) -> [Int] {
        let exposed = Set(exposedIndices(frames))
        return frames.indices.filter { resizable[$0] && (exposed.contains($0) || forced[$0]) }
    }

    private static func subtract(_ cover: CGRect, from rect: CGRect) -> [CGRect] {
        let intersection = rect.intersection(cover)
        guard !intersection.isNull, !intersection.isEmpty else { return [rect] }
        return [
            CGRect(x: rect.minX, y: rect.minY, width: intersection.minX - rect.minX, height: rect.height),
            CGRect(x: intersection.maxX, y: rect.minY, width: rect.maxX - intersection.maxX, height: rect.height),
            CGRect(x: intersection.minX, y: rect.minY, width: intersection.width, height: intersection.minY - rect.minY),
            CGRect(x: intersection.minX, y: intersection.maxY, width: intersection.width, height: rect.maxY - intersection.maxY),
        ].filter { !$0.isEmpty }
    }
}
