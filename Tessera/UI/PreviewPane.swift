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

            Section("Preview style") {
                Picker("Fill the preview with", selection: p.style) {
                    ForEach(PreviewStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Caption(Self.caption(for: s.style))
                if s.style == .snapshot, !screenCaptureAllowed {
                    Callout(.warning, "Needs Screen Recording permission. Until then the preview stays a tinted box.") {
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

            Section("Around the preview") {
                Toggle("Dim windows the snap would cover", isOn: p.showNeighbours)
                SliderRow(title: "Dim strength", value: p.dimStrength, range: 0...1, step: 0.05, format: SliderRow.percent)
                    .disabled(!s.showNeighbours)
                if !s.showNeighbours { Caption("Turn on dimming to adjust its strength.") }
                Toggle("Outline where the window is now (dashed)", isOn: p.showCurrentOutline)
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

    private static func caption(for style: PreviewStyle) -> String {
        switch style {
        case .tint: "A box in the accent colour. Appears instantly and looks the same every time."
        case .snapshot: "The box appears first, then a picture of the window fades in, scaled to fit."
        case .appIcon: "The box with the moving app's icon in the middle."
        }
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
            }
            if settings.showCurrentOutline {
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
            switch settings.style {
            case .tint:
                EmptyView()
            case .snapshot:
                MockWindow()
                    .frame(width: 160, height: 104)
            case .appIcon:
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
            }
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

/// Stand-in for a window snapshot in the sample: title bar with traffic lights over a body.
private struct MockWindow: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 6, height: 6) }
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 14)
            .background(.gray.opacity(0.35))
            Rectangle().fill(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.4)) }
    }
}

#Preview {
    PreviewPane(model: SettingsModel())
}
