import CoreGraphics

/// Retains physical motion that macOS clips at display edges. Coordinates and deltas both use y-up points.
public struct GesturePointer: Sendable {
    private var previous: CGPoint
    private var offset = CGSize.zero
    private var scale = CGSize(width: 1, height: 1)

    public init(origin: CGPoint) { previous = origin }

    public mutating func move(to point: CGPoint, delta: CGSize, bounds: CGRect) -> CGPoint {
        let actual = CGSize(width: point.x - previous.x, height: point.y - previous.y)
        let clippedX = (point.x <= bounds.minX + 1 && delta.width < 0)
            || (point.x >= bounds.maxX - 1 && delta.width > 0)
        let clippedY = (point.y <= bounds.minY + 1 && delta.height < 0)
            || (point.y >= bounds.maxY - 1 && delta.height > 0)
        if clippedX { offset.width += delta.width * scale.width - actual.width }
        else if abs(delta.width) > 0, abs(actual.width) > 0 {
            scale.width = min(max(abs(actual.width / delta.width), 0.25), 8)
        }
        if clippedY { offset.height += delta.height * scale.height - actual.height }
        else if abs(delta.height) > 0, abs(actual.height) > 0 {
            scale.height = min(max(abs(actual.height / delta.height), 0.25), 8)
        }
        previous = point
        return CGPoint(x: point.x + offset.width, y: point.y + offset.height)
    }
}
