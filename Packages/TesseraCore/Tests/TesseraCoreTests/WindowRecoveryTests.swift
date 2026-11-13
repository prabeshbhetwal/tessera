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
    @Test func oversizedFrameIsReachableAfterDisplayRemoval() {
        #expect(WindowRecovery.frame(CGRect(x: 1200,y: 0,width: 1800,height: 900), displays: [CGRect(x: 0,y: 0,width: 1000,height: 800)]) == CGRect(x: 0,y: 0,width: 1000,height: 800))
    }
}
