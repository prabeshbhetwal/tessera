import AppKit
import TesseraCore

/// Display geometry for placing and undoing moves, in AX (top-left origin) coordinates. Kept apart from
/// `WindowService.swift` for its line limit; it uses no actor state.
extension WindowService {
    /// Bounds of the display holding `goal`'s centre, or the main display.
    static func displayBounds(for goal: CGRect) -> CGRect {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let centre = CGPoint(x: goal.midX, y: goal.midY)
        let found = CGGetDisplaysWithPoint(centre, 1, &display, &count) == .success && count > 0
        return CGDisplayBounds(found ? display : CGMainDisplayID())
    }

    /// Equal within 2 pt on every edge: what an app reports back after a write it honoured.
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        max(abs(a.minX - b.minX), abs(a.maxX - b.maxX), abs(a.minY - b.minY), abs(a.maxY - b.maxY)) <= 2
    }
}
