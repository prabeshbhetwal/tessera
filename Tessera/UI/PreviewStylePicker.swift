import AppKit
import SwiftUI
import TesseraCore

/// "Fill the preview with": the three fills drawn as the theme draws the preview (its colour, opacity and border),
/// so the choice is seen rather than described.
struct PreviewStylePicker: View {
    @Binding var selection: PreviewStyle
    let theme: Theme

    var body: some View {
        ThumbnailPicker(selection: $selection, options: PreviewStyle.allCases, title: \.displayName) { style in
            ZStack {
                Color(white: 0.5).opacity(0.18)
                preview(style)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    private func preview(_ style: PreviewStyle) -> some View {
        let colour = Color(hex: theme.previewHex)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return shape.fill(colour.opacity(max(theme.preview.opacity, 0.2)))
            .overlay {
                switch style {
                case .tint: EmptyView()
                case .snapshot: MiniWindow(dark: false).scaleEffect(0.62).clipShape(shape).padding(3)
                case .appIcon: Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                }
            }
            .overlay(shape.strokeBorder(colour, lineWidth: 1.5))
    }
}
