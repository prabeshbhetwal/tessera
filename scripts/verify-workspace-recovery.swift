import AppKit
import os
import TesseraCore

final class WorkspaceFixture: Sendable {
    static let a = "201-1-1", b = "202-1-2"
    struct State {
        var spaces: [String: UInt64]? = [a: 11, b: 21]
        var frames: [CGWindowID: CGRect] = [:]
        var visible: [String: [UInt64: [CGWindowID]]] = [:]
        var removed: [CGWindowID: Bool] = [:]
        var writes: [CGWindowID] = []
        var oldStartupQueries = 0
        var minimumWidths: [CGWindowID: CGFloat] = [:]
        var refuses: Set<CGWindowID> = []
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    let refs: [WindowRef]
    init(elementPID: pid_t) {
        refs = (0..<4).map { index in
            WindowRef(element: AXUIElementCreateApplication(elementPID), pid: pid_t(-201 - index),
                      windowID: CGWindowID(520001 + index), bundleID: "test.workspace.\(index)")
        }
        state.withLock { state in
            state.frames = [520001: CGRect(x: 0, y: 0, width: 600, height: 800),
                            520002: CGRect(x: 600, y: 0, width: 400, height: 800),
                            520003: CGRect(x: 1000, y: 0, width: 300, height: 900),
                            520004: CGRect(x: 1300, y: 0, width: 300, height: 900)]
            state.visible = [Self.a: [11: [520001, 520002], 12: []], Self.b: [21: [520003, 520004], 22: []]]
        }
    }
    func topology() -> WindowTopology {
        WindowTopology(primary: 1, displays: [
            .init(number: 1, key: Self.a, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            .init(number: 2, key: Self.b, bounds: CGRect(x: 1000, y: 0, width: 600, height: 900))])
    }
    func spaces() -> [String: UInt64]? { state.withLock { $0.spaces } }
    func read(_ window: WindowRef) -> CGRect? { state.withLock { $0.frames[window.windowID!] } }
    func write(_ frame: CGRect, _ window: WindowRef, _ crossing: Bool) -> Bool {
        return state.withLock { state in
            guard !state.refuses.contains(window.windowID!) else { return false }
            var actual = frame
            actual.size.width = max(frame.width, state.minimumWidths[window.windowID!, default: 0])
            state.frames[window.windowID!] = actual
            state.writes.append(window.windowID!)
            return true
        }
    }
    func visible(_ display: CGRect) -> ManagedWindowGroup {
        let key = display.midX < 1000 ? Self.a : Self.b
        return state.withLock { state in
            if key == Self.a, WindowMutationScope.ticket?.workspaces[key] == 11 { state.oldStartupQueries += 1 }
            let ids = state.spaces?[key].flatMap { state.visible[key]?[$0] } ?? []
            return ids.compactMap { id in
                guard let ref = refs.first(where: { $0.windowID == id }), let frame = state.frames[id] else { return nil }
                return (ref, CoordinateSpace.fromAX(frame, primaryHeight: 800))
            }
        }
    }
    func displays() -> [DisplayContext] {
        topology().displays.enumerated().map { index, screen in
            DisplayContext(id: DisplayID(vendor: index == 0 ? 201 : 202, model: 1, serial: UInt32(index + 1), uuid: nil),
                visibleFrame: CoordinateSpace.fromAX(screen.bounds, primaryHeight: 800),
                range: ColumnRange(minCols: 2, maxCols: 2, defaultCols: 2, maxRows: 2, isPortrait: false),
                profile: DisplayProfile(columns: 2, gap: 0, padding: 0))
        }
    }
}

enum VerifyWorkspaceRecovery {
    @MainActor static func run() async throws {
        let pid = NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular }?.processIdentifier
            ?? ProcessInfo.processInfo.processIdentifier
        let fixture = WorkspaceFixture(elementPID: pid)
        let model = SettingsModel(); model.settings.snapSeconds = 0
        let context = WindowMutationContext(topology: fixture.topology, workspaces: fixture.spaces)
        let service = WindowService(readFrame: fixture.read, writeFrame: fixture.write,
            visibleWindows: { frame, _, _, _ in fixture.visible(frame) },
            removalKind: { ref in fixture.state.withLock { $0.removed[ref.windowID!] } }, mutationContext: context)
        let displays = DisplayService(settings: { model.settings }, snapshotProvider: fixture.displays)
        let watchers = SplitWatchers(windows: service, displays: displays, model: model)
        defer { watchers.stop() }
        let a = displays.displays[0], b = displays.displays[1]
        let groupA = fixture.visible(a.frame), groupB = fixture.visible(b.frame)
        watchers.watch(groupA, display: a); watchers.watch(groupB, display: b)
        fixture.state.withLock { $0.visible[WorkspaceFixture.a]?[11] = [520002]; $0.removed[520001] = false }
        watchers.watchers[WorkspaceFixture.a]?.closed()
        let primaryFill = watchers.fillIDs[WorkspaceFixture.a]
        fixture.state.withLock { $0.spaces?[WorkspaceFixture.b] = 22 }
        watchers.contextsChanged(spaceNotification: true)
        guard primaryFill != nil, watchers.fillIDs[WorkspaceFixture.a] == primaryFill else { throw Failure.primaryRecoveryCancelled }
        try await waitFrame(CGRect(x: 0, y: 0, width: 1000, height: 800), of: fixture.refs[1], fixture: fixture)
        print("PASS: A secondary Space transition preserves an unrelated display's pending close recovery")

        fixture.state.withLock { $0.visible[WorkspaceFixture.b]?[21] = [520004]; $0.removed[520003] = false }
        watchers.applicationTerminated(fixture.refs[2].pid)
        try await Task.sleep(for: .milliseconds(150))
        guard !fixture.state.withLock({ $0.writes.contains(520004) }),
              watchers.closedOutOf[fixture.refs[2].bundleID!]?[WorkspaceFixture.b] == nil else { throw Failure.inactiveWorkspaceMoved }
        fixture.state.withLock { $0.spaces?[WorkspaceFixture.b] = 21 }
        watchers.contextsChanged(spaceNotification: true)
        try await waitFrame(CGRect(x: 1000, y: 0, width: 600, height: 900), of: fixture.refs[3], fixture: fixture)
        print("PASS: An app quitting in a suspended workspace fills its gap only when that workspace returns")

        watchers.cancelPendingWork()
        fixture.state.withLock { state in
            state.frames[520004] = CGRect(x: 1300, y: 0, width: 300, height: 900)
            state.frames[520003] = CGRect(x: 1000, y: 0, width: 300, height: 900)
            state.visible[WorkspaceFixture.b]?[21] = [520003, 520004]
            state.removed[520003] = nil
        }
        watchers.watch(fixture.visible(b.frame), display: b)
        fixture.state.withLock { $0.visible[WorkspaceFixture.b]?[21] = [520004]; $0.removed[520003] = false }
        watchers.watchers[WorkspaceFixture.b]?.closed()
        fixture.state.withLock { $0.spaces?[WorkspaceFixture.b] = 22 }
        watchers.contextsChanged(spaceNotification: true)
        try await Task.sleep(for: .milliseconds(450))
        guard fixture.read(fixture.refs[3]) == CGRect(x: 1300, y: 0, width: 300, height: 900) else { throw Failure.inactiveWorkspaceMoved }
        fixture.state.withLock { $0.spaces?[WorkspaceFixture.b] = 21 }
        watchers.contextsChanged(spaceNotification: true)
        try await waitFrame(CGRect(x: 1000, y: 0, width: 600, height: 900), of: fixture.refs[3], fixture: fixture)
        print("PASS: A close immediately followed by a Space change resumes its cancelled recovery on return")

        fixture.state.withLock { $0.spaces = nil }
        watchers.contextsChanged(spaceNotification: true)
        watchers.watch(groupA, display: a)
        watchers.contextsChanged(spaceNotification: true)
        guard watchers.workspaceStore.records.keys.allSatisfy({ $0.space != nil }) else { throw Failure.unknownWorkspaceRetained }
        print("PASS: Unknown workspace identities discard unsafe suspended ownership")

        try await verifyStartup(pid: pid)
        verifyCache(group: groupA, topology: fixture.topology())
    }

    @MainActor private static func verifyStartup(pid: pid_t) async throws {
        let fixture = WorkspaceFixture(elementPID: pid), model = SettingsModel()
        model.settings.snapSeconds = 0
        let context = WindowMutationContext(topology: fixture.topology, workspaces: fixture.spaces)
        let service = WindowService(readFrame: fixture.read, writeFrame: fixture.write,
            visibleWindows: { frame, _, _, _ in fixture.visible(frame) }, mutationContext: context)
        let displays = DisplayService(settings: { model.settings }, snapshotProvider: fixture.displays)
        let watchers = SplitWatchers(windows: service, displays: displays, model: model)
        defer { watchers.stop() }
        let display = displays.displays[0]
        model.settings.learnedSplits = [LearnedSplit(key: SplitKey(fixture.visible(display.frame), on: display), slots: [
            Slot(bundleID: fixture.refs[0].bundleID!, rect: UnitRect(x: 0, y: 0, width: 0.5, height: 1)),
            Slot(bundleID: fixture.refs[1].bundleID!, rect: UnitRect(x: 0.5, y: 0, width: 0.5, height: 1))], updated: Date())]
        fixture.state.withLock { state in
            state.frames[520001] = CGRect(x: 0, y: 0, width: 700, height: 800)
            state.frames[520002] = CGRect(x: 400, y: 0, width: 600, height: 800)
            state.visible[WorkspaceFixture.a]?[12] = [520001, 520002]
            state.oldStartupQueries = 0
        }
        watchers.scheduleRestoration()
        let restoration = watchers.startupRestore
        try await Task.sleep(for: .milliseconds(80))
        fixture.state.withLock { $0.spaces?[WorkspaceFixture.a] = 12 }
        watchers.contextsChanged(spaceNotification: true)
        await restoration?.value
        guard fixture.state.withLock({ $0.writes.isEmpty && $0.oldStartupQueries == 0 }) else { throw Failure.startupCrossedWorkspace }
        print("PASS: Startup restoration cannot query or resize a later workspace after its initial delay")
    }

    @MainActor private static func verifyCache(group: ManagedWindowGroup, topology: WindowTopology) {
        let cache = SplitWorkspaceStore(limit: 2, lifetime: 60), now = Date()
        let one = SplitWorkspaceStore.Key(display: WorkspaceFixture.a, space: 1)
        let two = SplitWorkspaceStore.Key(display: WorkspaceFixture.a, space: 2)
        let active = SplitWorkspaceStore.Key(display: WorkspaceFixture.b, space: 3)
        for (index, key) in [one, two, active].enumerated() {
            cache.remember(group, at: key, topology: topology, baselineAt: .now,
                           now: now.addingTimeInterval(Double(index)))
        }
        cache[one]?.closedOutOf = ["test.closed": group.map(\.window)]
        precondition(cache.closedContexts(active: [two]).isEmpty)
        cache.prune(active: [active], now: now.addingTimeInterval(3))
        precondition(cache.records.count == 2 && cache[one] == nil && cache[active] != nil)
        cache.prune(active: [active], now: now.addingTimeInterval(100))
        precondition(cache.records.count == 1 && cache[active] != nil)
        print("PASS: Workspace recovery cache isolates origin contexts and bounds inactive retention")
    }

    @MainActor private static func waitFrame(_ frame: CGRect, of ref: WindowRef, fixture: WorkspaceFixture) async throws {
        for _ in 0..<100 {
            if let actual = fixture.read(ref), WindowService.matches(actual, frame) { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw Failure.frameNotRecovered
    }
    private enum Failure: Error {
        case primaryRecoveryCancelled, inactiveWorkspaceMoved, unknownWorkspaceRetained, startupCrossedWorkspace, frameNotRecovered
    }
}
