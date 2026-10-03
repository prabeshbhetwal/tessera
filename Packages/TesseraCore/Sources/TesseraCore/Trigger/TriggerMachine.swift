import CoreGraphics

/// Input as seen by the event tap. Locations are AppKit global coordinates.
/// `pressedModifiers` holds device-specific modifier keycodes (54/55 Cmd, 56/60 Shift,
/// 58/61 Option, 59/62 Control, 63 Fn), computed by InputService.
public enum InputEvent: Sendable, Equatable {
    case flagsChanged(pressedModifiers: Set<UInt16>, location: CGPoint)
    case keyDown(keyCode: UInt16, location: CGPoint)
    case mouseMoved(CGPoint)
    case leftMouseDown(CGPoint)
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

    private let chord: Set<UInt16>
    private var armed = true
    public private(set) var isOpen = false

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
            return isOpen ? TriggerResult(outputs: [.anchor(p)], suppress: true) : .ignored
        case .scroll(let deltaY):
            guard isOpen, deltaY != 0 else { return .ignored }
            return TriggerResult(outputs: [.step(deltaY > 0 ? 1 : -1)], suppress: true)
        }
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
            outputs.append(.open(origin: location))
        }

        // Re-arm only once every chord key is up (also covers apply + full release in one event).
        if held.isEmpty { armed = true }
        return TriggerResult(outputs: outputs, suppress: false)
    }
}
