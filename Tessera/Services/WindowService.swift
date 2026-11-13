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
    typealias UndoKey = WindowUndoHistory.Key

    static let timeout: Float = 0.3
    static let enhancedUI = "AXEnhancedUserInterface"
    static let frameInterval: Duration = .milliseconds(16)

    var undo = WindowUndoHistory()
    /// The generation of each window's latest move, so a glide still running gives way to the newer
    /// move. Generations come from one monotonic counter, so a value never repeats after a reset.
    var generations: [UndoKey: Int] = [:]
    private var nextGeneration = 0
    /// Where each moving window started, so a move that takes over mid-glide (or mid re-check) records undo from
    /// the real starting frame, not from mid-air.
    var glideStart: [UndoKey: CGRect] = [:]
    /// Moves not yet recorded for undo (gliding, or waiting to re-check a write), so ⌃⌥Z can stop and reverse them.
    var inFlight: [UndoKey: (window: WindowRef, before: CGRect, batch: Int?, generation: Int)] = [:]
    /// Batches handed out and not yet merged, and those of them Undo cancelled midway.
    var openBatches: Set<Int> = []
    var cancelledBatches: Set<Int> = []

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
        // Undo already took this batch back; its remaining moves must not land after it.
        if let batch, cancelledBatches.contains(batch) { return .superseded }
        let element = window.element
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        guard let now = AX.frame(element) else { return .failed(Self.unreadableMessage) }

        let goal = CoordinateSpace.toAX(target, primaryHeight: primaryHeight)
        let key = Self.key(for: window)
        let before = glideStart[key] ?? now
        nextGeneration += 1
        let generation = nextGeneration
        generations[key] = generation
        inFlight[key] = (window, before, batch, generation)
        glideStart[key] = before
        // A move this one took over had already moved the window: on failure, keep that earlier move undoable.
        func failed(_ reason: String) -> ApplyResult {
            if !Self.matches(before, now) {
                undo.push(before, for: window, key: key, batch: batch, placement: Self.placement(before))
            }
            return .failed(reason)
        }
        defer {
            if generations[key] == generation { generations[key] = nil; glideStart[key] = nil }
            if inFlight[key]?.generation == generation { inFlight[key] = nil }
        }
        if duration > 0, now != goal {
            // False when a newer move or Undo took over mid-flight; that one does the final write and records undo.
            guard await glide(window, from: now, to: goal, duration: duration, key: key, generation: generation) else {
                return .superseded
            }
        }

        // Some apps apply a frame a beat late: read it back, and write again (twice at most) until it holds.
        var readBack: CGRect?
        for attempt in 0..<3 {
            if let error = setFrame(goal, on: window, crossingDisplays: crossingDisplays) {
                return failed(Self.unmovableReason(of: element) ?? Self.reason(for: error))
            }
            readBack = AX.frame(element)
            guard let landed = readBack, !Self.matches(landed, goal), attempt < 2 else { break }
            // A full-screen window accepts the write and stays put: nothing moved, nothing to undo.
            if attempt == 0, let reason = Self.unmovableReason(of: element) { return failed(reason) }
            try? await Task.sleep(for: .milliseconds(40))
            guard generations[key] == generation else { return .superseded }
        }
        guard var actual = readBack else { return failed(Self.unreadableMessage) }

        // A size-constrained window is re-anchored to the targeted edges, bottom and right included.
        let anchored = WindowRecovery.anchoredOrigin(goal: goal, size: actual.size, display: Self.displayBounds(for: goal))
        if abs(actual.width - goal.width) > 1 || abs(actual.height - goal.height) > 1,
           anchored != actual.origin, AX.setPosition(element, anchored) == .success {
            actual.origin = anchored
        }
        // The app acknowledged the writes but the window never moved: nothing to undo.
        if Self.matches(actual, now), !Self.matches(now, goal),
           max(abs(actual.minX - anchored.x), abs(actual.minY - anchored.y)) > 2 {
            return failed(Self.refusedMessage)
        }

        undo.push(before, for: window, key: key, batch: batch, placement: Self.placement(before))
        let landed = CoordinateSpace.fromAX(actual, primaryHeight: primaryHeight)
        return Self.isConstrained(landed: actual.size, goal: goal.size) ? .constrained(landed) : .applied(landed)
    }

    /// A tag for moves that undo in one press (a Tile): pass it to `apply`, then `mergeMoves` when they are done.
    func newBatch() -> Int {
        let batch = undo.newBatch()
        openBatches.insert(batch)
        return batch
    }

    /// `mergeMoves`, also saying whether ⌃⌥Z took `batch` back before it finished (its caller should then report that,
    /// not a result). One call, so no Undo can slip in between the check and the merge.
    func finishBatch(_ batch: Int) -> (undoMarker: Int?, cancelled: Bool) {
        let cancelled = cancelledBatches.contains(batch)
        return (mergeMoves(batch), cancelled)
    }

    /// Joins the moves tagged `batch` into one undo step; moves made meanwhile by anything else stay their own steps.
    /// Returns `undoMarker()` when the next undo takes back exactly this batch, nil otherwise (`WindowUndoHistory.merge`).
    @discardableResult func mergeMoves(_ batch: Int) -> Int? {
        openBatches.remove(batch)
        cancelledBatches.remove(batch)
        return undo.merge(batch: batch)
    }

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
    /// screen), full-screen windows, panels and dialogs, and anything smaller than a tiny utility window. Front-most first.
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
                // A full-screen window has a Space of its own: tiling or a split must not pull it out.
                guard let id = SPI.windowID(of: element), let frame = frames[id],
                      (AX.value(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      AX.bool(element, "AXFullScreen") != true else { continue }
                result.append((WindowRef(element: element, pid: pid, windowID: id, bundleID: app.bundleIdentifier), frame))
            }
        }
        let sorted = result.sorted { depth[$0.window.windowID ?? 0, default: .max] < depth[$1.window.windowID ?? 0, default: .max] }
        return (sorted, skipped)
    }

    // MARK: - Private

    static func key(for window: WindowRef) -> UndoKey {
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
