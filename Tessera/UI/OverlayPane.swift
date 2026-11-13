import SwiftUI
import TesseraCore

/// The Appearance pane (key `overlay`): a sample, the theme, the ring's look, every colour, and the preview layers.
/// A theme is a snapshot of the colours and preview settings; picking one applies them together.
struct OverlayPane: View {
    @Bindable var model: SettingsModel
    @State private var newThemeName = ""
    @State private var screenCaptureAllowed = Permissions.isScreenCaptureAllowed
    @State private var confirmingDelete = false

    /// Name of the theme that takes edits made to a built-in theme.
    private static let editedName = SettingsModel.editedThemeName

    private var theme: Theme { model.settings.selectedTheme }
    private var customIndex: Int? { model.customThemeIndex }
    private var trimmedName: String { newThemeName.trimmingCharacters(in: .whitespaces) }
    private var nameTakenByBuiltIn: Bool { Theme.builtIn.contains { $0.name == trimmedName } }
    /// "Custom" is where colour edits to a built-in theme land, overwriting it each time.
    private var nameReserved: Bool { trimmedName == Self.editedName }
    private var canSave: Bool { !(trimmedName.isEmpty || nameTakenByBuiltIn || nameReserved) }

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
                    .help("Shows the message a shortcut gives. No window moves.")
                    .settingAnchor("Preview Shortcut")
                    Button("Show on Screen") {
                        NotificationCenter.default.post(name: .tesseraPreviewOverlay, object: nil)
                    }
                    .help("Shows the ring on screen for three seconds. No window moves.")
                    .settingAnchor("Show on Screen")
                }
            }

            Section {
                // Re-picking the current theme must not throw away preview changes made since it was picked.
                Picker("Theme", selection: Binding.choice(model.settings.themeName) { name in
                    model.settings.themeName = name
                    applyPreview(of: model.settings.selectedTheme)
                }) {
                    ForEach(model.settings.allThemes, id: \.name) { Text($0.name).tag($0.name) }
                }
                .settingAnchor("Theme")
                HStack {
                    TextField("Save the current look as", text: $newThemeName, prompt: Text("Theme name"))
                        .onSubmit { if canSave { saveTheme() } }
                    Button("Save Theme") { saveTheme() }
                        .disabled(!canSave)
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
                        let name = model.settings.customThemes[customIndex].name
                        Button("Delete \u{201C}\(name)\u{201D}\u{2026}", role: .destructive) { confirmingDelete = true }
                            .confirmationDialog("Delete the theme \u{201C}\(name)\u{201D}?", isPresented: $confirmingDelete,
                                                titleVisibility: .visible) {
                                Button("Delete Theme", role: .destructive) { deleteSelectedTheme() }
                                Button("Cancel", role: .cancel) {}
                            }
                    }
                }
            } header: {
                InfoHeader("Theme", info: "A theme saves the colours and preview settings on this page. "
                    + (customIndex == nil
                        ? "Built-in themes never change: when you change a colour, Tessera saves it as \u{201C}\(Self.editedName)\u{201D}."
                        : "Changes save to \u{201C}\(theme.name)\u{201D} as you make them."))
            }

            RingLookSections(model: model)

            Section {
                ColorPicker("Ring", selection: colorBinding(\.ring.fillHex), supportsOpacity: false).settingAnchor("Ring")
                SliderRow(title: "Ring tint", value: Binding(
                    get: { theme.ring.opacity }, set: { v in edit { $0.ring.opacity = v } }
                ), range: 0...1, step: 0.05, format: SliderRow.percent)
                ColorPicker("Lines and icons", selection: colorBinding(\.ring.strokeHex), supportsOpacity: false).settingAnchor("Lines and icons")
                ColorPicker("Selected layout", selection: colorBinding(\.accentHex), supportsOpacity: false).settingAnchor("Selected layout")
                ColorPicker("Grid", selection: colorBinding(\.ring.gridHex), supportsOpacity: false).settingAnchor("Grid")
            } header: {
                Text("Ring colours")
            }

            Section {
                ColorPicker("Snap preview", selection: colorBinding(\.previewHex), supportsOpacity: false).settingAnchor("Snap preview")
                ColorPicker("Label", selection: colorBinding(\.labelHex), supportsOpacity: false).settingAnchor("Label")
                ColorPicker("Label text", selection: colorBinding(\.labelTextHex), supportsOpacity: false).settingAnchor("Label text")
                ColorPicker("Outline of the current frame", selection: colorBinding(\.outlineHex), supportsOpacity: false).settingAnchor("Outline of the current frame")
                ColorPicker("Dimming", selection: colorBinding(\.dimHex), supportsOpacity: false).settingAnchor("Dimming")
            } header: {
                Text("Preview and label colours")
            }

            Section("Preview") {
                Picker("Fill the preview with", selection: preview(\.style)) {
                    ForEach(PreviewStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .settingAnchor("Fill the preview with")
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
                SliderRow(title: "Border width", value: preview(\.borderWidth), range: 0...10, step: 0.5,
                          format: { String(format: "%g pt", $0) })
                Toggle("Match the window's corner radius", isOn: preview(\.useWindowCornerRadius)).settingAnchor("Match the window's corner radius")
                SliderRow(title: "Corner radius", value: preview(\.cornerRadius), range: 0...30)
                    .disabled(s.useWindowCornerRadius)
            }

            Section("Label") {
                Toggle("Show a label on the preview", isOn: preview(\.showLabel)).settingAnchor("Show a label on the preview")
                Group {
                    Toggle("Size in points", isOn: preview(\.labelShowsSize)).settingAnchor("Size in points")
                    Toggle("Slot name", isOn: preview(\.labelShowsSlot)).settingAnchor("Slot name")
                    Picker("Position", selection: preview(\.labelPosition)) {
                        Text("Centre").tag(LabelPosition.center)
                        Text("Bottom").tag(LabelPosition.bottom)
                    }
                    .pickerStyle(.segmented)
                    .settingAnchor("Position")
                }
                .disabled(!s.showLabel)
                if s.showLabel, !s.labelShowsSize, !s.labelShowsSlot {
                    Caption("With both parts off, no label is shown.")
                }
            }

            Section("Around the preview") {
                Toggle("Dim the windows the preview covers", isOn: preview(\.showNeighbours)).settingAnchor("Dim the windows the preview covers")
                SliderRow(title: "Dim strength", value: preview(\.dimStrength), range: 0...1, step: 0.05, format: SliderRow.percent)
                    .disabled(!s.showNeighbours)
                Toggle("Outline where the window is now (dashed)", isOn: preview(\.showCurrentOutline)).settingAnchor("Outline where the window is now (dashed)")
            }

            ResetSection(keeps: "Keeps your saved themes.") {
                model.settings.themeName = Theme.default.name
                applyPreview(of: .default)
                model.settings.ring.takeLook(from: .default)
            }
        }
        .formStyle(.grouped)
        .onAppear { screenCaptureAllowed = Permissions.isScreenCaptureAllowed }
        // The permission is granted in System Settings, so re-read it when the person comes back to Tessera.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenCaptureAllowed = Permissions.isScreenCaptureAllowed
        }
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

    private func deleteSelectedTheme() {
        guard let customIndex else { return }
        model.settings.customThemes.remove(at: customIndex)
        model.settings.themeName = Theme.default.name
        applyPreview(of: .default)
    }

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
