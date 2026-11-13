import SwiftUI
import TesseraCore

/// Match System, Light or Dark as three window thumbnails, like System Settings › Appearance.
struct AppearancePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        ThumbnailPicker(selection: $selection, options: AppearanceMode.allCases, title: \.displayName) { thumbnail($0) }
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

/// Choices drawn as small pictures with their names under them, the selected one outlined in the accent colour.
/// For choices a picture explains better than a word (light or dark, how the snap preview is filled).
struct ThumbnailPicker<Value: Hashable, Thumbnail: View>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @ViewBuilder let thumbnail: (Value) -> Thumbnail

    var body: some View {
        HStack(spacing: 28) {
            Spacer(minLength: 0)
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button { selection = option } label: {
                    VStack(spacing: 8) {
                        thumbnail(option)
                            .frame(width: 92, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15),
                                              lineWidth: selected ? 3 : 1))
                        Text(title(option))
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// A tiny window sketch: desktop, title bar, sidebar and two content lines.
struct MiniWindow: View {
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

/// Liquid Glass, Frosted or Solid for the Settings window, each a small window on a toned desk so the sidebar shows
/// how much of the desk comes through.
struct WindowLookPicker: View {
    @Binding var selection: WindowMaterial

    var body: some View {
        ThumbnailPicker(selection: $selection, options: WindowMaterial.allCases, title: \.displayName) { LookThumbnail(look: $0) }
    }
}

private struct LookThumbnail: View {
    let look: WindowMaterial

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(white: 0.42), Color(white: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                sidebar.frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 30, height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.2)).frame(width: 40, height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.2)).frame(width: 24, height: 4)
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(width: 80, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.leading, 6)
            .padding(.top, 8)
        }
    }

    @ViewBuilder private var sidebar: some View {
        switch look {
        case .liquidGlass:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.42))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 0.5))
                .padding(2.5)
        case .frosted: Rectangle().fill(.white.opacity(0.3))
        case .solid: Color(nsColor: .underPageBackgroundColor)
        }
    }
}
