import SwiftUI
import TesseraCore

struct PreviewPane: View {
    @Bindable var model: SettingsModel
    @State private var screenCaptureAllowed = Permissions.isScreenCaptureAllowed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = $model.settings.preview
        let s = model.settings.preview
        Form {
            Section("Sample") {
                PreviewSample(settings: s, accent: Color(hex: model.settings.selectedTheme.accentHex))
                    .frame(height: 150)
            }

            Section("Window thumbnail") {
                Toggle("Show a snapshot of the window", isOn: p.showThumbnail)
                if !screenCaptureAllowed {
                    HStack {
                        Caption("Needs Screen Recording permission. Until then the preview is a plain tinted rectangle.")
                        Spacer()
                        Button("Enable Screen Recording") {
                            Permissions.requestScreenCapture()
                            screenCaptureAllowed = Permissions.isScreenCaptureAllowed
                        }
                    }
                }
            }

            Section("Label") {
                Toggle("Show size and slot", isOn: p.showLabel)
                Picker("Position", selection: p.labelPosition) {
                    Text("Center").tag(LabelPosition.center)
                    Text("Bottom").tag(LabelPosition.bottom)
                }
                .disabled(!s.showLabel)
                if !s.showLabel { Caption("Turn on the label to choose its position.") }
            }

            Section("Neighbours") {
                Toggle("Dim covered windows and outline the current frame", isOn: p.showNeighbours)
                SliderRow(title: "Dim strength", value: p.dimStrength, range: 0...1, step: 0.05, format: SliderRow.percent)
                    .disabled(!s.showNeighbours)
                if !s.showNeighbours { Caption("Turn on neighbour dimming to adjust its strength.") }
            }

            Section("Morph") {
                Toggle("Animate between selections", isOn: p.morph)
                SliderRow(title: "Spring response", value: p.springResponse, range: 0...0.4, step: 0.01, format: SliderRow.seconds)
                    .disabled(!s.morph)
                if !s.morph {
                    Caption("Turn on the morph to adjust its spring.")
                } else if reduceMotion {
                    Caption("Reduce Motion is on in System Settings, so the preview jumps instead of animating.")
                } else {
                    Caption("0 turns the animation off.")
                }
            }

            Section("Style") {
                SliderRow(title: "Fill opacity", value: p.opacity, range: 0...1, step: 0.05, format: SliderRow.percent)
                SliderRow(title: "Border width", value: p.borderWidth, range: 0...10, step: 0.5)
                Toggle("Use the window's own corner radius", isOn: p.useWindowCornerRadius)
                SliderRow(title: "Corner radius", value: p.cornerRadius, range: 0...30)
                    .disabled(s.useWindowCornerRadius)
                if s.useWindowCornerRadius { Caption("Using the window's corner radius instead of a fixed one.") }
            }

            ResetSection {
                model.settings.preview = model.settings.selectedTheme.preview
            }
            .help("Restores the preview settings of the selected theme.")
        }
        .formStyle(.grouped)
        .onAppear { screenCaptureAllowed = Permissions.isScreenCaptureAllowed }
    }
}

/// Static mock of the overlay preview, reflecting the current style values.
private struct PreviewSample: View {
    let settings: PreviewSettings
    let accent: Color

    var body: some View {
        let radius = settings.useWindowCornerRadius ? 10 : settings.cornerRadius
        ZStack {
            if settings.showNeighbours {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(settings.dimStrength))
                    .frame(width: 90, height: 70)
                    .offset(x: 110, y: -20)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.primary.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: 120, height: 80)
                    .offset(x: -100, y: 15)
            }
            RoundedRectangle(cornerRadius: radius)
                .fill(accent.opacity(settings.opacity))
                .overlay {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(accent, lineWidth: settings.borderWidth)
                }
                .frame(width: 200, height: 120)
            if settings.showLabel {
                Text("756 × 949 · Left half")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.72), in: Capsule())
                    .offset(y: settings.labelPosition == .bottom ? 40 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Preview sample")
    }
}

#Preview {
    PreviewPane(model: SettingsModel())
}
