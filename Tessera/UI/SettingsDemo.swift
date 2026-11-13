import SwiftUI
import TesseraCore

/// The stage beside a pane's form: a mock desktop on the person's wallpaper that acts out the pane's settings.
/// General, Excluded Apps, Updates and About have none; their form takes the full width.
struct SettingsDemo: View {
    let pane: SettingsPane
    let settings: TesseraSettings

    static func exists(for pane: SettingsPane) -> Bool {
        switch pane {
        case .ring, .shortcuts, .cycles, .displays, .splits, .overlay, .motion: true
        case .general, .excludedApps, .updates, .about: false
        }
    }

    var body: some View {
        StageColumn {
            switch pane {
            case .ring: RingDemo(settings: settings)
            case .shortcuts: ShortcutsDemo(settings: settings)
            case .cycles: CyclesDemo(settings: settings)
            case .displays: DisplaysDemo(settings: settings)
            case .splits: SplitsDemo(settings: settings)
            case .motion: MotionDemo(settings: settings)
            case .overlay: AppearanceDemo(settings: settings)
            case .general, .excludedApps, .updates, .about: EmptyView()
            }
        }
        // A new pane starts its own story rather than finishing the last one's.
        .id(pane)
    }
}

/// Appearance pane stage: the overlay as the theme draws it, mid-flick: the ring with Right lit, the "from"
/// outline, the preview with its label, and the window beside it dimmed. The sheet shows the ring large.
private struct AppearanceDemo: View {
    let settings: TesseraSettings

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.stage, settings: settings)
        let v = display.visibleFrame
        let neighbour = DemoWindow(id: 1, frame: CGRect(x: v.minX + v.width * 0.55, y: v.minY + v.height * 0.08,
                                                        width: v.width * 0.4, height: v.height * 0.5))
        let frames = RingDemo.story(settings: settings, display: display, cue: .wedge(2)).frames.prefix(3).map { frame in
            var frame = frame
            frame.windows.insert(neighbour, at: 0)
            frame.caption = frame.preview == nil ? frame.caption : "The preview, its label and the dimming, in this theme."
            return frame
        }
        let theme = settings.activeTheme
        StagePlayer(display: display, settings: settings, frames: Array(frames)) { index in
            RingDiagram(ring: settings.ring, fill: Color(hex: theme.ring.fillHex), tint: theme.ring.opacity,
                        stroke: Color(hex: theme.ring.strokeHex), accent: Color(hex: theme.accentHex),
                        active: index >= 2 ? 2 : nil, focused: nil, showBoundary: false)
                .frame(width: 170, height: 170)
                .opacity(settings.ring.showRing ? 1 : 0.25)
        }
    }
}
