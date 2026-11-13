import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct WindowVisibilityTests {
    @Test func twoForegroundWindowsHideTheWindowBehindThem() {
        let frames = [CGRect(x: 0,y: 0,width: 500,height: 800), CGRect(x: 500,y: 0,width: 500,height: 800), CGRect(x: 0,y: 0,width: 1000,height: 800)]
        #expect(WindowVisibility.exposedIndices(frames) == [0,1])
    }
    @Test func partiallyExposedWindowsRemainEligible() {
        #expect(WindowVisibility.exposedIndices([CGRect(x: 0,y: 0,width: 600,height: 800),CGRect(x: 500,y: 0,width: 500,height: 800)]) == [0,1])
    }
    @Test func gapBetweenForegroundWindowsRemainsVisible() {
        #expect(WindowVisibility.exposedIndices([CGRect(x: 0,y: 0,width: 400,height: 800),CGRect(x: 600,y: 0,width: 400,height: 800),CGRect(x: 0,y: 0,width: 1000,height: 800)]) == [0,1,2])
    }
}
