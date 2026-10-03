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

    static func describe(_ codes: Set<UInt16>) -> String {
        let names = all.filter { codes.contains($0.code) }.map(\.name)
        return names.isEmpty ? "None" : names.joined(separator: " + ")
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
