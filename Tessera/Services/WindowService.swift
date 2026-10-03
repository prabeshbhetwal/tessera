import AppKit
import ApplicationServices
import TesseraCore

/// A target window. AXUIElement is an immutable CF reference, safe to pass between actors.
struct WindowRef: @unchecked Sendable, Equatable {
    let element: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID?
    let bundleID: String?
}

enum ApplyResult: Sendable, Equatable {
    case applied(CGRect)
    case failed(String)
}

/// Serial actor that owns every Accessibility call (spec §5.4). All AX messaging uses a 0.3 s timeout.
actor WindowService {
    private enum UndoKey: Hashable {
        case window(CGWindowID)
        case element(Int)
    }

    /// Frames are stored in AX coordinates so undo needs no display geometry.
    private struct UndoStack {
        var ref: WindowRef
        var frames: [CGRect]
    }

    private static let timeout: Float = 0.3
    private static let undoDepth = 20
    private static let enhancedUI = "AXEnhancedUserInterface"
    private static let frameInterval: Duration = .milliseconds(16)

    private var stacks: [UndoKey: UndoStack] = [:]
    /// The generation of each window's latest move, so a glide still running gives way to the newer
    /// move. Generations come from one monotonic counter, so a value never repeats after a reset.
    private var generations: [UndoKey: Int] = [:]
    private var nextGeneration = 0
    /// Where each gliding window started, so a move that takes over mid-glide records undo from
    /// the real starting frame, not from mid-air.
    private var glideStart: [UndoKey: CGRect] = [:]
    /// Chronological move history. Each entry is one undo step: usually one window, several after a tile.
    /// Windows whose stack has run dry are skipped on undo.
    private var history: [[UndoKey]] = []

    func frontmostWindow() -> WindowRef? {
        // Never our own windows: AX calls on our own pid run in-process on this (non-main) thread and
        // AppKit traps "Must only be used from the main thread" inside NSWindow.setFrame → crash.
        guard let pid = Self.frontmostPID(), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        guard let window = AX.element(app, kAXFocusedWindowAttribute) ?? AX.element(app, kAXMainWindowAttribute) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(window, Self.timeout)
        return WindowRef(
            element: window,
            pid: pid,
            windowID: SPI.windowID(of: window),
            bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        )
    }

    /// Current frame in AppKit coordinates.
    func frame(of window: WindowRef) -> CGRect? {
        AXUIElementSetMessagingTimeout(window.element, Self.timeout)
        // The main display is NSScreen.screens[0]; CG keeps this readable off the main actor.
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return AX.frame(window.element).map { CoordinateSpace.fromAX($0, primaryHeight: primaryHeight) }
    }

    /// `duration` > 0 glides the window there first (time-based, so a slow app just gets fewer frames).
    func apply(
        _ target: CGRect, to window: WindowRef, primaryHeight: CGFloat, crossingDisplays: Bool, duration: Double = 0
    ) async -> ApplyResult {
        let element = window.element
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        guard let now = AX.frame(element) else { return .failed("Can't read the window's frame") }

        let goal = CoordinateSpace.toAX(target, primaryHeight: primaryHeight)
        let key = Self.key(for: window)
        let before = glideStart[key] ?? now
        nextGeneration += 1
        let generation = nextGeneration
        generations[key] = generation
        if duration > 0, now != goal {
            glideStart[key] = before
            guard await glide(window, from: now, to: goal, duration: duration, key: key, generation: generation) else {
                // A newer move of this window took over mid-flight; it does the final write and records undo.
                return .applied(target)
            }
        }
        glideStart[key] = nil
        if generations[key] == generation { generations[key] = nil }

        guard setFrame(goal, on: window, crossingDisplays: crossingDisplays) else {
            return .failed("The app didn't accept the new frame")
        }

        // Single read-back. A size-constrained window is re-anchored to the targeted edges.
        guard var actual = AX.frame(element) else { return .failed("Can't read the window's frame") }
        if abs(actual.width - goal.width) > 1 || abs(actual.height - goal.height) > 1 {
            let x = Self.anchorsRight(goal) ? goal.maxX - actual.width : goal.minX
            let anchored = CGPoint(x: x, y: goal.minY)
            if anchored != actual.origin, AX.setPosition(element, anchored) {
                actual.origin = anchored
            }
        }

        push(before, for: window)
        return .applied(CoordinateSpace.fromAX(actual, primaryHeight: primaryHeight))
    }

    /// Undoes the most recent step: one move, or every window of a tile. False when there is nothing to undo.
    func undoLast() -> Bool {
        while let step = history.popLast() {
            var restored = false
            for key in step {
                guard var stack = stacks[key], let frame = stack.frames.popLast() else { continue }
                stacks[key] = stack.frames.isEmpty ? nil : stack
                // A glide of this window still in flight would overwrite the restored frame on its next
                // tick; dropping its generation makes it stop (see `glide`).
                generations[key] = nil
                glideStart[key] = nil
                // Origin display unknown here, so use the cross-display order (safe on one display too).
                if setFrame(frame, on: stack.ref, crossingDisplays: true) { restored = true }
            }
            if restored { return true }
        }
        return false
    }

    /// Joins the last `count` moves into one undo step (a tile of `count` windows undoes in one press).
    func mergeLastMoves(_ count: Int) {
        guard count > 1, history.count >= count else { return }
        let merged = history.suffix(count).flatMap { $0 }
        history.removeLast(count)
        history.append(merged)
    }

    /// On-screen normal-layer windows of other apps, in AppKit coordinates.
    func neighbourFrames(excluding window: WindowRef, primaryHeight: CGFloat) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Without a window ID, recognise the target by owner + frame.
        let targetFrame = window.windowID == nil ? AX.frame(window.element) : nil

        return list.compactMap { info -> CGRect? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            if let id = window.windowID, (info[kCGWindowNumber as String] as? CGWindowID) == id { return nil }
            if let targetFrame, pid == window.pid, bounds == targetFrame { return nil }
            return CoordinateSpace.fromAX(bounds, primaryHeight: primaryHeight)
        }
    }

    /// Standard windows of regular apps whose centre is on `display` (AppKit frame), with their AppKit
    /// frames, for tiling. Skips Tessera, apps in `excluding`, minimised and hidden windows (they are not on
    /// screen), panels and dialogs, and anything smaller than a tiny utility window.
    func visibleWindows(on display: CGRect, primaryHeight: CGFloat, excluding: Set<String>) -> [(window: WindowRef, frame: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var framesByPID: [pid_t: [CGWindowID: CGRect]] = [:]
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.width >= 120, bounds.height >= 80 else { continue }
            let frame = CoordinateSpace.fromAX(bounds, primaryHeight: primaryHeight)
            guard display.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            framesByPID[pid, default: [:]][id] = frame
        }

        var result: [(window: WindowRef, frame: CGRect)] = []
        for (pid, frames) in framesByPID {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  !excluding.contains(app.bundleIdentifier ?? "") else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Self.timeout)
            guard let windows = AX.value(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, Self.timeout)
                guard let id = SPI.windowID(of: element), let frame = frames[id],
                      (AX.value(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else { continue }
                result.append((WindowRef(element: element, pid: pid, windowID: id, bundleID: app.bundleIdentifier), frame))
            }
        }
        return result
    }

    // MARK: - Private

    /// Writes an AX frame with Enhanced UI temporarily off. True if any write was accepted.
    private func setFrame(_ goal: CGRect, on window: WindowRef, crossingDisplays: Bool) -> Bool {
        let element = window.element
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        AXUIElementSetMessagingTimeout(element, Self.timeout)

        let enhanced = AX.bool(app, Self.enhancedUI) == true
        if enhanced { AX.setBool(app, Self.enhancedUI, false) }
        defer { if enhanced { AX.setBool(app, Self.enhancedUI, true) } }

        let results: [Bool] = crossingDisplays
            ? [AX.setSize(element, goal.size), AX.setPosition(element, goal.origin), AX.setSize(element, goal.size)]
            : [AX.setPosition(element, goal.origin), AX.setSize(element, goal.size)]
        return results.contains(true)
    }

    /// Eases (cubic ease-out) from `start` toward `goal` in AX coordinates, without the final exact write.
    /// False when a newer move of the same window took over. The actor is free between frames.
    private func glide(
        _ window: WindowRef, from start: CGRect, to goal: CGRect, duration: Double, key: UndoKey, generation: Int
    ) async -> Bool {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let enhanced = AX.bool(app, Self.enhancedUI) == true
        if enhanced { AX.setBool(app, Self.enhancedUI, false) }
        defer { if enhanced { AX.setBool(app, Self.enhancedUI, true) } }

        let clock = ContinuousClock()
        let begin = clock.now
        let total = Duration.seconds(duration)
        while true {
            let t = min((clock.now - begin) / total, 1)
            if t >= 1 { return true }
            let e = 1 - pow(1 - t, 3)
            let frame = CGRect(
                x: start.minX + (goal.minX - start.minX) * e, y: start.minY + (goal.minY - start.minY) * e,
                width: start.width + (goal.width - start.width) * e, height: start.height + (goal.height - start.height) * e)
            _ = AX.setPosition(window.element, frame.origin)
            _ = AX.setSize(window.element, frame.size)
            try? await Task.sleep(for: Self.frameInterval)
            guard generations[key] == generation else { return false }
        }
    }

    private static func key(for window: WindowRef) -> UndoKey {
        window.windowID.map { .window($0) } ?? .element(Int(bitPattern: CFHash(window.element)))
    }

    private func push(_ axFrame: CGRect, for window: WindowRef) {
        let key = Self.key(for: window)
        var stack = stacks[key] ?? UndoStack(ref: window, frames: [])
        stack.ref = window
        stack.frames.append(axFrame)
        if stack.frames.count > Self.undoDepth { stack.frames.removeFirst() }
        stacks[key] = stack
        history.append([key])
        if history.count > 500 { history.removeFirst(history.count - 500) }
    }

    private static func frontmostPID() -> pid_t? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid > 0 { return pid }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        guard let app = AX.element(system, kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    /// True when the goal sits nearer the right edge of its display than the left
    /// (right half, right quarters, right-hand columns), so a constrained window keeps its right edge.
    private static func anchorsRight(_ goal: CGRect) -> Bool {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let centre = CGPoint(x: goal.midX, y: goal.midY)
        let found = CGGetDisplaysWithPoint(centre, 1, &display, &count) == .success && count > 0
        let bounds = CGDisplayBounds(found ? display : CGMainDisplayID())
        return bounds.maxX - goal.maxX < goal.minX - bounds.minX
    }
}

/// Thin typed wrappers over the AX C API. No force casts: CF types are checked by type ID.
private enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(v, to: AXUIElement.self)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = axValue(element, kAXPositionAttribute, .cgPoint, CGPoint.zero),
              let size = axValue(element, kAXSizeAttribute, .cgSize, CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let v = value(element, attribute), CFGetTypeID(v) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(unsafeDowncast(v, to: CFBoolean.self))
    }

    static func setBool(_ element: AXUIElement, _ attribute: String, _ on: Bool) {
        _ = AXUIElementSetAttributeValue(element, attribute as CFString, NSNumber(value: on))
    }

    private static func axValue<T: BitwiseCopyable>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ initial: T) -> T? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var out = initial
        return AXValueGetValue(unsafeDowncast(v, to: AXValue.self), type, &out) ? out : nil
    }
}
