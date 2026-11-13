import AppKit
import os
import TesseraCore

enum VerifyWorkspaceTransactions {
    @MainActor static func run() async throws {
        let pid = NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular }?.processIdentifier
            ?? ProcessInfo.processInfo.processIdentifier
        let fixture = WorkspaceFixture(elementPID: pid), model = SettingsModel()
        model.settings.snapSeconds = 0
        let context = WindowMutationContext(topology: fixture.topology, workspaces: fixture.spaces)
        let windows = WindowService(readFrame: fixture.read, writeFrame: fixture.write,
            visibleWindows: { frame, _, _, _ in fixture.visible(frame) },
            removalKind: { ref in fixture.state.withLock { $0.removed[ref.windowID!] } }, mutationContext: context)
        let displays = DisplayService(settings: { model.settings }, snapshotProvider: fixture.displays)
        let watchers = SplitWatchers(windows: windows, displays: displays, model: model)
        defer { watchers.stop() }
        let display = displays.displays[0], key = SplitWorkspaceStore.Key(display: WorkspaceFixture.a, space: 11)
        let original = fixture.visible(display.frame), old = context.capture()
        watchers.watch(original, display: display)
        let revision = watchers.workspaceStore[key]!.revision
        fixture.state.withLock { $0.frames[520001]?.size.width = 550; $0.frames[520002]?.origin.x = 550 }
        watchers.watch(fixture.visible(display.frame), display: display)
        let newer = watchers.workspaceStore[key]!.revision
        watchers.fillSoon(original, displayKey: key.display, expectedRevision: revision)
        guard watchers.workspaceStore[key]?.revision == newer, watchers.pendingFills[key.display] == nil else { throw Failure.staleRecord }
        context.invalidateLayouts(on: [key.display])
        WindowMutationScope.$ticket.withValue(old) { watchers.fillSoon(original, displayKey: key.display) }
        guard watchers.workspaceStore[key]?.revision == newer, watchers.pendingFills[key.display] == nil else { throw Failure.staleRecord }
        print("PASS: Stale tickets and record revisions cannot replace a newer recovery baseline")

        let newcomerPID: pid_t = -901
        watchers.joinSoon(pid: newcomerPID, launched: false, windowCreated: true, createdWindowID: 91001)
        watchers.joinSoon(pid: newcomerPID, launched: false, windowCreated: true, createdWindowID: 91002)
        guard watchers.pendingNewWindows[newcomerPID] == [91001, 91002],
              watchers.firstWindowLooks.contains(newcomerPID) else { throw Failure.newcomerLost }
        watchers.joinSoon(pid: newcomerPID, launched: false)
        guard watchers.pendingNewWindows[newcomerPID] == [91001, 91002] else { throw Failure.newcomerLost }
        print("PASS: Rapid window creation retains every newcomer across replacement and activation looks")

        watchers.stop()
        fixture.state.withLock { state in
            state.frames[520001] = CGRect(x: 0, y: 0, width: 600, height: 800)
            state.frames[520002] = CGRect(x: 600, y: 0, width: 400, height: 800)
            state.visible[key.display]?[11] = [520001, 520002]
            state.removed = [:]; state.refuses = [520002]; state.writes = []
        }
        watchers.watch(fixture.visible(display.frame), display: display)
        fixture.state.withLock { $0.visible[key.display]?[11] = [520002]; $0.removed[520001] = false }
        watchers.watchers[key.display]?.closed()
        for _ in 0..<100 {
            if watchers.workspaceStore[key]?.retryAfter != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard let failed = watchers.workspaceStore[key], failed.recoveryPending,
              failed.recovery?.group.count == 2, failed.retryAfter != nil else { throw Failure.refusalForgotten }
        fixture.state.withLock { $0.refuses = [] }
        watchers.workspaceStore[key]?.retryAfter = .now - .seconds(1)
        watchers.retryPendingRecoveries()
        try await wait { fixture.read(fixture.refs[1]) == CGRect(x: 0, y: 0, width: 1000, height: 800) }
        guard watchers.workspaceStore[key]?.recoveryPending == false else { throw Failure.refusalForgotten }
        print("PASS: A refused placement retains its original vacancy and a bounded delayed retry recovers it")

        watchers.stop()
        fixture.state.withLock { state in
            state.frames[520001] = CGRect(x: 0, y: 0, width: 600, height: 800)
            state.frames[520002] = CGRect(x: 600, y: 0, width: 400, height: 800)
            state.visible[key.display]?[11] = [520001, 520002]; state.removed = [:]; state.writes = []
        }
        model.settings.snapSeconds = 0.5
        watchers.watch(fixture.visible(display.frame), display: display)
        fixture.state.withLock { $0.visible[key.display]?[11] = [520002]; $0.removed[520001] = false }
        watchers.watchers[key.display]?.closed()
        try await wait { fixture.state.withLock { !$0.writes.isEmpty } }
        model.settings.splitFillsClosedGap = false
        watchers.configurationChanged(model.settings)
        let writes = fixture.state.withLock { $0.writes.count }
        try await Task.sleep(for: .milliseconds(700))
        guard fixture.state.withLock({ $0.writes.count }) <= writes + 1,
              watchers.workspaceStore[key]?.recovery == nil else { throw Failure.policyCommitted }
        print("PASS: Disabling recovery during a glide stops subsequent writes and clears the stale candidate")

        watchers.stop(); model.settings.snapSeconds = 0; model.settings.splitFillsClosedGap = true
        fixture.state.withLock { state in
            state.frames[520003] = CGRect(x: 1000, y: 0, width: 300, height: 900)
            state.frames[520004] = CGRect(x: 1300, y: 0, width: 300, height: 900)
            state.visible[WorkspaceFixture.b]?[21] = [520003, 520004]; state.removed = [:]
        }
        let b = displays.displays[1]
        watchers.watch(fixture.visible(b.frame), display: b)
        fixture.state.withLock { $0.spaces?[WorkspaceFixture.b] = 22 }
        watchers.contextsChanged(spaceNotification: true)
        fixture.state.withLock { $0.visible[WorkspaceFixture.b]?[21] = [520004]; $0.spaces?[WorkspaceFixture.b] = 21 }
        watchers.contextsChanged(spaceNotification: true)
        try await wait { watchers.pendingFills[WorkspaceFixture.b] != nil }
        fixture.state.withLock { $0.removed[520003] = false }
        try await wait { fixture.read(fixture.refs[3]) == CGRect(x: 1000, y: 0, width: 600, height: 900) }
        print("PASS: Unresolved absence on a returning Space starts bounded recovery rather than abandoning ownership")

        let gesture = context.capture()
        context.invalidateLayouts(on: [key.display])
        guard let accepted = context.acceptingLayoutChange(gesture, on: [key.display]), context.isCurrent(accepted, on: [key.display]) else { throw Failure.columnChangeRejected }
        fixture.state.withLock { $0.spaces?[key.display] = 12 }
        guard context.acceptingLayoutChange(gesture, on: [key.display]) == nil else { throw Failure.columnChangedSpace }
        print("PASS: Ring column changes accept their layout version while retaining the original Space boundary")

        let cache = SplitWorkspaceStore(limit: 1)
        let keys = Set((1...3).map { SplitWorkspaceStore.Key(display: key.display, space: UInt64($0)) })
        for key in keys { cache.remember(original, at: key, topology: fixture.topology(), baselineAt: .now) }
        cache.prune(active: keys)
        guard cache.records.count == 3 else { throw Failure.activeEvicted }
        cache.prune(active: [keys.first!])
        guard cache.records.count == 1 else { throw Failure.inactiveRetained }
        print("PASS: Cache soft cap preserves every active workspace and evicts excess inactive records")
        try await verifyConvergence(fixture: fixture)
    }

    @MainActor private static func verifyConvergence(fixture: WorkspaceFixture) async throws {
        let ready = OSAllocatedUnfairLock(initialState: false), model = SettingsModel()
        let context = WindowMutationContext(topology: fixture.topology, workspaces: fixture.spaces)
        let displays = DisplayService(settings: { model.settings }, snapshotProvider: {
            var values = fixture.displays()
            if !ready.withLock({ $0 }) { values.removeLast() }
            return values
        })
        let watchers = SplitWatchers(windows: WindowService(mutationContext: context), displays: displays, model: model)
        defer { watchers.stop() }
        watchers.reconcileTopologyWhenReady()
        guard watchers.convergenceTask != nil else { throw Failure.convergenceMissing }
        ready.withLock { $0 = true }
        try await wait { displays.displays.count == 2 && watchers.convergenceTask == nil }
        print("PASS: Delayed AppKit display snapshots converge before workspace recovery is resumed")
    }
    @MainActor private static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 { if predicate() { return }; try await Task.sleep(for: .milliseconds(30)) }
        throw Failure.timedOut
    }
    private enum Failure: Error {
        case staleRecord, refusalForgotten, policyCommitted, columnChangeRejected, columnChangedSpace, newcomerLost
        case activeEvicted, inactiveRetained, convergenceMissing, timedOut
    }
}
