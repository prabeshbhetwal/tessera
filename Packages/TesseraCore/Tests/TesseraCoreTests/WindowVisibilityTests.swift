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
    // A fixed-size alert in front covers the window behind it but is never picked (the join -> fill loop it caused).
    @Test func fixedSizeWindowOccludesButIsNeverSelected() {
        let alert = CGRect(x: 0, y: 0, width: 420, height: 140), under = CGRect(x: 0, y: 0, width: 400, height: 120)
        let side = CGRect(x: 500, y: 0, width: 500, height: 800)
        #expect(WindowVisibility.selectedIndices([alert, under, side], resizable: [false, true, true],
                                                 forced: [false, false, false]) == [2])
    }
    @Test func forcedWindowIsKeptWhenCoveredButNotWhenFixed() {
        let front = CGRect(x: 0, y: 0, width: 1000, height: 800), behind = CGRect(x: 100, y: 100, width: 300, height: 300)
        #expect(WindowVisibility.selectedIndices([front, behind], resizable: [true, true], forced: [false, true]) == [0, 1])
        #expect(WindowVisibility.selectedIndices([front, behind], resizable: [true, false], forced: [false, true]) == [0])
    }
    @Test func gapBetweenForegroundWindowsRemainsVisible() {
        #expect(WindowVisibility.exposedIndices([CGRect(x: 0,y: 0,width: 400,height: 800),CGRect(x: 600,y: 0,width: 400,height: 800),CGRect(x: 0,y: 0,width: 1000,height: 800)]) == [0,1,2])
    }
}
