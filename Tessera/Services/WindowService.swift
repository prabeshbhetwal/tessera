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
    typealias UndoKey = WindowUndoHistory.Key

    static let timeout: Float = 0.3
    static let enhancedUI = "AXEnhancedUserInterface"
    static let frameInterval: Duration = .milliseconds(16)

    let readFrame: @Sendable (WindowRef) -> CGRect?
    nonisolated let mutationContext: WindowMutationContext
    private let fullscreen: @Sendable (WindowRef) -> Bool
    let writeOverride: (@Sendable (CGRect, WindowRef, Bool) -> Bool)?
    private let visibleOverride: (@Sendable (CGRect, CGFloat, Set<String>, [WindowRef]) -> [(window: WindowRef, frame: CGRect)])?
    let removalOverride: (@Sendable (WindowRef) -> Bool?)?

    init(readFrame: @escaping @Sendable (WindowRef) -> CGRect? = { AX.frame($0.element) },
         writeFrame: (@Sendable (CGRect, WindowRef, Bool) -> Bool)? = nil,
         visibleWindows: (@Sendable (CGRect, CGFloat, Set<String>, [WindowRef]) -> [(window: WindowRef, frame: CGRect)])? = nil,
         removalKind: (@Sendable (WindowRef) -> Bool?)? = nil,
         mutationContext: WindowMutationContext = WindowMutationContext(),
         fullscreen: @escaping @Sendable (WindowRef) -> Bool = { AX.bool($0.element, "AXFullScreen") == true }) {
        self.mutationContext = mutationContext
        self.fullscreen = fullscreen
        self.readFrame = readFrame
        self.writeOverride = writeFrame
        self.visibleOverride = visibleWindows
        self.removalOverride = removalKind
    }

    var placements: [UndoKey: (placement: WindowPlacementSnapshot, at: ContinuousClock.Instant)] = [:]
    var cancelledBatches: Set<Int> = []
    private var batchOrders: [Int: Int] = [:]
    var undo = WindowUndoHistory()
    /// The generation of each window's latest move, so a glide still running gives way to the newer
    /// move. Generations come from one monotonic counter, so a value never repeats after a reset.
    var generations: [UndoKey: Int] = [:]
    private var nextGeneration = 0
    /// Where each gliding window started, so a move that takes over mid-glide records undo from
    /// the real starting frame, not from mid-air.
    var glideStart: [UndoKey: CGRect] = [:]
    var inFlight: [UndoKey: (window: WindowRef, before: CGRect, placement: WindowPlacementSnapshot, batch: Int?, generation: Int, order: Int)] = [:]

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
        guard AX.value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              AX.bool(window, kAXMinimizedAttribute) != true else { return nil }
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
        let primaryHeight = (WindowMutationScope.ticket ?? mutationContext.capture()).topology.primaryHeight
        return readFrame(window).map { CoordinateSpace.fromAX($0, primaryHeight: primaryHeight) }
    }

    /// `duration` > 0 glides the window there first (time-based, so a slow app just gets fewer frames). The undo step
    /// is tagged `batch` (see `newBatch`).
    func apply(_ target: CGRect, to window: WindowRef, primaryHeight: CGFloat, crossingDisplays: Bool,
               duration: Double = 0, batch: Int? = nil) async -> ApplyResult {
        guard !Task.isCancelled else { return .failed("Move cancelled") }
        let ticket = WindowMutationScope.ticket ?? mutationContext.capture()
        guard mutationContext.isCurrent(ticket, on: [], refreshSpaces: true) else { return .failed("Display layout changed; try again") }
        let element = window.element
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        guard AX.bool(window.element, kAXMinimizedAttribute) != true else { return .failed("Restore the window before moving it") }
        guard !fullscreen(window) else { return .failed("Exit full screen before moving this window") }
        if let batch, cancelledBatches.contains(batch) { return .failed("Tile cancelled by Undo") }
        guard let now = readFrame(window) else { return .failed("Can't read the window's frame") }

        let goal = CoordinateSpace.toAX(target, primaryHeight: primaryHeight)
        guard let destination = ticket.topology.key(containing: goal) else { return .failed("The destination display is no longer available") }
        var displayKeys: Set<String> = [destination]
        if let source = ticket.topology.key(containing: now) { displayKeys.insert(source) }
        let valid = { [mutationContext] in !Task.isCancelled && mutationContext.isCurrent(ticket, on: displayKeys) }
        guard valid() else { return .failed("Workspace changed; try again") }
        let key = Self.key(for: window)
        let before = glideStart[key] ?? now
        let placement = ticket.topology.placement(before)
        nextGeneration += 1
        let generation = nextGeneration
        generations[key] = generation
        let order = batch.flatMap { batchOrders[$0] } ?? generation
        inFlight[key] = (window, before, placement, batch, generation, order)
        defer {
            if (Task.isCancelled || !valid()), generations[key] == generation,
               let actual = readFrame(window), !Self.matches(actual, before) {
                undo.push(before, for: window, key: key, batch: batch, order: order, placement: placement)
            }
            if generations[key] == generation { generations[key] = nil; glideStart[key] = nil }
            if inFlight[key]?.generation == generation { inFlight[key] = nil }
        }
        if duration > 0, now != goal {
            glideStart[key] = before
            guard await glide(window, from: now, to: goal, duration: duration, key: key, generation: generation, valid: valid) else {
                // A newer move of this window took over mid-flight; it does the final write and records undo.
                return .failed("Move cancelled by a newer command")
            }
        }
        glideStart[key] = nil
        guard !Task.isCancelled, generations[key] == generation, valid() else { return .failed("Move cancelled after a workspace or display change") }
        var observed: CGRect?
        for attempt in 0..<3 {
            guard !Task.isCancelled, generations[key] == generation,
                  mutationContext.isCurrent(ticket, on: displayKeys, refreshSpaces: true) else { return .failed("Move cancelled") }
            _ = setFrame(goal, on: window, crossingDisplays: crossingDisplays, valid: valid)
            observed = readFrame(window)
            if let observed, Self.matches(observed, goal) { break }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(40)) }
        }
        guard !Task.isCancelled, generations[key] == generation, valid() else { return .failed("Move cancelled") }
        guard var actual = observed else { return .failed("Can't read the window's frame") }
        if !Self.matches(actual, goal) {
            let bounds = ticket.topology.displays.first { $0.bounds.contains(CGPoint(x: goal.midX, y: goal.midY)) }?.bounds
                ?? Self.displayBounds(for: goal)
            let anchored = CGPoint(
                x: bounds.maxX - goal.maxX < goal.minX - bounds.minX
                    ? max(bounds.minX, goal.maxX - actual.width) : goal.minX,
                y: bounds.maxY - goal.maxY < goal.minY - bounds.minY
                    ? max(bounds.minY, goal.maxY - actual.height) : goal.minY)
            let accepted = writeOverride != nil
                ? setFrame(CGRect(origin: anchored, size: actual.size), on: window, crossingDisplays: false, valid: valid)
                : (valid() && AX.setPosition(element, anchored))
            if anchored != actual.origin, accepted, let verified = readFrame(window) {
                actual = verified
            }
        }
        guard !Self.matches(actual, now) || Self.matches(actual, goal) else {
            return .failed("The app didn't accept the requested placement")
        }
        rememberPlacement(actual, of: window)
        guard valid() else { return .failed("Workspace changed; try again") }
        undo.push(before, for: window, key: key, batch: batch, order: order, placement: placement)
        return .applied(CoordinateSpace.fromAX(actual, primaryHeight: primaryHeight))
    }

    /// A tag for moves that undo in one press (a Tile): pass it to `apply`, then `mergeMoves` when they are done.
    func newBatch() -> Int {
        let batch = undo.newBatch()
        nextGeneration += 1
        batchOrders[batch] = nextGeneration
        return batch
    }
    func isBatchCancelled(_ batch: Int) -> Bool { cancelledBatches.contains(batch) }
    func cancelPendingBatch(_ batch: Int) {
        if batchOrders[batch] != nil { cancelledBatches.insert(batch) }
    }

    /// Joins the moves tagged `batch` into one undo step; moves made meanwhile by anything else stay their own steps.
    /// Returns `undoMarker()` when the next undo takes back exactly this batch, nil otherwise (`WindowUndoHistory.merge`).
    @discardableResult func mergeMoves(_ batch: Int) -> Int? {
        defer { batchOrders[batch] = nil; cancelledBatches.remove(batch) }
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
    /// screen), panels and dialogs, and anything smaller than a tiny utility window. Front-most first.
    func visibleWindows(on display: CGRect, primaryHeight: CGFloat, excluding: Set<String>, retaining: [WindowRef] = [],
                        includingNewWindowsOf joiningPID: pid_t? = nil, existingWindowIDs: Set<CGWindowID> = []) -> [(window: WindowRef, frame: CGRect)] {
        if let visibleOverride { return visibleOverride(display, primaryHeight, excluding, retaining) }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var windowsByPID: [pid_t: Set<CGWindowID>] = [:]
        var depth: [CGWindowID: Int] = [:]  // the list runs front to back
        for (z, info) in list.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            // Mission Control transforms CG presentation bounds. Eligibility and placement use normal AX geometry.
            windowsByPID[pid, default: []].insert(id)
            depth[id] = z
        }

        var result: [(window: WindowRef, frame: CGRect)] = []
        for (pid, ids) in windowsByPID {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, !app.isHidden,
                  !excluding.contains(app.bundleIdentifier ?? "") else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Self.timeout)
            guard let windows = AX.value(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, Self.timeout)
                guard let id = SPI.windowID(of: element), ids.contains(id), AX.bool(element, kAXMinimizedAttribute) != true,
                      AX.bool(element, "AXFullScreen") != true,
                      (AX.value(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      let bounds = AX.frame(element), bounds.width >= 120, bounds.height >= 80 else { continue }
                let frame = CoordinateSpace.fromAX(bounds, primaryHeight: primaryHeight)
                guard display.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
                result.append((WindowRef(element: element, pid: pid, windowID: id, bundleID: app.bundleIdentifier), frame))
            }
        }
        let ordered = result.sorted { depth[$0.window.windowID ?? 0, default: .max] < depth[$1.window.windowID ?? 0, default: .max] }
        let exposed = Set(WindowVisibility.exposedIndices(ordered.map(\.frame)))
        return ordered.enumerated().filter { entry in
            exposed.contains(entry.offset) || retaining.contains(entry.element.window)
                || (entry.element.window.pid == joiningPID
                    && entry.element.window.windowID.map { !existingWindowIDs.contains($0) } == true)
        }.map(\.element)
    }

    // MARK: - Private

    static func key(for window: WindowRef) -> UndoKey {
        window.windowID.map { .window($0) } ?? .element(Int(bitPattern: CFHash(window.element)))
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
}
