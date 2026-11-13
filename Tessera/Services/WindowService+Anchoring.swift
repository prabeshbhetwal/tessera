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

    /// The connected displays now, keyed like `DisplayID.storageKey`, so Undo can map a frame onto a display that
    /// still exists. CG only, so it is safe off the main actor.
    static func currentDisplays() -> [WindowPlacementSnapshot.Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var numbers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &numbers, &count) == .success else { return [] }
        return numbers.prefix(Int(count)).map { number in
            let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
            let id = DisplayID(vendor: CGDisplayVendorNumber(number), model: CGDisplayModelNumber(number),
                               serial: CGDisplaySerialNumber(number),
                               uuid: uuid.map { CFUUIDCreateString(nil, $0) as String })
            return .init(key: id.storageKey, bounds: CGDisplayBounds(number))
        }
    }

    /// `frame` together with the display it sits on, for an Undo step.
    static func placement(_ frame: CGRect) -> WindowPlacementSnapshot {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return WindowPlacementSnapshot(frame: frame, display: currentDisplays().first { $0.bounds.contains(centre) })
    }

    /// Equal within 2 pt on every edge: what an app reports back after a write it honoured.
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        max(abs(a.minX - b.minX), abs(a.maxX - b.maxX), abs(a.minY - b.minY), abs(a.maxY - b.maxY)) <= 2
    }
}
