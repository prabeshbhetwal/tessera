import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct PreviewModelTests {
    private let display = DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil)

    private func input(
        target: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
        current: CGRect? = nil,
        neighbours: [CGRect] = [],
        selection: Selection = .wedge(index: 6, action: .leftHalf),
        reduceMotion: Bool = false
    ) -> PreviewInput {
        PreviewInput(
            target: target, current: current, neighbours: neighbours,
            selection: selection, reduceMotion: reduceMotion
        )
    }

    // MARK: Label

    @Test func testLabelFlick() {
        let label = PreviewModel.label(
            for: .wedge(index: 6, action: .leftHalf),
            frame: CGRect(x: 0, y: 0, width: 756, height: 949)
        )
        #expect(label == "756 × 949 · Left half")
    }

    @Test func testLabelParts() {
        let frame = CGRect(x: 0, y: 0, width: 756, height: 949)
        let wedge = Selection.wedge(index: 6, action: .leftHalf)
        #expect(PreviewModel.label(for: wedge, frame: frame, size: true, slot: false) == "756 × 949")
        #expect(PreviewModel.label(for: wedge, frame: frame, size: false, slot: true) == "Left half")
        #expect(PreviewModel.label(for: wedge, frame: frame, size: false, slot: false) == nil)

        var settings = PreviewSettings()
        settings.labelShowsSlot = false
        #expect(PreviewModel.layers(input(target: frame), settings: settings).label == "756 × 949")
    }

    @Test func testOutlineAndDimAreIndependent() {
        let current = CGRect(x: 10, y: 10, width: 50, height: 50)
        let covered = CGRect(x: 0, y: 0, width: 80, height: 80)
        var settings = PreviewSettings()
        settings.showNeighbours = false
        var layers = PreviewModel.layers(input(current: current, neighbours: [covered]), settings: settings)
        #expect(layers.dimRects.isEmpty && layers.fromOutline == current)

        settings.showNeighbours = true
        settings.showOutline = false
        layers = PreviewModel.layers(input(current: current, neighbours: [covered]), settings: settings)
        #expect(layers.dimRects == [covered] && layers.fromOutline == nil)
    }

    @Test func testLabelRoundsToNearestPoint() {
        let label = PreviewModel.label(
            for: .wedge(index: 0, action: .maximize),
            frame: CGRect(x: 0, y: 0, width: 755.6, height: 948.4)
        )
        #expect(label == "756 × 948 · Maximise")
    }

    @Test(arguments: [
        (Band.top, "1280 × 1047 · cols 2–3 · top"),
        (Band.bottom, "1280 × 1047 · cols 2–3 · bottom"),
        (Band.full, "1280 × 1047 · cols 2–3"),
    ])
    func testLabelSpan(band: Band, expected: String) {
        let span = ColumnSpan(columns: 1...2, band: band)
        let label = PreviewModel.label(
            for: .span(display: display, span: span),
            frame: CGRect(x: 0, y: 0, width: 1280, height: 1047)
        )
        #expect(label == expected)
        #expect(label?.contains("\u{2013}") == true, "must use an en dash")
    }

    @Test func testLabelSingleCol() {
        let frame = CGRect(x: 0, y: 0, width: 756, height: 1047)
        let full = PreviewModel.label(
            for: .span(display: display, span: ColumnSpan(columns: 2...2, band: .full)), frame: frame
        )
        let bottom = PreviewModel.label(
            for: .span(display: display, span: ColumnSpan(columns: 0...0, band: .bottom)), frame: frame
        )
        #expect(full == "756 × 1047 · col 3")
        #expect(bottom == "756 × 1047 · col 1 · bottom")
    }

    @Test func testLabelNoneIsNil() {
        #expect(PreviewModel.label(for: .none, frame: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }

    @Test func testLabelNonFiniteFrameIsNil() {
        let bad = CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)
        #expect(PreviewModel.label(for: .wedge(index: 0, action: .maximize), frame: bad) == nil)
    }

    // MARK: Neighbour dimming

    @Test func testDimThreshold() {
        let target = CGRect(x: 0, y: 0, width: 100, height: 100)
        let exactlyTwentyPercent = CGRect(x: 80, y: 0, width: 100, height: 100) // overlap 20x100 of 100x100
        let justOver = CGRect(x: 79.9, y: 0, width: 100, height: 100)
        let layers = PreviewModel.layers(
            input(target: target, neighbours: [exactlyTwentyPercent, justOver]),
            settings: PreviewSettings()
        )
        #expect(layers.dimRects == [justOver])
    }

    @Test func testDimUsesNeighbourOwnArea() {
        // The target is fully covered by this huge window, but that is a tiny share of the window itself.
        let huge = CGRect(x: -500, y: -500, width: 1000, height: 1000)
        let disjoint = CGRect(x: 500, y: 500, width: 50, height: 50)
        let touching = CGRect(x: 100, y: 0, width: 50, height: 50)
        let zeroArea = CGRect(x: 10, y: 10, width: 0, height: 0)
        let layers = PreviewModel.layers(
            input(neighbours: [huge, disjoint, touching, zeroArea]),
            settings: PreviewSettings()
        )
        #expect(layers.dimRects.isEmpty)
    }

    @Test func testFullyCoveredNeighbourIsDimmed() {
        let inside = CGRect(x: 10, y: 10, width: 20, height: 20)
        let layers = PreviewModel.layers(input(neighbours: [inside]), settings: PreviewSettings())
        #expect(layers.dimRects == [inside])
    }

    // MARK: From outline and frame

    @Test func testFromOutlineAndFrame() {
        let current = CGRect(x: 5, y: 5, width: 40, height: 40)
        let target = CGRect(x: 0, y: 0, width: 756, height: 949)
        let layers = PreviewModel.layers(input(target: target, current: current), settings: PreviewSettings())
        #expect(layers.frame == target)
        #expect(layers.fromOutline == current)
        #expect(layers.label == "756 × 949 · Left half")
        #expect(layers.showThumbnail)

        let none = PreviewModel.layers(input(current: nil), settings: PreviewSettings())
        #expect(none.fromOutline == nil)
    }

    // MARK: Switches

    @Test func testLayersOff() {
        var s = PreviewSettings()
        s.showThumbnail = false
        s.showLabel = false
        s.showNeighbours = false
        s.showOutline = false
        s.morph = false
        let layers = PreviewModel.layers(
            input(
                current: CGRect(x: 1, y: 1, width: 10, height: 10),
                neighbours: [CGRect(x: 10, y: 10, width: 20, height: 20)]
            ),
            settings: s
        )
        #expect(layers.label == nil)
        #expect(layers.dimRects.isEmpty)
        #expect(layers.fromOutline == nil)
        #expect(layers.showThumbnail == false)
        #expect(layers.animate == false)
    }

    @Test func testEachSwitchIndependent() {
        let current = CGRect(x: 1, y: 1, width: 10, height: 10)
        let neighbour = CGRect(x: 10, y: 10, width: 20, height: 20)
        let i = input(current: current, neighbours: [neighbour])

        var s = animated()
        s.showLabel = false
        var l = PreviewModel.layers(i, settings: s)
        #expect(l.label == nil && l.fromOutline == current && l.dimRects == [neighbour] && l.showThumbnail && l.animate)

        s = animated()
        s.showNeighbours = false
        l = PreviewModel.layers(i, settings: s)
        #expect(l.label != nil && l.fromOutline == current && l.dimRects.isEmpty && l.showThumbnail && l.animate)

        s = animated()
        s.showOutline = false
        l = PreviewModel.layers(i, settings: s)
        #expect(l.label != nil && l.fromOutline == nil && l.dimRects == [neighbour] && l.showThumbnail && l.animate)

        s = animated()
        s.showThumbnail = false
        l = PreviewModel.layers(i, settings: s)
        #expect(l.label != nil && l.fromOutline == current && l.dimRects == [neighbour] && !l.showThumbnail && l.animate)
    }

    // MARK: Animation

    @Test func testReduceMotionDisablesAnimate() {
        let s = animated()
        #expect(PreviewModel.layers(input(reduceMotion: false), settings: s).animate)
        #expect(PreviewModel.layers(input(reduceMotion: true), settings: s).animate == false)
    }

    @Test func testZeroResponseDisablesAnimate() {
        var s = PreviewSettings()
        s.springResponse = 0
        let layers = PreviewModel.layers(input(), settings: s)
        #expect(layers.animate == false)
        #expect(layers.springResponse == 0)
    }

    @Test func testSpringResponseClampedToRange() {
        var s = PreviewSettings()
        s.springResponse = 5
        #expect(PreviewModel.layers(input(), settings: s).springResponse == 0.4)
        s.springResponse = -1
        let negative = PreviewModel.layers(input(), settings: s)
        #expect(negative.springResponse == 0)
        #expect(negative.animate == false)
        s.springResponse = .nan
        #expect(PreviewModel.layers(input(), settings: s).animate == false)
    }

    @Test func testDefaultSpringResponsePassesThrough() {
        #expect(PreviewModel.layers(input(), settings: PreviewSettings()).springResponse == 0.1)
    }

    /// The glide is off by default so the preview tracks the cursor with no delay.
    @Test func testNoGlideByDefault() {
        #expect(PreviewModel.layers(input(), settings: PreviewSettings()).animate == false)
    }

    /// Default settings with the glide turned on, for tests about animation.
    private func animated() -> PreviewSettings {
        var s = PreviewSettings()
        s.morph = true
        return s
    }
}
