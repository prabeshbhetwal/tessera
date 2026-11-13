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
                Toggle("Flick towards a layout", isOn: ring.directions).settingAnchor("Directions: flick towards a layout")
                Toggle("Point for a column of the grid", isOn: ring.pointing).settingAnchor("Pointing: a longer move picks a column of the grid")
                Toggle("Click while pointing to span several columns", isOn: ring.clickToSpan).settingAnchor("Click while pointing to span several columns")
                    .disabled(!r.pointing)
                Toggle("Scroll while holding to change the column count", isOn: ring.scrollChangesColumns).settingAnchor("Scroll while holding to change the column count")
                Toggle("Press and release without moving to tile all windows", isOn: ring.tapTilesWindows).settingAnchor("Press and release without moving to tile all windows")
            } header: {
                InfoHeader("Gestures", info: "A short move towards an icon picks that layout. Keep going further out to point at a column. "
                    + "To cancel, let go in the middle of the ring or right-click.")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if r.tapTilesWindows && (r.directions || r.pointing) {
                        Footer("Pressing and letting go without moving tiles every window on that display.")
                    } else if !r.directions && !r.pointing {
                        Footer(model.settings.ringKeyNavigation
                            ? "Mouse gestures are off. While holding the trigger, use the arrow keys and Return."
                            : "Gestures and ring keys are both off, so holding the trigger does nothing.")
                    }
                    if !r.pointing {
                        Footer("Turn on pointing to span columns with a click.")
                    }
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

/// The diagram as a control: tap a wedge to focus it, ← → to move the focus. A highlight follows the pointer
/// (or the keyboard focus) around the ring on a spring, the short way round, lifting the tile under it.
private struct WedgePicker: View {
    let ring: RingSettings
    let theme: Theme
    @Binding var focused: Int
    @FocusState private var hasFocus: Bool
    @State private var hovered: Int?
    /// Unwrapped wedge position of the highlight; see `RingDiagram.glide`.
    @State private var glide: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: Int { hovered ?? focused }
    private var hover: Double { hovered != nil ? 1 : hasFocus ? 0.6 : 0 }

    var body: some View {
        GeometryReader { geometry in
            RingDiagram(
                ring: ring, fill: Color(hex: theme.ring.fillHex), tint: theme.ring.opacity,
                stroke: Color(hex: theme.ring.strokeHex), accent: Color(hex: theme.accentHex),
                active: nil, focused: focused, showBoundary: false, showFocusRing: hasFocus,
                glide: glide, hover: hover
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let hit = RingDiagram.wedge(at: location, size: geometry.size) { focused = hit }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = RingDiagram.wedge(at: point, size: geometry.size)
                case .ended: hovered = nil
                }
            }
        }
        .onAppear { glide = Double(focused) }
        .onChange(of: target) { _, wedge in
            // Take the short way round: from Up-left (7) to Up (0) is one step forward, not seven back.
            var step = (Double(wedge) - glide).truncatingRemainder(dividingBy: 8)
            if step > 4 { step -= 8 } else if step < -4 { step += 8 }
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) { glide += step }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hover)
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

#Preview {
    RingPane(model: SettingsModel())
}
