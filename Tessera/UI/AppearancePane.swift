import SwiftUI
import TesseraCore

/// How the ring and preview look: theme-bound colours plus the free sizes and preview style.
struct AppearancePane: View {
    @Bindable var model: SettingsModel
    @State private var newThemeName = ""

    private var customIndex: Int? {
        model.settings.customThemes.firstIndex { $0.name == model.settings.themeName }
    }

    private var trimmedName: String { newThemeName.trimmingCharacters(in: .whitespaces) }
    private var nameTakenByBuiltIn: Bool { Theme.builtIn.contains { $0.name == trimmedName } }

    var body: some View {
        let p = $model.settings.preview
        let s = model.settings.preview
        let ring = $model.settings.ring
        let r = model.settings.ring
        Form {
            Section {
                Picker("Theme", selection: Binding(
                    get: { model.settings.themeName },
                    set: { name in
                        model.settings.themeName = name
                        model.settings.preview = model.settings.selectedTheme.preview
                    }
                )) {
                    ForEach(model.settings.allThemes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                PreviewSample(settings: s, accent: Color(hex: model.settings.selectedTheme.accentHex))
                    .frame(height: 150)
                Caption("Choosing a theme replaces the preview style below with the theme's.")
            }

            Section("Ring size") {
                SliderRow(title: "Radius", value: ring.radius, range: 20...150)
                SliderRow(title: "Thickness", value: ring.thickness, range: 4...max(5, min(80, r.radius * 2)))
                Caption("Thickness can't exceed twice the radius.")
            }

            Section("Preview style") {
                SliderRow(title: "Fill opacity", value: p.opacity, range: 0...1, step: 0.05, format: SliderRow.percent)
                SliderRow(title: "Border width", value: p.borderWidth, range: 0...10, step: 0.5)
                Toggle("Use the window's own corner radius", isOn: p.useWindowCornerRadius)
                SliderRow(title: "Corner radius", value: p.cornerRadius, range: 0...30)
                    .disabled(s.useWindowCornerRadius)
                if s.useWindowCornerRadius { Caption("Using the window's corner radius instead of a fixed one.") }
            }

            Section("Ring colours and accent") {
                ColorPicker("Ring fill", selection: colorBinding(\.ring.fillHex), supportsOpacity: false)
                ColorPicker("Ring outline", selection: colorBinding(\.ring.strokeHex), supportsOpacity: false)
                SliderRow(
                    title: "Ring opacity",
                    value: Binding(
                        get: { model.settings.selectedTheme.ring.opacity },
                        set: { v in editCustom { $0.ring.opacity = v } }
                    ),
                    range: 0...1, step: 0.05, format: SliderRow.percent
                )
                ColorPicker("Accent", selection: colorBinding(\.accentHex), supportsOpacity: false)
            }
            .disabled(customIndex == nil)
            if customIndex == nil {
                Section {
                    Callout(.info, "Built-in themes can't be edited. Save the current look as a custom theme to change its colours.")
                }
            }

            Section("Custom themes") {
                HStack {
                    TextField("Theme name", text: $newThemeName)
                    Button("Save current as theme…", action: saveTheme)
                        .disabled(trimmedName.isEmpty || nameTakenByBuiltIn)
                }
                if nameTakenByBuiltIn {
                    Caption("\(trimmedName) is a built-in theme name. Pick another.")
                } else if model.settings.customThemes.contains(where: { $0.name == trimmedName }) {
                    Caption("Saving replaces the custom theme named \(trimmedName).")
                }
                if let customIndex {
                    Button("Delete \(model.settings.customThemes[customIndex].name)", role: .destructive) {
                        model.settings.customThemes.remove(at: customIndex)
                        model.settings.themeName = Theme.default.name
                    }
                }
            }

            ResetSection {
                model.settings.themeName = Theme.default.name
                model.settings.preview = Theme.default.preview
                model.settings.ring.radius = RingSettings.default.radius
                model.settings.ring.thickness = RingSettings.default.thickness
            }
            Caption("Reset keeps your custom themes.")
        }
        .formStyle(.grouped)
    }

    private func editCustom(_ change: (inout Theme) -> Void) {
        guard let customIndex else { return }
        change(&model.settings.customThemes[customIndex])
    }

    private func colorBinding(_ field: WritableKeyPath<Theme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.settings.selectedTheme[keyPath: field]) },
            set: { color in editCustom { $0[keyPath: field] = color.hex } }
        )
    }

    private func saveTheme() {
        let base = model.settings.selectedTheme
        let theme = Theme(name: trimmedName, ring: base.ring, preview: model.settings.preview, accentHex: base.accentHex)
        model.settings.customThemes.removeAll { $0.name == theme.name }
        model.settings.customThemes.append(theme)
        model.settings.themeName = theme.name
        newThemeName = ""
    }
}

#Preview {
    AppearancePane(model: SettingsModel())
}
