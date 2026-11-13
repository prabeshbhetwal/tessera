import SwiftUI
import TesseraCore

/// Ring pane stage: hold the trigger over a window, the ring opens, the pointer flicks (or points at a column),
/// the preview shows where it lands, and the window snaps there. Pointing at a direction on the ring picker,
/// or at a gesture switch, acts that one out.
struct RingDemo: View {
    let settings: TesseraSettings
    @Environment(DemoCueState.self) private var cues: DemoCueState?

    static let directions = ["up", "up-right", "right", "down-right", "down", "down-left", "left", "up-left"]

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.stage, settings: settings)
        let story = Self.story(settings: settings, display: display, cue: cues?.cue)
        StagePlayer(display: display, settings: settings, frames: story.frames, detail: Self.detail(settings, cue: cues?.cue),
                    anchor: "Directions")
    }

    /// The settings behind a flick, read back.
    static func detail(_ settings: TesseraSettings, cue: DemoCue?) -> String {
        if case .ringSize(let anchor) = cue {
            let r = settings.ring
            let limit = anchor == "Thickness" ? "Thickness 4–\(Int(r.thicknessCap)) pt" : "Radius 20–\(Int(r.radiusCap)) pt"
            return "\(limit), kept inside the point threshold. Esc while dragging puts it back."
        }
        let keys = ModifierKey.names(settings.trigger.keyCodes)
        let trigger = keys.isEmpty ? "No trigger set" : "Trigger " + keys.joined(separator: " ")
        return "\(trigger) · flick past \(Int(settings.ring.flickDistance)) pt to point at a column"
    }

    /// Display points per ring point on the stage (`MockDesktop.ringScale` view points, at the stage's scale).
    static let displayPerRingPoint = Double(MockDesktop.ringScale) * DemoDisplay.stage.width / StageColumn<EmptyView>.width

    struct Story {
        var frames: [StageFrame]
    }

    static func story(settings: TesseraSettings, display: DisplayContext, cue: DemoCue?) -> Story {
        let ring = settings.ring
        let window = DemoDisplay.loose(on: display)
        let centre = CGPoint(x: window.midX, y: window.midY)
        let hold = StageFrame(windows: [DemoWindow(id: 0, frame: window, live: true)], pointer: centre,
                              caption: "Hold the trigger over a window.")
        var open = hold
        open.ring = centre
        open.caption = "The ring opens where the pointer is."

        if cue == .tapTiles, ring.tapTilesWindows {
            return tapTiles(display: display)
        }
        if case .ringSize = cue {
            var sized = open
            sized.badge = "Radius \(Int(ring.radius)) pt · thickness \(Int(ring.thickness)) pt"
            sized.handle = cue == .ringSize("Thickness") ? .thickness : .radius
            sized.pointer = nil
            sized.caption = "Drag the handle on the ring’s edge to resize it."
            return Story(frames: [hold, sized])
        }
        if cue == .flickDistance {
            var story = pointing(open, display: display)
            for i in story.frames.indices where story.frames[i].ring != nil {
                story.frames[i].threshold = ring.flickDistance
                story.frames[i].badge = "Point threshold \(Int(ring.flickDistance)) pt"
            }
            guard ring.pointing, story.frames.count > 2 else { return story }
            // Rest on the moment it crosses the circle, which is what the threshold decides.
            story.frames[2].caption = "Past the dashed circle, you point at a column."
            return Story(frames: Array(story.frames.prefix(3)))
        }
        if cue == .pointing || !ring.directions, ring.pointing {
            return pointing(open, display: display)
        }
        guard ring.directions else {
            open.caption = "Flicking and pointing are both off, so the ring only opens."
            return Story(frames: [hold, open])
        }
        let wedges = Array(ring.wedges.prefix(8))
        var index = 2
        if case .wedge(let w) = cue, wedges.indices.contains(w) { index = w }
        guard wedges.indices.contains(index) else { return Story(frames: [hold, open]) }
        let action = wedges[index]
        let target = GridGeometry.frame(for: action, display: display, current: window)
        let angle = Double(index) * .pi / 4
        var flick = open
        // Halfway between the ring's edge and the point threshold: far enough to pick the icon, not to point.
        let reach = (ring.outerRadius + ring.flickDistance) / 2 * displayPerRingPoint
        flick.pointer = CGPoint(x: centre.x + reach * sin(angle), y: centre.y + reach * cos(angle))
        flick.wedge = index
        flick.preview = target
        flick.selection = .wedge(index: index, action: action)
        flick.caption = "Flick \(directions[index]): \(action.displayName)."
        let release = StageFrame(windows: [DemoWindow(id: 0, frame: target, live: true)], pointer: flick.pointer,
                                 caption: "Flick \(directions[index]), let go: \(action.displayName.lowercased()).")
        return Story(frames: [hold, open, flick, release])
    }

    private static func pointing(_ open: StageFrame, display: DisplayContext) -> Story {
        let columns = max(display.profile.columns, 1)
        let column = columns - 1
        let span = ColumnSpan(columns: column...column, band: .full)
        let target = GridGeometry.frame(for: span, display: display)
        var point = open
        point.pointer = CGPoint(x: target.midX, y: target.midY)
        point.grid = true
        point.wedge = nil
        point.preview = target
        point.selection = .span(display: display.id, span: span)
        point.caption = "Keep going past the icons to point at column \(column + 1)."
        var release = point
        release.windows = [DemoWindow(id: 0, frame: target, live: true)]
        release.ring = nil
        release.grid = false
        release.preview = nil
        release.caption = "Point at column \(column + 1), let go: it takes the column."
        return Story(frames: [open.withoutRing, open, point, release])
    }

    private static func tapTiles(display: DisplayContext) -> Story {
        let v = display.visibleFrame
        let loose = [CGRect(x: v.minX + v.width * 0.05, y: v.minY + v.height * 0.3, width: v.width * 0.4, height: v.height * 0.55),
                     CGRect(x: v.minX + v.width * 0.3, y: v.minY + v.height * 0.1, width: v.width * 0.45, height: v.height * 0.5),
                     CGRect(x: v.minX + v.width * 0.5, y: v.minY + v.height * 0.35, width: v.width * 0.42, height: v.height * 0.5)]
        let tiles = GridGeometry.tiles(3, display: display)
        let before = StageFrame(windows: loose.enumerated().map { DemoWindow(id: $0, frame: $1) },
                                caption: "Press the trigger and let go without moving.")
        let after = StageFrame(windows: tiles.enumerated().map { DemoWindow(id: $0, frame: $1) },
                               caption: "Every window on the display tiles side by side.")
        return Story(frames: [before, after])
    }
}

private extension StageFrame {
    var withoutRing: StageFrame {
        var frame = self
        frame.ring = nil
        frame.caption = "Hold the trigger over a window."
        return frame
    }
}
