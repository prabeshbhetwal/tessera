import AppKit
import SwiftUI
import TesseraCore

/// The Settings window's right-hand stage: edge to edge, on the window look's backdrop (translucent unless Solid).
struct StageColumn<Content: View>: View {
    static var width: CGFloat { 420 }
    var look: WindowMaterial = .liquidGlass
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .background { WindowBackdrop(look: look, surface: .stage) }
            .clipped()
    }
}

extension View {
    /// A surface on the stage, drawn as a plain fill, never glass or a material, so the stage adds no blur of its own.
    /// Decorative surfaces keep a little translucency; `opaque` ones carry text. Opaque under Reduce Transparency and
    /// Increase Contrast.
    func stageGlass(cornerRadius: CGFloat, clear: Bool = false, opaque: Bool = false) -> some View {
        modifier(StageFill(cornerRadius: cornerRadius, opacity: opaque ? 1 : clear ? 0.72 : 0.88))
    }
}

private struct StageFill: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let solid = reduceTransparency || contrast == .increased
        content.background(Color(nsColor: .controlBackgroundColor).opacity(solid ? 1 : opacity),
                           in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
