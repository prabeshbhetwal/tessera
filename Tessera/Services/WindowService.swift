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
    /// Landed, but the app kept a different size (a minimum size, or it refuses resizing). Still an undoable move.
    case constrained(CGRect)
    /// A newer move of the same window took over mid-glide; that move does the final write and records undo.
    case superseded
    case failed(String)
}

/// Serial actor that owns every Accessibility call (spec §5.4). All AX messaging uses a 0.3 s timeout.
actor WindowService {
    private typealias UndoKey = WindowUndoHistory.Key

    static let timeout: Float = 0.3
    private static let enhancedUI = "AXEnhancedUserInterface"
    private static let frameInterval: Duration = .milliseconds(16)

    private var undo = WindowUndoHistory()
    /// The generation of each window's latest move, so a glide still running gives way to the newer
    /// move. Generations come from one monotonic counter, so a value never repeats after a reset.
    private var generations: [UndoKey: Int] = [:]
    private var nextGeneration = 0
    /// Where each gliding window started, so a move that takes over mid-glide records undo from
    /// the real starting frame, not from mid-air.
    private var glideStart: [UndoKey: CGRect] = [:]

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

    /// `duration` > 0 glides the window there first (time-based, so a slow app just gets fewer frames). The undo step
    /// is tagged `batch` (see `newBatch`).
    func apply(_ target: CGRect, to window: WindowRef, primaryHeight: CGFloat, crossingDisplays: Bool,
               duration: Double = 0, batch: Int? = nil) async -> ApplyResult {
        let element = window.element
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        guard let now = AX.frame(element) else { return .failed(Self.unreadableMessage) }

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
                return .superseded
            }
        }
        glideStart[key] = nil
        if generations[key] == generation { generations[key] = nil }

        if let error = setFrame(goal, on: window, crossingDisplays: crossingDisplays) {
            return .failed(Self.unmovableReason(of: element) ?? Self.reason(for: error))
        }

        // Single read-back. A size-constrained window is re-anchored to the targeted edges.
        guard var actual = AX.frame(element) else { return .failed(Self.unreadableMessage) }
        let sizeDiffers = abs(actual.width - goal.width) > 1 || abs(actual.height - goal.height) > 1
        if sizeDiffers {
            // A full-screen window accepts the write and stays put: nothing moved, nothing to undo.
            if let reason = Self.unmovableReason(of: element) { return .failed(reason) }
            let x = Self.anchorsRight(goal) ? goal.maxX - actual.width : goal.minX
            let anchored = CGPoint(x: x, y: goal.minY)
            if anchored != actual.origin, AX.setPosition(element, anchored) == .success {
                actual.origin = anchored
            }
        }

        undo.push(before, for: window, key: key, batch: batch)
        let landed = CoordinateSpace.fromAX(actual, primaryHeight: primaryHeight)
        return Self.isConstrained(landed: actual.size, goal: goal.size) ? .constrained(landed) : .applied(landed)
    }

    /// Undoes the most recent step: one move, or every window of a tile. Windows of apps in `excluding` (excluded
    /// after the move) are left alone. A step whose windows are all gone is dropped and the one before it tried; a
    /// step every live window refused is put back, so the next ⌃⌥Z can try again; a step held only by excluded apps
    /// is dropped and undo stops there, never reaching back to an older, unrelated step.
    func undoLast(excluding: Set<String> = []) -> UndoOutcome {
        while let step = undo.popStep() {
            var restored = false
            var refused: WindowRef?
            var excluded = false
            for (key, ref, frame) in step {
                if let id = ref.bundleID, excluding.contains(id) { excluded = true; continue }
                // A glide of this window still in flight would overwrite the restored frame on its next
                // tick; dropping its generation makes it stop (see `glide`).
                generations[key] = nil
                glideStart[key] = nil
                // Origin display unknown here, so use the cross-display order (safe on one display too).
                guard let error = setFrame(frame, on: ref, crossingDisplays: true) else { restored = true; continue }
                if refused == nil, !Self.isGone(ref, error: error) { refused = ref }
            }
            if restored { return .restored }
            if let refused {
                undo.reinstate(step)
                return .refused(refused)
            }
            if excluded { return .nothing }
        }
        return .nothing
    }

    /// A tag for moves that undo in one press (a Tile): pass it to `apply`, then `mergeMoves` when they are done.
    func newBatch() -> Int { undo.newBatch() }

    /// Joins the moves tagged `batch` into one undo step; moves made meanwhile by anything else stay their own steps.
    /// Returns `undoMarker()` when the next undo takes back exactly this batch, nil otherwise (`WindowUndoHistory.merge`).
    @discardableResult func mergeMoves(_ batch: Int) -> Int? { undo.merge(batch: batch) }

    /// Changes with every recorded move, merge and undo, so a caller can tell whether the latest step is still its own.
    func undoMarker() -> Int { undo.marker }

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
    /// screen), panels and dialogs, and anything smaller than a tiny utility window. Front-most first.
    func visibleWindows(on display: CGRect, primaryHeight: CGFloat, excluding: Set<String>) -> [(window: WindowRef, frame: CGRect)] {
        visibleWindowsCounted(on: display, primaryHeight: primaryHeight, excluding: excluding).found
    }

    /// `visibleWindows`, plus how many apps with windows there were skipped because their Accessibility read failed
    /// (timed out or refused), so Tile can say so instead of ignoring them.
    func visibleWindowsCounted(on display: CGRect, primaryHeight: CGFloat, excluding: Set<String>)
        -> (found: [(window: WindowRef, frame: CGRect)], skipped: Int) {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return ([], 0) }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var framesByPID: [pid_t: [CGWindowID: CGRect]] = [:]
        var depth: [CGWindowID: Int] = [:]  // the list runs front to back
        for (z, info) in list.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.width >= 120, bounds.height >= 80 else { continue }
            let frame = CoordinateSpace.fromAX(bounds, primaryHeight: primaryHeight)
            guard display.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            framesByPID[pid, default: [:]][id] = frame
            depth[id] = z
        }

        var result: [(window: WindowRef, frame: CGRect)] = []
        var skipped = 0
        for (pid, frames) in framesByPID {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  !excluding.contains(app.bundleIdentifier ?? "") else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Self.timeout)
            guard let windows = AX.value(axApp, kAXWindowsAttribute) as? [AXUIElement] else {
                skipped += 1
                Self.log.notice("skipped \(app.bundleIdentifier ?? "?", privacy: .public): its windows couldn't be read")
                continue
            }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, Self.timeout)
                guard let id = SPI.windowID(of: element), let frame = frames[id],
                      (AX.value(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else { continue }
                result.append((WindowRef(element: element, pid: pid, windowID: id, bundleID: app.bundleIdentifier), frame))
            }
        }
        let sorted = result.sorted { depth[$0.window.windowID ?? 0, default: .max] < depth[$1.window.windowID ?? 0, default: .max] }
        return (sorted, skipped)
    }

    // MARK: - Private

    /// Writes an AX frame with Enhanced UI temporarily off. Nil if any write was accepted; otherwise the first
    /// write's error, which is logged.
    private func setFrame(_ goal: CGRect, on window: WindowRef, crossingDisplays: Bool) -> AXError? {
        let element = window.element
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        AXUIElementSetMessagingTimeout(element, Self.timeout)

        let enhanced = AX.bool(app, Self.enhancedUI) == true
        if enhanced { AX.setBool(app, Self.enhancedUI, false) }
        defer { if enhanced { AX.setBool(app, Self.enhancedUI, true) } }

        let results: [AXError] = crossingDisplays
            ? [AX.setSize(element, goal.size), AX.setPosition(element, goal.origin), AX.setSize(element, goal.size)]
            : [AX.setPosition(element, goal.origin), AX.setSize(element, goal.size)]
        guard !results.contains(.success), let error = results.first else { return nil }
        Self.log.notice("set frame failed for \(window.bundleID ?? "?", privacy: .public): AXError \(error.rawValue, privacy: .public)")
        return error
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
            let slept = (try? await Task.sleep(for: Self.frameInterval)) != nil  // cancelled: stop, don't spin
            guard generations[key] == generation, slept else { return generations[key] == generation }
        }
    }

    private static func key(for window: WindowRef) -> UndoKey {
        window.windowID.map { .window($0) } ?? .element(Int(bitPattern: CFHash(window.element)))
    }

    static func frontmostPID() -> pid_t? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid > 0 { return pid }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        guard let app = AX.element(system, kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid > 0 else { return nil }
        return pid
    }
}
