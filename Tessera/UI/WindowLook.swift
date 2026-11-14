import AppKit
import SwiftUI
import TesseraCore

/// What each part of the Settings window sits on, in the look chosen in General › Window look: the sidebar, the pane
/// behind the form, and the stage. Form cards stay on top, so text never depends on the desktop. Reduce Transparency
/// and Increase Contrast draw Solid. Switching looks cross-fades (instantly with Reduce Motion).
struct WindowBackdrop: View {
    enum Surface { case sidebar, pane, stage }

    let look: WindowMaterial
    let surface: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// The look actually drawn, after Reduce Transparency.
    static func effective(_ look: WindowMaterial, reduceTransparency: Bool) -> WindowMaterial {
        reduceTransparency ? .solid : look
    }

    private var drawn: WindowMaterial {
        contrast == .increased ? .solid : Self.effective(look, reduceTransparency: reduceTransparency)
    }

    var body: some View {
        ZStack {
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
