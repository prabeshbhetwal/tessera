import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct CoachGeometryTests {
    static let screen = CGRect(x: 0, y: 0, width: 3840, height: 1080)

    @Test func seamBetweenSideBySide() throws {
        let frames = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1928, y: 0, width: 1912, height: 1080)]
        let seam = try #require(CoachGeometry.seam(frames, portrait: false, gap: 8))
        #expect(seam.midX == 1924)
        #expect(seam.width == 8)
        #expect(seam.height == 1080)
    }

    @Test func seamNilWhenApart() {
        let frames = [CGRect(x: 0, y: 0, width: 1000, height: 1080), CGRect(x: 1500, y: 0, width: 1000, height: 1080)]
        #expect(CoachGeometry.seam(frames, portrait: false, gap: 8) == nil)
        #expect(CoachGeometry.seam([frames[0]], portrait: false, gap: 8) == nil)
    }

    @Test func seamPortraitIsHorizontal() throws {
        let frames = [CGRect(x: 0, y: 1008, width: 1080, height: 912), CGRect(x: 0, y: 0, width: 1080, height: 1000)]
        let seam = try #require(CoachGeometry.seam(frames, portrait: true, gap: 8))
        #expect(seam.midY == 1004)
        #expect(seam.height == 8)
        #expect(seam.width == 1080)
    }

    @Test func cardStaysInsideScreen() {
        let target = CGRect(x: 3540, y: 0, width: 300, height: 200)
        let size = CGSize(width: 320, height: 160)
        let card = CGRect(origin: CoachGeometry.cardOrigin(size: size, target: target, screen: Self.screen), size: size)
        #expect(card.minX >= 12 && card.minY >= 12)
        #expect(card.maxX <= Self.screen.maxX - 12 && card.maxY <= Self.screen.maxY - 12)
    }

    @Test func cardPrefersBelow() {
        let target = CGRect(x: 1000, y: 600, width: 400, height: 300)
        let size = CGSize(width: 320, height: 160)
        let origin = CoachGeometry.cardOrigin(size: size, target: target, screen: Self.screen)
        #expect(origin.x == target.midX - 160)
        #expect(origin.y == target.minY - 12 - 160)
    }
}
