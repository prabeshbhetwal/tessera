import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

/// Packed layouts stay inside the display, and offset displays work the same as one at the origin.
extension SplitApplierTests {
    static func expectInside(_ f: CGRect, _ bounds: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(f.minX >= bounds.minX - 1e-9 && f.maxX <= bounds.maxX + 1e-9, "x \(f) outside \(bounds)",
                sourceLocation: sourceLocation)
        #expect(f.minY >= bounds.minY - 1e-9 && f.maxY <= bounds.maxY + 1e-9, "y \(f) outside \(bounds)",
                sourceLocation: sourceLocation)
    }

    @Test func followsNeighbourKeepsOverlappingPairInside() throws {
        // A 0…0.52 overlaps B 0.48…1 by 0.04, so the gap between them is negative.
        let split = Self.split([Self.slot("A", 0, 0.52), Self.slot("B", 0.48, 0.52)])
        let swapped = [Self.window("A", at: 500), Self.window("B", at: 0)]
        for placement in SplitGapPlacement.allCases {
            let f = try Self.frames(split, swapped, gapPlacement: placement)
            for frame in f { Self.expectInside(frame, Self.usable) }
            Self.expectFrame(f[0], 480, 0, 520, 500)   // A slides back to end at the edge
            Self.expectFrame(f[1], 0, 0, 520, 500)
        }
    }

    @Test func everyOrderStaysInsideWithoutOverlap() throws {
        // T 0.1…0.3, gap 0.1, S 0.4…0.7, gap 0.05, X 0.75…0.95, 0.05 empty at the right.
        let split = Self.split([Self.slot("T", 0.1, 0.2), Self.slot("S", 0.4, 0.3), Self.slot("X", 0.75, 0.2)])
        let apps = ["T", "S", "X"]
        let widths = [200.0, 300, 200]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]   // app indices, left to right
        for order in orders {
            let windows = try apps.indices.map { app in
                Self.window(apps[app], at: Double(try #require(order.firstIndex(of: app))) * 300)
            }
            for placement in SplitGapPlacement.allCases {
                let f = try Self.frames(split, windows, gapPlacement: placement)
                for (frame, width) in zip(f, widths) {
                    Self.expectInside(frame, Self.usable)
                    #expect(abs(frame.width - width) < 1e-9, "\(order) \(placement): width \(frame.width) vs \(width)")
                }
                for i in f.indices {
                    for j in f.indices where j > i {
                        #expect(f[i].maxX <= f[j].minX + 1e-9 || f[j].maxX <= f[i].minX + 1e-9,
                                "\(order) \(placement): \(f[i]) overlaps \(f[j])")
                    }
                }
            }
        }
    }

    @Test func offsetDisplayLeftOfMainPacksAndRestores() throws {
        let left = CGRect(x: -1512, y: 0, width: 1512, height: 949)
        let windows = [Self.window("T", at: -1112), Self.window("S", at: -812), Self.window("X", at: -1512)]
        for placement in SplitGapPlacement.allCases {
            let f = try Self.frames(Self.tsx, windows, usable: left, gapPlacement: placement)
            Self.expectFrame(f[0], -756, 0, 378, 949)    // T
            Self.expectFrame(f[1], -378, 0, 378, 949)    // S
            Self.expectFrame(f[2], -1512, 0, 756, 949)   // X leads
        }
        let restored = try Self.frames(Self.tsx, windows, usable: left, restoresOrder: true)
        Self.expectFrame(restored[0], -1512, 0, 378, 949)
        Self.expectFrame(restored[1], -1134, 0, 378, 949)
        Self.expectFrame(restored[2], -756, 0, 756, 949)
    }

    @Test func offsetPortraitDisplayPacksFromItsOwnTop() throws {
        let above = CGRect(x: -500, y: 1000, width: 500, height: 1000)
        let column = Self.split([Self.slot("T", 0, 1, y: 0.7, height: 0.3), Self.slot("X", 0, 1, y: 0.2, height: 0.5)])
        let windows: [Window] = [("X", CGRect(x: -500, y: 1500, width: 500, height: 500)),
                                 ("T", CGRect(x: -500, y: 1000, width: 500, height: 500))]
        let f = try Self.frames(column, windows, usable: above, portrait: true)
        Self.expectFrame(f[0], -500, 1500, 500, 500)
        Self.expectFrame(f[1], -500, 1200, 500, 300)
    }
}
