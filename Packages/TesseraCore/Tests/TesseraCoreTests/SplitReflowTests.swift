import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct SplitReflowTests {
    private let usable = CGRect(x: 0, y: 0, width: 1000, height: 500)
    private let gap = 10.0

    private func rect(_ x0: Double, _ x1: Double, _ y0: Double = 0, _ y1: Double = 500) -> CGRect {
        CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func reflow(_ before: [CGRect], _ after: [CGRect]) -> [CGRect]? {
        SplitReflow.frames(before: before, after: after, usable: usable, gap: gap)
    }

    @Test func widenedWindowShrinksItsNeighbour() {
        let before = [rect(0, 495), rect(505, 1000)]
        #expect(reflow(before, [rect(0, 695), before[1]]) == [rect(0, 695), rect(705, 1000)])
    }

    @Test func narrowedWindowGrowsItsNeighbour() {
        let before = [rect(0, 495), rect(505, 1000)]
        #expect(reflow(before, [before[0], rect(805, 1000)]) == [rect(0, 795), rect(805, 1000)])
    }

    @Test func middleWindowPushesBothSides() {
        let before = [rect(0, 326), rect(336, 663), rect(673, 1000)]
        let after = [before[0], rect(200, 800), before[2]]
        #expect(reflow(before, after) == [rect(0, 190), rect(200, 800), rect(810, 1000)])
    }

    @Test func draggedWindowPullsOneNeighbourAndPushesTheOther() {
        let before = [rect(0, 326), rect(336, 663), rect(673, 1000)]
        let after = [before[0], rect(436, 763), before[2]]
        #expect(reflow(before, after) == [rect(0, 426), rect(436, 763), rect(773, 1000)])
    }

    /// A and B stacked on the left, C full height on the right: widening A moves C, and C drags B so the left
    /// column's seam moves as one.
    @Test func seamMovesAcrossAStack() {
        let a = rect(0, 495, 255, 500), b = rect(0, 495, 0, 245), c = rect(505, 1000)
        let result = reflow([a, b, c], [rect(0, 595, 255, 500), b, c])
        #expect(result == [rect(0, 595, 255, 500), rect(0, 595, 0, 245), rect(605, 1000)])
    }

    /// 2×2 grid: widening the top-left window only moves the top-right one; the bottom row shares no band with it.
    @Test func otherRowIsLeftAlone() {
        let tl = rect(0, 495, 255, 500), tr = rect(505, 1000, 255, 500)
        let bl = rect(0, 495, 0, 245), br = rect(505, 1000, 0, 245)
        let result = reflow([tl, tr, bl, br], [rect(0, 695, 255, 500), tr, bl, br])
        #expect(result == [rect(0, 695, 255, 500), rect(705, 1000, 255, 500), bl, br])
    }

    @Test func tallerWindowShrinksTheOneBelow() {
        let top = rect(0, 1000, 255, 500), bottom = rect(0, 1000, 0, 245)
        #expect(reflow([top, bottom], [rect(0, 1000, 155, 500), bottom]) == [rect(0, 1000, 155, 500), rect(0, 1000, 0, 145)])
    }

    @Test func noChangeOrTwoChangesIsLeftAlone() {
        let before = [rect(0, 495), rect(505, 1000)]
        #expect(reflow(before, before) == nil)
        #expect(reflow(before, [rect(0, 595), rect(605, 1000)]) == nil)
    }

    @Test func neighbourIsNeverSqueezedBelowTheMinimum() {
        let before = [rect(0, 495), rect(505, 1000)]
        #expect(reflow(before, [rect(0, 900), before[1]]) == nil)
    }

    @Test func nothingFacingTheMovedEdgeIsLeftAlone() {
        // Shrinking away from the display edge leaves no neighbour to follow.
        let before = [rect(0, 495), rect(505, 1000)]
        #expect(reflow(before, [rect(100, 495), before[1]]) == nil)
    }

    @Test func neighbourAcrossAHoleCloses() {
        // Windows restored at login, or a dead seam, leave a hole; the next adjustment still fills the display.
        let before = [rect(0, 400), rect(700, 1000)]
        #expect(reflow(before, [rect(0, 300), before[1]]) == [rect(0, 300), rect(310, 1000)])
    }

    @Test func onlyTheNearestWindowFollowsAcrossAHole() {
        let before = [rect(0, 400), rect(500, 700), rect(710, 1000)]
        #expect(reflow(before, [rect(0, 300), before[1], before[2]]) == [rect(0, 300), rect(310, 700), rect(710, 1000)])
    }

    @Test func pushNeverJumpsOverTheWindowThatMoved() {
        // Widening one side of the middle window: the right column follows, the left column is behind the anchor.
        let before = [rect(0, 326), rect(336, 663), rect(673, 1000)]
        let after = [before[0], rect(336, 763), before[2]]
        #expect(reflow(before, after) == [rect(0, 326), rect(336, 763), rect(773, 1000)])
    }

    @Test func toleratedOverlapKeepsTheWholeSeamFollowing() {
        // Stacked neighbours with slightly misaligned edges, one of them overlapping the moved window a little.
        let before = [rect(0, 495), rect(480, 1000, 250, 500), rect(505, 1000, 0, 250)]
        let after = [rect(0, 595), before[1], before[2]]
        #expect(reflow(before, after) == [rect(0, 595), rect(605, 1000, 250, 500), rect(605, 1000, 0, 250)])
    }

    @Test func windowDroppedOverAnotherIsLeftAlone() {
        let before = [rect(0, 326), rect(336, 663), rect(673, 1000)]
        #expect(reflow(before, [rect(500, 826), before[1], before[2]]) == nil)
    }
}
