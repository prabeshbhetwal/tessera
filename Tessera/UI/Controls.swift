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
                Slider(value: $value, in: range, step: step)
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

/// Final section of every pane.
struct ResetSection: View {
    let action: () -> Void

    var body: some View {
        Section {
            HStack {
                Spacer()
                Button("Reset section", action: action)
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
            .shadow(color: .black.opacity(0.1), radius: 0, y: 1)
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
