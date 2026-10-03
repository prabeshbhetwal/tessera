import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct RingCancelTests {
    private static let chord: Set<UInt16> = [59, 58, 55]
    private static let here = CGPoint(x: 100, y: 200)

    private func opened() -> TriggerMachine {
        var m = TriggerMachine(chord: .default)
        _ = m.handle(.flagsChanged(pressedModifiers: Self.chord, location: Self.here))
        return m
    }

    @Test func testCancelRadiusFollowsTheRingHole() {
        var ring = RingSettings()
        #expect(ring.cancelRadius == 39)
        ring.thickness = 200 // thicker than the ring: still a small cancel area
        #expect(ring.cancelRadius == 8)
    }

    @Test func testRightClickCancelsAndIsSwallowed() {
        var m = opened()
        #expect(m.isOpen)
        let down = m.handle(.rightMouseDown)
        #expect(down == TriggerResult(outputs: [.cancel], suppress: true))
        #expect(!m.isOpen)
        #expect(m.handle(.rightMouseUp) == TriggerResult(outputs: [], suppress: true))
        // Releasing the chord afterwards applies nothing.
        #expect(m.handle(.flagsChanged(pressedModifiers: [], location: Self.here)).outputs.isEmpty)
    }

    @Test func testRightClickIgnoredWhileClosed() {
        var m = TriggerMachine(chord: .default)
        #expect(m.handle(.rightMouseDown) == TriggerResult(outputs: [], suppress: false))
        #expect(m.handle(.rightMouseUp) == TriggerResult(outputs: [], suppress: false))
    }

    @Test func testResetForgetsAPendingRightMouseUp() {
        var m = opened()
        _ = m.handle(.rightMouseDown)
        _ = m.reset()
        #expect(m.handle(.rightMouseUp).suppress == false)
    }
}
