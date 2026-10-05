import AppKit
import QuartzCore
import TesseraCore

/// Owns one reusable non-activating panel per display plus a HUD panel.
///
/// Each display panel is two views: a vibrant material cut to the ring's shape (the same `NSVisualEffectView`
/// the system uses for HUDs, so the ring picks up whatever is behind it), and a layer-hosting canvas above it
/// for the grid, the preview and the ring's paint. The hot path (`update`) is Core Animation only.
@MainActor
final class OverlayController {
    /// Layers drawn on one display's panel. All coordinates are panel-local, AppKit orientation.
    @MainActor
    private final class Scene {
        let panel: NSPanel
        let material = NSVisualEffectView()
        let canvas = NSView()
        let gridHalo = CAShapeLayer()
        /// Cells outside the pointed span, faint.
        let grid = CAShapeLayer()
        /// Cells inside the pointed span, outlined in the accent colour on top of the preview.
        let gridActive = CAShapeLayer()
        var numbers: [CATextLayer] = []
        let preview = PreviewLayer()
        let ring = RingLayer()
        let caption = RingCaptionLayer()
        var gridKey: GridKey?

        init(frame: CGRect) {
            panel = OverlayController.makePanel(frame: frame)
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.isHidden = true
            canvas.wantsLayer = true
            canvas.layer = CALayer()
            canvas.autoresizingMask = [.width, .height]
            canvas.frame = CGRect(origin: .zero, size: frame.size)
            panel.contentView?.addSubview(material)
            panel.contentView?.addSubview(canvas)
            let root = canvas.layer
            root?.addSublayer(gridHalo)
            root?.addSublayer(grid)
            root?.addSublayer(preview.root)
            root?.addSublayer(gridActive)
            root?.addSublayer(ring.root)
            root?.addSublayer(caption.root)
            // A dark halo under every light stroke keeps the grid legible on light wallpapers.
            gridHalo.strokeColor = CGColor(gray: 0, alpha: 0.3)
            gridHalo.fillColor = nil
            gridHalo.lineWidth = 3
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
    private let hudMaterial = NSVisualEffectView()
    private let hudText = NSTextField(labelWithString: "")
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
            for layer in [scene.grid, scene.gridHalo, scene.gridActive] {
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
            scene.caption.configure(bounds: bounds, center: center, ring: ring, theme: theme, scale: scale)
            Self.layoutMaterial(scene.material, center: center, ring: ring, theme: theme)
            // Cells outside the pointed span stay faint; the picked ones are outlined in the accent colour.
            scene.grid.strokeColor = HexColor.cgColor(theme.ring.gridHex, alpha: 0.28)
            scene.grid.fillColor = HexColor.cgColor(theme.ring.gridHex, alpha: 0.03)
            // A dark grid colour gets a light halo, a light one a dark halo.
            scene.gridHalo.strokeColor = CGColor(gray: HexColor.isLight(theme.ring.gridHex) ? 0 : 1, alpha: 0.3)
            scene.panel.orderFrontRegardless()
        }
        CATransaction.commit()
    }

    /// Hot path: called on every mouse move while the menu is open.
    func update(
        selection: Selection, layers: PreviewLayers?, image: CGImage?,
        displays: [DisplayContext], pointMode: Bool, cancelling: Bool,
        keyboard: Bool = false, keyboardEnabled: Bool = true, tapToTile: Bool = false, hasMoved: Bool = false
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let activeWedge: Int? = switch selection {
        case .wedge(let index, _): index
        default: nil
        }
        let gridKey: GridKey? = switch selection {
        case .span(let id, let span) where pointMode && ring.showGrid:
            displays.first { $0.id == id }.map { GridKey(display: $0, span: span) }
        default: nil
        }
        let visibleLayers = selection == .none ? nil : layers

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, scene) in scenes {
            if case let .span(displayID, span) = selection, let display = displays.first(where: { $0.id == displayID }) {
                scene.ring.setSpan(span, columns: display.profile.columns, portrait: display.range.isPortrait)
            } else { scene.ring.setActive(activeWedge) }
            scene.ring.setCancelling(cancelling)
            scene.ring.setPointMode(pointMode)
            scene.caption.render(RingFeedback.make(selection: selection, ring: ring, keyboard: keyboard,
                                                  keyboardEnabled: keyboardEnabled, tapToTile: tapToTile,
                                                  cancelling: cancelling && hasMoved))
            scene.material.alphaValue = pointMode ? 0.35 : 1
            updateGrid(scene, key: gridKey?.display.id == id ? gridKey : nil)
            // Only the display the preview is on draws it; the others just keep theirs cleared.
            if let visibleLayers, scene.panel.frame.intersects(visibleLayers.frame) {
                scene.preview.render(
                    visibleLayers, image: image, offset: scene.origin, style: theme.preview,
                    theme: theme, animate: visibleLayers.animate && !reduceMotion
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
            scene.material.isHidden = true
        }
    }

    // MARK: HUD

    /// Shows `text` on the screen under the mouse at `position`, holds it `seconds`, then fades.
    func showHUD(_ text: String, position: HUDPosition = .bottom, seconds: Double = 1.2) {
        hudTask?.cancel()
        hudText.stringValue = text
        hudText.sizeToFit()
        let padding = CGSize(width: 20, height: 10)
        let textSize = hudText.frame.size
        let panelSize = CGSize(width: ceil(textSize.width) + padding.width * 2, height: ceil(textSize.height) + padding.height * 2)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: panelSize)
        let y: CGFloat = switch position {
        case .bottom: visible.minY + visible.height * 0.18
        case .center: visible.midY - panelSize.height / 2
        case .top: visible.maxY - visible.height * 0.18 - panelSize.height
        }
        let frame = CGRect(
            x: visible.midX - panelSize.width / 2, y: y,
            width: panelSize.width, height: panelSize.height
        )

        let panel = hudPanel ?? makeHUDPanel(frame: frame)
        hudPanel = panel
        panel.setFrame(frame, display: false)
        hudMaterial.frame = CGRect(origin: .zero, size: panelSize)
        hudMaterial.maskImage = Self.capsuleMask(size: panelSize)
        hudText.frame = CGRect(origin: CGPoint(x: padding.width, y: padding.height), size: textSize)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hudTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
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
        hudMaterial.material = .hudWindow
        hudMaterial.blendingMode = .behindWindow
        hudMaterial.state = .active
        hudMaterial.appearance = NSAppearance(named: .darkAqua)
        hudText.font = Self.hudFont
        hudText.textColor = .labelColor
        hudText.alignment = .center
        hudMaterial.addSubview(hudText)
        panel.contentView?.addSubview(hudMaterial)
        return panel
    }

    // MARK: Material

    /// Cuts the material to the eight icon tiles (layout pictures and arrows share them). A light ring fill gets
    /// the light material, a dark one the dark.
    private static var maskCache: (key: CGSize, image: NSImage)?

    private static func layoutMaterial(_ view: NSVisualEffectView, center: CGPoint, ring: RingSettings, theme: Theme) {
        let extent = RingGeometry.extent(ring)
        let box = CGRect(x: center.x - extent, y: center.y - extent, width: extent * 2, height: extent * 2)
        view.frame = box
        view.alphaValue = 1  // a session that ended in point mode left it dimmed
        view.appearance = NSAppearance(named: HexColor.isLight(theme.ring.fillHex) ? .aqua : .darkAqua)
        // The mask only depends on the ring's size, so it is drawn once and reused on every open.
        let key = CGSize(width: ring.radius, height: ring.thickness)
        if maskCache?.key != key {
            let path = RingGeometry.path(center: CGPoint(x: extent, y: extent), ring: ring)
            let image = NSImage(size: box.size, flipped: false) { _ in
                NSColor.black.setFill()
                NSBezierPath(cgPath: path).fill()
                return true
            }
            maskCache = (key, image)
        }
        if view.maskImage !== maskCache?.image { view.maskImage = maskCache?.image }
        view.isHidden = !(ring.showRing && ring.showGlyphs && ring.frosted)
    }

    private static func capsuleMask(size: CGSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: size.height / 2, left: size.height / 2, bottom: size.height / 2, right: size.height / 2)
        return image
    }

    // MARK: Grid

    private func updateGrid(_ scene: Scene, key: GridKey?) {
        guard key != scene.gridKey else { return }
        scene.gridKey = key
        guard let key else {
            scene.grid.path = nil
            scene.gridHalo.path = nil
            scene.gridActive.path = nil
            for t in scene.numbers { t.isHidden = true }
            return
        }
        let paths = Self.gridPaths(for: key.display, span: key.span, ring: ring, offset: scene.origin)
        scene.grid.path = paths.faint
        let halo = CGMutablePath()
        halo.addPath(paths.faint)
        halo.addPath(paths.active)
        scene.gridHalo.path = halo
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
                active.addRoundedRect(in: picked.offsetBy(dx: -offset.x, dy: -offset.y), cornerWidth: 6, cornerHeight: 6)
            } else {
                faint.addRoundedRect(in: cell, cornerWidth: 6, cornerHeight: 6)
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
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return panel
    }
}
