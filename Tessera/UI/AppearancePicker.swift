import SwiftUI
import TesseraCore

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
