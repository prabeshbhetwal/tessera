import SwiftUI
import TesseraCore

/// Labelled slider with its current value shown on the right.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0.rounded())) pt" }

    var body: some View {
        LabeledContent(title) {
            HStack {
                // No `step:` argument: AppKit draws a tick mark for every step. The binding rounds instead.
                Slider(value: Binding(
                    get: { value },
                    set: { value = min(max((($0 - range.lowerBound) / step).rounded() * step + range.lowerBound, range.lowerBound), range.upperBound) }
                ), in: range)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue(format(value))
                Text(format(value))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }
    static func seconds(_ v: Double) -> String { v == 0 ? "Off" : String(format: "%.2f s", v) }
}

/// Labelled stepper with its value shown next to the control, like `SliderRow`.
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Text(format(value)).monospacedDigit()
                Stepper(title, value: $value, in: range).labelsHidden()
            }
        }
    }
}

/// Secondary explanatory text, used under controls that are disabled or have side effects.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension Binding where Value: Equatable {
    /// Binding for a picker that rebuilds a value when its option changes (a kind, a mode, a theme).
    /// `apply` runs only when a different option is picked: picking the current one again is a no-op, so it
    /// can never reset what that option already holds (e.g. re-picking "Action" turning "Left half" into the
    /// default). Use it for every such picker.
    static func choice(_ current: Value, apply: @escaping (Value) -> Void) -> Binding {
        Binding(get: { current }, set: { if $0 != current { apply($0) } })
    }
}

/// Explanation under a group, the way System Settings puts it: outside the rounded box, leading-aligned.
struct Footer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Match System, Light or Dark as three window thumbnails, like System Settings › Appearance.
struct AppearancePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 28) {
            Spacer(minLength: 0)
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Button { selection = mode } label: {
                    VStack(spacing: 8) {
                        thumbnail(mode)
                            .frame(width: 92, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selection == mode ? Color.accentColor : Color.primary.opacity(0.15),
                                              lineWidth: selection == mode ? 3 : 1))
                        Text(mode.displayName)
                            .font(.callout.weight(selection == mode ? .semibold : .regular))
                            .foregroundStyle(selection == mode ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selection == mode ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func thumbnail(_ mode: AppearanceMode) -> some View {
        switch mode {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniWindow(dark: false).frame(width: 46).clipped()
                MiniWindow(dark: true).frame(width: 46).clipped()
            }
        }
    }
}

/// A tiny window sketch: desktop, title bar, sidebar and two content lines.
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let desk = dark ? Color(white: 0.18) : Color(white: 0.86)
        let window = dark ? Color(white: 0.27) : Color.white
        let line = dark ? Color(white: 0.45) : Color(white: 0.8)
        ZStack(alignment: .topLeading) {
            desk
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 4, height: 4) }
                }
                HStack(alignment: .top, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5).fill(line.opacity(0.6)).frame(width: 14, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 34, height: 4)
                        RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 46, height: 4)
                        RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 28, height: 4)
                    }
                }
            }
            .padding(6)
            .frame(width: 80, height: 46, alignment: .topLeading)
            .background(window, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.leading, 6)
            .padding(.top, 8)
        }
    }
}

/// Inline notice with an icon: side effects, warnings and results that a plain caption would bury.
struct Callout<Action: View>: View {
    enum Kind { case info, warning, success }

    let kind: Kind
    let text: String
    let action: Action

    init(_ kind: Kind, _ text: String, @ViewBuilder action: () -> Action) {
        self.kind = kind
        self.text = text
        self.action = action()
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .info: .secondary
        case .warning: .orange
        case .success: .green
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

extension Callout where Action == EmptyView {
    init(_ kind: Kind, _ text: String) {
        self.init(kind, text) { EmptyView() }
    }
}

/// Final section of every pane: one verb everywhere, with an optional line saying what is kept.
struct ResetSection: View {
    var keeps: String? = nil
    let action: () -> Void

    init(keeps: String? = nil, action: @escaping () -> Void) {
        self.keeps = keeps
        self.action = action
    }

    var body: some View {
        Section {
            HStack {
                if let keeps { Caption(keeps) }
                Spacer()
                Button("Restore Defaults", action: action)
            }
        }
    }
}

/// Device-specific modifier keycodes and their `NX_DEVICE*KEYMASK` bits.
enum ModifierKey {
    static let all: [(code: UInt16, mask: UInt, name: String)] = [
        (59, 0x0001, "Left ⌃"), (62, 0x2000, "Right ⌃"),
        (58, 0x0020, "Left ⌥"), (61, 0x0040, "Right ⌥"),
        (55, 0x0008, "Left ⌘"), (54, 0x0010, "Right ⌘"),
        (56, 0x0002, "Left ⇧"), (60, 0x0004, "Right ⇧"),
        (63, 0x80_0000, "fn"),
    ]

    static func pressed(in flags: NSEvent.ModifierFlags) -> Set<UInt16> {
        Set(all.filter { flags.rawValue & $0.mask != 0 }.map(\.code))
    }

    /// Names of the held keys in the table's order (left before right, ⌃ ⌥ ⌘ ⇧ fn).
    static func names(_ codes: Set<UInt16>) -> [String] {
        all.filter { codes.contains($0.code) }.map(\.name)
    }

    static func describe(_ codes: Set<UInt16>) -> String {
        let names = names(codes)
        return names.isEmpty ? "None" : names.joined(separator: " + ")
    }
}

/// Modifier or key names drawn as keycaps, joined by "+".
struct KeycapRow: View {
    let keys: [String]
    var prominent = false

    var body: some View {
        HStack(spacing: 6) {
            if keys.isEmpty {
                Text("No trigger set").foregroundStyle(.secondary)
            }
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                if i > 0 { Text("+").foregroundStyle(.tertiary) }
                Keycap(key, prominent: prominent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.isEmpty ? "No trigger set" : keys.joined(separator: " plus "))
    }
}

/// One key drawn as a keycap.
struct Keycap: View {
    let text: String
    var prominent = false

    init(_ text: String, prominent: Bool = false) {
        self.text = text
        self.prominent = prominent
    }

    var body: some View {
        Text(text)
            .font(.system(prominent ? .title3 : .callout, design: .rounded).weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, prominent ? 14 : 10)
            .padding(.vertical, prominent ? 8 : 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// Invisible button that only exists to carry a keyboard shortcut (pane switching, onboarding Esc).
struct KeyCommand: View {
    let shortcut: KeyboardShortcut
    let action: () -> Void

    init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void) {
        shortcut = KeyboardShortcut(key, modifiers: modifiers)
        self.action = action
    }

    init(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        self.shortcut = shortcut
        self.action = action
    }

    /// Borderless with an empty label: a bordered button squeezed to 0×0 has negative bezel width,
    /// which AppKit re-lays out on every display cycle (endless layout, high CPU).
    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(.plain)
            .keyboardShortcut(shortcut)
            .frame(width: 0, height: 0)
            .focusable(false)
            .accessibilityHidden(true)
    }
}

/// Theme editing shared by every pane that shows a theme colour (Ring, Overlay).
extension SettingsModel {
    /// Name of the theme that takes edits made while a built-in theme is selected.
    static let editedThemeName = "Custom"

    var customThemeIndex: Int? { settings.customThemes.firstIndex { $0.name == settings.themeName } }

    /// Applies `change` to the selected theme. A built-in theme is never changed: it is first copied to
    /// "Custom" (with the live preview settings) and that copy is selected and edited.
    func editTheme(_ change: (inout Theme) -> Void) {
        if customThemeIndex == nil {
            var forked = settings.selectedTheme
            forked.name = Self.editedThemeName
            forked.preview = settings.preview
            settings.customThemes.removeAll { $0.name == Self.editedThemeName }
            settings.customThemes.append(forked)
            settings.themeName = Self.editedThemeName
        }
        guard let i = customThemeIndex else { return }
        change(&settings.customThemes[i])
    }

    /// A colour well's binding for one theme colour. Writing back an unchanged colour does nothing, so merely
    /// opening and closing a well never forks a built-in theme.
    func themeColor(_ field: WritableKeyPath<Theme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: self.settings.selectedTheme[keyPath: field]) },
            set: { color in
                guard color.hex != self.settings.selectedTheme[keyPath: field].uppercased() else { return }
                self.editTheme { $0[keyPath: field] = color.hex }
            }
        )
    }

    /// The selected theme's ring tint (0...1), editable like a colour.
    var themeRingTint: Binding<Double> {
        Binding(get: { self.settings.selectedTheme.ring.opacity }, set: { v in self.editTheme { $0.ring.opacity = v } })
    }
}

extension TesseraSettings {
    /// Built-in themes first, then the user's.
    var allThemes: [Theme] { Theme.builtIn + customThemes }

    /// The theme picked in Appearance, falling back to Default.
    var selectedTheme: Theme { allThemes.first { $0.name == themeName } ?? .default }

    /// What the overlay draws with: the selected theme's ring and accent plus the user's preview settings.
    var activeTheme: Theme {
        var theme = selectedTheme
        theme.preview = preview
        return theme
    }
}

extension Color {
    init(hex: String) { self.init(cgColor: HexColor.cgColor(hex)) }
    var hex: String { HexColor.hex(NSColor(self).cgColor) }
}
