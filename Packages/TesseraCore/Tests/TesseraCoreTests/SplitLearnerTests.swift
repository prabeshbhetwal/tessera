import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct SplitLearnerTests {
    static let usable = CGRect(x: 0, y: 0, width: 1000, height: 500)

    /// Every window gets a distinct bundle ID (`app0`, `app1`, ...) in the order given.
    static func learn(_ frames: [CGRect], gap: Double = 8) -> Result<[Slot], SplitRejection> {
        let windows = frames.enumerated().map { index, frame -> (bundleID: String?, frame: CGRect) in
            ("app\(index)", frame)
        }
        return SplitLearner.learn(windows, usable: usable, gap: gap)
    }

    static func expectRect(_ r: UnitRect, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(r.x - x) < 1e-9, "x \(r.x) vs \(x)", sourceLocation: sourceLocation)
        #expect(abs(r.y - y) < 1e-9, "y \(r.y) vs \(y)", sourceLocation: sourceLocation)
        #expect(abs(r.width - width) < 1e-9, "w \(r.width) vs \(width)", sourceLocation: sourceLocation)
        #expect(abs(r.height - height) < 1e-9, "h \(r.height) vs \(height)", sourceLocation: sourceLocation)
    }

    @Test func twoWindowRow() throws {
        let slots = try Self.learn([
            CGRect(x: 0, y: 0, width: 300, height: 500),
            CGRect(x: 308, y: 0, width: 692, height: 500),
        ]).get()
        #expect(slots.map(\.bundleID) == ["app0", "app1"])
        Self.expectRect(slots[0].rect, 0, 0, 0.3, 1)
        Self.expectRect(slots[1].rect, 0.308, 0, 0.692, 1)
    }

    @Test func sloppyEdgesSnap() throws {
        let slots = try Self.learn([
            CGRect(x: 5, y: 0, width: 295, height: 500),      // starts 5 pt in, ends at 300
            CGRect(x: 312, y: 0, width: 683, height: 500),    // 12 pt gap, ends 5 pt short of the edge
        ]).get()
        #expect(abs(slots[0].rect.x) < 1e-9)
        #expect(abs(slots[1].rect.x + slots[1].rect.width - 1) < 1e-9)
        let gap = (slots[1].rect.x - (slots[0].rect.x + slots[0].rect.width)) * Self.usable.width
        #expect(abs(gap - 8) < 1e-9, "gap \(gap)")
    }

    @Test func largeGapKept() throws {
        let slots = try Self.learn([CGRect(x: 0, y: 0, width: 800, height: 500)]).get()
        Self.expectRect(slots[0].rect, 0, 0, 0.8, 1)
    }

    @Test func gridAccepted() throws {
        let slots = try Self.learn([
            CGRect(x: 504, y: 0, width: 496, height: 246),    // bottom-right
            CGRect(x: 0, y: 254, width: 496, height: 246),    // top-left
            CGRect(x: 0, y: 0, width: 496, height: 246),      // bottom-left
            CGRect(x: 504, y: 254, width: 496, height: 246),  // top-right
        ]).get()
        #expect(slots.map(\.bundleID) == ["app1", "app3", "app2", "app0"])
    }

    @Test func overlapRejected() {
        let result = Self.learn([
            CGRect(x: 0, y: 0, width: 600, height: 500),
            CGRect(x: 500, y: 0, width: 500, height: 500),
        ])
        #expect(result == .failure(.overlap))
    }

    @Test func smallOverlapTolerated() throws {
        let slots = try Self.learn([
            CGRect(x: 0, y: 0, width: 510, height: 500),
            CGRect(x: 490, y: 0, width: 510, height: 500),
        ]).get()
        #expect(slots.count == 2)
    }

    @Test func settlingIgnoresInputOrder() throws {
        // A tall window beside two stacked windows whose left edges differ by 3 pt (gaps of 10 and 13).
        let windows: [(bundleID: String?, frame: CGRect)] = [
            ("tall", CGRect(x: 0, y: 0, width: 496, height: 500)),
            ("top", CGRect(x: 506, y: 254, width: 494, height: 246)),
            ("bottom", CGRect(x: 509, y: 0, width: 491, height: 246)),
        ]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        let results = try orders.map { order in
            try SplitLearner.learn(order.map { windows[$0] }, usable: Self.usable, gap: 8).get()
        }
        for result in results { #expect(result == results[0]) }

        let byApp = Dictionary(uniqueKeysWithValues: results[0].map { ($0.bundleID, $0.rect) })
        let tall = try #require(byApp["tall"])
        for name in ["top", "bottom"] {
            let neighbour = try #require(byApp[name])
            let gap = (neighbour.x - (tall.x + tall.width)) * Self.usable.width
            #expect(abs(gap - 8) < 1e-9, "\(name) gap \(gap)")
        }
    }

    @Test func sliverBetweenNeighboursNeverCollapses() throws {
        // Settling both 0 pt spaces to 8 pt would leave the 4 pt sliver with negative width, so no gap is touched.
        let slots = try Self.learn([
            CGRect(x: 0, y: 0, width: 496, height: 500),
            CGRect(x: 496, y: 0, width: 4, height: 500),
            CGRect(x: 500, y: 0, width: 500, height: 500),
        ]).get()
        #expect(slots.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
        Self.expectRect(slots[1].rect, 0.496, 0, 0.004, 1)
    }

    @Test func emptyRejected() {
        #expect(Self.learn([]) == .failure(.noWindows))
    }

    @Test func fullyOffscreenRejected() {
        #expect(Self.learn([CGRect(x: 2000, y: 0, width: 300, height: 500)]) == .failure(.noWindows))
    }

    @Test func clipsOffscreen() throws {
        let slots = try Self.learn([CGRect(x: -200, y: 0, width: 600, height: 500)]).get()
        Self.expectRect(slots[0].rect, 0, 0, 0.4, 1)
    }

    @Test func nilBundleBecomesPlaceholder() throws {
        let slots = try SplitLearner.learn(
            [(bundleID: nil, frame: CGRect(x: 0, y: 0, width: 1000, height: 500))],
            usable: Self.usable, gap: 8).get()
        #expect(slots[0].bundleID == "?")
    }

    @Test func readingOrderTopRowFirstThenLeftToRight() {
        let rects = [
            CGRect(x: 504, y: 0, width: 496, height: 246),     // 0 bottom-right
            CGRect(x: 0, y: 0, width: 496, height: 500),       // 1 tall left
            CGRect(x: 504, y: 254, width: 496, height: 246),   // 2 top-right
        ]
        // The tall window shares a row with both right-hand windows, so it leads and the right column follows top-down.
        #expect(SplitLearner.readingOrder(rects) == [1, 2, 0])
    }

    @Test func rejectionMessages() {
        #expect(SplitRejection.noWindows.message == "No windows on this display")
        #expect(SplitRejection.overlap.message == "Windows overlap, so there's no split to remember")
    }
}
