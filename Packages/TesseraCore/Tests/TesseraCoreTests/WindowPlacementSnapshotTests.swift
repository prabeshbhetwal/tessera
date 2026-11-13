import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct WindowPlacementSnapshotTests {
    @Test func primaryChangeKeepsPhysicalDisplay() {
        let old = WindowPlacementSnapshot.Display(key: "physical", bounds: CGRect(x: 0, y: 0, width: 3840, height: 1080))
        let record = WindowPlacementSnapshot(frame: CGRect(x: 2000, y: 30, width: 1500, height: 1000), display: old)
        let targets = [WindowPlacementSnapshot.Display(key: "physical", bounds: CGRect(x: -3840, y: 0, width: 3840, height: 1080)),
                       .init(key: "virtual", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        #expect(record.resolved(in: targets) == CGRect(x: -1840, y: 30, width: 1500, height: 1000))
    }

    @Test func resolutionChangeScalesRelativeFrame() {
        let old = WindowPlacementSnapshot.Display(key: "a", bounds: CGRect(x: -1000, y: -100, width: 1000, height: 800))
        let record = WindowPlacementSnapshot(frame: CGRect(x: -500, y: 100, width: 500, height: 400), display: old)
        #expect(record.resolved(in: [.init(key: "a", bounds: CGRect(x: 0, y: 0, width: 2000, height: 1600))])
                == CGRect(x: 1000, y: 400, width: 1000, height: 800))
    }

    @Test func unchangedDisplayPreservesExactFrame() {
        let display = WindowPlacementSnapshot.Display(key: "a", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let frame = CGRect(x: -120, y: 25, width: 700, height: 620)
        #expect(WindowPlacementSnapshot(frame: frame, display: display).resolved(in: [display]) == frame)
    }

    @Test func disconnectedDisplayUsesReachableFallback() {
        let record = WindowPlacementSnapshot(frame: CGRect(x: 2000, y: 0, width: 1200, height: 900),
            display: .init(key: "gone", bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080)))
        #expect(record.resolved(in: [.init(key: "a", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))])
                == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func ambiguousIdentityDoesNotPickAnArbitraryDisplay() {
        let frame = CGRect(x: 30, y: 30, width: 500, height: 700)
        let record = WindowPlacementSnapshot(frame: frame, display: .init(key: "same", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        #expect(record.resolved(in: [.init(key: "same", bounds: CGRect(x: -1000, y: 0, width: 1000, height: 800)),
                                     .init(key: "same", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))]) == frame)
    }

    @Test func zeroSourceBoundsAvoidDivisionByZero() {
        let frame = CGRect(x: 30, y: 30, width: 500, height: 700)
        #expect(WindowPlacementSnapshot(frame: frame, display: .init(key: "a", bounds: .zero))
            .resolved(in: [.init(key: "a", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))]) == frame)
    }
}
