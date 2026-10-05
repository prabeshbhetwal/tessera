import AppKit
import QuartzCore
import TesseraCore

/// Compile with the production overlay files and the TesseraCore SwiftPM objects.
/// Offscreen rendering verifies real drawing code without Accessibility or changing desktop windows.
@main
struct VerifyRingRendering {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sheet = CALayer()
        sheet.frame = CGRect(x: 0, y: 0, width: 960, height: 560)
        let display = DisplayID(vendor: 1, model: 1, serial: 1, uuid: nil)
        var light = Theme.default
        light.ring.fillHex = "#EEF0F4"
        light.ring.strokeHex = "#242831"
        light.labelHex = "#F6F7FA"
        light.labelTextHex = "#242831"
        light.accentHex = "#007AFF"
        let states: [(String, Selection, Bool)] = [
            ("READY", .none, false),
            ("DIRECTION", .wedge(index: 2, action: .rightHalf), false),
            ("KEYBOARD", .span(display: display, span: ColumnSpan(columns: 1...2, band: .top)), true),
        ]
        var checked = 0
        for (row, theme) in [Theme.default, light].enumerated() {
            for (column, state) in states.enumerated() {
                let cell = CALayer()
                cell.frame = CGRect(x: column * 320, y: (1 - row) * 280, width: 320, height: 280)
                cell.backgroundColor = HexColor.cgColor(row == 0 ? "#252830" : "#E2E5EB")
                sheet.addSublayer(cell)
                let name = CATextLayer()
                name.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                name.fontSize = 11
                name.foregroundColor = HexColor.cgColor(theme.ring.strokeHex, alpha: 0.7)
                name.string = state.0
                name.alignmentMode = .center
                name.contentsScale = 2
                name.frame = CGRect(x: 0, y: 250, width: 320, height: 18)
                cell.addSublayer(name)
                let ring = RingSettings.default
                let center = CGPoint(x: 160, y: 167)
                // The live app uses NSVisualEffectView; this image uses an opaque material stand-in.
                let backing = CAShapeLayer()
                backing.path = RingGeometry.path(center: center, ring: ring)
                backing.fillColor = HexColor.cgColor(theme.ring.fillHex)
                cell.addSublayer(backing)
                let dial = RingLayer()
                dial.configure(bounds: cell.bounds, center: center, ring: ring, theme: theme, scale: 2)
                if case let .wedge(index, _) = state.1 { dial.setActive(index) }
                if case let .span(_, span) = state.1 { dial.setSpan(span, columns: 4) }
                dial.setCancelling(state.1 == .none)
                dial.setPointMode(state.2)
                cell.addSublayer(dial.root)
                let caption = RingCaptionLayer()
                caption.configure(bounds: cell.bounds, center: center, ring: ring, theme: theme, scale: 2)
                caption.render(.make(selection: state.1, ring: ring, keyboard: state.2,
                                     keyboardEnabled: true, tapToTile: false, cancelling: false))
                cell.addSublayer(caption.root)
                assertCaptionInside(caption, bounds: cell.bounds)
                checked += 1
            }
        }
        // Edge anchoring, non-origin displays, hidden labels and unusual configured ring sizes.
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        for center in [CGPoint(x: 2, y: 2), CGPoint(x: 798, y: 598), CGPoint(x: 400, y: 30)] {
            for radius in [20.0, 50, 140] {
                var ring = RingSettings.default
                ring.radius = radius
                let caption = RingCaptionLayer()
                caption.configure(bounds: bounds, center: center, ring: ring, theme: .default, scale: 2)
                caption.render(.make(selection: .none, ring: ring, keyboard: false,
                                     keyboardEnabled: true, tapToTile: false, cancelling: true))
                assertCaptionInside(caption, bounds: bounds)
                checked += 1
            }
        }
        let hidden = RingCaptionLayer()
        hidden.configure(bounds: bounds, center: CGPoint(x: -400, y: 300), ring: .default, theme: .default, scale: 2)
        precondition(hidden.root.isHidden, "A non-origin display must not show a stray caption")
        for radius in [20.0, 50, 140] {
            for thickness in [1.0, 22, 100] {
                var ring = RingSettings.default
                ring.radius = radius; ring.thickness = thickness
                for index in 0..<8 {
                    let path = RingGeometry.tilePath(index: index, center: .zero, ring: ring)
                    precondition(!path.boundingBox.isNull && path.boundingBox.width.isFinite)
                    checked += 1
                }
            }
        }
        CATransaction.commit()
        // Layout targets must correspond to the actual gesture directions, with no overlapping tiles.
        let ring = RingSettings.default
        let engine = SelectionEngine(ring: ring)
        for i in 0..<8 {
            let tile = RingGeometry.tileRect(index: i, center: .zero, ring: ring)
            let selection = engine.select(origin: .zero, cursor: CGPoint(x: tile.midX, y: tile.midY), displays: [], anchor: nil)
            precondition(selection == .wedge(index: i, action: ring.wedges[i]), "Tile and gesture direction disagree")
            for j in (i + 1)..<8 {
                precondition(!tile.intersects(RingGeometry.tileRect(index: j, center: .zero, ring: ring)), "Layout tiles overlap")
                checked += 1
            }
            checked += 1
        }
        let transition = RingLayer()
        transition.configure(bounds: bounds, center: CGPoint(x: 400, y: 300), ring: ring, theme: .default, scale: 2)
        transition.setSpan(ColumnSpan(columns: 1...2, band: .top), columns: 4)
        precondition(named("destination-preview", in: transition.root)?.path != nil)
        precondition(!namedLayer("column-preview", in: transition.root)!.isHidden)
        transition.setActive(nil)
        precondition(named("destination-preview", in: transition.root)?.path == nil, "Returning to centre kept a stale destination")
        transition.setActive(2)
        precondition(named("destination-preview", in: transition.root)?.path != nil)
        precondition(namedLayer("column-preview", in: transition.root)!.isHidden, "Direction selection drew a centre card")
        transition.setSpan(ColumnSpan(columns: 0...0, band: .full), columns: 3, portrait: true)
        precondition(named("destination-preview", in: transition.root)!.path!.boundingBox.height > 0)
        transition.setActive(nil)
        precondition(named("destination-preview", in: transition.root)?.path == nil)
        checked += 7
        let output = CommandLine.arguments.dropFirst().first ?? "/tmp/tessera-ring-redesign-preview.png"
        let context = CGContext(data: nil, width: 1920, height: 1120, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        sheet.render(in: context)
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        print("Passed \(checked + 1) production-layer rendering/geometry checks. Preview: \(output)")
    }

    @MainActor private static func assertCaptionInside(_ caption: RingCaptionLayer, bounds: CGRect) {
        let frame = caption.root.sublayers!.first!.frame
        precondition(bounds.contains(frame), "Caption clipped at \(frame)")
    }

    @MainActor private static func named(_ name: String, in layer: CALayer) -> CAShapeLayer? {
        if layer.name == name { return layer as? CAShapeLayer }
        return layer.sublayers?.compactMap { named(name, in: $0) }.first
    }

    @MainActor private static func namedLayer(_ name: String, in layer: CALayer) -> CALayer? {
        if layer.name == name { return layer }
        return layer.sublayers?.compactMap { namedLayer(name, in: $0) }.first
    }
}
