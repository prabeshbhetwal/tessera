import SwiftUI
import TesseraCore

/// A pretend window in a Settings demo. Never one of the user's windows.
struct DemoWindow: Identifiable, Equatable {
    let id: Int
    var frame: CGRect
    /// The window the demo acts on: outlined in the accent colour.
    var live = false
}

/// A mock display for the Settings demos: a screen with a menu bar strip and pretend windows, placed from
/// display-space rects (AppKit, y up) the way `TesseraCore` computes them, so a demo shows real geometry.
struct MockDesktop<Extra: View>: View {
    let display: DisplayContext
    var windows: [DemoWindow] = []
    /// Where the snap preview would land, drawn in the accent colour.
    var preview: CGRect?
    /// Drawn over the windows; given the display-to-view mapping so it can sit on a window.
    @ViewBuilder var extra: (_ map: @escaping (CGRect) -> CGRect) -> Extra

    var body: some View {
        let screen = display.frame
        GeometryReader { geometry in
            let scale = geometry.size.width / max(screen.width, 1)
            let map = { (r: CGRect) -> CGRect in
                CGRect(x: (r.minX - screen.minX) * scale, y: (screen.maxY - r.maxY) * scale,
                       width: r.width * scale, height: r.height * scale)
            }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.quaternary.opacity(0.6))
                    .frame(height: max(map(display.visibleFrame).minY, 3))
                ForEach(windows) { window in
                    placed(MockWindow(live: window.live), in: map(window.frame))
                }
                if let preview {
                    let r = map(preview)
                    placed(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)), in: r)
                }
                extra(map)
            }
        }
        .aspectRatio(screen.width / max(screen.height, 1), contentMode: .fit)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
    }

    private func placed(_ view: some View, in r: CGRect) -> some View {
        view.frame(width: max(r.width, 0), height: max(r.height, 0)).offset(x: r.minX, y: r.minY)
    }
}

extension MockDesktop where Extra == EmptyView {
    init(display: DisplayContext, windows: [DemoWindow] = [], preview: CGRect? = nil) {
        self.init(display: display, windows: windows, preview: preview) { _ in EmptyView() }
    }
}

/// Stand-in for a window: title bar with three neutral dots over a body. `live` marks the window being moved.
struct MockWindow: View {
    var live = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(.secondary.opacity(0.5)).frame(width: 4, height: 4) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 10)
            .background(.quaternary)
            Rectangle().fill(.background)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(live ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                                    lineWidth: live ? 1.5 : 1))
    }
}

/// Reference displays for the demos, sized by `TesseraCore` the way `DisplayService` sizes a real screen.
enum DemoDisplay {
    /// A 14-inch MacBook Pro at its default scaling.
    static let laptop = CGSize(width: 1512, height: 982)
    /// A 34-inch 21:9 ultrawide.
    static let ultrawide = CGSize(width: 3440, height: 1440)

    /// A display of `size` with a menu bar, its columns sized from `settings` as a new display would be.
    static func context(_ size: CGSize, settings: TesseraSettings) -> DisplayContext {
        let frame = CGRect(origin: .zero, size: size)
        let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - 33)
        let range = SizingRule.range(for: visible.size, constants: settings.sizing)
        return DisplayContext(
            id: DisplayID(vendor: 0, model: 0, serial: 0, uuid: "demo"), frame: frame, visibleFrame: visible,
            range: range, profile: .auto(range: range, gap: settings.defaultGap, padding: settings.defaultPadding))
    }

    /// A window that hasn't been snapped yet: off-centre, a little over half the usable area.
    static func loose(on display: DisplayContext) -> CGRect {
        let v = display.visibleFrame
        return CGRect(x: v.minX + v.width * 0.16, y: v.minY + v.height * 0.2, width: v.width * 0.5, height: v.height * 0.6)
    }
}
