import SwiftUI
import TesseraCore

/// The ring is the control: click a wedge in the diagram (or use ← →) and pick its layout underneath.
struct RingPane: View {
    @Bindable var model: SettingsModel
    @State private var focusedWedge = 0

    static let directions = ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left"]

    var body: some View {
        let ring = $model.settings.ring
        let r = model.settings.ring
        let theme = model.settings.activeTheme
        Form {
            Section {
                Toggle("Directions: flick towards a layout", isOn: ring.directions)
                Toggle("Pointing: a longer move picks a column of the grid", isOn: ring.pointing)
                Toggle("Click while pointing to span several columns", isOn: ring.clickToSpan)
                    .disabled(!r.pointing)
                Toggle("Scroll while holding to change the column count", isOn: ring.scrollChangesColumns)
                Toggle("Press and release without moving to tile all windows", isOn: ring.tapTilesWindows)
            } header: {
                Text("Gestures")
            } footer: {
                Footer(gestureSummary(r, keys: model.settings.ringKeyNavigation) + (r.tapTilesWindows
                    ? " Pressing and releasing in place puts every window on that display side by side, in your learned split"
                        + " for those apps or in equal shares."
                    : " Pressing and releasing in place does nothing.")
                    + " To cancel, release in the ring's empty middle, press Esc or right-click.")
            }

            Section {
                WedgePicker(ring: r, theme: theme, focused: $focusedWedge)
                    .frame(height: 200)
                Picker(Self.directions[focusedWedge % Self.directions.count], selection: ring.wedges[focusedWedge]) {
                    ForEach(WindowAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            } header: {
                Text("Directions")
            } footer: {
                Footer("Click a layout icon, or use ← →, then choose its action.")
            }
            .disabled(!r.directions)

            Section {
                Toggle("Show the ring", isOn: ring.showRing)
                Group {
                    Toggle("Action name and input hints", isOn: ring.showActionLabels)
                    Picker("Layout icons", selection: Binding(
                        get: { r.showGlyphs ? WedgeIcons(r.iconStyle) : .none },
                        set: { choice in
                            model.settings.ring.showGlyphs = choice != .none
                            if let style = choice.style { model.settings.ring.iconStyle = style }
                        }
                    )) {
                        ForEach(WedgeIcons.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Dashed circle where pointing begins", isOn: ring.showBoundary)
                        .disabled(!(r.directions && r.pointing))
                    Toggle("Frosted background", isOn: ring.frosted)
                }
                .disabled(!r.showRing)
                // Not tied to Pointing: the arrow keys pick columns too, and show the grid while they do.
                Toggle("Grid lines while picking a column", isOn: ring.showGrid)
                Toggle("Number the grid's columns", isOn: ring.showColumnNumbers)
                    .disabled(!r.showGrid)
                Toggle("Show \u{201C}click to add columns\u{201D} the first few times", isOn: ring.showPointingHint)
                    .disabled(!r.pointing)
                Button("Show the hint again") { model.settings.ring.pointingHintsSeen = nil }
                    .disabled(!r.pointing || !r.showPointingHint || r.pointingHintDue)
            } header: {
                Text("Appearance")
            } footer: {
                Footer(r.showRing
                    ? "Move towards a layout icon. Your selection lights up; its name appears below."
                    : "The ring stays hidden, but every gesture still works: the preview shows what you'll get.")
            }

            Section {
                ColorPicker("Ring", selection: model.themeColor(\.ring.fillHex), supportsOpacity: false)
                SliderRow(title: "Ring tint", value: model.themeRingTint, range: 0...1, step: 0.05, format: SliderRow.percent)
                ColorPicker("Lines and icons", selection: model.themeColor(\.ring.strokeHex), supportsOpacity: false)
                ColorPicker("Selected layout", selection: model.themeColor(\.accentHex), supportsOpacity: false)
                ColorPicker("Grid", selection: model.themeColor(\.ring.gridHex), supportsOpacity: false)
            } header: {
                Text("Colours")
            } footer: {
                Footer(model.customThemeIndex == nil
                    ? "Changing a colour saves your look as the theme \u{201C}\(SettingsModel.editedThemeName)\u{201D}; \u{201C}\(model.settings.themeName)\u{201D} stays as shipped. Themes and the preview's colours are in Overlay."
                    : "Saved to the theme \u{201C}\(model.settings.themeName)\u{201D}. Themes and the preview's colours are in Overlay.")
            }
            .disabled(!r.showRing)

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
                SliderRow(title: "Bottom band", value: ring.bottomBand, range: 0.1...max(0.11, 0.9 - r.topBand), step: 0.05, format: SliderRow.percent)
            } header: {
                Text("Size and zones")
            } footer: {
                Footer("Releasing in the ring's empty middle (\(Int(r.cancelRadius)) pt) cancels. The ring always stays inside the point threshold; past it the grid takes over, so raise it if you slip into pointing by accident. While pointing, the top and bottom bands of the screen snap a window to half height; the middle is full height.")
            }

            ResetSection {
                model.settings.ring = .default
            }
        }
        .formStyle(.grouped)
    }

    /// One sentence that says what holding the trigger and moving will do with the current switches.
    private func gestureSummary(_ r: RingSettings, keys: Bool) -> String {
        switch (r.directions, r.pointing) {
        case (true, true): "Move a little for a wedge's layout; keep going further out to point at a column."
        case (true, false): "Every move picks a wedge, however far you go. The grid is off."
        case (false, true): "Any move points straight at a column of the grid. The wedges are off."
        case (false, false) where keys: "Mouse gestures are off. Use the arrow keys and Return while holding the trigger, or the hotkeys."
        case (false, false): "Mouse gestures and ring keys are both off, so holding the trigger does nothing. Turn one on, or use the hotkeys."
        }
    }
}

/// The "Wedge icons" menu: the show switch and the style folded into one choice.
private enum WedgeIcons: CaseIterable {
    case layouts, arrows, none

    init(_ style: RingIconStyle) { self = style == .arrows ? .arrows : .layouts }

    var style: RingIconStyle? {
        switch self {
        case .layouts: .layouts
        case .arrows: .arrows
        case .none: nil
        }
    }

    var title: String {
        switch self {
        case .layouts: "Layout pictures"
        case .arrows: "Arrows"
        case .none: "None"
        }
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
                if ring.showGlyphs && ring.iconStyle == .layouts {
                    context.fill(wedge, with: .color(fill.opacity(max(tint, 0.85))))
                }
            }
            if ring.showGlyphs, let glyphs = RingLayer.glyphPaths(ring: scaled, center: .zero, aspect: 1.6) {
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
