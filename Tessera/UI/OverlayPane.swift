import SwiftUI
import TesseraCore

/// Everything about how the overlay looks: a sample, the theme and its colours, and the preview layers.
/// A theme is a snapshot of this pane; picking one applies its colours and preview settings together.
struct OverlayPane: View {
    @Bindable var model: SettingsModel
    @State private var newThemeName = ""
    @State private var screenCaptureAllowed = Permissions.isScreenCaptureAllowed

    /// Name of the theme that takes edits made to a built-in theme.
    private static let editedName = SettingsModel.editedThemeName

    private var theme: Theme { model.settings.selectedTheme }
    private var customIndex: Int? { model.customThemeIndex }
    private var trimmedName: String { newThemeName.trimmingCharacters(in: .whitespaces) }
    private var nameTakenByBuiltIn: Bool { Theme.builtIn.contains { $0.name == trimmedName } }
    /// "Custom" is where colour edits to a built-in theme land, overwriting it each time.
    private var nameReserved: Bool { trimmedName == Self.editedName }

    var body: some View {
        let s = model.settings.preview
        Form {
            Section {
                OverlaySample(ring: model.settings.ring, theme: model.settings.activeTheme)
                    .frame(height: 190)
                HStack {
                    Spacer()
                    Button("Preview Shortcut") {
                        NotificationCenter.default.post(name: .tesseraPreviewOverlay, object: nil,
                                                        userInfo: ["shortcut": true])
                    }
                    Button("Show on Screen") {
                        NotificationCenter.default.post(name: .tesseraPreviewOverlay, object: nil)
                    }
                }
            } footer: {
                Footer("Show on Screen previews the ring for three seconds. Preview Shortcut shows the confirmation; neither moves a window.")
            }

            Section {
                // Re-picking the current theme must not throw away preview changes made since it was picked.
                Picker("Theme", selection: Binding.choice(model.settings.themeName) { name in
                    model.settings.themeName = name
                    applyPreview(of: model.settings.selectedTheme)
                }) {
                    ForEach(model.settings.allThemes, id: \.name) { Text($0.name).tag($0.name) }
                }
                HStack {
                    TextField("Save the current look as", text: $newThemeName, prompt: Text("Theme name"))
                    Button("Save") { saveTheme() }
                        .disabled(trimmedName.isEmpty || nameTakenByBuiltIn || nameReserved)
                }
                if nameTakenByBuiltIn {
                    Caption("\(trimmedName) is a built-in theme. Pick another name.")
                } else if nameReserved {
                    Caption("\u{201C}\(trimmedName)\u{201D} holds your unsaved colour changes. Pick another name.")
                } else if model.settings.customThemes.contains(where: { $0.name == trimmedName }) {
                    Caption("Saving replaces the theme named \(trimmedName).")
                }
                if let customIndex {
                    HStack {
                        Spacer()
                        Button("Delete \u{201C}\(model.settings.customThemes[customIndex].name)\u{201D}", role: .destructive) {
                            model.settings.customThemes.remove(at: customIndex)
                            model.settings.themeName = Theme.default.name
                            applyPreview(of: .default)
                        }
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Footer("A theme is a snapshot of everything on this page: colours and preview settings, including the ring colours you can also set in Ring › Colours. "
                    + (customIndex == nil
                        ? "Built-in themes stay as shipped: changing a colour saves the result as \u{201C}\(Self.editedName)\u{201D}."
                        : "Changes are saved to \u{201C}\(theme.name)\u{201D} as you make them."))
            }

            Section {
                ColorPicker("Ring", selection: colorBinding(\.ring.fillHex), supportsOpacity: false)
                SliderRow(title: "Ring tint", value: Binding(
                    get: { theme.ring.opacity }, set: { v in edit { $0.ring.opacity = v } }
                ), range: 0...1, step: 0.05, format: SliderRow.percent)
                ColorPicker("Lines and icons", selection: colorBinding(\.ring.strokeHex), supportsOpacity: false)
                ColorPicker("Selected layout", selection: colorBinding(\.accentHex), supportsOpacity: false)
                ColorPicker("Grid", selection: colorBinding(\.ring.gridHex), supportsOpacity: false)
            } header: {
                Text("Ring colours")
            }

            Section {
                ColorPicker("Snap preview", selection: colorBinding(\.previewHex), supportsOpacity: false)
                ColorPicker("Label", selection: colorBinding(\.labelHex), supportsOpacity: false)
                ColorPicker("Label text", selection: colorBinding(\.labelTextHex), supportsOpacity: false)
                ColorPicker("Outline of the current frame", selection: colorBinding(\.outlineHex), supportsOpacity: false)
                ColorPicker("Dimming", selection: colorBinding(\.dimHex), supportsOpacity: false)
            } header: {
                Text("Preview and label colours")
            }

            Section("Preview") {
                Picker("Fill the preview with", selection: preview(\.style)) {
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
                SliderRow(title: "Fill opacity", value: preview(\.opacity), range: 0...1, step: 0.05, format: SliderRow.percent)
                SliderRow(title: "Border width", value: preview(\.borderWidth), range: 0...10, step: 0.5)
                Toggle("Match the window's corner radius", isOn: preview(\.useWindowCornerRadius))
                SliderRow(title: "Corner radius", value: preview(\.cornerRadius), range: 0...30)
                    .disabled(s.useWindowCornerRadius)
            }

            Section("Label") {
                Toggle("Show a label on the preview", isOn: preview(\.showLabel))
                Group {
                    Toggle("Size in points", isOn: preview(\.labelShowsSize))
                    Toggle("Slot name", isOn: preview(\.labelShowsSlot))
                    Picker("Position", selection: preview(\.labelPosition)) {
                        Text("Centre").tag(LabelPosition.center)
                        Text("Bottom").tag(LabelPosition.bottom)
                    }
                    .pickerStyle(.segmented)
                }
                .disabled(!s.showLabel)
                if s.showLabel, !s.labelShowsSize, !s.labelShowsSlot {
                    Caption("With both parts off, no label is shown.")
                }
            }

            Section("Around the preview") {
                Toggle("Dim the windows the preview covers", isOn: preview(\.showNeighbours))
                SliderRow(title: "Dim strength", value: preview(\.dimStrength), range: 0...1, step: 0.05, format: SliderRow.percent)
                    .disabled(!s.showNeighbours)
                Toggle("Outline where the window is now (dashed)", isOn: preview(\.showCurrentOutline))
            }

            ResetSection(keeps: "Keeps your custom themes.") {
                model.settings.themeName = Theme.default.name
                applyPreview(of: .default)
            }
        }
        .formStyle(.grouped)
        .onAppear { screenCaptureAllowed = Permissions.isScreenCaptureAllowed }
    }

    private static func caption(for style: PreviewStyle) -> String {
        switch style {
        case .tint: "A box in the preview colour. Appears instantly and looks the same every time."
        case .snapshot: "The box appears first, then a picture of the window fades in, scaled to fit."
        case .appIcon: "The box with the moving app's icon in the middle."
        }
    }

    /// Takes a theme's preview look. Motion owns the morph and spring speed, so picking, deleting or
    /// resetting a theme here must leave those two alone.
    private func applyPreview(of theme: Theme) {
        var preview = theme.preview
        preview.morph = model.settings.preview.morph
        preview.springResponse = model.settings.preview.springResponse
        model.settings.preview = preview
    }

    /// Applies a change to the selected custom theme, forking a built-in one into "Custom" first.
    private func edit(_ change: (inout Theme) -> Void) { model.editTheme(change) }

    /// Preview settings are what the overlay uses right now. A selected custom theme keeps them in step;
    /// a built-in theme is never changed by them (they are captured by "Save as Theme").
    private func preview<T>(_ field: WritableKeyPath<PreviewSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings.preview[keyPath: field] },
            set: { value in
                model.settings.preview[keyPath: field] = value
                if let i = customIndex { model.settings.customThemes[i].preview = model.settings.preview }
            }
        )
    }

    private func colorBinding(_ field: WritableKeyPath<Theme, String>) -> Binding<Color> { model.themeColor(field) }

    private func saveTheme() {
        let base = theme
        var saved = base
        saved.name = trimmedName
        saved.preview = model.settings.preview
        model.settings.customThemes.removeAll { $0.name == saved.name }
        model.settings.customThemes.append(saved)
        model.settings.themeName = saved.name
        newThemeName = ""
    }
}

#Preview {
    OverlayPane(model: SettingsModel())
}
