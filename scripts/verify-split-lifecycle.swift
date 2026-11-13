import AppKit
import os
import TesseraCore

private typealias Group = [(window: WindowRef, frame: CGRect)]

private final class LifecycleFixture: Sendable {
    struct State {
        var frames: [CGWindowID: CGRect]
        var visible: [WindowRef]
        var gateRemoval = false
        var removalStarted = false
        var removed: [CGWindowID: Bool] = [:]
        var gateVisible = false
        var visibleStarted = false
    }
    let state: OSAllocatedUnfairLock<State>
    let primaryHeight: CGFloat
    let resumeRemoval = DispatchSemaphore(value: 0)
    let resumeVisible = DispatchSemaphore(value: 0)
    init(_ group: Group, primaryHeight: CGFloat) {
        self.primaryHeight = primaryHeight
        state = OSAllocatedUnfairLock(initialState: State(
            frames: Dictionary(uniqueKeysWithValues: group.map {
                ($0.window.windowID!, CoordinateSpace.toAX($0.frame, primaryHeight: primaryHeight))
            }), visible: group.map(\.window)))
    }
    func read(_ window: WindowRef) -> CGRect? { state.withLock { $0.frames[window.windowID!] } }
    func write(_ goal: CGRect, _ window: WindowRef, _ crossing: Bool) -> Bool {
        state.withLock { $0.frames[window.windowID!] = goal }
        return true
    }
    func visible() -> Group {
        state.withLock { state in state.visible.reversed().compactMap { window in
            state.frames[window.windowID!].map {
                (window, CoordinateSpace.fromAX($0, primaryHeight: primaryHeight))
            }
        } }
    }
    func queryVisible() -> Group {
        let snapshot = visible()
        let gated = state.withLock { state in
            guard state.gateVisible else { return false }
            state.gateVisible = false
            state.visibleStarted = true
            return true
        }
        if gated { _ = resumeVisible.wait(timeout: .now() + 3) }
        return snapshot
    }
    func removal(_ window: WindowRef) -> Bool? {
        let gated = state.withLock { state in
            guard state.gateRemoval else { return false }
            state.gateRemoval = false
            state.removalStarted = true
            return true
        }
        guard gated else { return state.withLock { $0.removed[window.windowID!] } }
        _ = resumeRemoval.wait(timeout: .now() + 3)
        return false
    }
}

enum VerifySplitLifecycle {
    @MainActor static func run() async throws {
        let model = SettingsModel()
        model.settings.snapSeconds = 0
        let display = DisplayContext(
            id: DisplayID(vendor: 91, model: 92, serial: 93, uuid: nil),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 1000),
            range: ColumnRange(minCols: 2, maxCols: 6, defaultCols: 3, maxRows: 2, isPortrait: false),
            profile: DisplayProfile(columns: 3, gap: 0, padding: 0))
        let bundleIDs = ["test.dia", "test.chat", "test.claude"]
        let refs: [WindowRef] = (0..<3).map { index in
            let pid: pid_t = index == 2 ? ProcessInfo.processInfo.processIdentifier : 0
            return WindowRef(element: AXUIElementCreateApplication(pid), pid: pid,
                             windowID: CGWindowID(123470 + index), bundleID: bundleIDs[index])
        }
        let group: Group = [(refs[0], CGRect(x: 0, y: 0, width: 1796, height: 1000)),
                            (refs[1], CGRect(x: 1796, y: 0, width: 1101, height: 1000)),
                            (refs[2], CGRect(x: 2897, y: 0, width: 943, height: 1000))]
        let fixture = LifecycleFixture(group, primaryHeight: 1000)
        let context = WindowMutationContext(topology: {
            WindowTopology(primary: 1, displays: [.init(number: 1, key: display.id.storageKey, bounds: display.frame)])
        }, workspaces: { [display.id.storageKey: 1] })
        let windows = WindowService(readFrame: fixture.read, writeFrame: fixture.write,
                                    visibleWindows: { _, _, _, _ in fixture.queryVisible() }, removalKind: fixture.removal,
                                    mutationContext: context)
        let displays = DisplayService(settings: { model.settings }, displays: [display])
        let watchers = SplitWatchers(windows: windows, displays: displays, model: model)
        let key = SplitKey(display: display.id.storageKey, bundleIDs: [refs[0].bundleID, refs[1].bundleID])
        let saved = LearnedSplit(key: key, slots: [
            Slot(bundleID: "test.dia", rect: UnitRect(x: 0, y: 0, width: 2284.0 / 3840, height: 1)),
            Slot(bundleID: "test.chat", rect: UnitRect(x: 2284.0 / 3840, y: 0, width: 1556.0 / 3840, height: 1))
        ], updated: Date(timeIntervalSinceReferenceDate: 123))
        model.settings.learnedSplits = [saved]
        watchers.watch(group, display: display)
        try await Task.sleep(for: .milliseconds(350))
        fixture.state.withLock { $0.visible = Array(refs.prefix(2)) }
        for _ in 0..<4 { await watchers.arm(fixture.visible(), on: display) }
        guard watchers.watchers[display.id.storageKey]?.watched.contains(refs[2]) == true else {
            throw Failure.membershipLostBeforeTermination
        }
        print("PASS: Unknown disappearance preserves membership after fast retries exhaust")
        fixture.state.withLock { $0.removed[refs[2].windowID!] = false }
        watchers.applicationTerminated(refs[2].pid)
        let expected = CGRect(x: 0, y: 0, width: 2284, height: 1000)
        for _ in 0..<40 {
            if fixture.visible().contains(where: { $0.window == refs[0] && $0.frame == expected }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        defer { watchers.stop() }
        guard fixture.visible().contains(where: { $0.window == refs[0] && $0.frame == expected }),
              fixture.visible().contains(where: { $0.window == refs[1] && WindowService.matches($0.frame, CGRect(x: 2284, y: 0, width: 1556, height: 1000)) }),
              model.settings.learnedSplits == [saved] else { throw Failure.pairNotRecovered }
        print("PASS: Late app termination restores the remembered pair in inverted MRU order")

        let pair = fixture.visible()
        watchers.cancelPendingWork()
        watchers.closedOutOf["test.claude"] = nil
        watchers.watch(group, display: display)
        watchers.watchers[display.id.storageKey]?.closed()  // AX destruction arrives before Workspace termination
        watchers.applicationTerminated(refs[2].pid)
        guard watchers.closedOutOf["test.claude"]?[display.id.storageKey] == Array(refs.prefix(2)) else {
            throw Failure.earlyTerminationContextLost
        }
        print("PASS: AX destruction before Workspace termination preserves immediate-reopen context")

        watchers.watch(pair, display: display)
        let child = watchers.watchers[display.id.storageKey]!
        child.handle(kAXUIElementDestroyedNotification, element: refs[2].element)
        guard child.watches(pair) else { throw Failure.staleCallbackClosedNewGroup }
        print("PASS: A queued callback for the old Claude window cannot close the replacement pair")

        watchers.cancelPendingWork()
        watchers.watch(group, display: display)
        fixture.state.withLock { $0.gateRemoval = true }
        let staleRead = Task { await watchers.arm(pair, on: display) }
        for _ in 0..<100 {
            if fixture.state.withLock({ $0.removalStarted }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fixture.state.withLock { $0.removalStarted }, "The controlled AX read never began")
        watchers.watch(pair, display: display)
        fixture.resumeRemoval.signal()
        await staleRead.value
        guard child.watches(pair) else { throw Failure.staleReadClosedNewGroup }
        print("PASS: A stale re-arm result cannot close a newer watch")

        watchers.watch(group, display: display)
        fixture.state.withLock { $0.gateVisible = true }
        let staleList = Task { await watchers.readAndArm(display) }
        for _ in 0..<100 {
            if fixture.state.withLock({ $0.visibleStarted }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fixture.state.withLock { $0.visibleStarted }, "The controlled window-list read never began")
        watchers.watch(pair, display: display)
        fixture.resumeVisible.signal()
        await staleList.value
        guard child.watches(pair) else { throw Failure.staleListReplacedNewGroup }
        print("PASS: A window-list snapshot captured before a newer watch cannot replace it")

        func reset(_ visible: [WindowRef]) {
            watchers.cancelPendingWork()
            fixture.state.withLock { state in
                state.frames = Dictionary(uniqueKeysWithValues: group.map {
                    ($0.window.windowID!, CoordinateSpace.toAX($0.frame, primaryHeight: fixture.primaryHeight))
                })
                state.visible = visible
                state.visibleStarted = false
                state.removed[refs[2].windowID!] = false
            }
            watchers.watch(group, display: display)
        }
        func pairRecovered() -> Bool {
            let visible = fixture.visible()
            return visible.contains { $0.window == refs[0] && WindowService.matches($0.frame, expected) }
                && visible.contains { $0.window == refs[1] && WindowService.matches($0.frame, CGRect(x: 2284, y: 0, width: 1556, height: 1000)) }
        }
        reset(refs)
        watchers.applicationTerminated(refs[2].pid)
        try await Task.sleep(for: .milliseconds(1150))  // beyond the old three-look 900 ms limit
        fixture.state.withLock { $0.visible = Array(refs.prefix(2)) }
        for _ in 0..<80 {
            if pairRecovered() { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard pairRecovered() else { throw Failure.delayedDisappearanceLost }
        print("PASS: Window-list disappearance after the old retry limit still restores the saved pair")

        reset([])
        watchers.applicationTerminated(refs[2].pid)
        try await Task.sleep(for: .milliseconds(400))
        fixture.state.withLock { $0.visible = Array(refs.prefix(2)) }
        for _ in 0..<80 {
            if pairRecovered() { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard pairRecovered() else { throw Failure.transientReadLost }
        print("PASS: A transient empty survivor query retries rather than discarding recovery")

        reset([refs[0]])
        watchers.applicationTerminated(refs[2].pid)
        try await Task.sleep(for: .milliseconds(400))
        guard fixture.visible().first?.frame == group[0].frame else { throw Failure.unconfirmedMemberFilled }
        fixture.state.withLock { $0.visible = Array(refs.prefix(2)) }
        for _ in 0..<80 {
            if pairRecovered() { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard pairRecovered() else { throw Failure.transientReadLost }
        print("PASS: One confirmed quit cannot consume another temporarily unavailable member's space")

        reset(Array(refs.prefix(2)))
        fixture.state.withLock { $0.gateVisible = true }
        watchers.applicationTerminated(refs[2].pid)
        for _ in 0..<100 {
            if fixture.state.withLock({ $0.visibleStarted }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fixture.state.withLock { $0.visibleStarted }, "The recovery read never began")
        model.settings.splitFillsClosedGap = false
        fixture.resumeVisible.signal()
        try await Task.sleep(for: .milliseconds(650))
        guard !pairRecovered() else { throw Failure.staleSettingsMoved }
        model.settings.splitFillsClosedGap = true
        print("PASS: Disabling recovery during an AX read prevents stale-policy writes")

        model.settings.splitOnCloseKeepsRunning = .leaveSpace
        reset(Array(refs.prefix(2)))
        fixture.state.withLock { $0.gateVisible = true }
        watchers.applicationTerminated(refs[2].pid)
        for _ in 0..<100 {
            if fixture.state.withLock({ $0.visibleStarted }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fixture.state.withLock { $0.visibleStarted }, "The close-policy read never began")
        model.settings.splitOnCloseKeepsRunning = .retile
        fixture.resumeVisible.signal()
        for _ in 0..<80 {
            if pairRecovered() { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard pairRecovered() else { throw Failure.staleClosePolicySkipped }
        print("PASS: Enabling close recovery during an AX read re-plans before the old leave-space exit")

        reset(Array(refs.prefix(2)))
        watchers.watchers[display.id.storageKey]?.stop()
        fixture.state.withLock { $0.removed[refs[2].windowID!] = true }
        watchers.fillSoon(group, displayKey: display.id.storageKey, minimised: true)
        try await Task.sleep(for: .milliseconds(100))
        model.settings.splitOnMinimise = .leaveSpace
        try await Task.sleep(for: .milliseconds(450))
        guard !pairRecovered() else { throw Failure.disabledMinimiseMoved }
        model.settings.splitOnMinimise = .retile
        print("PASS: Disabling minimise filling before the queued look prevents recovery writes")

        reset(Array(refs.prefix(2)))
        watchers.applicationTerminated(refs[2].pid)
        try await Task.sleep(for: .milliseconds(100))
        watchers.cancelPendingWork()
        try await Task.sleep(for: .milliseconds(450))
        guard !pairRecovered(), watchers.ownMoves == 0, model.settings.learnedSplits == [saved] else {
            throw Failure.cancelledRecoveryMoved
        }
        print("PASS: Undo-style cancellation prevents queued recovery writes")

        reset(Array(refs.prefix(2)))
        model.settings.excludedBundleIDs = ["test.claude"]
        try await Task.sleep(for: .milliseconds(350))
        await watchers.arm(fixture.visible(), on: display)
        guard child.watches(fixture.visible()) else { throw Failure.exclusionRetainedOldMember }
        watchers.applicationTerminated(refs[2].pid)
        try await Task.sleep(for: .milliseconds(400))
        guard !pairRecovered() else { throw Failure.excludedQuitMoved }
        print("PASS: Excluding an old member retires it without a later quit moving the remaining group")
    }

    private enum Failure: Error {
        case membershipLostBeforeTermination, pairNotRecovered, staleCallbackClosedNewGroup, staleReadClosedNewGroup
        case delayedDisappearanceLost, transientReadLost, cancelledRecoveryMoved
        case staleListReplacedNewGroup, unconfirmedMemberFilled
        case staleSettingsMoved
        case staleClosePolicySkipped, disabledMinimiseMoved
        case earlyTerminationContextLost
        case exclusionRetainedOldMember, excludedQuitMoved
    }
}
