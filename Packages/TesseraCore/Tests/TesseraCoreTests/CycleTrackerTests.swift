import Foundation
import Testing

@testable import TesseraCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

@Suite struct CycleTrackerTests {
    @Test func firstPressStartsAtStepZero() {
        var c = CycleTracker()
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: t0) == 0)
    }

    @Test func repeatsWithinTimeoutAdvanceAndWrap() {
        var c = CycleTracker()
        var seen: [Int] = []
        for i in 0..<7 { seen.append(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(Double(i) * 0.5))) }
        #expect(seen == [0, 1, 2, 0, 1, 2, 0])
    }

    @Test func timeoutIsMeasuredFromTheLastPress() {
        var c = CycleTracker(timeout: 2)
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0)) == 0)
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(1.9)) == 1)
        // 3.8 s after the first press but only 1.9 s after the last: still advancing.
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(3.8)) == 2)
    }

    @Test func exactlyAtTimeoutStillAdvancesAndJustPastRestarts() {
        var c = CycleTracker(timeout: 2)
        _ = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0))
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(2)) == 1)
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(4.01)) == 0)
    }

    @Test func defaultTimeoutIsTwoSeconds() {
        var c = CycleTracker()
        _ = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0))
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(2.5)) == 0)
    }

    // Review Focus 4
    @Test func pressingTheCycleOnADifferentWindowRestartsAtStepZero() {
        var c = CycleTracker()
        _ = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0))
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0.3)) == 1)
        #expect(c.step(cycle: "left", windowKey: "w2", stepCount: 3, now: at(0.6)) == 0)
        // And the new window continues from there.
        #expect(c.step(cycle: "left", windowKey: "w2", stepCount: 3, now: at(0.9)) == 1)
        // Going back to the first window does not resume its old position either.
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(1.2)) == 0)
    }

    @Test func aDifferentCycleRestartsAtStepZero() {
        var c = CycleTracker()
        _ = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0))
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0.1)) == 1)
        #expect(c.step(cycle: "right", windowKey: "w1", stepCount: 3, now: at(0.2)) == 0)
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0.3)) == 0)
    }

    @Test func clockGoingBackwardsRestarts() {
        var c = CycleTracker()
        _ = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(10))
        #expect(c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(5)) == 0)
    }

    @Test func stepCountChangesNeverReturnOutOfRange() {
        var c = CycleTracker()
        for i in 0..<4 { _ = c.step(cycle: "left", windowKey: "w1", stepCount: 5, now: at(Double(i) * 0.1)) }
        // The user shortened the cycle to 2 steps between presses.
        let next = c.step(cycle: "left", windowKey: "w1", stepCount: 2, now: at(0.5))
        #expect((0..<2).contains(next))
    }

    @Test func emptyOrSingleStepCyclesAreSafe() {
        var c = CycleTracker()
        #expect(c.step(cycle: "x", windowKey: "w1", stepCount: 0, now: at(0)) == 0)
        #expect(c.step(cycle: "x", windowKey: "w1", stepCount: -3, now: at(0.1)) == 0)
        #expect(c.step(cycle: "one", windowKey: "w1", stepCount: 1, now: at(0.2)) == 0)
        #expect(c.step(cycle: "one", windowKey: "w1", stepCount: 1, now: at(0.3)) == 0)
    }

    @Test func skippingStepsByRepeatedCallsAdvancesWithinOnePass() {
        // The executor skips a no-op step by calling step() again with the same `now`.
        var c = CycleTracker()
        let first = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0))
        let skipped = c.step(cycle: "left", windowKey: "w1", stepCount: 3, now: at(0))
        #expect(first == 0 && skipped == 1)
    }
}
