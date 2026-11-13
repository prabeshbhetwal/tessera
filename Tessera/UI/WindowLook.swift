import AppKit
import SwiftUI
import TesseraCore

/// What a Settings surface sits on, in the look chosen in General › Window look. Reduce Transparency draws every look
/// as Solid; Liquid Glass needs macOS 26 and draws as Frosted before it.
struct WindowBackdrop: View {
    enum Surface { case sidebar, stage }

    let look: WindowMaterial
    let surface: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The look actually drawn, after Reduce Transparency and the macOS version.
    static func effective(_ look: WindowMaterial, reduceTransparency: Bool) -> WindowMaterial {
        if reduceTransparency { return .solid }
        if look == .liquidGlass, #unavailable(macOS 26) { return .frosted }
        return look
    }

    var body: some View {
        let drawn = Self.effective(look, reduceTransparency: reduceTransparency)
        base(drawn)
            // A soft neutral shade, so the stage's glass windows have something to stand on; see-through unless Solid.
            .overlay { if surface == .stage { tint.opacity(drawn == .solid ? 0.5 : 1) } }
    }

    private var tint: LinearGradient {
        LinearGradient(colors: [Color.primary.opacity(0.12), Color.primary.opacity(0.04)],
                       startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder private func base(_ drawn: WindowMaterial) -> some View {
        switch drawn {
        case .solid:
            Color(nsColor: surface == .sidebar ? .windowBackgroundColor : .underPageBackgroundColor)
        case .frosted:
            WindowGlass(material: blur)
        case .liquidGlass:
            if #available(macOS 26, *) {
                ZStack {
                    WindowGlass(material: blur)
                    // The sidebar floats as a pane of glass inset from the window's edges, as in System Settings.
                    if surface == .sidebar {
                        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                        shape.fill(.clear)
                            .glassEffect(.regular, in: shape)
                            .padding(8)
                    }
                }
            }
        }
    }

    private var blur: NSVisualEffectView.Material { surface == .sidebar ? .sidebar : .underWindowBackground }
}

/// Blurs what is behind the window (SwiftUI materials only blur inside it).
struct WindowGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
