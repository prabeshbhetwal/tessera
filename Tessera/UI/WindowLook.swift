import AppKit
import SwiftUI
import TesseraCore

/// What each part of the Settings window sits on, in the look chosen in General › Window look: the sidebar, the pane
/// behind the form, and the stage. Form cards stay on top, so text never depends on the desktop. Reduce Transparency
/// and Increase Contrast draw Solid; Liquid Glass needs macOS 26 and draws as Frosted before it. Switching looks
/// cross-fades (instantly with Reduce Motion).
struct WindowBackdrop: View {
    enum Surface { case sidebar, pane, stage }

    let look: WindowMaterial
    let surface: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// The look actually drawn, after Reduce Transparency and the macOS version.
    static func effective(_ look: WindowMaterial, reduceTransparency: Bool) -> WindowMaterial {
        if reduceTransparency { return .solid }
        if look == .liquidGlass, #unavailable(macOS 26) { return .frosted }
        return look
    }

    private var drawn: WindowMaterial {
        contrast == .increased ? .solid : Self.effective(look, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        ZStack {
            // Liquid Glass and Frosted share this layer; the sidebar's glass pane is drawn on top by `SidebarGlassPane`.
            if drawn == .solid {
                solid.transition(.opacity)
            } else {
                material.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: drawn)
    }

    /// Opaque, with the sidebar a step away from the content so the two never merge: grey beside white in light,
    /// lifted grey beside near black in dark, the way Mail and Finder draw it with Reduce Transparency.
    @ViewBuilder private var solid: some View {
        switch surface {
        // The system window colour is white in light mode on macOS 26, the same as the pane: the sidebar takes a
        // fixed step of the label colour over it so the two never merge (light grey in light, lifted grey in dark).
        case .sidebar: Color(nsColor: .windowBackgroundColor).overlay(Color(nsColor: .labelColor).opacity(0.05))
        case .pane: Color(nsColor: .textBackgroundColor)
        case .stage: Color(nsColor: .underPageBackgroundColor)
        }
    }

    /// The desktop blurred through Apple's material for this surface, under a colourless top-to-bottom shade. Any hue
    /// comes from the desktop: macOS tints window materials with what is behind them.
    private var material: some View {
        WindowGlass(material: blur)
            .overlay {
                LinearGradient(colors: [Color(nsColor: .labelColor).opacity(0),
                                        Color(nsColor: .labelColor).opacity(colorScheme == .dark ? 0.10 : 0.05)],
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

/// The Liquid Glass sidebar: one pane of glass floating `inset` in from the window's top, left and bottom edges, its
/// corners concentric with the window's, the window buttons sitting on it as in System Settings.
struct SidebarGlassPane: View {
    let inset: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(macOS 26, *) {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            // In dark mode the glass is shaded a little, or its lift leaves white labels at the 4.5:1 edge.
            let glass: Glass = colorScheme == .dark ? .regular.tint(.black.opacity(0.25)) : .regular
            shape.fill(.clear)
                .glassEffect(glass, in: shape)
                .padding(inset)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
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
