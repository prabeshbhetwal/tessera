import SwiftUI
import TesseraCore

/// How the ring behaves: the trigger that opens it, gestures, what each direction does, and its size and zones.
/// How it looks (whether it shows, icons, grid, colours) is in Appearance (`RingLookSections`).
struct RingPane: View {
    @Bindable var model: SettingsModel
    @State private var focusedWedge = 0
    @State private var recordingChord = false

    static let directions = ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left"]

    var body: some View {
        let ring = $model.settings.ring
        let r = model.settings.ring
        let theme = model.settings.activeTheme
        Form {
            Section {
                KeycapRow(keys: ModifierKey.names(model.settings.trigger.keyCodes), prominent: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                ChordRecorder(chord: $model.settings.trigger, recording: $recordingChord)
                    .settingAnchor("Chord")
            } header: {
                InfoHeader("Trigger", info: "Hold these keys to open the ring, then let go to snap. "
                    + "Click the keys to record new ones, or select them and press Delete for the default.")
            } footer: {
                if recordingChord {
                    Footer("Hold the keys you want, then let go. Esc cancels.")
                } else if model.settings.trigger.keyCodes.count == 1 {
                    Footer("With one key, the ring opens every time you press it.")
                }
            }

            Section {
                Toggle("Directions: flick towards a layout", isOn: ring.directions).settingAnchor("Directions: flick towards a layout")
                Toggle("Pointing: a longer move picks a column of the grid", isOn: ring.pointing).settingAnchor("Pointing: a longer move picks a column of the grid")
                Toggle("Click while pointing to span several columns", isOn: ring.clickToSpan).settingAnchor("Click while pointing to span several columns")
                    .disabled(!r.pointing)
                Toggle("Scroll while holding to change the column count", isOn: ring.scrollChangesColumns).settingAnchor("Scroll while holding to change the column count")
                Toggle("Press and release without moving to tile all windows", isOn: ring.tapTilesWindows).settingAnchor("Press and release without moving to tile all windows")
            } header: {
                InfoHeader("Gestures", info: "A short move towards an icon picks that layout. Keep going further out to point at a column. "
                    + "To cancel, let go in the middle of the ring, press Esc or right-click.")
            } footer: {
                if r.tapTilesWindows && (r.directions || r.pointing) {
                    Footer("Pressing and letting go without moving tiles every window on that display.")
                } else if !r.directions && !r.pointing {
                    Footer(model.settings.ringKeyNavigation
                        ? "Mouse gestures are off. While holding the trigger, use the arrow keys and Return."
                        : "Gestures and ring keys are both off, so holding the trigger does nothing.")
                }
            }

            Section {
                WedgePicker(ring: r, theme: theme, focused: $focusedWedge)
                    .frame(height: 200)
                    .settingAnchor("Directions")
                Picker(Self.directions[focusedWedge % Self.directions.count], selection: ring.wedges[focusedWedge]) {
                    ForEach(WindowAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            } header: {
                InfoHeader("Directions", info: "Click a direction on the ring, or use ← →, then choose what it does.")
            }
            .disabled(!r.directions)

            Section {
                let pointMin = max(r.outerRadius, r.deadZone + 1).rounded(.up)
                SliderRow(title: "Radius", value: ring.radius, range: 20...max(21, min(150, r.flickDistance - r.thickness / 2)))
                    .disabled(!r.showRing)
                SliderRow(title: "Thickness", value: ring.thickness,
                          range: 4...max(5, min(80, r.radius * 2, (r.flickDistance - r.radius) * 2)))
                    .disabled(!r.showRing)
                SliderRow(title: "Point threshold", value: ring.flickDistance, range: pointMin...max(pointMin + 1, 400))
                    .disabled(!(r.directions && r.pointing))
                SliderRow(title: "Top band", value: ring.topBand, range: 0.1...max(0.11, 0.9 - r.bottomBand), step: 0.05, format: SliderRow.percent)
                    .disabled(!r.pointing)
                SliderRow(title: "Bottom band", value: ring.bottomBand, range: 0.1...max(0.11, 0.9 - r.topBand), step: 0.05, format: SliderRow.percent)
                    .disabled(!r.pointing)
            } header: {
                InfoHeader("Size and zones", info: "Letting go within \(Int(r.cancelRadius)) pt of the centre cancels. "
                    + "Raise Point threshold if quick flicks pick a column by mistake. "
                    + "While pointing, the top and bottom bands snap a window to half height.")
            }

            // The ring's look switches belong to Appearance, which resets them.
            ResetSection(keeps: "Keeps the ring's look (Appearance).") {
                let current = model.settings.ring
                model.settings.ring = .default
                model.settings.ring.takeLook(from: current)
                model.settings.trigger = .default
            }
        }
        .formStyle(.grouped)
    }
}

/// The diagram as a control: tap a wedge to focus it, ← → to move the focus. Draws the cancel area,
/// the point threshold and every wedge with its layout glyph.
private struct WedgePicker: View {
    let ring: RingSettings
    let theme: Theme
    @Binding var focused: Int
    @FocusState private var hasFocus: Bool

    var body: some View {
        GeometryReader { geometry in
            RingDiagram(
                ring: ring, fill: Color(hex: theme.ring.fillHex), tint: theme.ring.opacity,
                stroke: Color(hex: theme.ring.strokeHex), accent: Color(hex: theme.accentHex),
                active: nil, focused: focused, showBoundary: false, showFocusRing: hasFocus
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let hit = RingDiagram.wedge(at: location, size: geometry.size) { focused = hit }
            }
        }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { focused = (focused + 7) % 8; return .handled }
        .onKeyPress(.rightArrow) { focused = (focused + 1) % 8; return .handled }
        .accessibilityElement()
        .accessibilityLabel("Ring directions")
        .accessibilityValue("\(RingPane.directions[focused]): \(ring.wedges[focused].displayName)")
        .accessibilityAdjustableAction { direction in
            focused = (focused + (direction == .increment ? 1 : 7)) % 8
        }
    }
}

/// Scaled drawing of the ring with the same wedge geometry and glyphs as the overlay. `active` is filled
/// in the accent colour like the live ring; `focused` is outlined for the Ring pane's picker.
struct RingDiagram: View {
    let ring: RingSettings
    let fill: Color
    let tint: Double
    let stroke: Color
    let accent: Color
    let active: Int?
    let focused: Int?
    var showBoundary: Bool
    var showFocusRing = false

    /// Diagram scale: the ring itself fills the diagram. The point threshold is drawn at true proportion
    /// and simply runs off the edge when it is far outside the ring, which is what it does on screen too.
    private static func scale(_ ring: RingSettings, in size: CGSize, showBoundary: Bool) -> CGFloat {
        let outer = RingGeometry.extent(ring)
        let reach = showBoundary ? min(max(CGFloat(ring.flickDistance), outer), outer * 1.6) : outer
        return (min(size.width, size.height) / 2 - 16) / max(reach, 1)
    }

    /// Wedge index in the direction of `point` (view coordinates, y down), or nil at the very centre.
    static func wedge(at point: CGPoint, size: CGSize) -> Int? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x, dy = center.y - point.y
        guard hypot(dx, dy) > 4 else { return nil }
        let deg = atan2(dx, dy) * 180 / .pi
        let shifted = ((deg + 22.5).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return min(Int(shifted / 45), 7)
    }

    var body: some View {
        Canvas { context, size in
            let s = Self.scale(ring, in: size, showBoundary: showBoundary)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var scaled = ring
            scaled.radius = ring.radius * s
            scaled.thickness = ring.thickness * s
            // RingLayer paths are y-up; flip into the Canvas.
            func flipped(_ path: CGPath) -> Path {
                Path(path).applying(CGAffineTransform(scaleX: 1, y: -1)).offsetBy(dx: center.x, dy: center.y)
            }

            if showBoundary {
                let flick = CGFloat(ring.flickDistance) * s
                let circle = Path(ellipseIn: CGRect(x: center.x - flick, y: center.y - flick, width: flick * 2, height: flick * 2))
                context.fill(circle, with: .color(accent.opacity(0.06)))
                context.stroke(circle, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                let dead = CGFloat(ring.cancelRadius) * s  // the cancel area
                context.fill(Path(ellipseIn: CGRect(x: center.x - dead, y: center.y - dead, width: dead * 2, height: dead * 2)),
                             with: .color(.secondary.opacity(0.25)))
            }

            for i in 0..<8 {
                let wedge = flipped(RingGeometry.tilePath(index: i, center: .zero, ring: scaled))
                if ring.iconStyle == .layouts {
                    context.fill(wedge, with: .color(fill.opacity(max(tint, 0.85))))
                }
            }
            if let glyphs = RingLayer.glyphPaths(ring: scaled, center: .zero, aspect: 1.6) {
                context.stroke(flipped(glyphs.outlines), with: .color(stroke.opacity(0.65)), lineWidth: 1.25)
                context.fill(flipped(glyphs.fills), with: .color(stroke.opacity(0.28)))
                if let active, let selected = RingLayer.glyphPaths(ring: scaled, center: .zero, aspect: 1.6, only: active) {
                    context.stroke(flipped(selected.outlines), with: .color(stroke), lineWidth: 1.5)
                    context.fill(flipped(selected.fills), with: .color(accent))
                }
            }
            if let focused {
                let wedge = flipped(RingGeometry.tilePath(index: focused, center: .zero, ring: scaled))
                context.stroke(wedge, with: .color(accent), lineWidth: showFocusRing ? 3 : 2)
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)),
                         with: .color(stroke.opacity(0.35)))
        }
        .background {
            if showFocusRing {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
            }
        }
    }
}

#Preview {
    RingPane(model: SettingsModel())
}
