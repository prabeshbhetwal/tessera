// TEMPORARY STUB — coordinator deletes at merge
// Signatures copied from the milestone-1 plan (Tracks A and B) so Track D compiles alone.
import CoreGraphics
import TesseraCore

// MARK: Track A (GridKit)

enum SizingRule {
    static func range(for usable: CGSize, constants: SizingConstants) -> ColumnRange {
        ColumnRange(minCols: 1, maxCols: 1, defaultCols: 1, maxRows: 1, isPortrait: usable.height > usable.width)
    }
}

extension DisplayProfile {
    static func auto(range: ColumnRange, gap: Double, padding: Double) -> DisplayProfile {
        DisplayProfile(columns: range.defaultCols, gap: gap, padding: padding)
    }

    func clamped(to range: ColumnRange) -> DisplayProfile { self }
}

enum CoordinateSpace {
    static func toAX(_ r: CGRect, primaryHeight: CGFloat) -> CGRect { r }
    static func fromAX(_ r: CGRect, primaryHeight: CGFloat) -> CGRect { r }
    static func pointFromCG(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint { p }
}

// MARK: Track B (Trigger)

enum InputEvent: Sendable, Equatable {
    case flagsChanged(pressedModifiers: Set<UInt16>, location: CGPoint)
    case keyDown(keyCode: UInt16, location: CGPoint)
    case mouseMoved(CGPoint)
    case leftMouseDown(CGPoint)
    case scroll(deltaY: Double)
}

enum TriggerOutput: Sendable, Equatable {
    case open(origin: CGPoint)
    case move(CGPoint)
    case anchor(CGPoint)
    case step(Int)
    case apply
    case cancel
}

struct TriggerResult: Equatable {
    let outputs: [TriggerOutput]
    let suppress: Bool
}

struct TriggerMachine: Sendable {
    init(chord: TriggerChord) {}
    mutating func handle(_ e: InputEvent) -> TriggerResult { TriggerResult(outputs: [], suppress: false) }
    var isOpen: Bool { false }
}
