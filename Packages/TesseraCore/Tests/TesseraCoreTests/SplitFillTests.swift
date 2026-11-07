import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct SplitFillTests {
    private let gap = 10.0

    private func rect(_ x0: Double, _ x1: Double, _ y0: Double = 0, _ y1: Double = 500) -> CGRect {
        CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func fill(_ hole: CGRect, _ frames: [CGRect]) -> [CGRect]? {
        SplitFill.frames(filling: hole, frames: frames, gap: gap)
    }

    /// Four in a row, the second closes: the most recently used neighbour takes its space.
    @Test func mostRecentNeighbourTakesTheSpace() {
        let (a, c, d) = (rect(0, 240), rect(500, 740), rect(750, 1000))
        let hole = rect(250, 490)
        #expect(fill(hole, [a, c, d]) == [rect(0, 490), c, d])
        #expect(fill(hole, [c, a, d]) == [rect(250, 740), a, d])
    }

    @Test func lastWindowInTheRowLeavesItsSpaceToTheOneBeside() {
        #expect(fill(rect(505, 1000), [rect(0, 495)]) == [rect(0, 1000)])
    }

    /// A full-height window and a column of two: closing the full-height one widens the whole column.
    @Test func columnGrowsIntoAClosedColumn() {
        let (top, bottom) = (rect(505, 1000, 255, 500), rect(505, 1000, 0, 245))
        #expect(fill(rect(0, 495), [top, bottom]) == [rect(0, 1000, 255, 500), rect(0, 1000, 0, 245)])
    }

    /// The full-height window beside a closed cell would cover the cell below it, so the cell below grows instead.
    @Test func tallerNeighbourGivesWayToTheCellInTheSameColumn() {
        let (left, bottom) = (rect(0, 495), rect(505, 1000, 0, 245))
        #expect(fill(rect(505, 1000, 255, 500), [left, bottom]) == [left, rect(505, 1000, 0, 500)])
    }

    @Test func gridCellGoesToTheMostRecentOfItsNeighbours() {
        let (topRight, bottomLeft, bottomRight) = (rect(505, 1000, 255, 500), rect(0, 495, 0, 245), rect(505, 1000, 0, 245))
        let hole = rect(0, 495, 255, 500)
        #expect(fill(hole, [topRight, bottomLeft, bottomRight]) == [rect(0, 1000, 255, 500), bottomLeft, bottomRight])
        #expect(fill(hole, [bottomLeft, topRight, bottomRight]) == [rect(0, 495, 0, 500), topRight, bottomRight])
    }

    /// An app with two columns quits: the column nothing faces at first is filled once its neighbour has grown.
    @Test func adjacentHolesFillInAnyOrder() {
        let holes = [rect(0, 326), rect(336, 663)]
        let b = rect(673, 1000)
        #expect(SplitFill.frames(filling: holes, frames: [b], gap: gap) == [rect(0, 1000)])
        #expect(SplitFill.frames(filling: holes.reversed(), frames: [b], gap: gap) == [rect(0, 1000)])
        #expect(SplitFill.frames(filling: [rect(0, 100)], frames: [rect(600, 1000)], gap: gap) == nil)
    }

    @Test func nothingBesideTheSpaceLeavesTheWindowsAlone() {
        #expect(fill(rect(600, 1000), [rect(0, 300)]) == nil)
        #expect(fill(rect(0, 500), []) == nil)
    }
}
