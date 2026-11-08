import AppKit
import TesseraCore

extension MenuBarIcon {
    /// The menu bar picture as a template image, so it follows light, dark and tinted menu bars.
    ///
    /// `paused` cuts a pause disc into the bottom-right corner (hotkeys off) and `updateWaiting` a dot into the
    /// top-right, so the chosen picture always shows and each state stays recognisable in one colour.
    func image(paused: Bool = false, updateWaiting: Bool = false) -> NSImage {
        let icon = self
        // AppKit may run the handler on any thread, so it captures only values.
        let image = NSImage(size: NSSize(width: MenuBarGlyph.side, height: MenuBarGlyph.side), flipped: false) { @Sendable _ in
            MenuBarGlyph.draw(icon)
            if updateWaiting { MenuBarGlyph.updateDot() }
            if paused { MenuBarGlyph.pauseDisc() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = (["Tessera"] + (paused ? ["hotkeys off"] : [])
            + (updateWaiting ? ["update available"] : [])).joined(separator: ", ")
        return image
    }
}

/// Tessera's own menu bar glyphs: flat tiles in the app icon's language, no SF Symbols.
///
/// Drawn on an 18 × 18 pt canvas, y up. Every tile edge sits on a whole point and gaps are 2 pt, so the glyphs stay
/// sharp on 1x displays as well as Retina.
enum MenuBarGlyph {
    static let side: CGFloat = 18

    static func draw(_ icon: MenuBarIcon) {
        switch icon {
        case .tiles:
            for tile in grid(cols: 3, rows: 2, x: 1, y: 4, size: 4, gap: 2) { fill(tile, radius: 1) }
        case .badge:
            fill(NSRect(x: 0, y: 2, width: 18, height: 13), radius: 3.2)
            for tile in grid(cols: 3, rows: 2, x: 2, y: 4, size: 4, gap: 1) { cut(tile, radius: 0.8) }
        case .slot:
            for tile in grid(cols: 3, rows: 2, x: 1, y: 4, size: 4, gap: 2) { fill(tile, radius: 1) }
            // The last tile is left open: a slot waiting for a window.
            cut(NSRect(x: 14, y: 5, width: 2, height: 2), radius: 0.3)
        case .mosaic:
            for tile in [NSRect(x: 1, y: 3, width: 6, height: 12), NSRect(x: 9, y: 10, width: 8, height: 5),
                         NSRect(x: 9, y: 3, width: 3, height: 5), NSRect(x: 14, y: 3, width: 3, height: 5)] {
                fill(tile, radius: 1)
            }
        case .ring:
            ring()
        case .split:
            for tile in [NSRect(x: 1, y: 3, width: 8, height: 12), NSRect(x: 11, y: 10, width: 6, height: 5),
                         NSRect(x: 11, y: 3, width: 6, height: 5)] {
                fill(tile, radius: 1)
            }
        case .columns:
            for column in 0..<3 { fill(NSRect(x: 1 + CGFloat(column) * 6, y: 3, width: 4, height: 12), radius: 1) }
        case .quarters:
            for tile in grid(cols: 2, rows: 2, x: 3, y: 3, size: 5, gap: 2) { fill(tile, radius: 1.2) }
        }
    }

    /// Hotkeys off: a disc with two bars cut out, in the bottom-right corner.
    static func pauseDisc() {
        let disc = NSRect(x: side - 8, y: 0, width: 8, height: 8)
        cut(NSBezierPath(ovalIn: disc.insetBy(dx: -1.2, dy: -1.2)))
        fill(NSBezierPath(ovalIn: disc))
        for x in [disc.midX - 2.2, disc.midX + 0.6] { cut(NSRect(x: x, y: disc.midY - 2, width: 1.6, height: 4), radius: 0.4) }
    }

    /// An update is waiting: a dot in the top-right corner.
    static func updateDot() {
        let dot = NSRect(x: side - 6, y: side - 6, width: 6, height: 6)
        cut(NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)))
        fill(NSBezierPath(ovalIn: dot))
    }

    /// The snap ring: eight wedges round a centre dot, split where the ring's directions meet.
    private static func ring() {
        let centre = side / 2
        let band = NSBezierPath(ovalIn: NSRect(x: centre - 8.4, y: centre - 8.4, width: 16.8, height: 16.8))
        band.append(NSBezierPath(ovalIn: NSRect(x: centre - 4.8, y: centre - 4.8, width: 9.6, height: 9.6)).reversed)
        fill(band)
        for wedge in 0..<8 {
            let split = NSBezierPath(rect: NSRect(x: 0, y: -0.8, width: 10, height: 1.6))
            var turn = AffineTransform(translationByX: centre, byY: centre)
            turn.rotate(byDegrees: CGFloat(wedge) * 45 + 22.5)
            split.transform(using: turn)
            cut(split)
        }
        fill(NSBezierPath(ovalIn: NSRect(x: centre - 1.8, y: centre - 1.8, width: 3.6, height: 3.6)))
    }

    /// Square tiles, left to right then top to bottom, from the bottom-left corner of the block.
    private static func grid(cols: Int, rows: Int, x: CGFloat, y: CGFloat, size: CGFloat, gap: CGFloat) -> [NSRect] {
        (0..<rows).flatMap { row in
            (0..<cols).map { col in
                NSRect(x: x + CGFloat(col) * (size + gap), y: y + CGFloat(rows - 1 - row) * (size + gap),
                       width: size, height: size)
            }
        }
    }

    private static func fill(_ rect: NSRect, radius: CGFloat) {
        fill(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius))
    }

    private static func fill(_ path: NSBezierPath) {
        NSColor.black.setFill()
        path.fill()
    }

    private static func cut(_ rect: NSRect, radius: CGFloat) {
        cut(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius))
    }

    /// Clears to transparent, so a cut-out reads as a gap in any menu bar colour.
    private static func cut(_ path: NSBezierPath) {
        let context = NSGraphicsContext.current
        context?.compositingOperation = .clear
        path.fill()
        context?.compositingOperation = .sourceOver
    }
}
