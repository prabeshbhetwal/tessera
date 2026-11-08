import SwiftUI
import TesseraCore

/// Static picture of the overlay: the ring with its glyphs and the active wedge, next to a preview frame
/// with its label, over a mock desktop. Uses the same geometry as the real layers.
struct OverlaySample: View {
    let ring: RingSettings
    let theme: Theme

    var body: some View {
        let preview = theme.preview
        let accent = Color(hex: theme.accentHex)
        let previewColor = Color(hex: theme.previewHex)
        let stroke = Color(hex: theme.ring.strokeHex)
        let ringFill = Color(hex: theme.ring.fillHex)
        let label = PreviewModel.label(
            for: .wedge(index: 2, action: .rightHalf), frame: CGRect(x: 0, y: 0, width: 756, height: 949),
            size: preview.labelShowsSize, slot: preview.labelShowsSlot)
        // Mock desktop: the ring, a window outlined as the "from" frame, and the preview over a dimmed window.
        HStack(spacing: 22) {
            RingDiagram(ring: ring, fill: ringFill, tint: theme.ring.opacity, stroke: stroke, accent: accent,
                        active: 2, focused: nil, showBoundary: false)
                .frame(width: 140, height: 140)
                .opacity(ring.showRing ? 1 : 0.15)
                .overlay { if !ring.showRing { Caption("Ring hidden") } }
            Group {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                    .overlay {
                        if preview.showCurrentOutline {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(hex: theme.outlineHex).opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .shadow(color: .black.opacity(0.4), radius: 1)
                                .padding(10)
                        }
                    }
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                    if preview.showNeighbours {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: theme.dimHex).opacity(preview.dimStrength))
                    }
                    let radius = preview.useWindowCornerRadius ? 10 : preview.cornerRadius
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(previewColor.opacity(preview.opacity))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(previewColor, lineWidth: preview.borderWidth))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .padding(6)
                    switch preview.style {
                    case .tint:
                        EmptyView()
                    case .snapshot:
                        MockWindow().padding(16)
                    case .appIcon:
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 36, height: 36)
                    }
                    if preview.showLabel, let label {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: theme.labelTextHex))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: theme.labelHex).opacity(0.82), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                            .offset(y: preview.labelPosition == .bottom ? 38 : 0)
                    }
                }
            }
            .frame(width: 160, height: 120)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Overlay sample: the ring with the right half selected, and the preview frame.")
    }
}

/// Stand-in for a window snapshot in the sample: title bar with traffic lights over a body.
private struct MockWindow: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 6, height: 6) }
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 14)
            .background(.quaternary)
            Rectangle().fill(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)) }
    }
}
