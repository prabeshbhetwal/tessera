import AppKit
import SwiftUI
import TesseraCore

/// What each part of the Settings window sits on, in the look chosen in General › Window look. The whole window takes
/// part: the sidebar, the pane behind the form, and the stage. Form cards stay opaque on top, so text never depends on
/// the desktop. Reduce Transparency and Increase Contrast draw Solid without the shading; Liquid Glass needs macOS 26
/// and draws as Frosted before it.
struct WindowBackdrop: View {
    enum Surface { case sidebar, pane, stage }

    let look: WindowMaterial
    let surface: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// The look actually drawn, after Reduce Transparency and the macOS version.
    static func effective(_ look: WindowMaterial, reduceTransparency: Bool) -> WindowMaterial {
        if reduceTransparency { return .solid }
        if look == .liquidGlass, #unavailable(macOS 26) { return .frosted }
        return look
    }

    /// Reduce Transparency or Increase Contrast: flat and opaque, no shading.
    private var plain: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        if plain {
            Color(nsColor: .windowBackgroundColor)
        } else {
            switch Self.effective(look, reduceTransparency: false) {
            case .solid:
                // Opaque tone on tone, so Solid still has depth.
                LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                               startPoint: .top, endPoint: .bottom)
            case .frosted:
                material
            case .liquidGlass:
                ZStack {
                    material
                    if #available(macOS 26, *), surface == .sidebar {
                        // The sidebar floats as a pane of glass inset from the window's edges, as in System Settings.
                        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                        // In dark mode the glass is shaded a little, or its lift leaves white labels at the 4.5:1 edge.
                        let glass: Glass = colorScheme == .dark ? .regular.tint(.black.opacity(0.25)) : .regular
                        shape.fill(.clear).glassEffect(glass, in: shape).padding(8)
                    }
                }
            }
        }
    }

    /// The desktop blurred through Apple's material for this surface, under a colourless top-to-bottom shade. Any hue
    /// comes from the desktop: macOS tints window materials with what is behind them.
    private var material: some View {
        WindowGlass(material: blur)
            .overlay {
                LinearGradient(colors: [Color(nsColor: .labelColor).opacity(0),
                                        Color(nsColor: .labelColor).opacity(colorScheme == .dark ? 0.10 : 0.06)],
                               startPoint: .top, endPoint: .bottom)
            }
    }

    private var blur: NSVisualEffectView.Material {
        switch surface {
        case .sidebar: .sidebar
        case .pane: .windowBackground  // made for text, so section headers on it stay readable
        case .stage: .underWindowBackground
        }
    }
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
