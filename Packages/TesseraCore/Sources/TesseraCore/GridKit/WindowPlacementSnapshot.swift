import CoreGraphics

/// An Undo frame with the display coordinate system in which it was recorded.
public struct WindowPlacementSnapshot: Equatable, Sendable {
    public struct Display: Equatable, Sendable {
        public let key: String
        public let bounds: CGRect
        public init(key: String, bounds: CGRect) { self.key = key; self.bounds = bounds }
    }

    public let frame: CGRect
    public let display: Display?
    public init(frame: CGRect, display: Display?) { self.frame = frame; self.display = display }

    public func resolved(in displays: [Display]) -> CGRect {
        if let display, display.bounds.width > 0, display.bounds.height > 0 {
            let matches = displays.filter { $0.key == display.key }
            if matches.count == 1, let destination = matches.first {
                if destination.bounds == display.bounds { return frame }
                let xScale = destination.bounds.width / display.bounds.width
                let yScale = destination.bounds.height / display.bounds.height
                return CGRect(x: destination.bounds.minX + (frame.minX - display.bounds.minX) * xScale,
                              y: destination.bounds.minY + (frame.minY - display.bounds.minY) * yScale,
                              width: frame.width * xScale, height: frame.height * yScale)
            }
        }
        return WindowRecovery.frame(frame, displays: displays.map(\.bounds))
    }
}
