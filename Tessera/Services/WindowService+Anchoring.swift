import CoreGraphics
import TesseraCore

/// Moved out of `WindowService.swift` to keep that file under 300 lines; it uses no actor state.
extension WindowService {
    /// True when the goal (AX coordinates) sits nearer the right edge of its display than the left
    /// (right half, right quarters, right-hand columns), so a constrained window keeps its right edge.
    static func recoveredUndoFrame(_ frame: CGRect, placement: WindowPlacementSnapshot? = nil,
                                   topology: WindowTopology? = nil) -> CGRect {
        if let placement, let topology { return placement.resolved(in: topology.recoveryDisplays) }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return frame }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return frame }
        return WindowRecovery.frame(frame, displays: ids.prefix(Int(count)).map { CGDisplayBounds($0).insetBy(dx: 0, dy: 24) })
    }

    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        max(abs(a.minX - b.minX), abs(a.maxX - b.maxX), abs(a.minY - b.minY), abs(a.maxY - b.maxY)) <= 2
    }

    static func anchorsRight(_ goal: CGRect) -> Bool {
        let bounds = displayBounds(for: goal)
        return bounds.maxX - goal.maxX < goal.minX - bounds.minX
    }

    static func displayBounds(for goal: CGRect) -> CGRect {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let centre = CGPoint(x: goal.midX, y: goal.midY)
        let found = CGGetDisplaysWithPoint(centre, 1, &display, &count) == .success && count > 0
        return CGDisplayBounds(found ? display : CGMainDisplayID())
    }
}
