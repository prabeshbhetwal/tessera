import AppKit
import QuartzCore
import TesseraCore

/// A compact Ring receipt for completed shortcuts, separate from the interactive overlay session.
@MainActor
final class ShortcutReceipt {
    private var panel: NSPanel?
    private let material = NSVisualEffectView()
    private let canvas = NSView()
    private let resultGlyph = CAShapeLayer()
    private let resultFill = CAShapeLayer()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "Shortcut applied")
    private let symbol = NSImageView()
    private var task: Task<Void, Never>?

    func show(title text: String, action: WindowAction?, settings: TesseraSettings) {
        task?.cancel()
        let theme = settings.activeTheme
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: min(max(248, ceil(textWidth) + 102), min(420, visible.width - 24)), height: 82)
        let y: CGFloat = switch settings.hudPosition {
        case .bottom: visible.minY + visible.height * 0.18
        case .center: visible.midY - size.height / 2
        case .top: visible.maxY - visible.height * 0.18 - size.height
        }
        let frame = CGRect(x: visible.midX - size.width / 2, y: y, width: size.width, height: size.height)
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        panel.setFrame(frame, display: false)
        let bounds = CGRect(origin: .zero, size: size)
        material.frame = bounds
        material.appearance = NSAppearance(named: HexColor.isLight(theme.ring.fillHex) ? .aqua : .darkAqua)
        material.layer?.backgroundColor = HexColor.cgColor(theme.ring.fillHex,
            alpha: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.65)
        canvas.frame = bounds
        canvas.layer?.frame = bounds
        canvas.layer?.removeAllAnimations()
        canvas.layer?.opacity = 1
        material.layer?.removeAllAnimations()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let icon = CGRect(x: 29, y: 31, width: 30, height: 20)
        resultGlyph.path = action.map { _ in CGPath(roundedRect: icon, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil) }
        resultGlyph.strokeColor = HexColor.cgColor(theme.ring.strokeHex)
        resultGlyph.contentsScale = screen?.backingScaleFactor ?? 2
        resultFill.contentsScale = resultGlyph.contentsScale
        let inset = icon.insetBy(dx: 3, dy: 3)
        resultFill.path = action.map {
            let unit = RingLayer.unitRect($0)
            return CGPath(roundedRect: CGRect(x: inset.minX + unit.minX * inset.width, y: inset.minY + unit.minY * inset.height,
                                             width: unit.width * inset.width, height: unit.height * inset.height),
                          cornerWidth: 1, cornerHeight: 1, transform: nil)
        }
        resultFill.fillColor = HexColor.cgColor(theme.accentHex)
        CATransaction.commit()

        title.font = font
        title.stringValue = text
        title.textColor = NSColor(cgColor: HexColor.cgColor(theme.ring.strokeHex)) ?? .labelColor
        title.frame = CGRect(x: 88, y: 42, width: size.width - 104, height: 18)
        detail.textColor = title.textColor?.withAlphaComponent(0.7)
        detail.frame = CGRect(x: 88, y: 23, width: size.width - 104, height: 16)
        symbol.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Applied")
        symbol.isHidden = action != nil
        symbol.contentTintColor = title.textColor
        symbol.frame = CGRect(x: 36, y: 33, width: 16, height: 16)
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion, settings.preview.morph {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.12
            material.layer?.add(fade, forKey: "appear")
        }
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(settings.hudSeconds))
            guard !Task.isCancelled, let self else { return }
            self.panel?.orderOut(nil)
        }
    }

    func hide() {
        task?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = OverlayController.makePanel(frame: frame)
        panel.title = "Tessera shortcut confirmation"
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 18
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = CGColor(gray: 1, alpha: 0.18)
        canvas.wantsLayer = true
        canvas.layer = CALayer()
        resultGlyph.fillColor = nil
        resultGlyph.lineWidth = 1.5
        canvas.layer?.addSublayer(resultGlyph)
        canvas.layer?.addSublayer(resultFill)
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        panel.contentView?.addSubview(material)
        material.addSubview(canvas)
        material.addSubview(symbol)
        material.addSubview(title)
        material.addSubview(detail)
        return panel
    }
}
