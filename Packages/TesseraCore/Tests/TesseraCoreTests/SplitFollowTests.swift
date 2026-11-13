import CoreGraphics
import Testing
@testable import TesseraCore

/// A window that lands short of its goal (a fixed-width app such as System Settings) leaves no hole: the windows beside
/// it follow (`SplitReflow.following`), and a hole left earlier is still covered when a window closes (`SplitFill`).
@Suite struct SplitFollowTests {
    private let gap = 10.0

    private func rect(_ x0: Double, _ x1: Double, _ y0: Double = 0, _ y1: Double = 500) -> CGRect {
        CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Settings gets the right-hand slot but keeps its width, anchored right: the window beside it widens to meet it.
    @Test func neighbourMeetsAWindowThatLandedNarrow() {
        let goals = [rect(0, 495), rect(505, 1000)]
        let landed: [CGRect?] = [goals[0], rect(620, 1000)]
        #expect(SplitReflow.following(goals: goals, landed: landed, gap: gap) == [rect(0, 610), rect(505, 1000)])
    }

    @Test func nothingFollowsWhenEveryWindowLanded() {
        let goals = [rect(0, 495), rect(505, 1000)]
        #expect(SplitReflow.following(goals: goals, landed: goals, gap: gap) == goals)
    }

    @Test func aRefusedMoveIsNotFollowed() {
        let goals = [rect(0, 495), rect(505, 1000)]
        #expect(SplitReflow.following(goals: goals, landed: [goals[0], nil], gap: gap) == goals)
    }

    /// Two stacked windows on the left both land narrow. The right window shares its seam with both, so following
    /// either would resize the other, which never moves again: it stays in its slot rather than overlap one.
    @Test func aLandedWindowIsNeverResizedByALaterFollow() {
        let goals = [rect(0, 495, 255, 500), rect(0, 495, 0, 245), rect(505, 1000)]
        let landed: [CGRect?] = [rect(0, 450, 255, 500), rect(0, 300, 0, 245), goals[2]]
        let followed = SplitReflow.following(goals: goals, landed: landed, gap: gap)
        let real = [landed[0]!, landed[1]!, followed[2]]
        #expect(!SplitReflow.stacked(real))
        #expect(followed == goals)
    }

    /// The window beside the hole sits well short of it (an earlier fixed-width window left space): it still covers it.
    @Test func fillReachesAcrossEmptySpace() {
        let left = rect(0, 400)
        let hole = rect(620, 1000)
        #expect(SplitFill.frames(filling: hole, frames: [left], gap: gap) == [rect(0, 1000)])
    }

    /// A window right beside the hole still wins over one across empty space.
    @Test func adjacentWindowWinsOverOneAcrossSpace() {
        let (far, near) = (rect(0, 200), rect(1010, 1500))
        let hole = rect(500, 1000)
        #expect(SplitFill.frames(filling: hole, frames: [far, near], gap: gap) == [far, rect(500, 1500)])
    }
}
