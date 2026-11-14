import AppKit
import SwiftUI

/// What each part of the Settings window sits on, the way System Settings, Finder and Mail draw it: only the sidebar
/// lets the desktop show through (the system `.sidebar` material); the form and the stage are opaque, so their text
/// and the stage's mock desktop never depend on the wallpaper. The material turns opaque by itself under Reduce
/// Transparency and adapts to Increase Contrast.
struct WindowBackdrop: View {
    enum Surface { case sidebar, pane, stage }

    let surface: Surface

    var body: some View {
        switch surface {
        case .sidebar: WindowGlass(material: .sidebar)
        case .pane: Color(nsColor: .windowBackgroundColor)
        case .stage: Color(nsColor: .underPageBackgroundColor)
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
