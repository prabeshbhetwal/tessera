import SwiftUI
import TesseraCore

struct AppearancePane: View {
    @Bindable var model: SettingsModel
    @State private var newThemeName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var customIndex: Int? {
        model.settings.customThemes.firstIndex { $0.name == model.settings.themeName }
    }

    private var trimmedName: String { newThemeName.trimmingCharacters(in: .whitespaces) }
    private var nameTakenByBuiltIn: Bool { Theme.builtIn.contains { $0.name == trimmedName } }

    var body: some View {
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
                Caption("Choosing a theme also replaces the Preview pane's look with the theme's.")
            }

            Section("Ring and accent") {
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

            Section("Motion") {
                Caption(reduceMotion
                    ? "Reduce Motion is on in System Settings, so the overlay doesn't animate."
                    : "The overlay follows System Settings › Accessibility › Display › Reduce Motion.")
            }

            ResetSection {
                model.settings.themeName = Theme.default.name
                model.settings.preview = Theme.default.preview
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
