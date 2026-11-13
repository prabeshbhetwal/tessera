import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct WindowRecoveryTests {
    @Test func removedDisplayFrameReturnsToConnectedScreen() {
        #expect(WindowRecovery.frame(CGRect(x: 1200,y: 100,width: 400,height: 500), displays: [CGRect(x: 0,y: 0,width: 1000,height: 800)]) == CGRect(x: 600,y: 100,width: 400,height: 500))
    }
    @Test func intentionalPartiallyVisibleFrameStaysPut() {
        let frame = CGRect(x: 900,y: 100,width: 400,height: 500)
        #expect(WindowRecovery.frame(frame, displays: [CGRect(x: 0,y: 0,width: 1000,height: 800)]) == frame)
    }
    @Test func tallWindowInBottomSlotKeepsBottomEdge() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let bottom = CGRect(x: 0, y: 400, width: 500, height: 400)
        #expect(WindowRecovery.anchoredOrigin(goal: bottom, size: CGSize(width: 500, height: 600), display: display)
            == CGPoint(x: 0, y: 200))
        let top = CGRect(x: 0, y: 0, width: 500, height: 400)
        #expect(WindowRecovery.anchoredOrigin(goal: top, size: CGSize(width: 500, height: 600), display: display)
            == CGPoint(x: 0, y: 0))
    }
    @Test func wideWindowInRightSlotKeepsRightEdgeButStaysOnDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 700, y: 0, width: 300, height: 800)
        #expect(WindowRecovery.anchoredOrigin(goal: right, size: CGSize(width: 500, height: 800), display: display)
            == CGPoint(x: 500, y: 0))
        #expect(WindowRecovery.anchoredOrigin(goal: right, size: CGSize(width: 1200, height: 800), display: display)
            == CGPoint(x: 0, y: 0))
    }
    @Test func oversizedFrameIsReachableAfterDisplayRemoval() {
        #expect(WindowRecovery.frame(CGRect(x: 1200,y: 0,width: 1800,height: 900), displays: [CGRect(x: 0,y: 0,width: 1000,height: 800)]) == CGRect(x: 0,y: 0,width: 1000,height: 800))
    }
}
