import SwiftUI
import TesseraCore

/// Every speed in one place: how windows glide after a snap and how the preview morphs between selections.
struct MotionPane: View {
    @Bindable var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = $model.settings.preview
        let s = model.settings.preview
        let seconds = model.settings.snapSeconds
        Form {
            if reduceMotion {
                Section {
                    Callout(.info, "Reduce Motion is on in System Settings › Accessibility › Display, so windows and the preview jump instead of animating. The settings below take effect when it's off.")
                }
            }

            Section("Snap speed") {
                Picker("Speed", selection: Binding(
                    get: { SnapSpeed(seconds: seconds) },
                    set: { if let speed = $0 { model.settings.snapSeconds = speed.seconds } }
                )) {
                    ForEach(SnapSpeed.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                SliderRow(title: "Duration", value: $model.settings.snapSeconds, range: 0...SnapSpeed.maxSeconds,
                          step: 0.01, format: { $0 == 0 ? "Instant" : String(format: "%.2f s", $0) })
                Caption(SnapSpeed(seconds: seconds) == nil
                    ? "Custom speed. Pick a preset above or drag to any duration."
                    : "How long a window takes to glide into place, for the ring and shortcuts alike. Instant jumps straight there.")
            }

            Section("Preview morph") {
                Toggle("Animate the preview between selections", isOn: p.morph)
                SliderRow(title: "Spring response", value: p.springResponse, range: 0...0.4, step: 0.01, format: SliderRow.seconds)
                    .disabled(!s.morph)
                Caption(s.morph ? "Lower is snappier. 0 turns the animation off." : "Turn on the morph to adjust its spring.")
            }

            ResetSection {
                let theme = model.settings.selectedTheme.preview
                model.settings.snapSeconds = TesseraSettings.defaults.snapSeconds
                model.settings.preview.morph = theme.morph
                model.settings.preview.springResponse = theme.springResponse
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    MotionPane(model: SettingsModel())
}
