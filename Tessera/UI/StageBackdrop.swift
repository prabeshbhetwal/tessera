import AppKit
import SwiftUI
import TesseraCore

/// The Settings window's right-hand stage: edge to edge, on the person's own wallpaper.
struct StageColumn<Content: View>: View {
    static var width: CGFloat { 420 }
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .background { StageWallpaper() }
            .clipped()
    }
}

/// The current desktop picture, read once, scaled down and kept in memory; never sent anywhere. A soft gradient
/// in the accent colour when it can't be read (a folder of pictures, a dynamic wallpaper without a still, the
/// screenshot harness).
struct StageWallpaper: View {
    @MainActor private static let image: NSImage? = load()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: [.accentColor.opacity(0.85), .purple.opacity(0.55), .cyan.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(.background)
        }
    }

    @MainActor private static func load() -> NSImage? {
        guard ProcessInfo.processInfo.environment["TESSERA_SETTINGS_SNAPSHOTS"] == nil,
              let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              !url.hasDirectoryPath,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1400,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later; a frosted material before that. `clear` is the lighter variant.
    /// `tint` lays the window background colour under the glass, so text and edges stay readable on any
    /// wallpaper (and under Reduce Transparency).
    @ViewBuilder func stageGlass(cornerRadius: CGFloat, clear: Bool = false, tint: Double = 0.3) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tinted = background(Color(nsColor: .windowBackgroundColor).opacity(tint), in: shape)
        if #available(macOS 26, *) {
            tinted.glassEffect(clear ? .clear : .regular, in: shape)
        } else {
            tinted.background(clear ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial), in: shape)
        }
    }
}

/// Displays for the demos, sized by `TesseraCore` the way `DisplayService` sizes a real screen.
enum DemoDisplay {
    /// The stage's own screen, a little taller than a laptop's so the column has more desktop than sheet.
    static let stage = CGSize(width: 1512, height: 1400)
    static let laptop = CGSize(width: 1512, height: 982)
    static let ultrawide = CGSize(width: 3440, height: 1440)

    /// A display of `size`, its columns sized from `settings` as a new display would be. With `menuBar`, the top
    /// 33 pt are the menu bar and out of the visible frame.
    static func context(_ size: CGSize, settings: TesseraSettings, menuBar: Bool = false) -> DisplayContext {
        let frame = CGRect(origin: .zero, size: size)
        let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - (menuBar ? 33 : 0))
        let range = SizingRule.range(for: visible.size, constants: settings.sizing)
        return DisplayContext(
            id: DisplayID(vendor: 0, model: 0, serial: 0, uuid: "demo"), frame: frame, visibleFrame: visible,
            range: range, profile: .auto(range: range, gap: settings.defaultGap, padding: settings.defaultPadding))
    }

    /// A window that hasn't been snapped yet: off-centre, about half the screen.
    static func loose(on display: DisplayContext) -> CGRect {
        let v = display.visibleFrame
        return CGRect(x: v.minX + v.width * 0.12, y: v.minY + v.height * 0.18, width: v.width * 0.48, height: v.height * 0.6)
    }
}

/// The sidebar material, blurring what is behind the window (SwiftUI materials only blur inside it).
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
