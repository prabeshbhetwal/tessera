import CoreGraphics

/// Input as seen by the event tap. Locations are AppKit global coordinates.
/// `pressedModifiers` holds device-specific modifier keycodes (54/55 Cmd, 56/60 Shift,
/// 58/61 Option, 59/62 Control, 63 Fn), computed by InputService.
public enum InputEvent: Sendable, Equatable {
    case flagsChanged(pressedModifiers: Set<UInt16>, location: CGPoint)
    case keyDown(keyCode: UInt16, location: CGPoint)
    case mouseMoved(CGPoint)
    case leftMouseDown(CGPoint)
    case leftMouseUp(CGPoint)
    /// Point delta. InputService maps one mouse-wheel notch to `TriggerMachine.scrollStepPoints`
    /// and drops trackpad momentum to 0.
    case scroll(deltaY: Double)
}

public enum TriggerOutput: Sendable, Equatable {
    case open(origin: CGPoint)
    case move(CGPoint)
    case anchor(CGPoint)
    case step(Int)
    case apply
    case cancel
}

public struct TriggerResult: Equatable, Sendable {
    public let outputs: [TriggerOutput]
    /// True when the event tap must swallow the event.
    public let suppress: Bool

    public init(outputs: [TriggerOutput], suppress: Bool) {
        self.outputs = outputs
        self.suppress = suppress
    }

    static let ignored = TriggerResult(outputs: [], suppress: false)
}

/// Chord-held state machine. A value type confined to the event-tap thread, which owns it so
/// it can decide synchronously whether to suppress an event (spec §5.3).
public struct TriggerMachine: Sendable {
    private static let escapeKeyCode: UInt16 = 53
    /// Accumulated scroll distance that changes the column count by one.
    public static let scrollStepPoints: Double = 60

    private let chord: Set<UInt16>
    private var armed = true
    public private(set) var isOpen = false
    private var scrollAccumulator: Double = 0
    private var swallowNextMouseUp = false

    public init(chord: TriggerChord) { self.chord = chord.keyCodes }

    public mutating func handle(_ e: InputEvent) -> TriggerResult {
        switch e {
        case .flagsChanged(let pressed, let location):
            return flagsChanged(pressed, location)
        case .keyDown(let keyCode, _):
            guard isOpen else { return .ignored }
            isOpen = false
            return TriggerResult(outputs: [.cancel], suppress: keyCode == Self.escapeKeyCode)
        case .mouseMoved(let p):
            return isOpen ? TriggerResult(outputs: [.move(p)], suppress: false) : .ignored
        case .leftMouseDown(let p):
            guard isOpen else { return .ignored }
            swallowNextMouseUp = true
            return TriggerResult(outputs: [.anchor(p)], suppress: true)
        case .leftMouseUp:
            // Pair every swallowed mouse-down with a swallowed mouse-up, even if the ring closed in between.
            guard swallowNextMouseUp || isOpen else { return .ignored }
            swallowNextMouseUp = false
            return TriggerResult(outputs: [], suppress: true)
        case .scroll(let deltaY):
            guard isOpen else { return .ignored }
            // Swallow every scroll while open (incl. zero/momentum) so the window below never scrolls.
            scrollAccumulator += deltaY
            guard abs(scrollAccumulator) >= Self.scrollStepPoints else { return TriggerResult(outputs: [], suppress: true) }
            let step = scrollAccumulator > 0 ? 1 : -1
            scrollAccumulator = 0
            return TriggerResult(outputs: [.step(step)], suppress: true)
        }
    }

    /// Called when the system disabled the tap: key-ups may have been lost, so close without applying.
    public mutating func reset() -> [TriggerOutput] {
        let wasOpen = isOpen
        isOpen = false
        armed = true
        scrollAccumulator = 0
        return wasOpen ? [.cancel] : []
    }

    private mutating func flagsChanged(_ pressed: Set<UInt16>, _ location: CGPoint) -> TriggerResult {
        var outputs: [TriggerOutput] = []
        let held = chord.intersection(pressed)

        if isOpen {
            if held.count < chord.count {
                isOpen = false
                outputs.append(.apply)
            }
        } else if armed, !chord.isEmpty, held.count == chord.count {
            isOpen = true
            armed = false
            scrollAccumulator = 0
            outputs.append(.open(origin: location))
        }

        // Re-arm only once every chord key is up (also covers apply + full release in one event).
        if held.isEmpty { armed = true }
        return TriggerResult(outputs: outputs, suppress: false)
    }
}
