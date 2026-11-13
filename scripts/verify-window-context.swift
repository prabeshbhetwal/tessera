import AppKit
import os
import TesseraCore

private final class ContextFixture: Sendable {
    struct State {
        var topology = WindowTopology(primary: 1, displays: [
            .init(number: 1, key: "a", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            .init(number: 2, key: "b", bounds: CGRect(x: 1000, y: 0, width: 600, height: 900))])
        var spaces: [String: UInt64]? = ["a": 11, "b": 21]
        var frame = CGRect(x: 0, y: 0, width: 500, height: 800)
        var writes: [CGWindowID] = []
        var changeBOnWrite = false
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    func topology() -> WindowTopology { state.withLock { $0.topology } }
    func spaces() -> [String: UInt64]? { state.withLock { $0.spaces } }
    func read(_ window: WindowRef) -> CGRect? { state.withLock { $0.frame } }
    func write(_ frame: CGRect, _ window: WindowRef, _ crossing: Bool) -> Bool {
        state.withLock { state in
            state.frame = frame
            state.writes.append(window.windowID!)
            if state.changeBOnWrite { state.spaces?["b"] = 22; state.changeBOnWrite = false }
            return true
        }
    }
}

enum VerifyWindowContext {
    @MainActor static func run() async throws {
        let fixture = ContextFixture()
        let context = WindowMutationContext(topology: fixture.topology, workspaces: fixture.spaces)
        let pid = ProcessInfo.processInfo.processIdentifier
        let window = WindowRef(element: AXUIElementCreateApplication(pid), pid: pid, windowID: 123580, bundleID: "test.context")
        let service = WindowService(readFrame: fixture.read, writeFrame: fixture.write, mutationContext: context)
        let moving = Task { await service.apply(CGRect(x: 500, y: 0, width: 500, height: 800), to: window,
                                                 primaryHeight: 800, crossingDisplays: false, duration: 0.4) }
        for _ in 0..<400 {
            if fixture.state.withLock({ !$0.writes.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(fixture.state.withLock { !$0.writes.isEmpty }, "The controlled glide never began")
        try await Task.sleep(for: .milliseconds(40))
        fixture.state.withLock { state in
            state.topology = WindowTopology(primary: 2, displays: [
                .init(number: 1, key: "a", bounds: CGRect(x: -1000, y: 0, width: 1000, height: 800)),
                .init(number: 2, key: "b", bounds: CGRect(x: 0, y: 0, width: 600, height: 900))])
        }
        let writesAtChange = fixture.state.withLock { $0.writes.count }
        let result = await moving.value
        // A synchronous AX request already in flight cannot be recalled; subsequent requests must stop.
        guard case .failed = result, fixture.state.withLock({ $0.writes.count }) <= writesAtChange + 1 else {
            throw Failure.staleGlideWrote
        }
        print("PASS: Primary-display change stops subsequent glide writes without waiting for AppKit notification")
        let undone = await service.undoLast()
        guard undone, fixture.read(window) == CGRect(x: -1000, y: 0, width: 500, height: 800) else {
            throw Failure.undoUsedWrongDisplay
        }
        print("PASS: Undo maps a partial move back to its source display after the global origin changes")

        let original = context.capture()
        fixture.state.withLock { $0.spaces?["b"] = 22 }
        guard context.isCurrent(original, on: ["a"], refreshSpaces: true),
              !context.isCurrent(original, on: ["b"]) else { throw Failure.unrelatedSpaceInvalidated }
        let change = context.consumeChanges(spaceNotification: true)
        guard change.displays == ["a", "b"] || change.displays == ["b"] else { throw Failure.badChangeSet }
        // The first change also includes the unconsumed primary-display change above.
        let afterTopology = context.capture()
        fixture.state.withLock { $0.spaces?["b"] = 23 }
        let next = context.consumeChanges(spaceNotification: true)
        guard !next.topology, next.displays == ["b"], context.isCurrent(afterTopology, on: ["a"]) else {
            throw Failure.unrelatedSpaceInvalidated
        }
        print("PASS: A secondary Space change invalidates its work while preserving another display's token")

        let count = fixture.state.withLock { $0.writes.count }
        let stale = await WindowMutationScope.$ticket.withValue(afterTopology) {
            await service.apply(CGRect(x: 0, y: 0, width: 600, height: 800), to: window,
                                primaryHeight: 900, crossingDisplays: true)
        }
        guard case .failed = stale, fixture.state.withLock({ $0.writes.count }) == count else { throw Failure.staleProducerWrote }
        print("PASS: Work captured before a Space change cannot begin a late frame write")

        fixture.state.withLock { $0.spaces = nil }
        let unknown = context.capture()
        _ = context.consumeChanges(spaceNotification: true)
        guard !context.isCurrent(unknown, on: ["a"]) else { throw Failure.unknownSpaceAccepted }
        print("PASS: Missing Space SPI conservatively invalidates work on a real Space notification")

        let fullscreen = WindowService(readFrame: fixture.read, writeFrame: fixture.write, mutationContext: context,
                                       fullscreen: { _ in true })
        let before = fixture.state.withLock { $0.writes.count }
        let refused = await fullscreen.apply(.zero, to: window, primaryHeight: 900, crossingDisplays: false)
        let hasUndo = await fullscreen.undoLast()
        guard case .failed(let message) = refused, message.contains("Exit full screen"), !hasUndo,
              fixture.state.withLock({ $0.writes.count }) == before else { throw Failure.fullscreenMoved }
        print("PASS: Full-screen placement is refused before any write or Undo entry")

        let batchFixture = ContextFixture()
        let batchContext = WindowMutationContext(topology: batchFixture.topology, workspaces: batchFixture.spaces)
        let batchService = WindowService(readFrame: batchFixture.read, writeFrame: batchFixture.write, mutationContext: batchContext)
        let second = WindowRef(element: window.element, pid: pid, windowID: 123581, bundleID: "test.context")
        let batchTicket = batchContext.capture()
        batchFixture.state.withLock { $0.spaces?["b"] = 22 }
        _ = await WindowMutationScope.$ticket.withValue(batchTicket) {
            await batchService.moveTogether([(window, CGRect(x: 0, y: 0, width: 500, height: 800)),
                                              (second, CGRect(x: 1000, y: 0, width: 600, height: 800))],
                                             primaryHeight: 800, duration: 0)
        }
        guard !batchFixture.state.withLock({ $0.writes.contains(second.windowID!) }) else { throw Failure.batchLostScope }
        print("PASS: Multi-window movement propagates its original workspace token to child tasks")
    }

    private enum Failure: Error {
        case staleGlideWrote, undoUsedWrongDisplay, unrelatedSpaceInvalidated, badChangeSet, staleProducerWrote
        case unknownSpaceAccepted, fullscreenMoved, batchLostScope
    }
}
