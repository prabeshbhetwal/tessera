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

/// The current desktop picture, decoded once off the main thread, scaled down and kept in memory for the app's
/// life; never sent anywhere. A soft accent gradient until it arrives, and for good when it can't be read (a folder
/// of pictures, the screenshot harness).
struct StageWallpaper: View {
    @State private var store = WallpaperStore.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [.accentColor.opacity(0.85), .purple.opacity(0.55), .cyan.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(.background)
            if let image = store.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.image != nil)
        // Scaled to fill, a wide picture runs far past the stage's 420 pt. `.clipped()` trims only the drawing, so
        // the unseen overflow still took every click and drag over the form beside it, freezing its controls.
        .allowsHitTesting(false)
        .onAppear { store.load() }
    }
}

@MainActor @Observable
final class WallpaperStore {
    static let shared = WallpaperStore()
    private(set) var image: NSImage?
    @ObservationIgnored private var started = false

    func load() {
        guard !started else { return }
        started = true
        guard ProcessInfo.processInfo.environment["TESSERA_SETTINGS_SNAPSHOTS"] == nil,
              let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              !url.hasDirectoryPath else { return }
        Task {
            let decoded = await Task.detached(priority: .utility) { Self.decode(url) }.value
            if let cg = decoded?.image { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        }
    }

    /// A 1400 px thumbnail: a 6K wallpaper decoded at full size would take a few hundred milliseconds and ~100 MB.
    nonisolated private static func decode(_ url: URL) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1400,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        return Decoded(image: thumb)
    }

    /// A decoded CGImage is immutable, so it is safe to hand from the decoding thread to the main actor.
    private struct Decoded: @unchecked Sendable {
        let image: CGImage
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
    /// The stage's own screen: the whole column under the menu bar. The footer sits over its bottom the way the
    /// Dock does, so the visible frame stops above it (`footer`, in display points).
    static let stage = CGSize(width: 1512, height: 2360)
    /// The footer's height in display points: 190 pt on the 420 pt column.
    static let footer: CGFloat = 684
    static let laptop = CGSize(width: 1512, height: 982)
    static let ultrawide = CGSize(width: 3440, height: 1440)

    /// A display of `size`, its columns sized from `settings` as a new display would be. With `menuBar`, the top
    /// 33 pt are the menu bar and out of the visible frame.
    static func context(_ size: CGSize, settings: TesseraSettings, menuBar: Bool = false) -> DisplayContext {
        let frame = CGRect(origin: .zero, size: size)
        let dock = size == stage ? footer : 0
        let visible = CGRect(x: 0, y: dock, width: size.width, height: size.height - dock - (menuBar ? 33 : 0))
        // The stage is drawn taller than a laptop screen but behaves like one: sized from a 14-inch MacBook's visible
        // frame, so it gets a laptop's columns side by side rather than a portrait screen's rows.
        let sizedFrom = size == stage ? CGSize(width: laptop.width, height: laptop.height - 33) : visible.size
        let range = SizingRule.range(for: sizedFrom, constants: settings.sizing)
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
