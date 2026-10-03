import CoreGraphics
import Foundation
import os
import TesseraCore

/// Owns the global event tap on a dedicated thread. The callback converts each event to an
/// `InputEvent`, feeds the tap-thread-confined `TriggerMachine`, forwards outputs, and decides
/// suppression synchronously. It never blocks.
final class InputService: @unchecked Sendable {
    /// Everything the tap thread's `TriggerMachine` is built from.
    fileprivate struct MachineConfig: Sendable {
        var chord: TriggerChord
        var hotkeys: [HotkeyBinding] = []
        var ringKeyNavigation = true
    }

    private struct Shared: Sendable {
        var config: MachineConfig
        /// Bumped on every config change so the tap thread can detect it without comparing arrays.
        var generation = 0
        var primaryHeight: CGFloat = 0
        /// Frontmost app is on the excluded list: the machine opens no ring and fires no hotkeys.
        var frontmostExcluded = false
        /// Main asked to drop an open ring it can't show (no window, no permission).
        var abortRequested = false
        var session: TapSession?
        var restarts: [TimeInterval] = []
    }

    fileprivate static let logger = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "InputService")

    fileprivate let onOutput: @Sendable (TriggerOutput) -> Void
    private let shared: OSAllocatedUnfairLock<Shared>

    init(chord: TriggerChord, onOutput: @escaping @Sendable (TriggerOutput) -> Void) {
        self.onOutput = onOutput
        self.shared = OSAllocatedUnfairLock(initialState: Shared(config: MachineConfig(chord: chord)))
    }

    /// Creates the tap and starts its thread. False when the tap can't be created (no permission).
    func start() -> Bool {
        if shared.withLock({ $0.session != nil }) { return true }

        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .scrollWheel, .mouseMoved, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let (config, generation) = shared.withLock { ($0.config, $0.generation) }
        let session = TapSession(service: self, config: config, generation: generation)
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
        shared.withLock {
            guard $0.config.chord != c else { return }
            $0.config.chord = c
            $0.generation += 1
        }
    }

    /// Like `updateChord`: the machine is rebuilt at the next event while the ring is closed.
    func updateHotkeys(_ bindings: [HotkeyBinding], ringKeyNavigation: Bool) {
        shared.withLock {
            guard $0.config.hotkeys != bindings || $0.config.ringKeyNavigation != ringKeyNavigation else { return }
            $0.config.hotkeys = bindings
            $0.config.ringKeyNavigation = ringKeyNavigation
            $0.generation += 1
        }
    }

    /// Call from main whenever displays change (`DisplayService.primaryHeight`), and before `start()`.
    func updatePrimaryHeight(_ height: CGFloat) {
        shared.withLock { $0.primaryHeight = height }
    }

    /// Call from main when the frontmost app changes or the excluded list changes.
    func setFrontmostExcluded(_ excluded: Bool) {
        shared.withLock { $0.frontmostExcluded = excluded }
    }

    /// Closes an open ring without outputs (main already handled the session ending).
    func abortSession() {
        shared.withLock { $0.abortRequested = true }
    }

    fileprivate func snapshot() -> (generation: Int, primaryHeight: CGFloat, excluded: Bool, abort: Bool) {
        shared.withLock { state in
            defer { state.abortRequested = false }
            return (state.generation, state.primaryHeight, state.frontmostExcluded, state.abortRequested)
        }
    }

    fileprivate func currentConfig() -> (config: MachineConfig, generation: Int) {
        shared.withLock { ($0.config, $0.generation) }
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

/// One tap lifetime. `machine` and `generation` are touched only on the tap thread.
private final class TapSession: @unchecked Sendable {
    private struct Control {
        var runLoop: CFRunLoop?
        var stopped = false
    }

    let service: InputService
    /// Set once in `InputService.start()` before the thread starts; read-only afterwards.
    var tap: CFMachPort?
    private var machine: TriggerMachine
    private var generation: Int
    private let control = OSAllocatedUnfairLock(uncheckedState: Control())

    init(service: InputService, config: InputService.MachineConfig, generation: Int) {
        self.service = service
        self.generation = generation
        self.machine = Self.machine(config)
    }

    private static func machine(_ c: InputService.MachineConfig) -> TriggerMachine {
        TriggerMachine(chord: c.chord, hotkeys: c.hotkeys, ringKeyNavigation: c.ringKeyNavigation)
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
            // Key-ups may have been lost while disabled: close the ring instead of leaving it stuck.
            for output in machine.reset() { service.onOutput(output) }
            service.tapWasDisabled(self)
            return false
        }
        let snapshot = service.snapshot()
        if snapshot.abort { _ = machine.reset() }
        machine.frontmostExcluded = snapshot.excluded
        if snapshot.generation != generation, !machine.isOpen {
            let current = service.currentConfig()
            generation = current.generation
            machine = Self.machine(current.config)
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
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return .keyDown(keyCode: code, modifiers: hotkeyModifiers(event.flags, keyCode: code), location: location,
                            isRepeat: isRepeat)
        case .keyUp:
            return .keyUp(keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
        case .mouseMoved, .leftMouseDragged:
            return .mouseMoved(location)
        case .leftMouseDown:
            return .leftMouseDown(location)
        case .leftMouseUp:
            return .leftMouseUp(location)
        case .rightMouseDown:
            return .rightMouseDown
        case .rightMouseUp:
            return .rightMouseUp
        case .scrollWheel:
            // Trackpad: point deltas accumulate in the machine; momentum is swallowed but never steps.
            // Mouse wheel: one notch = one step.
            if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return .scroll(deltaY: 0) }
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
                return .scroll(deltaY: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            }
            let notches = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            return .scroll(deltaY: Double(notches.signum()) * TriggerMachine.scrollStepPoints)
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

    /// Arrow and navigation-cluster keys carry a synthetic Fn flag; dropping it lets ⌃⌥← match exactly.
    /// Same normalization as the shortcut recorder, so recorded hotkeys (incl. F-keys) match.
    static func hotkeyModifiers(_ flags: CGEventFlags, keyCode: UInt16) -> Modifiers {
        Modifiers(deviceKeyCodes: pressedModifiers(flags)).normalized(forKeyCode: keyCode)
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
