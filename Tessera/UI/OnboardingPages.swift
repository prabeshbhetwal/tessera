import SwiftUI

/// Setup's tiling step: Tile All Windows, splits learned from hand adjustments, and closed windows leaving no hole.
struct OnboardingTilingStep: View {
    var body: some View {
        StepPage(
            symbol: "rectangle.split.3x1.fill", title: "Tiling that remembers",
            text: "Tile All Windows (⌃⌥T by default) puts every window on a display side by side. Tessera then learns from how you arrange them."
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                GestureHint("arrow.left.and.right", "Drag the edge between two windows: the one beside it follows, and Tessera saves the layout as your split for those apps.")
                GestureHint("rectangle.3.group", "Tile All Windows again any time to put those apps back the way you left them.")
                GestureHint("xmark.rectangle", "Close a window and the others fill its space: your split for the apps left, or the window beside it you used last.")
                GestureHint("arrow.uturn.backward", "Not what you wanted? Undo (⌃⌥Z by default) puts the windows back. Settings › Splits turns any of this off.")
            }
            .frame(maxWidth: 480)
        }
    }
}

// MARK: - Building blocks shared by setup's steps

/// Centred step layout: neutral icon tile, title, body, then the step's controls.
struct StepPage<Extra: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quinary))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title).font(.title.weight(.bold))
                Text(text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            extra
        }
        .frame(maxWidth: .infinity)
    }
}

/// Plain secondary symbol next to one gesture description.
struct GestureHint: View {
    let symbol: String
    let text: String

    init(_ symbol: String, _ text: String) {
        self.symbol = symbol
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
