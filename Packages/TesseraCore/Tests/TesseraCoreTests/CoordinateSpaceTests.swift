import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct CoordinateSpaceTests {
    /// Primary MacBook, 1512x982, origin (0,0). AX/CG y is measured down from the primary's top-left.
    static let primaryHeight: CGFloat = 982

    @Test func chg90RightOfMacBook() {
        // Top-aligned with the MacBook: AppKit bottom is 982 - 1080, AX top is 0.
        let appKit = CGRect(x: 1512, y: -98, width: 3840, height: 1080)
        let ax = CoordinateSpace.toAX(appKit, primaryHeight: Self.primaryHeight)
        #expect(ax == CGRect(x: 1512, y: 0, width: 3840, height: 1080))
        #expect(CoordinateSpace.fromAX(ax, primaryHeight: Self.primaryHeight) == appKit)
    }

    @Test func chg90AboveMacBook() {
        // Entirely above the primary: AppKit y >= 982, AX y is negative.
        let appKit = CGRect(x: -1164, y: 982, width: 3840, height: 1080)
        let ax = CoordinateSpace.toAX(appKit, primaryHeight: Self.primaryHeight)
        #expect(ax == CGRect(x: -1164, y: -1080, width: 3840, height: 1080))
        #expect(CoordinateSpace.fromAX(ax, primaryHeight: Self.primaryHeight) == appKit)
    }

    @Test func portraitScreenLeftOfMacBook() {
        // Negative x; 2560 tall and bottom-aligned with the MacBook, so it extends above it (negative AX y).
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 2560)
        #expect(CoordinateSpace.toAX(screen, primaryHeight: Self.primaryHeight)
                == CGRect(x: -1440, y: -1578, width: 1440, height: 2560))
        // A window near the top of that screen.
        let window = CGRect(x: -1400, y: 2000, width: 600, height: 400)
        #expect(CoordinateSpace.toAX(window, primaryHeight: Self.primaryHeight)
                == CGRect(x: -1400, y: -1418, width: 600, height: 400))
    }

    @Test func primaryScreenItselfFlipsAboutItsHeight() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(CoordinateSpace.toAX(primary, primaryHeight: Self.primaryHeight) == primary)
        // Bottom-left window in AppKit is bottom-left in AX too (y = 982 - h).
        let w = CGRect(x: 10, y: 0, width: 300, height: 200)
        #expect(CoordinateSpace.toAX(w, primaryHeight: Self.primaryHeight).origin == CGPoint(x: 10, y: 782))
    }

    @Test func pointFromCG() {
        let p = CoordinateSpace.pointFromCG(CGPoint(x: 100, y: 50), primaryHeight: Self.primaryHeight)
        #expect(p == CGPoint(x: 100, y: 932))
        // Above the primary: CG y negative -> AppKit y beyond primaryHeight.
        #expect(CoordinateSpace.pointFromCG(CGPoint(x: 0, y: -10), primaryHeight: Self.primaryHeight).y == 992)
    }

    @Test(arguments: [
        CGRect(x: 1512, y: -98, width: 3840, height: 1080),
        CGRect(x: -1164, y: 982, width: 3840, height: 1080),
        CGRect(x: -1440, y: 0, width: 1440, height: 2560),
        CGRect(x: 12.5, y: 33.25, width: 640.75, height: 480.125),
        CGRect(x: 0, y: 0, width: 0, height: 0),
    ])
    func roundTrip(_ r: CGRect) {
        for h in [CGFloat(982), 1117, 0] {
            #expect(CoordinateSpace.fromAX(CoordinateSpace.toAX(r, primaryHeight: h), primaryHeight: h) == r)
            #expect(CoordinateSpace.toAX(CoordinateSpace.fromAX(r, primaryHeight: h), primaryHeight: h) == r)
        }
    }

    @Test func pointRoundTripThroughCGMatchesRectCorner() {
        // The cursor at the top-left corner of a rect, seen through both conversions, must agree.
        let appKit = CGRect(x: 200, y: 100, width: 300, height: 200)
        let ax = CoordinateSpace.toAX(appKit, primaryHeight: Self.primaryHeight)
        let cursorAppKit = CoordinateSpace.pointFromCG(ax.origin, primaryHeight: Self.primaryHeight)
        #expect(cursorAppKit == CGPoint(x: appKit.minX, y: appKit.maxY))
    }
}
