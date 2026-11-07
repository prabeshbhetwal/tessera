import CoreGraphics

/// Moved out of `WindowService.swift` to keep that file under 300 lines; it uses no actor state.
extension WindowService {
    /// True when the goal (AX coordinates) sits nearer the right edge of its display than the left
    /// (right half, right quarters, right-hand columns), so a constrained window keeps its right edge.
    static func anchorsRight(_ goal: CGRect) -> Bool {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let centre = CGPoint(x: goal.midX, y: goal.midY)
        let found = CGGetDisplaysWithPoint(centre, 1, &display, &count) == .success && count > 0
        let bounds = CGDisplayBounds(found ? display : CGMainDisplayID())
        return bounds.maxX - goal.maxX < goal.minX - bounds.minX
    }
}
