import SwiftUI
import TesseraCore

/// A pretend window in a Settings demo. Never one of the user's windows.
struct DemoWindow: Identifiable, Equatable {
    let id: Int
    var frame: CGRect
    /// The window the demo acts on.
    var live = false
    /// Its close button is being pressed: drawn red with a cross, as when the pointer is on it.
    var closing = false

    /// Where the close button sits, in display points, for a pointer to click it. The title bar is drawn at a
    /// fixed size on the stage, so this is the stage's 9 × 7 pt offset at its display scale (about 0.28).
    var closeButton: CGPoint { CGPoint(x: frame.minX + 32, y: frame.maxY - 24) }
}

/// The stage's screen: a menu bar over the wallpaper, glass windows, and the overlay drawn the way the active theme
/// draws it on screen (preview fill, border, corners, label, dimming, the "from" outline, the ring and the grid).
/// Everything is placed from display-space rects (AppKit, y up) computed by `TesseraCore`.
struct MockDesktop: View {
    let display: DisplayContext
    let settings: TesseraSettings
    let frame: StageFrame
    /// Where the live window started; outlined faintly once it has moved.
    var ghost: CGRect?

    var body: some View {
        let screen = display.frame
        VStack(spacing: 0) {
            menuBar
            GeometryReader { geometry in
                let scale = geometry.size.width / max(screen.width, 1)
                let map = { (r: CGRect) -> CGRect in
                    CGRect(x: (r.minX - screen.minX) * scale, y: (screen.maxY - r.maxY) * scale,
                           width: r.width * scale, height: r.height * scale)
                }
                ZStack(alignment: .topLeading) {
                    if frame.grid { grid(map) }
                    if let ghost { placed(ghostOutline, in: map(ghost)) }
                    ForEach(frame.windows) { window in
                        placed(StageWindow(theme: theme, dimmed: dims(window), outlined: outlines(window),
                                           closing: window.closing), in: map(window.frame))
                            // A closed window shrinks into itself and fades, as macOS closes one.
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }
                    if let preview = frame.preview { previewView(map(preview), size: preview) }
                    if let centre = frame.ring {
                        let at = map(CGRect(origin: centre, size: .zero)).origin
                        if let threshold = frame.threshold { thresholdCircle(threshold).position(at) }
                        ring.position(at)
                        if let badge = frame.badge { badgeView(badge).position(x: at.x, y: at.y + ringSide / 2 + 6) }
                        if let handle = frame.handle, let edit = cues?.ringEdit {
                            let outer = (settings.ring.radius + settings.ring.thickness / 2) * Self.ringScale
                            StageRingHandleView(handle: handle, ring: settings.ring, scale: Self.ringScale, edit: edit)
                                // Just outside the icons, so it doesn't sit on the Right one.
                                .position(x: at.x + outer + 12, y: at.y)
                        }
                    }
                    if let pointer = frame.pointer { pointerView.position(map(CGRect(origin: pointer, size: .zero)).origin) }
                }
            }
            .aspectRatio(screen.width / max(screen.height, 1), contentMode: .fit)
        }
    }

    @Environment(DemoCueState.self) private var cues: DemoCueState?

    private var theme: Theme { settings.activeTheme }
    private var look: PreviewSettings { theme.preview }
    private var previewing: Bool { frame.preview != nil }

    private func dims(_ window: DemoWindow) -> Bool { previewing && look.showNeighbours && !window.live }
    private func outlines(_ window: DemoWindow) -> Bool { previewing && look.showCurrentOutline && window.live }

    private var menuBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.logo").font(.system(size: 9))
            Capsule().fill(.primary.opacity(0.35)).frame(width: 26, height: 4)
            Capsule().fill(.primary.opacity(0.2)).frame(width: 18, height: 4)
            Spacer()
            Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 18)
        .stageGlass(cornerRadius: 0, clear: true, tint: 0.15)
        .accessibilityHidden(true)
    }

    private func grid(_ map: @escaping (CGRect) -> CGRect) -> some View {
        ForEach(0..<max(display.profile.columns, 1), id: \.self) { c in
            let cell = map(GridGeometry.frame(for: ColumnSpan(columns: c...c, band: .full), display: display))
            placed(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(hex: theme.ring.gridHex).opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .overlay { Text("\(c + 1)").font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.white) }
                .shadow(color: .black.opacity(0.4), radius: 1), in: cell)
        }
    }

    private var ghostOutline: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .shadow(color: .black.opacity(0.35), radius: 1)
    }

    /// The preview as the theme draws it, its border and corners scaled down with the stage.
    private func previewView(_ r: CGRect, size: CGRect) -> some View {
        let colour = Color(hex: theme.previewHex)
        let radius = look.useWindowCornerRadius ? 6 : min(look.cornerRadius * 0.5, 12)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let label = look.showLabel
            ? PreviewModel.label(for: frame.selection, frame: size, size: look.labelShowsSize, slot: look.labelShowsSlot) : nil
        return placed(shape.fill(colour.opacity(look.opacity))
            .overlay(shape.strokeBorder(colour, lineWidth: max(look.borderWidth * 0.6, look.borderWidth > 0 ? 1 : 0)))
            .overlay(alignment: look.labelPosition == .bottom ? .bottom : .center) {
                if let label {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(Color(hex: theme.labelTextHex))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(hex: theme.labelHex).opacity(0.82), in: Capsule())
                        .padding(6)
                }
            }, in: r)
    }

    private var ring: some View {
        RingDiagram(ring: settings.ring, fill: Color(hex: theme.ring.fillHex), tint: theme.ring.opacity,
                    stroke: Color(hex: theme.ring.strokeHex), accent: Color(hex: theme.accentHex),
                    active: frame.wedge, focused: nil, showBoundary: false)
            .frame(width: ringSide, height: ringSide)
            .opacity(settings.ring.showRing ? 1 : 0.25)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    /// View points per ring point. The stage draws the ring larger than true scale so its icons read, but keeps
    /// its size, the point threshold and the pointer's flick in proportion, so a bigger radius shows bigger.
    static let ringScale: CGFloat = 0.8

    /// `RingDiagram` fits the ring's extent into its frame less a 16 pt margin, so this frame draws it at `ringScale`.
    private var ringSide: CGFloat { 2 * (RingGeometry.extent(settings.ring) * Self.ringScale + 16) }

    private func thresholdCircle(_ radius: Double) -> some View {
        let side = 2 * radius * Self.ringScale
        return Circle()
            .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .shadow(color: .black.opacity(0.35), radius: 1)
            .frame(width: side, height: side)
            .transition(.opacity)
    }

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor, in: Capsule())
            .fixedSize()
            .transition(.opacity)
    }

    private var pointerView: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.black)
            .shadow(color: .white, radius: 0.6)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .offset(x: 4, y: 7)
            // A click: the pointer presses in while a close button is held.
            .scaleEffect(frame.windows.contains(where: \.closing) ? 0.85 : 1)
    }

    private func placed(_ view: some View, in r: CGRect) -> some View {
        view.frame(width: max(r.width, 0), height: max(r.height, 0)).offset(x: r.minX, y: r.minY)
    }
}

/// A pretend window: a frosted body with a title bar of three neutral dots. Dimmed while another window
/// is previewed (the theme's dimming); outlined while it is the "from" window.
private struct StageWindow: View {
    let theme: Theme
    var dimmed = false
    var outlined = false
    var closing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    if i == 0, closing {
                        Circle().fill(Color.red)
                            .overlay(Image(systemName: "xmark").font(.system(size: 3.5, weight: .black)).foregroundStyle(.black.opacity(0.6)))
                            .frame(width: 5, height: 5)
                            .scaleEffect(1.25)
                    } else {
                        Circle().fill(.primary.opacity(0.35)).frame(width: 5, height: 5)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 13)
            Color.clear
        }
        .stageGlass(cornerRadius: 6, tint: 0.55)
        .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        .overlay { if dimmed { shape.fill(Color(hex: theme.dimHex).opacity(theme.preview.dimStrength)) } }
        .overlay {
            if outlined {
                shape.strokeBorder(Color(hex: theme.outlineHex).opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                    .padding(3)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}
