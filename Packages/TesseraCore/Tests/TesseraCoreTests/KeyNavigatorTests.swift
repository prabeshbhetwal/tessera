import CoreGraphics
import Testing

@testable import TesseraCore

private func id(_ n: UInt32) -> DisplayID { DisplayID(vendor: n, model: n, serial: n, uuid: nil) }

private func display(_ n: UInt32, x: CGFloat, y: CGFloat = 0, width: CGFloat = 3840, height: CGFloat = 1047,
                     columns: Int, portrait: Bool = false) -> DisplayContext {
    DisplayContext(
        id: id(n),
        visibleFrame: CGRect(x: x, y: y, width: width, height: height),
        range: ColumnRange(minCols: 1, maxCols: 8, defaultCols: columns, maxRows: 2, isPortrait: portrait),
        profile: DisplayProfile(columns: columns, gap: 8, padding: 8))
}

/// Deliberately listed out of left-to-right order: the navigator must sort by frame.minX then minY.
/// Sorted order: wide (x 0, 5 cols), mid (x 3840, 2 cols), far (x 5352, 3 cols).
private let far = display(3, x: 5352, width: 1500, columns: 3)
private let wide = display(1, x: 0, columns: 5)
private let mid = display(2, x: 3840, width: 1512, height: 949, columns: 2)
private let displays = [far, wide, mid]

private func state(_ d: Int, _ c: ClosedRange<Int>, _ b: Band = .full) -> NavState {
    NavState(displayIndex: d, columns: c, band: b)
}

private func reduce(_ s: NavState, _ k: NavKey, _ ds: [DisplayContext] = displays) -> NavState {
    KeyNavigator.reduce(s, k, displays: ds)
}

@Suite struct KeyNavigatorTests {
    // MARK: start

    @Test func startUsesWindowDisplayAndCentreColumn() {
        // Centre x = 1800 on a 3840-wide display, padding 8, 5 columns -> column 2.
        let s = KeyNavigator.start(windowFrame: CGRect(x: 1500, y: 100, width: 600, height: 400), displays: displays)
        #expect(s == state(0, 2...2))
        // Window on the second display (sorted index 1), right half -> column 1 of 2.
        let t = KeyNavigator.start(windowFrame: CGRect(x: 4800, y: 100, width: 400, height: 400), displays: displays)
        #expect(t == state(1, 1...1))
    }

    @Test func startFallsBackToDisplayZeroColumnZero() {
        #expect(KeyNavigator.start(windowFrame: nil, displays: displays) == state(0, 0...0))
        // Window nowhere near any display.
        let off = CGRect(x: -9000, y: -9000, width: 100, height: 100)
        #expect(KeyNavigator.start(windowFrame: off, displays: displays) == state(0, 0...0))
        #expect(KeyNavigator.start(windowFrame: nil, displays: []) == nil)
    }

    // MARK: horizontal

    @Test func leftRightMoveOneColumnAndCollapseSpan() {
        #expect(reduce(state(0, 2...2), .left) == state(0, 1...1))
        #expect(reduce(state(0, 2...2), .right) == state(0, 3...3))
        // A span collapses: left steps from its left edge, right from its right edge.
        #expect(reduce(state(0, 1...3), .left) == state(0, 0...0))
        #expect(reduce(state(0, 1...3), .right) == state(0, 4...4))
    }

    @Test func leftRightClampAtEdges() {
        #expect(reduce(state(0, 0...0), .left) == state(0, 0...0))
        #expect(reduce(state(0, 4...4), .right) == state(0, 4...4))
        #expect(reduce(state(0, 0...4), .left) == state(0, 0...0))
        #expect(reduce(state(0, 0...4), .right) == state(0, 4...4))
    }

    @Test func extendGrowsSpanAndClamps() {
        #expect(reduce(state(0, 2...2), .extendRight) == state(0, 2...3))
        #expect(reduce(state(0, 2...2), .extendLeft) == state(0, 1...2))
        #expect(reduce(state(0, 1...3), .extendRight) == state(0, 1...4))
        #expect(reduce(state(0, 0...4), .extendRight) == state(0, 0...4))
        #expect(reduce(state(0, 0...4), .extendLeft) == state(0, 0...4))
    }

    // MARK: band

    @Test func bandMovesBottomFullTopAndClamps() {
        #expect(reduce(state(0, 1...1, .bottom), .bandUp) == state(0, 1...1, .full))
        #expect(reduce(state(0, 1...1, .full), .bandUp) == state(0, 1...1, .top))
        #expect(reduce(state(0, 1...1, .top), .bandUp) == state(0, 1...1, .top))
        #expect(reduce(state(0, 1...1, .top), .bandDown) == state(0, 1...1, .full))
        #expect(reduce(state(0, 1...1, .full), .bandDown) == state(0, 1...1, .bottom))
        #expect(reduce(state(0, 1...1, .bottom), .bandDown) == state(0, 1...1, .bottom))
    }

    // MARK: digits

    @Test func columnKeyJumpsAndClamps() {
        #expect(reduce(state(0, 0...2), .column(4)) == state(0, 3...3))
        #expect(reduce(state(0, 0...2), .column(1)) == state(0, 0...0))
        // 9 on a 5-column display clamps to the last column; on the 2-column display too.
        #expect(reduce(state(0, 0...0), .column(9)) == state(0, 4...4))
        #expect(reduce(state(1, 0...0), .column(9)) == state(1, 1...1))
        // Defensive: 0 and negatives never produce an out-of-range column.
        #expect(reduce(state(0, 2...2), .column(0)) == state(0, 0...0))
        #expect(reduce(state(0, 2...2), .column(-3)) == state(0, 0...0))
    }

    // MARK: re-clamp (columnsPlus / columnsMinus / apply)

    @Test func columnCountKeysAndApplyReclampToCurrentCount() {
        // The coordinator changed the count underneath us: display 0 now has 3 columns.
        let shrunk = [display(1, x: 0, columns: 3), mid, far]
        for key in [NavKey.columnsPlus, .columnsMinus, .apply] {
            #expect(reduce(state(0, 1...4), key, shrunk) == state(0, 1...2))
            #expect(reduce(state(0, 3...4), key, shrunk) == state(0, 2...2))
            #expect(reduce(state(0, 0...1), key, shrunk) == state(0, 0...1))
        }
    }

    @Test func staleDisplayIndexIsClampedIntoRange() {
        #expect(reduce(state(7, 0...0), .apply) == state(2, 0...0))
        #expect(reduce(state(-1, 0...0), .apply) == state(0, 0...0))
    }

    // MARK: displays

    @Test func nextDisplayKeepsColumnRatioAndWraps() {
        // Columns 2-3 of 5 -> columns 2-3 of... display 1 has 2 columns: round(2*2/5)=1 ... max(1, round(4*2/5)-1)=1 -> 1...1.
        #expect(reduce(state(0, 2...3), .nextDisplay) == state(1, 1...1))
        // 2 columns -> 3 columns: column 1 of 2 -> round(1*3/2)=2 ... max(2, round(2*3/2)-1=2) -> 2...2.
        #expect(reduce(state(1, 1...1), .nextDisplay) == state(2, 2...2))
        // Last -> first wraps; 3 -> 5: column 2 -> round(2*5/3)=3 ... max(3, round(3*5/3)-1=4) -> 3...4.
        #expect(reduce(state(2, 2...2), .nextDisplay) == state(0, 3...4))
    }

    @Test func previousDisplayWrapsFromFirstToLast() {
        // 5 -> 3: columns 0-1 -> round(0)=0 ... max(0, round(2*3/5)-1) = round(1.2)-1 = 0 -> 0...0.
        #expect(reduce(state(0, 0...1), .previousDisplay) == state(2, 0...0))
        #expect(reduce(state(2, 0...0), .previousDisplay) == state(1, 0...0))
    }

    @Test func fullWidthSpanStaysFullWidthAcrossDisplays() {
        #expect(reduce(state(0, 0...4), .nextDisplay) == state(1, 0...1))
        #expect(reduce(state(1, 0...1), .nextDisplay) == state(2, 0...2))
    }

    @Test func singleDisplayDisplayKeysAreNoOps() {
        let only = [wide]
        #expect(reduce(state(0, 1...2, .top), .nextDisplay, only) == state(0, 1...2, .top))
        #expect(reduce(state(0, 1...2, .top), .previousDisplay, only) == state(0, 1...2, .top))
    }

    @Test func emptyDisplaysLeaveStateUntouched() {
        let s = state(0, 1...2)
        for key in [NavKey.left, .right, .nextDisplay, .apply, .column(3)] {
            #expect(reduce(s, key, []) == s)
        }
    }

    // MARK: selection

    @Test func selectionMapsToSpanOnOrderedDisplay() {
        let sel = KeyNavigator.selection(state(1, 0...1, .top), displays: displays)
        #expect(sel == .span(display: mid.id, span: ColumnSpan(columns: 0...1, band: .top)))
        #expect(KeyNavigator.selection(state(0, 0...0), displays: []) == .none)
    }

    @Test func selectionClampsStaleState() {
        let sel = KeyNavigator.selection(state(9, 3...8), displays: displays)
        #expect(sel == .span(display: far.id, span: ColumnSpan(columns: 2...2, band: .full)))
    }
}
