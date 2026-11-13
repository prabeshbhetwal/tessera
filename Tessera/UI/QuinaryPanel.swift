import SwiftUI

/// The shared `.quinary` rounded panel. Under Increase Contrast it gains a 1 pt `.separator` stroke, because the
/// quinary fill alone is too faint to mark the panel's edge.
private struct QuinaryPanel: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.quinary, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(.separator, lineWidth: 1).allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Backs the view with the shared `.quinary` panel (the stroke is added by Increase Contrast).
    func quinaryPanel(cornerRadius: CGFloat = 8) -> some View {
        modifier(QuinaryPanel(cornerRadius: cornerRadius))
    }
}
