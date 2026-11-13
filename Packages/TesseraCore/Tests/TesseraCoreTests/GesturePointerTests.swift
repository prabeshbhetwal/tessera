import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct GesturePointerTests {
    private let bounds = CGRect(x: 0,y: 0,width: 1440,height: 900)
    @Test func clippedMovementStillReachesTheLeftDirection() {
        var pointer = GesturePointer(origin: CGPoint(x: 0,y: 450))
        let point = pointer.move(to: CGPoint(x: 0,y: 450), delta: CGSize(width: -50,height: 0), bounds: bounds)
        var ring = RingSettings.default
        ring.pointing = false
        #expect(SelectionEngine(ring: ring).select(origin: CGPoint(x: 0,y: 450), cursor: point, displays: [], anchor: nil) == .wedge(index: 6, action: ring.wedges[6]))
    }
    @Test func returningPhysicalMotionCanCancelAtAnEdge() {
        var pointer = GesturePointer(origin: CGPoint(x: 0,y: 450))
        _ = pointer.move(to: CGPoint(x: 0,y: 450), delta: CGSize(width: -50,height: 0), bounds: bounds)
        #expect(pointer.move(to: CGPoint(x: 50,y: 450), delta: CGSize(width: 50,height: 0), bounds: bounds) == CGPoint(x: 0,y: 450))
    }
    @Test func ordinaryMotionIsUnchanged() {
        var pointer = GesturePointer(origin: CGPoint(x: 400,y: 450))
        #expect(pointer.move(to: CGPoint(x: 460,y: 470), delta: CGSize(width: 30,height: 10), bounds: bounds) == CGPoint(x: 460,y: 470))
    }
}
