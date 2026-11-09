import SwiftUI

/// Rounded, tinted tile with a white symbol: sidebar rows and pane headers.
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 20

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        // Fit every glyph into the same box so wide and tall symbols read at the same size.
        Image(systemName: pane.symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: size * 0.58, height: size * 0.58)
            .frame(width: size, height: size)
            .background(tile.fill(pane.tint))
            .overlay(tile.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Title and purpose at the top of a pane, above its form.
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PaneIcon(pane: pane, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title).font(.title2.weight(.semibold))
                Text(pane.blurb)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
