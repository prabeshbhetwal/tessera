import CoreGraphics
import Foundation
import os
import TesseraCore

/// Owns the global event tap on a dedicated thread. The callback converts each event to an
/// `InputEvent`, feeds the tap-thread-confined `TriggerMachine`, forwards outputs, and decides
/// suppression synchronously. It never blocks.
final class InputService: @unchecked Sendable {
    private struct Shared: Sendable {
        var chord: TriggerChord
        var primaryHeight: CGFloat = 0
        var session: TapSession?
        var restarts: [TimeInterval] = []
    }

    fileprivate static let logger = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "InputService")

    fileprivate let onOutput: @Sendable (TriggerOutput) -> Void
    private let shared: OSAllocatedUnfairLock<Shared>

    init(chord: TriggerChord, onOutput: @escaping @Sendable (TriggerOutput) -> Void) {
        self.onOutput = onOutput
        self.shared = OSAllocatedUnfairLock(initialState: Shared(chord: chord))
    }

    /// Creates the tap and starts its thread. False when the tap can't be created (no permission).
    func start() -> Bool {
        if shared.withLock({ $0.session != nil }) { return true }

        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .scrollWheel, .mouseMoved, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let session = TapSession(service: self, chord: shared.withLock { $0.chord })
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: inputTapCallback,
            userInfo: Unmanaged.passUnretained(session).toOpaque()
        ) else {
            Self.logger.error("CGEvent.tapCreate failed; Accessibility / Input Monitoring not granted?")
            return false
        }
        session.tap = tap
        shared.withLock { $0.session = session }

        // The thread's closure keeps `session` (the refcon) alive until the run loop exits.
        let thread = Thread { session.run() }
        thread.name = "com.prabeshbhetwal.Tessera.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        let session = shared.withLock { state -> TapSession? in
            defer { state.session = nil }
            return state.session
        }
        session?.stop()
    }

    /// Takes effect on the tap thread at the next event while the menu is closed.
    func updateChord(_ c: TriggerChord) {
        shared.withLock { $0.chord = c }
    }

    /// Call from main whenever displays change (`DisplayService.primaryHeight`), and before `start()`.
    func updatePrimaryHeight(_ height: CGFloat) {
        shared.withLock { $0.primaryHeight = height }
    }

    fileprivate func snapshot() -> (chord: TriggerChord, primaryHeight: CGFloat) {
        shared.withLock { ($0.chord, $0.primaryHeight) }
    }

    /// Re-enables a tap the system disabled. More than 5 restarts within 2 s → pause 2 s first.
    fileprivate func tapWasDisabled(_ session: TapSession) {
        let now = ProcessInfo.processInfo.systemUptime
        let needsBackoff = shared.withLock { state -> Bool in
            state.restarts = state.restarts.filter { now - $0 < 2 } + [now]
            return state.restarts.count > 5
        }
        if needsBackoff {
            Self.logger.warning("Event tap disabled repeatedly; pausing 2 s")
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 2) { session.enable() }
        } else {
            session.enable()
        }
    }
}

/// One tap lifetime. `machine` and `chord` are touched only on the tap thread.
private final class TapSession: @unchecked Sendable {
    private struct Control {
        var runLoop: CFRunLoop?
        var stopped = false
    }

    let service: InputService
    /// Set once in `InputService.start()` before the thread starts; read-only afterwards.
    var tap: CFMachPort?
    private var machine: TriggerMachine
    private var chord: TriggerChord
    private let control = OSAllocatedUnfairLock(uncheckedState: Control())

    init(service: InputService, chord: TriggerChord) {
        self.service = service
        self.chord = chord
        self.machine = TriggerMachine(chord: chord)
    }

    /// Tap-thread body: runs until `stop()`, then tears the tap down on this same thread.
    func run() {
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return }
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        control.withLockUnchecked { $0.runLoop = runLoop }
        CGEvent.tapEnable(tap: tap, enable: true)

        // Bounded runs so a stop() that lands before CFRunLoopRun starts is still observed.
        while !control.withLockUnchecked({ $0.stopped }) {
            _ = CFRunLoopRunInMode(.defaultMode, 0.5, false)
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(tap)
    }

    func stop() {
        let runLoop = control.withLockUnchecked { state -> CFRunLoop? in
            state.stopped = true
            return state.runLoop
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    func enable() {
        guard let tap, !control.withLockUnchecked({ $0.stopped }) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns true when the event must be suppressed.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            service.tapWasDisabled(self)
            return false
        }
        let snapshot = service.snapshot()
        if snapshot.chord != chord, !machine.isOpen {
            chord = snapshot.chord
            machine = TriggerMachine(chord: chord)
        }
        guard let input = Self.inputEvent(type, event, primaryHeight: snapshot.primaryHeight) else { return false }
        let result = machine.handle(input)
        for output in result.outputs { service.onOutput(output) }
        return result.suppress
    }

    private static func inputEvent(_ type: CGEventType, _ event: CGEvent, primaryHeight: CGFloat) -> InputEvent? {
        let location = CoordinateSpace.pointFromCG(event.location, primaryHeight: primaryHeight)
        switch type {
        case .flagsChanged:
            return .flagsChanged(pressedModifiers: pressedModifiers(event.flags), location: location)
        case .keyDown:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            return .keyDown(keyCode: code, location: location)
        case .mouseMoved, .leftMouseDragged:
            return .mouseMoved(location)
        case .leftMouseDown:
            return .leftMouseDown(location)
        case .scrollWheel:
            // Line delta: small trackpad jitter reads as 0, which the machine ignores.
            return .scroll(deltaY: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)))
        default:
            return nil
        }
    }

    /// `NX_DEVICE*KEYMASK` bits → device-specific modifier keycodes.
    private static let deviceMasks: [(mask: UInt64, keyCode: UInt16)] = [
        (0x0000_0001, 59), (0x0000_2000, 62), // left / right Control
        (0x0000_0002, 56), (0x0000_0004, 60), // left / right Shift
        (0x0000_0020, 58), (0x0000_0040, 61), // left / right Option
        (0x0000_0008, 55), (0x0000_0010, 54), // left / right Command
    ]

    private static func pressedModifiers(_ flags: CGEventFlags) -> Set<UInt16> {
        var keys = Set<UInt16>()
        for entry in deviceMasks where flags.rawValue & entry.mask != 0 {
            keys.insert(entry.keyCode)
        }
        if flags.contains(.maskSecondaryFn) { keys.insert(63) }
        return keys
    }
}

private func inputTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<TapSession>.fromOpaque(refcon).takeUnretainedValue()
    return session.handle(type, event) ? nil : Unmanaged.passUnretained(event)
}
