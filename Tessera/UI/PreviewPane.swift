import SwiftUI
import TesseraCore

/// What the preview shows. Its look lives in Appearance, its animation in Motion.
struct PreviewPane: View {
    @Bindable var model: SettingsModel
    @State private var screenCaptureAllowed = Permissions.isScreenCaptureAllowed

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
                    Callout(.warning, "Needs Screen Recording permission. Until then the preview is a plain tinted rectangle.") {
                        Button("Allow…") {
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

            Section {
                Caption("Colours, border and corners are in Appearance. Animation speed is in Motion.")
            }

            ResetSection {
                let theme = model.settings.selectedTheme.preview
                model.settings.preview.showThumbnail = theme.showThumbnail
                model.settings.preview.showLabel = theme.showLabel
                model.settings.preview.labelPosition = theme.labelPosition
                model.settings.preview.showNeighbours = theme.showNeighbours
                model.settings.preview.dimStrength = theme.dimStrength
            }
            .help("Restores what the selected theme's preview shows.")
        }
        .formStyle(.grouped)
        .onAppear { screenCaptureAllowed = Permissions.isScreenCaptureAllowed }
    }
}

/// Static mock of the overlay preview, reflecting the current style values. Shared with Appearance.
struct PreviewSample: View {
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
