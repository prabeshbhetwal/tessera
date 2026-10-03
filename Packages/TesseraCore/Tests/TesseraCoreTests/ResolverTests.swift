import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct ResolverTests {
    /// Gap and padding are 0 so frames are plain fractions of the display.
    static func display(_ serial: UInt32, x: CGFloat, y: CGFloat = 0, width: CGFloat = 1000, height: CGFloat = 800,
                        columns: Int) -> DisplayContext {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let range = ColumnRange(minCols: 1, maxCols: 8, defaultCols: columns, maxRows: 4, isPortrait: false)
        return DisplayContext(id: DisplayID(vendor: 1, model: 1, serial: serial, uuid: nil), frame: frame, visibleFrame: frame,
                              range: range, profile: DisplayProfile(columns: columns, gap: 0, padding: 0))
    }

    static func span(_ cols: ClosedRange<Int>, _ band: Band = .full) -> Target { .span(columns: cols, band: band) }

    // MARK: DisplayResolver.ordered

    @Test func orderedSortsByMinXThenMinY() {
        let right = Self.display(1, x: 2000, columns: 3)
        let leftTop = Self.display(2, x: 0, y: 900, columns: 3)
        let leftBottom = Self.display(3, x: 0, y: 0, columns: 3)
        let ordered = DisplayResolver.ordered([right, leftTop, leftBottom])
        #expect(ordered.map(\.id.serial) == [3, 2, 1])
    }

    // MARK: DisplayResolver.resolve

    static let a = display(1, x: 0, columns: 2)
    static let b = display(2, x: 1000, columns: 3)
    static let c = display(3, x: 2000, columns: 5)
    static let all = [c, a, b]   // deliberately unsorted

    @Test func indexUsesLeftToRightOrder() {
        #expect(DisplayResolver.resolve(.index(1), displays: Self.all, windowFrame: nil, cursor: .zero)?.id == Self.a.id)
        #expect(DisplayResolver.resolve(.index(2), displays: Self.all, windowFrame: nil, cursor: .zero)?.id == Self.b.id)
        #expect(DisplayResolver.resolve(.index(3), displays: Self.all, windowFrame: nil, cursor: .zero)?.id == Self.c.id)
    }

    @Test func indexOutOfRangeIsNil() {
        #expect(DisplayResolver.resolve(.index(0), displays: Self.all, windowFrame: nil, cursor: .zero) == nil)
        #expect(DisplayResolver.resolve(.index(4), displays: Self.all, windowFrame: nil, cursor: .zero) == nil)
        #expect(DisplayResolver.resolve(.index(-1), displays: Self.all, windowFrame: nil, cursor: .zero) == nil)
    }

    @Test func idMatchesStorageKey() {
        #expect(DisplayResolver.resolve(.id(Self.b.id.storageKey), displays: Self.all, windowFrame: nil, cursor: .zero)?.id == Self.b.id)
        #expect(DisplayResolver.resolve(.id("nope"), displays: Self.all, windowFrame: nil, cursor: .zero) == nil)
    }

    @Test func cursorPicksDisplayUnderPoint() {
        #expect(DisplayResolver.resolve(.cursor, displays: Self.all, windowFrame: nil, cursor: CGPoint(x: 1500, y: 10))?.id == Self.b.id)
        #expect(DisplayResolver.resolve(.cursor, displays: Self.all, windowFrame: nil, cursor: CGPoint(x: -50, y: 10)) == nil)
    }

    @Test func currentUsesWindowCentre() {
        // Window straddles a and b but its centre (x = 1100) is on b.
        let w = CGRect(x: 900, y: 100, width: 400, height: 300)
        #expect(DisplayResolver.resolve(.current, displays: Self.all, windowFrame: w, cursor: .zero)?.id == Self.b.id)
    }

    @Test func currentWithoutWindowIsNil() {
        #expect(DisplayResolver.resolve(.current, displays: Self.all, windowFrame: nil, cursor: .zero) == nil)
    }

    @Test func currentWithCentreOffEveryScreenFallsBackToLargestOverlap() {
        // Centre at x = 3100 is off all screens; the window overlaps display c (x 2000-3000) the most.
        let w = CGRect(x: 2800, y: 100, width: 600, height: 300)
        #expect(DisplayResolver.resolve(.current, displays: Self.all, windowFrame: w, cursor: .zero)?.id == Self.c.id)
        let far = CGRect(x: 9000, y: 9000, width: 10, height: 10)
        #expect(DisplayResolver.resolve(.current, displays: Self.all, windowFrame: far, cursor: .zero) == nil)
    }

    @Test func emptyDisplaysResolveToNil() {
        #expect(DisplayResolver.resolve(.index(1), displays: [], windowFrame: nil, cursor: .zero) == nil)
        #expect(DisplayResolver.step(.next, from: Self.a, displays: []) == nil)
    }

    // MARK: DisplayResolver.step

    @Test func nextWrapsFromLastToFirst() {
        #expect(DisplayResolver.step(.next, from: Self.c, displays: Self.all)?.id == Self.a.id)
        #expect(DisplayResolver.step(.next, from: Self.a, displays: Self.all)?.id == Self.b.id)
    }

    @Test func previousWrapsFromFirstToLast() {
        #expect(DisplayResolver.step(.previous, from: Self.a, displays: Self.all)?.id == Self.c.id)
        #expect(DisplayResolver.step(.previous, from: Self.c, displays: Self.all)?.id == Self.b.id)
    }

    @Test func stepIndexIsOneBasedAndBoundsChecked() {
        #expect(DisplayResolver.step(.index(2), from: Self.a, displays: Self.all)?.id == Self.b.id)
        #expect(DisplayResolver.step(.index(9), from: Self.a, displays: Self.all) == nil)
    }

    @Test func singleDisplayStepsToItself() {
        #expect(DisplayResolver.step(.next, from: Self.a, displays: [Self.a])?.id == Self.a.id)
        #expect(DisplayResolver.step(.previous, from: Self.a, displays: [Self.a])?.id == Self.a.id)
    }

    @Test func stepFromUnknownDisplayIsNil() {
        #expect(DisplayResolver.step(.next, from: Self.c, displays: [Self.a, Self.b]) == nil)
    }

    // MARK: TargetResolver.span

    static func resolved(_ cols: ClosedRange<Int>, columns n: Int, band: Band = .full) -> ColumnSpan? {
        TargetResolver.span(for: .span(columns: cols, band: band), display: display(9, x: 0, columns: n))
    }

    @Test func actionHasNoSpan() {
        #expect(TargetResolver.span(for: .action(.maximize), display: Self.a) == nil)
    }

    @Test func oneBasedBecomesZeroBased() {
        #expect(Self.resolved(2...4, columns: 5)?.columns == 1...3)
        #expect(Self.resolved(1...1, columns: 5)?.columns == 0...0)
    }

    @Test func bandIsPreserved() {
        #expect(Self.resolved(1...1, columns: 3, band: .top)?.band == .top)
    }

    @Test func negativeColumnsCountFromRight() {
        #expect(Self.resolved(-2 ... -1, columns: 5)?.columns == 3...4)
        #expect(Self.resolved(-1 ... -1, columns: 5)?.columns == 4...4)
    }

    // Review Focus 1
    @Test func zeroColumnClampsToFirst() {
        #expect(Self.resolved(0...0, columns: 2)?.columns == 0...0)
        #expect(Self.resolved(0...2, columns: 2)?.columns == 0...1)
    }

    @Test func tooLargeColumnClampsToLast() {
        #expect(Self.resolved(9...9, columns: 2)?.columns == 1...1)
        #expect(Self.resolved(1...9, columns: 2)?.columns == 0...1)
    }

    @Test func negativeBeyondLeftClampsToFirst() {
        #expect(Self.resolved(-5 ... -1, columns: 3)?.columns == 0...2)
        #expect(Self.resolved(-9 ... -9, columns: 3)?.columns == 0...0)
        #expect(Self.resolved(-5 ... -5, columns: 3)?.columns == 0...0)
    }

    @Test func crossedRangeAfterMappingIsReorderedNotEmpty() {
        // -3 is column 3 of 5, 2 is column 2: mapped 2...1 must become 1...2.
        #expect(Self.resolved(-3...2, columns: 5)?.columns == 1...2)
    }

    @Test func everySpanInASweepIsValid() {
        for n in 1...8 {
            for lo in -12...12 {
                for hi in lo...12 {
                    guard let s = Self.resolved(lo...hi, columns: n) else {
                        Issue.record("nil span for \(lo)...\(hi) on \(n)")
                        continue
                    }
                    #expect(s.columns.lowerBound >= 0 && s.columns.upperBound <= n - 1, "\(lo)...\(hi) on \(n) -> \(s.columns)")
                }
            }
        }
    }

    @Test func degenerateColumnCountTreatedAsOne() {
        let d = DisplayContext(id: Self.a.id, frame: Self.a.frame, visibleFrame: Self.a.visibleFrame, range: Self.a.range,
                               profile: DisplayProfile(columns: 0, gap: 0, padding: 0))
        #expect(TargetResolver.span(for: .span(columns: 3...5, band: .full), display: d)?.columns == 0...0)
    }

    // MARK: TargetResolver.frame

    @Test func spanFrameUsesGridGeometry() {
        let d = Self.display(1, x: 100, columns: 4)   // x 100..1100, y 0..800
        let f = TargetResolver.frame(for: Self.span(2...3, .top), display: d, current: .zero)
        #expect(f == CGRect(x: 350, y: 400, width: 500, height: 400))
    }

    @Test func negativeSpanFrame() {
        let d = Self.display(1, x: 0, columns: 4)
        let f = TargetResolver.frame(for: Self.span(-2 ... -1), display: d, current: .zero)
        #expect(f == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func outOfRangeSpanFrameStaysInsideDisplay() {
        let d = Self.display(1, x: 0, columns: 2)
        let f = TargetResolver.frame(for: Self.span(9...9), display: d, current: .zero)
        #expect(f == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func actionFrameUsesGridGeometry() {
        let d = Self.display(1, x: 0, columns: 4)
        #expect(TargetResolver.frame(for: .action(.leftHalf), display: d, current: .zero) == CGRect(x: 0, y: 0, width: 500, height: 800))
        let current = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(TargetResolver.frame(for: .action(.center), display: d, current: current)
            == GridGeometry.frame(for: .center, display: d, current: current))
    }

    // MARK: TargetResolver.relocate

    static func relocated(_ cols: ClosedRange<Int>, from: Int, to: Int) -> ClosedRange<Int> {
        TargetResolver.relocate(span: ColumnSpan(columns: cols, band: .top),
                                from: display(1, x: 0, columns: from), to: display(2, x: 0, columns: to)).columns
    }

    @Test func relocateAppliesTheRatioRule() {
        // 0-based 1...2 of 5 -> 6: start round(1.2) = 1, end round(3 * 1.2) - 1 = 3.
        #expect(Self.relocated(1...2, from: 5, to: 6) == 1...3)
        // Whole display maps to whole display.
        #expect(Self.relocated(0...4, from: 5, to: 2) == 0...1)
        #expect(Self.relocated(0...1, from: 2, to: 5) == 0...4)
    }

    @Test func relocateKeepsBandAndIdentityOnSameCount() {
        let moved = TargetResolver.relocate(span: ColumnSpan(columns: 1...2, band: .bottom),
                                            from: Self.display(1, x: 0, columns: 5), to: Self.display(2, x: 0, columns: 5))
        #expect(moved == ColumnSpan(columns: 1...2, band: .bottom))
    }

    @Test func relocateNeverProducesEmptyOrOutOfRangeSpans() {
        for from in 1...8 {
            for to in 1...8 {
                for lo in 0..<from {
                    for hi in lo..<from {
                        let r = Self.relocated(lo...hi, from: from, to: to)
                        #expect(r.lowerBound >= 0 && r.upperBound <= to - 1, "\(lo)...\(hi) \(from)->\(to) = \(r)")
                    }
                }
            }
        }
    }

    @Test func relocateToSingleColumn() {
        #expect(Self.relocated(3...4, from: 5, to: 1) == 0...0)
    }
}
