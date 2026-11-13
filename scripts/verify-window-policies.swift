import AppKit
import TesseraCore

enum VerifyWindowPolicies {
    @MainActor static func run() async throws {
        let pid = NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular }?.processIdentifier
            ?? ProcessInfo.processInfo.processIdentifier
        let fixture = WorkspaceFixture(elementPID: pid), model = SettingsModel()
        model.settings.snapSeconds = 0
        model.settings.splitOnMinimise = .leaveSpace
        let context = WindowMutationContext(topology: fixture.topology, workspaces: fixture.spaces)
        let windows = WindowService(readFrame: fixture.read, writeFrame: fixture.write,
            visibleWindows: { frame, _, _, _ in fixture.visible(frame) },
            removalKind: { ref in fixture.state.withLock { $0.removed[ref.windowID!] } }, mutationContext: context)
        let displays = DisplayService(settings: { model.settings }, snapshotProvider: fixture.displays)
        let watchers = SplitWatchers(windows: windows, displays: displays, model: model)
        defer { watchers.stop() }
        let display = displays.displays[0], key = workspaceKey(display)
        let min = fixture.refs[0], closed = fixture.refs[1], survivor = fixture.refs[2]
        fixture.state.withLock { state in
            state.frames[min.windowID!] = CGRect(x: 0, y: 0, width: 400, height: 800)
            state.frames[closed.windowID!] = CGRect(x: 400, y: 0, width: 300, height: 800)
            state.frames[survivor.windowID!] = CGRect(x: 700, y: 0, width: 300, height: 800)
            state.visible[WorkspaceFixture.a]?[11] = [min.windowID!, closed.windowID!, survivor.windowID!]
        }
        let group = fixture.visible(display.frame)
        model.settings.learnedSplits = [LearnedSplit(key: SplitKey(display: display.id.storageKey, bundleIDs: [survivor.bundleID]),
            slots: [Slot(bundleID: survivor.bundleID!, rect: UnitRect(x: 0, y: 0, width: 1, height: 1))], updated: Date())]
        watchers.watch(group, display: display)
        fixture.state.withLock { state in
            state.visible[WorkspaceFixture.a]?[11] = [survivor.windowID!]
            state.removed[min.windowID!] = true; state.removed[closed.windowID!] = false
        }
        watchers.watchers[WorkspaceFixture.a]?.closed()
        try await wait(CGRect(x: 400, y: 0, width: 600, height: 800), ref: survivor, fixture: fixture)
        guard watchers.workspaceStore[key]?.reserved.contains(where: { $0.window == min }) == true else { throw Failure.reservationLost }
        print("PASS: A close fills its own vacancy without consuming a protected minimised window's space")
        fixture.state.withLock { $0.removed[min.windowID!] = false }
        watchers.applicationTerminated(min.pid)
        try await wait(CGRect(x: 0, y: 0, width: 1000, height: 800), ref: survivor, fixture: fixture)
        print("PASS: Quitting a previously reserved app releases its space even during another recovery")

        watchers.stop(); model.settings.learnedSplits = []
        fixture.state.withLock { state in
            state.frames[min.windowID!] = CGRect(x: 0, y: 0, width: 400, height: 800)
            state.frames[closed.windowID!] = CGRect(x: 400, y: 0, width: 300, height: 800)
            state.frames[survivor.windowID!] = CGRect(x: 700, y: 0, width: 300, height: 800)
            state.visible[WorkspaceFixture.a]?[11] = [min.windowID!, closed.windowID!, survivor.windowID!]
            state.removed = [:]; state.writes = []
        }
        watchers.watch(fixture.visible(display.frame), display: display)
        fixture.state.withLock { $0.visible[WorkspaceFixture.a]?[11] = [closed.windowID!, survivor.windowID!]; $0.removed[min.windowID!] = true }
        try await Task.sleep(for: .milliseconds(350))
        await watchers.arm(fixture.visible(display.frame), on: display)
        guard watchers.workspaceStore[key]?.reserved.contains(where: { $0.window == min }) == true else { throw Failure.reservationLost }
        fixture.state.withLock { $0.visible[WorkspaceFixture.a]?[11] = [min.windowID!, closed.windowID!, survivor.windowID!]; $0.removed[min.windowID!] = nil }
        watchers.restoredWindow(min)
        try await Task.sleep(for: .milliseconds(450))
        guard fixture.state.withLock({ $0.writes.isEmpty }) else { throw Failure.protectedRestoreRetiled }
        print("PASS: Restoring a leave-space window re-arms ownership without moving its neighbours")

        watchers.stop()
        fixture.state.withLock { state in
            state.frames[closed.windowID!] = CGRect(x: 600, y: 0, width: 400, height: 800)
            state.visible[WorkspaceFixture.a]?[11] = [min.windowID!, closed.windowID!]
        }
        watchers.watch(fixture.visible(display.frame), display: display)
        let b = displays.displays[1]
        watchers.watch(fixture.visible(b.frame), display: b)
        let old = context.capture(), goal = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let overrides = watchers.manualOverrides(closed, goal: goal, ticket: old)
        guard overrides == [WorkspaceFixture.a], let replacement = context.overridingLayouts(old, on: overrides) else { throw Failure.manualOverrideMissing }
        watchers.relinquish(overrides, windows: [closed])
        guard !context.isCurrent(old, on: [WorkspaceFixture.a]), context.isCurrent(old, on: [WorkspaceFixture.b]),
              context.isCurrent(replacement, on: [WorkspaceFixture.a]),
              watchers.workspaceStore[workspaceKey(b)] != nil, watchers.workspaceStore[key] == nil else { throw Failure.unrelatedOverride }
        _ = await WindowMutationScope.$ticket.withValue(replacement) {
            await windows.apply(goal, to: closed, primaryHeight: 800, crossingDisplays: false)
        }
        watchers.applicationTerminated(min.pid)
        try await Task.sleep(for: .milliseconds(450))
        guard fixture.read(closed) == goal else { throw Failure.manualMoveUndone }
        print("PASS: An explicit overlapping placement supersedes old ownership on its display only")

        watchers.stop()
        fixture.state.withLock { state in
            state.frames[min.windowID!] = CGRect(x: 0, y: 0, width: 600, height: 800)
            state.frames[closed.windowID!] = CGRect(x: 600, y: 0, width: 400, height: 800)
            state.visible[WorkspaceFixture.a]?[11] = [min.windowID!, closed.windowID!]
            state.removed = [:]; state.minimumWidths[closed.windowID!] = 1200
        }
        var partial = false
        watchers.onHelpEvent = { event in if case .tilePartial = event.kind { partial = true } }
        watchers.watch(fixture.visible(display.frame), display: display)
        fixture.state.withLock { $0.visible[WorkspaceFixture.a]?[11] = [closed.windowID!]; $0.removed[min.windowID!] = false }
        watchers.watchers[WorkspaceFixture.a]?.closed()
        for _ in 0..<100 { if partial { break }; try await Task.sleep(for: .milliseconds(40)) }
        guard partial else { throw Failure.constraintReportedSuccess }
        print("PASS: A constrained gap placement reports a partial result rather than claiming the gap was filled")
    }

    @MainActor private static func workspaceKey(_ display: DisplayContext) -> SplitWorkspaceStore.Key {
        .init(display: display.id.storageKey, space: display.id.storageKey == WorkspaceFixture.a ? 11 : 21)
    }
    private static func wait(_ expected: CGRect, ref: WindowRef, fixture: WorkspaceFixture) async throws {
        for _ in 0..<150 {
            if let actual = fixture.read(ref), WindowService.matches(actual, expected) { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw Failure.frameNotRecovered
    }
    private enum Failure: Error {
        case reservationLost, protectedRestoreRetiled, manualOverrideMissing, unrelatedOverride, manualMoveUndone
        case constraintReportedSuccess, frameNotRecovered
    }
}
