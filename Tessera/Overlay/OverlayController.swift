import AppKit
import QuartzCore
import TesseraCore

/// Owns one reusable non-activating panel per display plus a HUD panel.
/// Every update is Core Animation only; nothing here touches SwiftUI or Accessibility.
@MainActor
final class OverlayController {
    /// Layers drawn on one display's panel. All coordinates are panel-local, AppKit orientation.
    @MainActor
    private final class Scene {
        let panel: NSPanel
        /// Cells outside the pointed span, faint.
        let grid = CAShapeLayer()
        /// Cells inside the pointed span, outlined in the accent colour on top of the preview.
        let gridActive = CAShapeLayer()
        var numbers: [CATextLayer] = []
        let preview = PreviewLayer()
        let ring = RingLayer()
        var gridKey: GridKey?

        init(frame: CGRect) {
            panel = OverlayController.makePanel(frame: frame)
            let root = panel.contentView?.layer
            root?.addSublayer(grid)
            root?.addSublayer(preview.root)
            root?.addSublayer(gridActive)
            root?.addSublayer(ring.root)
            grid.strokeColor = CGColor(gray: 1, alpha: 0.28)
            grid.fillColor = CGColor(gray: 1, alpha: 0.03)
            grid.lineWidth = 1
            gridActive.fillColor = nil
            gridActive.lineWidth = 2
        }

        /// Reuses text layers; extra ones are hidden, not removed.
        func numberLayer(_ i: Int) -> CATextLayer {
            while numbers.count <= i {
                let t = CATextLayer()
                t.font = OverlayController.numberFont
                t.fontSize = OverlayController.numberFont.pointSize
                t.alignmentMode = .center
                t.shadowColor = CGColor(gray: 0, alpha: 1)
                t.shadowOpacity = 0.7
                t.shadowRadius = 2
                t.shadowOffset = .zero
                gridActive.addSublayer(t)
                numbers.append(t)
            }
            return numbers[i]
        }

        var origin: CGPoint { panel.frame.origin }
        var bounds: CGRect { CGRect(origin: .zero, size: panel.frame.size) }
    }

    /// What the grid was last drawn for; redrawn only when the display or pointed span changes.
    private struct GridKey: Equatable {
        let display: DisplayContext
        let span: ColumnSpan
    }

    private var scenes: [DisplayID: Scene] = [:]
    private var theme: Theme = .default
    private var ring: RingSettings = .default
    private var hudPanel: NSPanel?
    private let hudPill = CALayer()
    private let hudText = CATextLayer()
    private var hudTask: Task<Void, Never>?

    private static let hudFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    fileprivate static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)

    init() {}

    // MARK: Session

    /// `origin` is the cursor at open time, in global AppKit coordinates. `theme.preview` supplies
    /// preview styling, so pass the user's current `PreviewSettings` inside the theme.
    func show(origin: CGPoint, displays: [DisplayContext], ring: RingSettings, theme: Theme) {
        self.theme = theme
        self.ring = ring
        let live = Set(displays.map(\.id))
        for (id, scene) in scenes where !live.contains(id) {
            scene.panel.close()
            scenes[id] = nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for display in displays {
            let screen = Self.screen(for: display)
            let frame = screen?.frame ?? display.visibleFrame
            let scale = screen?.backingScaleFactor ?? 2
            let scene = scenes[display.id] ?? Scene(frame: frame)
            scenes[display.id] = scene
            if scene.panel.frame != frame { scene.panel.setFrame(frame, display: false) }

            let bounds = scene.bounds
            for layer in [scene.grid, scene.gridActive] {
                layer.frame = bounds
                layer.contentsScale = scale
                layer.path = nil
            }
            for t in scene.numbers {
                t.contentsScale = scale
                t.isHidden = true
            }
            scene.gridActive.strokeColor = HexColor.cgColor(theme.accentHex)
            scene.gridKey = nil
            scene.preview.layout(bounds: bounds, scale: scale)
            scene.preview.clear()
            let center = CGPoint(x: origin.x - scene.origin.x, y: origin.y - scene.origin.y)
            scene.ring.configure(bounds: bounds, center: center, ring: ring, theme: theme, scale: scale)
            scene.panel.orderFrontRegardless()
        }
        CATransaction.commit()
    }

    /// Hot path: called on every mouse move while the menu is open.
    func update(
        selection: Selection, layers: PreviewLayers?, image: CGImage?,
        displays: [DisplayContext], pointMode: Bool, cancelling: Bool
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let activeWedge: Int? = switch selection {
        case .wedge(let index, _): index
        default: nil
        }
        let gridKey: GridKey? = switch selection {
        case .span(let id, let span) where pointMode: displays.first { $0.id == id }.map { GridKey(display: $0, span: span) }
        default: nil
        }
        let visibleLayers = selection == .none ? nil : layers
        let accent = HexColor.cgColor(theme.accentHex)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, scene) in scenes {
            scene.ring.setActive(activeWedge)
            scene.ring.setCancelling(cancelling)
            scene.ring.setPointMode(pointMode)
            updateGrid(scene, key: gridKey?.display.id == id ? gridKey : nil)
            if let visibleLayers {
                scene.preview.render(
                    visibleLayers, image: image, offset: scene.origin, style: theme.preview,
                    accent: accent, animate: visibleLayers.animate && !reduceMotion
                )
            } else {
                scene.preview.clear()
            }
        }
        CATransaction.commit()
    }

    func hide() {
        for scene in scenes.values {
            scene.panel.orderOut(nil)
            scene.preview.clear()
            scene.gridKey = nil
        }
    }

    // MARK: HUD

    /// Shows `text` near the bottom of the screen under the mouse, holds 1.2 s, then fades.
    func showHUD(_ text: String) {
        hudTask?.cancel()
        let size = (text as NSString).size(withAttributes: [.font: Self.hudFont])
        let padding = CGSize(width: 20, height: 10)
        let panelSize = CGSize(width: ceil(size.width) + padding.width * 2, height: ceil(size.height) + padding.height * 2)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: panelSize)
        let frame = CGRect(
            x: visible.midX - panelSize.width / 2, y: visible.minY + visible.height * 0.18,
            width: panelSize.width, height: panelSize.height
        )

        let panel = hudPanel ?? makeHUDPanel(frame: frame)
        hudPanel = panel
        panel.setFrame(frame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = screen?.backingScaleFactor ?? 2
        hudPill.frame = CGRect(origin: .zero, size: panelSize)
        hudPill.cornerRadius = panelSize.height / 2
        hudText.string = text
        hudText.frame = CGRect(x: padding.width, y: padding.height, width: ceil(size.width), height: ceil(size.height))
        hudPill.contentsScale = scale
        hudText.contentsScale = scale
        CATransaction.commit()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hudTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let panel = self?.hudPanel else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderOut(nil)
                return
            }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func makeHUDPanel(frame: CGRect) -> NSPanel {
        let panel = Self.makePanel(frame: frame)
        hudPill.backgroundColor = CGColor(gray: 0.1, alpha: 0.85)
        hudText.font = Self.hudFont
        hudText.fontSize = Self.hudFont.pointSize
        hudText.foregroundColor = CGColor(gray: 1, alpha: 1)
        hudText.alignmentMode = .center
        hudPill.addSublayer(hudText)
        panel.contentView?.layer?.addSublayer(hudPill)
        return panel
    }

    // MARK: Grid

    private func updateGrid(_ scene: Scene, key: GridKey?) {
        guard key != scene.gridKey else { return }
        scene.gridKey = key
        guard let key else {
            scene.grid.path = nil
            scene.gridActive.path = nil
            for t in scene.numbers { t.isHidden = true }
            return
        }
        let paths = Self.gridPaths(for: key.display, span: key.span, ring: ring, offset: scene.origin)
        scene.grid.path = paths.faint
        scene.gridActive.path = paths.active

        let columns = ring.showColumnNumbers ? paths.columns : []
        let accent = HexColor.cgColor(theme.accentHex)
        for (i, cell) in columns.enumerated() {
            let t = scene.numberLayer(i)
            let text = "\(i + 1)"
            if t.string as? String != text { t.string = text }
            t.foregroundColor = key.span.columns.contains(i) ? accent : CGColor(gray: 1, alpha: 0.75)
            let height = ceil(Self.numberFont.ascender - Self.numberFont.descender)
            t.frame = CGRect(x: cell.minX, y: cell.maxY - 12 - height, width: cell.width, height: height)
            t.isHidden = false
        }
        for t in scene.numbers.dropFirst(columns.count) { t.isHidden = true }
    }

    /// Faint cells outside `span` plus the top/bottom band split lines (landscape only; portrait spans
    /// ignore bands), the accent outlines of the cells inside `span`, and every full-height column
    /// rect (panel-local) for placing numbers.
    static func gridPaths(
        for display: DisplayContext, span: ColumnSpan, ring: RingSettings, offset: CGPoint
    ) -> (faint: CGPath, active: CGPath, columns: [CGRect]) {
        let faint = CGMutablePath()
        let active = CGMutablePath()
        var columns: [CGRect] = []
        for c in 0..<max(1, display.profile.columns) {
            let cell = GridGeometry.frame(for: ColumnSpan(columns: c...c, band: .full), display: display)
                .offsetBy(dx: -offset.x, dy: -offset.y)
            columns.append(cell)
            if span.columns.contains(c) {
                let picked = GridGeometry.frame(for: ColumnSpan(columns: c...c, band: span.band), display: display)
                active.addRect(picked.offsetBy(dx: -offset.x, dy: -offset.y))
            } else {
                faint.addRect(cell)
            }
        }
        if !display.range.isPortrait {
            let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
            let visible = display.visibleFrame
            for y in [visible.maxY - visible.height * CGFloat(ring.topBand), visible.minY + visible.height * CGFloat(ring.bottomBand)] {
                faint.move(to: CGPoint(x: usable.minX - offset.x, y: y - offset.y))
                faint.addLine(to: CGPoint(x: usable.maxX - offset.x, y: y - offset.y))
            }
        }
        return (faint, active, columns)
    }

    // MARK: Panels

    private static func screen(for display: DisplayContext) -> NSScreen? {
        let center = CGPoint(x: display.visibleFrame.midX, y: display.visibleFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    static func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false  // Tessera is an accessory app and is never active.
        panel.animationBehavior = .none
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.layer = CALayer()
        view.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return panel
    }
}
