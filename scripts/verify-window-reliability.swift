import AppKit
import os
import TesseraCore

private final class WindowFixture: Sendable {
    struct State { var frame = CGRect(x: 0,y: 0,width: 1000,height: 1000); var acceptsWrites = true; var minimumHeight: CGFloat = 0 }
    let state = OSAllocatedUnfairLock(initialState: State())
    func read(_ window: WindowRef) -> CGRect? { state.withLock { $0.frame } }
    func write(_ goal: CGRect, _ window: WindowRef, _ crossing: Bool) -> Bool {
        state.withLock { s in
            guard s.acceptsWrites else { return false }
            s.frame = CGRect(origin: goal.origin, size: CGSize(width: goal.width, height: max(goal.height, s.minimumHeight)))
            return true
        }
    }
}

private enum ReliabilityFailure: Error { case partialBatchUndo, commandOrder, cancelledMove }

@main private struct VerifyWindowReliability {
    @MainActor static func main() async {
        do { try await verify() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
    @MainActor private static func verify() async throws {
        func context() -> WindowMutationContext {
            WindowMutationContext(topology: {
                WindowTopology(primary: 1, displays: [.init(number: 1, key: "fixture-main", bounds: CGRect(x: 0, y: 0, width: 4000, height: 1000))])
            }, workspaces: { ["fixture-main": 1] })
        }
        let fixture = WindowFixture()
        let app = NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular } ?? NSRunningApplication.current
        // Only identity/validity is read from AX. Every frame read/write goes to the isolated fixture.
        let window = WindowRef(element: AXUIElementCreateApplication(app.processIdentifier), pid: app.processIdentifier,
                               windowID: 123456, bundleID: app.bundleIdentifier)
        let service = WindowService(readFrame: fixture.read, writeFrame: fixture.write, mutationContext: context())
        let before = CGRect(x: 0,y: 0,width: 1000,height: 1000)
        let target = CGRect(x: 500,y: 0,width: 500,height: 1000)
        let moving = Task { await service.apply(target, to: window, primaryHeight: 1000, crossingDisplays: false, duration: 0.45) }
        try await Task.sleep(for: .milliseconds(50))
        let baselineBeforeUndo = ContinuousClock.now
        let cancelled = await service.undoLast()
        precondition(cancelled, "Undo failed to cancel a pending move")
        _ = await moving.value
        precondition(fixture.read(window) == before, "A cancelled glide overwrote Undo")
        print("PASS: Undo cancels the first animated move")
        let refreshed = await service.placement(of: window, after: baselineBeforeUndo, primaryHeight: 1000)
        precondition(refreshed == before, "Lifecycle recovery could not see Undo-restored geometry")
        let laterBaseline = ContinuousClock.now
        let stale = await service.placement(of: window, after: laterBaseline, primaryHeight: 1000)
        precondition(stale == nil, "An older write replaced a newer observed layout")
        print("PASS: Lifecycle recovery uses newer writes without replacing newer hand layouts")

        _ = await service.apply(target, to: window, primaryHeight: 1000, crossingDisplays: false)
        fixture.state.withLock { $0.acceptsWrites = false }
        let refused = await service.undoLast()
        precondition(!refused, "Refused writes reported as restored")
        fixture.state.withLock { $0.acceptsWrites = true }
        let retried = await service.undoLast()
        precondition(retried, "Transient failure destroyed Undo history")
        precondition(fixture.read(window) == before)
        print("PASS: Failed Undo remains retryable")

        fixture.state.withLock { $0.minimumHeight = 700 }
        let height: CGFloat = 1000
        _ = await service.apply(CGRect(x: 0,y: 0,width: 500,height: 500), to: window,
                                primaryHeight: height, crossingDisplays: false)
        precondition(fixture.read(window)?.maxY == height, "Constrained bottom window lost its bottom edge")
        print("PASS: Constrained bottom placement preserves the bottom edge")

        let fast = WindowFixture(), slow = WindowFixture()
        slow.state.withLock { $0.minimumHeight = 700 }
        let second = WindowRef(element: window.element, pid: window.pid, windowID: 123457, bundleID: window.bundleID)
        let batchService = WindowService(readFrame: { $0.windowID == window.windowID ? fast.read($0) : slow.read($0) },
                                        writeFrame: { goal, ref, cross in
            ref.windowID == window.windowID ? fast.write(goal,ref,cross) : slow.write(goal,ref,cross)
        }, mutationContext: context())
        let batch = await batchService.newBatch()
        _ = await batchService.apply(target, to: window, primaryHeight: 1000, crossingDisplays: false, batch: batch)
        let remaining = Task { await batchService.apply(CGRect(x: 0,y: 0,width: 500,height: 500), to: second,
                                                        primaryHeight: 1000, crossingDisplays: false, batch: batch) }
        try await Task.sleep(for: .milliseconds(20))
        _ = await batchService.undoLast()
        _ = await remaining.value
        guard fast.read(window) == before, slow.read(second) == before else { throw ReliabilityFailure.partialBatchUndo }
        print("PASS: One Undo restores completed and pending members of a tile batch")

        let orderFast = WindowFixture(), orderSlow = WindowFixture()
        orderSlow.state.withLock { $0.minimumHeight = 700 }
        let orderedService = WindowService(readFrame: { $0.windowID == window.windowID ? orderFast.read($0) : orderSlow.read($0) },
                                          writeFrame: { goal,ref,cross in
            ref.windowID == window.windowID ? orderFast.write(goal,ref,cross) : orderSlow.write(goal,ref,cross)
        }, mutationContext: context())
        let orderedBatch = await orderedService.newBatch()
        _ = await orderedService.apply(target, to: window, primaryHeight: 1000, crossingDisplays: false, batch: orderedBatch)
        let older = Task { await orderedService.apply(CGRect(x: 0,y: 0,width: 500,height: 500), to: second,
                                                      primaryHeight: 1000, crossingDisplays: false, batch: orderedBatch) }
        try await Task.sleep(for: .milliseconds(20))
        _ = await orderedService.apply(CGRect(x: 250,y: 0,width: 600,height: 1000), to: window,
                                       primaryHeight: 1000, crossingDisplays: false)
        _ = await orderedService.undoLast()
        let latestWasUndoneFirst = orderFast.read(window) == target
        _ = await older.value
        guard latestWasUndoneFirst else { throw ReliabilityFailure.commandOrder }
        print("PASS: Newer standalone move undoes before an older pending tile")

        let cancelledFixture = WindowFixture()
        let cancelledService = WindowService(readFrame: cancelledFixture.read, writeFrame: cancelledFixture.write, mutationContext: context())
        let interrupted = Task { await cancelledService.apply(target, to: window, primaryHeight: 1000,
                                                               crossingDisplays: false, duration: 0.45) }
        try await Task.sleep(for: .milliseconds(50))
        interrupted.cancel()
        _ = await interrupted.value
        let undoCancelled = await cancelledService.undoLast()
        guard undoCancelled, cancelledFixture.read(window) == before else { throw ReliabilityFailure.cancelledMove }
        print("PASS: Cancelling partial motion preserves its Undo entry")

        let lifecycle = WindowLifecycleMonitor(existingWindows: [42: [10]])
        var created: [pid_t] = []
        lifecycle.onCreated = { pid, _ in created.append(pid) }
        lifecycle.created(42, windowID: 10)
        precondition(created.isEmpty, "Unhiding an existing window was treated as new")
        lifecycle.created(42, windowID: 11)
        lifecycle.created(42, windowID: 11)
        precondition(created == [42], "A genuine new window was dropped or duplicated")
        print("PASS: Existing-window announcements are ignored; genuine new windows still join")

        let model = SettingsModel()
        let displays = DisplayService(settings: { model.settings })
        let display = DisplayContext(
            id: DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil),
            visibleFrame: CGRect(x: 0, y: 0, width: 2000, height: 1000),
            range: ColumnRange(minCols: 2, maxCols: 2, defaultCols: 2, maxRows: 2, isPortrait: false),
            profile: DisplayProfile(columns: 2, gap: 0, padding: 0))
        let watcher = SplitWatcher(windows: service, displays: displays, model: model)
        let watched = [(window: window, frame: before), (window: second, frame: target)]
        var closedGroups: [[WindowRef]] = []
        watcher.onWindowClosed = { group, _, _, _ in closedGroups.append(group.map(\.window)) }
        model.settings.splitOnMinimise = .leaveSpace
        watcher.watch(watched, display: display)
        watcher.closed(minimised: true)
        precondition(closedGroups.isEmpty && watcher.watched.isEmpty,
                     "State reconciliation ignored the leave-space setting")
        print("PASS: Reconciled minimisation respects leaving the space empty")
        model.settings.splitOnMinimise = .retile
        watcher.watch(watched, display: display)
        watcher.closed(minimised: true)
        precondition(closedGroups == [[window, second]],
                     "A removal before delayed baseline refresh lost the original group")
        watcher.closed(minimised: true)
        precondition(closedGroups.count == 1, "Duplicate removal processed the same group twice")
        print("PASS: Immediate removal retains the group and is processed once")

        var cycles = model.settings.cycles
        cycles[0].name = "work"
        model.updateCycles(cycles)
        precondition(model.settings.hotkeys.contains { $0.command == .cycle(name: "work") })
        model.updateCycles([])
        precondition(model.settings.hotkeys.filter { if case .cycle = $0.command { return true }; return false }.allSatisfy { !$0.enabled })
        print("PASS: Cycle renames repair bindings; removal disables them")
        try await VerifySplitLifecycle.run()
        try await VerifyWindowContext.run()
        try await VerifyWorkspaceRecovery.run()
        try await VerifyWindowPolicies.run()
        try await VerifyWorkspaceTransactions.run()
    }
}

// Presentation-only dependencies of SplitWatcher; these paths do not run in the lifecycle checks above.
@MainActor enum SplitLabel {
    static func apps(_ key: SplitKey) -> String { key.apps.joined(separator: ", ") }
    static func display(_ key: SplitKey, displays: [DisplayContext]) -> String { key.display }
}
enum CommandExecutor {
    static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1
            && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }
}

// Permission prompting is outside this isolated state-machine executable.
@MainActor enum Permissions {
    static let isAccessibilityTrusted = true
}
