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
    static let changedMessage = "Display or Space changed; try again"

    /// Display topology and Space versions, shared with the producers that queue moves (see `WindowMutationScope`).
    nonisolated let mutationContext: WindowMutationContext
    /// The AX boundary. The defaults talk to the real windows; the native checks in `scripts/` inject fixtures.
    let readFrame: @Sendable (WindowRef) -> CGRect?
    let writeOverride: (@Sendable (CGRect, WindowRef, Bool) -> Bool)?
    let visibleOverride: (@Sendable (CGRect, CGFloat, Set<String>, [WindowRef]) -> [(window: WindowRef, frame: CGRect)])?
    let removalOverride: (@Sendable (WindowRef) -> Bool?)?
    private let fullscreen: @Sendable (WindowRef) -> Bool

    init(readFrame: @escaping @Sendable (WindowRef) -> CGRect? = { AX.frame($0.element) },
         writeFrame: (@Sendable (CGRect, WindowRef, Bool) -> Bool)? = nil,
         visibleWindows: (@Sendable (CGRect, CGFloat, Set<String>, [WindowRef]) -> [(window: WindowRef, frame: CGRect)])? = nil,
         removalKind: (@Sendable (WindowRef) -> Bool?)? = nil,
         mutationContext: WindowMutationContext = WindowMutationContext(),
         fullscreen: @escaping @Sendable (WindowRef) -> Bool = { AX.bool($0.element, "AXFullScreen") == true }) {
        self.readFrame = readFrame
        writeOverride = writeFrame
        visibleOverride = visibleWindows
        removalOverride = removalKind
        self.mutationContext = mutationContext
        self.fullscreen = fullscreen
    }

    var undo = WindowUndoHistory()
    /// Verified landings, so a close that arrives before a watch refreshes its baseline still knows where a window was.
    var placements: [UndoKey: (placement: WindowPlacementSnapshot, at: ContinuousClock.Instant)] = [:]
    /// The generation of each window's latest move, so a glide still running gives way to the newer
    /// move. Generations come from one monotonic counter, so a value never repeats after a reset.
    var generations: [UndoKey: Int] = [:]
    private var nextGeneration = 0
    /// Where each moving window started, so a move that takes over mid-glide (or mid re-check) records undo from
    /// the real starting frame, not from mid-air.
    var glideStart: [UndoKey: CGRect] = [:]
    /// Moves not yet recorded for undo (gliding, or waiting to re-check a write), so ⌃⌥Z can stop and reverse them.
    var inFlight: [UndoKey: (window: WindowRef, before: CGRect, placement: WindowPlacementSnapshot, batch: Int?,
                             generation: Int, order: Int)] = [:]
    /// Batches handed out and not yet merged, with the order they started in (see `WindowUndoHistory.Step.order`),
    /// and those of them Undo cancelled midway.
    var batchOrders: [Int: Int] = [:]
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
        // CG keeps the primary height readable off the main actor.
        let primaryHeight = (WindowMutationScope.ticket ?? mutationContext.capture()).topology.primaryHeight
        return readFrame(window).map { CoordinateSpace.fromAX($0, primaryHeight: primaryHeight) }
    }

    /// `duration` > 0 glides the window there first (time-based, so a slow app just gets fewer frames). The undo step
    /// is tagged `batch` (see `newBatch`). A display or Space change on the displays involved stops the move at the
    /// next write: the producer's ticket (`WindowMutationScope`) no longer matches.
    func apply(_ target: CGRect, to window: WindowRef, primaryHeight: CGFloat, crossingDisplays: Bool,
               duration: Double = 0, batch: Int? = nil) async -> ApplyResult {
        // Undo already took this batch back; its remaining moves must not land after it.
        if let batch, cancelledBatches.contains(batch) { return .superseded }
        guard !Task.isCancelled else { return .superseded }
        let ticket = WindowMutationScope.ticket ?? mutationContext.capture()
        guard mutationContext.isCurrent(ticket, on: [], refreshSpaces: true) else { return .failed(Self.changedMessage) }
        let element = window.element
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        guard let now = readFrame(window) else { return .failed(Self.unreadableMessage) }
        // A full-screen window accepts a write and stays put: refuse before writing, with nothing to undo.
        guard !fullscreen(window) else { return .failed(Self.fullScreenMessage) }

        let goal = CoordinateSpace.toAX(target, primaryHeight: primaryHeight)
        guard let destination = ticket.topology.key(containing: goal) else { return .failed(Self.changedMessage) }
        let displayKeys = Set([destination] + [ticket.topology.key(containing: now)].compactMap { $0 })
        let valid = { [mutationContext] in
            !Task.isCancelled && !(batch.map { self.cancelledBatches.contains($0) } ?? false)
                && mutationContext.isCurrent(ticket, on: displayKeys)
        }
        guard valid() else { return .failed(Self.changedMessage) }

        let key = Self.key(for: window)
        let before = glideStart[key] ?? now
        let placement = ticket.topology.placement(before)
        nextGeneration += 1
        let generation = nextGeneration
        generations[key] = generation
        // A Tile's moves all take the order of the Tile, so a move started after it undoes first.
        let order = batch.flatMap { batchOrders[$0] } ?? generation
        inFlight[key] = (window, before, placement, batch, generation, order)
        glideStart[key] = before
        // On failure, a window this move (or one it took over) already moved stays undoable.
        func failed(_ reason: String) -> ApplyResult {
            if let actual = readFrame(window), !Self.matches(actual, before) {
                undo.push(before, for: window, key: key, batch: batch, order: order, placement: placement)
            }
            return .failed(reason)
        }
        defer {
            if generations[key] == generation { generations[key] = nil; glideStart[key] = nil }
            if inFlight[key]?.generation == generation { inFlight[key] = nil }
        }
        if duration > 0, now != goal {
            // False when a newer move or Undo took over mid-flight; that one does the final write and records undo.
            guard await glide(window, from: now, to: goal, duration: duration, key: key, generation: generation,
                              valid: valid) else {
                return generations[key] == generation ? failed(Self.changedMessage) : .superseded
            }
        }

        // Some apps apply a frame a beat late: read it back, and write again (twice at most) until it holds.
        var readBack: CGRect?
        for attempt in 0..<3 {
            if let error = setFrame(goal, on: window, crossingDisplays: crossingDisplays, valid: valid) {
                guard valid() else { return failed(Self.changedMessage) }
                return failed(Self.unmovableReason(of: element) ?? Self.reason(for: error))
            }
            readBack = readFrame(window)
            guard let landed = readBack, !Self.matches(landed, goal), attempt < 2 else { break }
            if attempt == 0, writeOverride == nil, let reason = Self.unmovableReason(of: element) { return failed(reason) }
            try? await Task.sleep(for: .milliseconds(40))
            guard generations[key] == generation else { return .superseded }
            guard valid() else { return failed(Self.changedMessage) }
        }
        guard var actual = readBack else { return failed(Self.unreadableMessage) }

        // A size-constrained window is re-anchored to the targeted edges, bottom and right included.
        let bounds = ticket.topology.displays.first { $0.key == destination }?.bounds ?? Self.displayBounds(for: goal)
        let anchored = WindowRecovery.anchoredOrigin(goal: goal, size: actual.size, display: bounds)
        if abs(actual.width - goal.width) > 1 || abs(actual.height - goal.height) > 1, anchored != actual.origin,
           setFrame(CGRect(origin: anchored, size: actual.size), on: window, crossingDisplays: false, valid: valid,
                    positionOnly: true) == nil {
            actual = readFrame(window) ?? CGRect(origin: anchored, size: actual.size)
        }
        // The app acknowledged the writes but the window never moved: nothing to undo.
        if Self.matches(actual, now), !Self.matches(now, goal),
           max(abs(actual.minX - anchored.x), abs(actual.minY - anchored.y)) > 2 {
            return failed(Self.refusedMessage)
        }
        guard valid() else { return failed(Self.changedMessage) }

        rememberPlacement(actual, of: window)
        undo.push(before, for: window, key: key, batch: batch, order: order, placement: placement)
        let landed = CoordinateSpace.fromAX(actual, primaryHeight: primaryHeight)
        return Self.isConstrained(landed: actual.size, goal: goal.size) ? .constrained(landed) : .applied(landed)
    }

    /// A tag for moves that undo in one press (a Tile): pass it to `apply`, then `mergeMoves` when they are done.
    func newBatch() -> Int {
        let batch = undo.newBatch()
        nextGeneration += 1
        batchOrders[batch] = nextGeneration
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
        batchOrders[batch] = nil
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
