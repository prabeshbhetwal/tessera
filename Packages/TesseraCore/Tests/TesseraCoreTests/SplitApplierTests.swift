import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

@Suite struct SplitApplierTests {
    typealias Window = (bundleID: String?, frame: CGRect)

    static let usable = CGRect(x: 0, y: 0, width: 1000, height: 500)
    static let tall = CGRect(x: 0, y: 0, width: 500, height: 1000)

    /// A slot in a row: `x` and `width` as fractions of the usable width.
    static func slot(_ app: String, _ x: Double, _ width: Double, y: Double = 0, height: Double = 1) -> Slot {
        Slot(bundleID: app, rect: UnitRect(x: x, y: y, width: width, height: height))
    }

    static func split(_ slots: [Slot]) -> LearnedSplit {
        LearnedSplit(key: SplitKey(display: "d", bundleIDs: slots.map(\.bundleID)), slots: slots,
                     updated: Date(timeIntervalSince1970: 0))
    }

    /// A full-height window whose left edge is `x`; only its position matters to the applier.
    static func window(_ app: String?, at x: Double) -> Window {
        (app, CGRect(x: x, y: 0, width: 100, height: 500))
    }

    static func apply(_ split: LearnedSplit, _ windows: [Window], usable: CGRect = usable, portrait: Bool = false,
                      restoresOrder: Bool = false, gapPlacement: SplitGapPlacement = .staysInPlace) -> [CGRect]? {
        SplitApplier.frames(for: split, windows: windows, usable: usable, portrait: portrait,
                            restoresOrder: restoresOrder, gapPlacement: gapPlacement)
    }

    static func frames(_ split: LearnedSplit, _ windows: [Window], usable: CGRect = usable, portrait: Bool = false,
                       restoresOrder: Bool = false, gapPlacement: SplitGapPlacement = .staysInPlace,
                       sourceLocation: SourceLocation = #_sourceLocation) throws -> [CGRect] {
        try #require(apply(split, windows, usable: usable, portrait: portrait, restoresOrder: restoresOrder,
                           gapPlacement: gapPlacement), sourceLocation: sourceLocation)
    }

    static func expectFrame(_ f: CGRect, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(f.minX - x) < 1e-6, "x \(f.minX) vs \(x)", sourceLocation: sourceLocation)
        #expect(abs(f.minY - y) < 1e-6, "y \(f.minY) vs \(y)", sourceLocation: sourceLocation)
        #expect(abs(f.width - width) < 1e-6, "w \(f.width) vs \(width)", sourceLocation: sourceLocation)
        #expect(abs(f.height - height) < 1e-6, "h \(f.height) vs \(height)", sourceLocation: sourceLocation)
    }

    /// T 0.25 | S 0.25 | X 0.5, no gaps.
    static let tsx = split([slot("T", 0, 0.25), slot("S", 0.25, 0.25), slot("X", 0.5, 0.5)])
    /// Input order T, S, X; current left-to-right order X, T, S.
    static let xts: [Window] = [window("T", at: 400), window("S", at: 700), window("X", at: 0)]

    // MARK: sizes follow the app

    @Test func restoresAppSizesInCurrentOrder() throws {
        let f = try Self.frames(Self.tsx, Self.xts)
        Self.expectFrame(f[0], 500, 0, 250, 500)   // T
        Self.expectFrame(f[1], 750, 0, 250, 500)   // S
        Self.expectFrame(f[2], 0, 0, 500, 500)     // X
    }

    @Test func restoresOrderWhenAsked() throws {
        let f = try Self.frames(Self.tsx, Self.xts, restoresOrder: true)
        Self.expectFrame(f[0], 0, 0, 250, 500)
        Self.expectFrame(f[1], 250, 0, 250, 500)
        Self.expectFrame(f[2], 500, 0, 500, 500)
    }

    @Test func scalesToNewUsableFrame() throws {
        let big = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let f = try Self.frames(Self.tsx, Self.xts, usable: big)
        Self.expectFrame(f[0], 1000, 0, 500, 1000)
        Self.expectFrame(f[1], 1500, 0, 500, 1000)
        Self.expectFrame(f[2], 0, 0, 1000, 1000)
    }

    @Test func singleWindowStrip() throws {
        let f = try Self.frames(Self.split([Self.slot("X", 0, 0.7)]), [Self.window("X", at: 300)])
        Self.expectFrame(f[0], 0, 0, 700, 500)
    }

    @Test func noWindowsNoFrames() throws {
        let f = try Self.frames(Self.split([]), [])
        #expect(f.isEmpty)
    }

    @Test func tiedLeftEdgesOrderTopFirst() throws {
        let split = Self.split([Self.slot("T", 0, 0.4), Self.slot("X", 0.4, 0.6)])
        let windows: [Window] = [("T", CGRect(x: 0, y: 0, width: 100, height: 250)),
                                 ("X", CGRect(x: 0, y: 250, width: 100, height: 250))]
        let f = try Self.frames(split, windows)
        Self.expectFrame(f[0], 600, 0, 400, 500)   // X is higher, so it leads
        Self.expectFrame(f[1], 0, 0, 600, 500)
    }

    // MARK: gaps

    @Test func stripStaysInPlace() throws {
        let split = Self.split([Self.slot("T", 0, 0.3), Self.slot("X", 0.3, 0.5)])   // 0.2 empty at the right
        let f = try Self.frames(split, [Self.window("X", at: 0), Self.window("T", at: 600)])
        Self.expectFrame(f[0], 0, 0, 500, 500)
        Self.expectFrame(f[1], 500, 0, 300, 500)
    }

    @Test func stripFollowsNeighbour() throws {
        let split = Self.split([Self.slot("T", 0, 0.3), Self.slot("X", 0.5, 0.5)])   // 0.2 gap after T
        let f = try Self.frames(split, [Self.window("X", at: 0), Self.window("T", at: 600)],
                                gapPlacement: .followsNeighbour)
        Self.expectFrame(f[0], 0, 0, 500, 500)
        Self.expectFrame(f[1], 500, 0, 300, 500)   // the gap that followed T (800…1000) still follows it
    }

    @Test func gapStaysAtItsIndexWhenNotFollowing() throws {
        let split = Self.split([Self.slot("T", 0, 0.3), Self.slot("X", 0.5, 0.5)])
        let f = try Self.frames(split, [Self.window("X", at: 0), Self.window("T", at: 600)])
        Self.expectFrame(f[0], 0, 0, 500, 500)
        Self.expectFrame(f[1], 700, 0, 300, 500)   // the 0.2 gap stays between the first and second window
    }

    @Test func leadingGapStaysAtTheStartOrTravelsWithFirstSlot() throws {
        let split = Self.split([Self.slot("T", 0.1, 0.3), Self.slot("X", 0.4, 0.6)])
        let windows = [Self.window("X", at: 0), Self.window("T", at: 600)]
        let stays = try Self.frames(split, windows)
        Self.expectFrame(stays[0], 100, 0, 600, 500)
        Self.expectFrame(stays[1], 700, 0, 300, 500)
        let follows = try Self.frames(split, windows, gapPlacement: .followsNeighbour)
        Self.expectFrame(follows[0], 0, 0, 600, 500)
        Self.expectFrame(follows[1], 700, 0, 300, 500)   // T brings the leading 0.1 with it
    }

    @Test func windowsInLearnedOrderReproduceTheLayoutEitherWay() throws {
        let split = Self.split([Self.slot("T", 0.1, 0.3), Self.slot("X", 0.5, 0.4)])
        let windows = [Self.window("T", at: 0), Self.window("X", at: 500)]
        for placement in SplitGapPlacement.allCases {
            let f = try Self.frames(split, windows, gapPlacement: placement)
            Self.expectFrame(f[0], 100, 0, 300, 500)
            Self.expectFrame(f[1], 500, 0, 400, 500)
        }
    }

    // MARK: pairing

    @Test func duplicatesPairInReadingOrder() throws {
        let split = Self.split([Self.slot("Chrome", 0, 0.3), Self.slot("Chrome", 0.3, 0.7)])
        let f = try Self.frames(split, [Self.window("Chrome", at: 0), Self.window("Chrome", at: 300)])
        Self.expectFrame(f[0], 0, 0, 300, 500)
        Self.expectFrame(f[1], 300, 0, 700, 500)
        let swapped = try Self.frames(split, [Self.window("Chrome", at: 300), Self.window("Chrome", at: 0)],
                                      restoresOrder: true)
        Self.expectFrame(swapped[0], 300, 0, 700, 500)   // the window on the right takes the right-hand slot
        Self.expectFrame(swapped[1], 0, 0, 300, 500)
    }

    @Test func packedDuplicatesPairLeftToRight() throws {
        // Learned Chrome 30 | Chrome 70. Now one Chrome is top-right and the other bottom-left: reading order puts
        // the top-right one first, but packing goes left to right, so the left one must take the left 30 %.
        let split = Self.split([Self.slot("Chrome", 0, 0.3), Self.slot("Chrome", 0.3, 0.7)])
        let windows: [Window] = [("Chrome", CGRect(x: 600, y: 250, width: 400, height: 250)),
                                 ("Chrome", CGRect(x: 0, y: 0, width: 400, height: 250))]
        for placement in SplitGapPlacement.allCases {
            let f = try Self.frames(split, windows, gapPlacement: placement)
            Self.expectFrame(f[0], 300, 0, 700, 500)
            Self.expectFrame(f[1], 0, 0, 300, 500)
        }
    }

    @Test func missingBundleIDPairsWithPlaceholderSlot() throws {
        let split = Self.split([Self.slot(SplitKey.unknownApp, 0, 0.4), Self.slot("X", 0.4, 0.6)])
        let f = try Self.frames(split, [Self.window("X", at: 0), Self.window(nil, at: 500)])
        Self.expectFrame(f[0], 0, 0, 600, 500)
        Self.expectFrame(f[1], 600, 0, 400, 500)
    }

    @Test func mismatchedAppsReturnNil() {
        let split = Self.split([Self.slot("T", 0, 0.5), Self.slot("S", 0.5, 0.5)])
        #expect(Self.apply(split, [Self.window("T", at: 0), Self.window("X", at: 500)]) == nil)
    }

    @Test func mismatchedCountsReturnNil() {
        let twoSlots = Self.split([Self.slot("T", 0, 0.5), Self.slot("T", 0.5, 0.5)])
        #expect(Self.apply(twoSlots, [Self.window("T", at: 0)]) == nil)
        let oneSlot = Self.split([Self.slot("T", 0, 1)])
        #expect(Self.apply(oneSlot, [Self.window("T", at: 0), Self.window("T", at: 500)]) == nil)
    }

    // MARK: not a single line

    @Test func gridAlwaysRestores() throws {
        let grid = Self.split([
            Self.slot("T", 0, 0.5, y: 0.5, height: 0.5), Self.slot("S", 0.5, 0.5, y: 0.5, height: 0.5),
            Self.slot("X", 0, 0.5, y: 0, height: 0.5), Self.slot("C", 0.5, 0.5, y: 0, height: 0.5),
        ])
        let windows: [Window] = [  // every window sits in a different quarter from the one it was learned in
            ("T", CGRect(x: 500, y: 0, width: 500, height: 250)), ("S", CGRect(x: 0, y: 0, width: 500, height: 250)),
            ("X", CGRect(x: 500, y: 250, width: 500, height: 250)), ("C", CGRect(x: 0, y: 250, width: 500, height: 250)),
        ]
        let f = try Self.frames(grid, windows)
        Self.expectFrame(f[0], 0, 250, 500, 250)
        Self.expectFrame(f[1], 500, 250, 500, 250)
        Self.expectFrame(f[2], 0, 0, 500, 250)
        Self.expectFrame(f[3], 500, 0, 500, 250)
    }

    @Test func columnSplitOnLandscapeRestores() throws {
        let column = Self.split([Self.slot("T", 0, 1, y: 0.5, height: 0.5), Self.slot("X", 0, 1, y: 0, height: 0.5)])
        let windows: [Window] = [("T", CGRect(x: 0, y: 0, width: 1000, height: 250)),
                                 ("X", CGRect(x: 0, y: 250, width: 1000, height: 250))]
        let f = try Self.frames(column, windows)
        Self.expectFrame(f[0], 0, 250, 1000, 250)
        Self.expectFrame(f[1], 0, 0, 1000, 250)
    }

    @Test func rowSplitOnPortraitRestores() throws {
        let f = try Self.frames(Self.tsx, Self.xts, usable: Self.tall, portrait: true)
        Self.expectFrame(f[0], 0, 0, 125, 1000)   // T keeps its learned slot; nothing is repacked
        Self.expectFrame(f[1], 125, 0, 125, 1000)
        Self.expectFrame(f[2], 250, 0, 250, 1000)
    }

    // MARK: across the axis

    @Test func keepsEachSlotsOwnCrossAxisExtent() throws {
        let split = Self.split([Self.slot("T", 0, 0.4), Self.slot("X", 0.4, 0.6, y: 0.1, height: 0.8)])
        let f = try Self.frames(split, [Self.window("X", at: 0), Self.window("T", at: 500)])
        Self.expectFrame(f[0], 0, 50, 600, 400)
        Self.expectFrame(f[1], 600, 0, 400, 500)
    }

    // MARK: portrait

    /// Windows stacked on a tall display: X on top, T below.
    static let xOverT: [Window] = [("X", CGRect(x: 0, y: 500, width: 500, height: 500)),
                                   ("T", CGRect(x: 0, y: 0, width: 500, height: 500))]

    @Test func portraitColumnPacksAlongY() throws {
        // From the top: T 0…0.3, X 0.3…0.8, then 0.2 empty at the bottom. AppKit y runs from the bottom.
        let column = Self.split([Self.slot("T", 0, 1, y: 0.7, height: 0.3), Self.slot("X", 0, 1, y: 0.2, height: 0.5)])
        let f = try Self.frames(column, Self.xOverT, usable: Self.tall, portrait: true)
        Self.expectFrame(f[0], 0, 500, 500, 500)   // X now leads: 0…0.5 from the top
        Self.expectFrame(f[1], 0, 200, 500, 300)   // T follows at 0.5…0.8; the strip below stays empty
    }

    @Test func portraitColumnGapFollowsNeighbour() throws {
        // From the top: T 0…0.3, 0.2 gap, X 0.5…1.
        let column = Self.split([Self.slot("T", 0, 1, y: 0.7, height: 0.3), Self.slot("X", 0, 1, y: 0, height: 0.5)])
        let stays = try Self.frames(column, Self.xOverT, usable: Self.tall, portrait: true)
        Self.expectFrame(stays[1], 0, 0, 500, 300)     // the gap stays at index 1, so T is pushed to the bottom
        let follows = try Self.frames(column, Self.xOverT, usable: Self.tall, portrait: true,
                                      gapPlacement: .followsNeighbour)
        Self.expectFrame(follows[0], 0, 500, 500, 500)
        Self.expectFrame(follows[1], 0, 200, 500, 300)   // T at 0.5…0.8, then the gap that followed it
    }
}
