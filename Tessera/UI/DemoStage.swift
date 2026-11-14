import Observation
import SwiftUI
import TesseraCore

/// One moment of a demo: where the pretend windows are, and what the overlay and pointer show.
/// Coordinates are the stage display's (AppKit, y up), as `TesseraCore` computes them.
struct StageFrame: Equatable {
    var windows: [DemoWindow]
    /// The snap preview, and the selection its label describes.
    var preview: CGRect?
    var selection: Selection = .none
    /// The ring's centre and its lit wedge.
    var ring: CGPoint?
    var wedge: Int?
    /// The column grid, shown while pointing (and on Displays).
    var grid = false
    var pointer: CGPoint?
    /// What this moment shows, in a few words. Caption and VoiceOver value.
    var caption: String
    /// How long the move into this frame takes, when it isn't the stage's usual glide (Motion's snap speed).
    var seconds: Double?
    /// A setting's value, shown beside the part of the screen it shapes ("Radius 50 pt").
    var badge: String?
    /// The point threshold: a dashed circle round the ring, its radius in the ring's own points.
    var threshold: Double?
    /// A grab handle on the ring's edge that resizes it (where the stage can edit settings).
    var handle: RingHandle?
}

/// What the person is pointing at in the form, so the stage can act out that control.
enum DemoCue: Hashable {
    case wedge(Int), pointing, tapTiles
    /// A ring size slider, by its row's anchor ("Radius", "Thickness").
    case ringSize(String)
    case flickDistance
    case hotkey(String), cycle(String)
    case reflow, fillGap

    /// The form row (its `settingAnchor`) this cue acts out, lit while the pointer is on the stage.
    var anchor: String? {
        switch self {
        case .wedge: "Directions"
        case .pointing: "Pointing: a longer move picks a column of the grid"
        case .tapTiles: "Press and release without moving to tile all windows"
        case .ringSize(let anchor): anchor
        case .flickDistance: "Point threshold"
        case .reflow: "Resize neighbours to fill the display"
        case .fillGap: "Fill the space when a window closes"
        case .hotkey, .cycle: nil
        }
    }
}

/// The cue last pointed at. Sticky: it changes only when another cued control is pointed at, so the stage
/// doesn't restart every time the pointer crosses a gap between rows.
@MainActor @Observable
final class DemoCueState {
    var cue: DemoCue?
    /// The form row the stage is about, lit (more softly than a search result) while the pointer is on the stage.
    var spotlight: String?
    /// A handle on the stage is being dragged: the stage holds its frame instead of replaying at every change.
    var editing = false
    /// Changes the live settings from the stage's grips; set once by the Settings window. Nil (no grips) elsewhere.
    /// Observed, so the grips appear once it is set; it is set only once, so that costs a single redraw.
    var apply: SettingsApply?
}

extension View {
    /// Pointing at this control (hover) makes the stage act out `cue`.
    func demoCue(_ cue: DemoCue) -> some View { modifier(DemoCueModifier(cue: cue)) }
}

/// Sets the cue after the pointer rests on the control for a moment, so sweeping across the form on the way
/// somewhere else doesn't restart the stage at every row.
private struct DemoCueModifier: ViewModifier {
    let cue: DemoCue
    @Environment(DemoCueState.self) private var state: DemoCueState?
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onHover { inside in
            pending?.cancel()
            guard inside, state?.cue != cue else { return }
            pending = Task {
                // Just long enough that sweeping the pointer across rows doesn't flicker the stage; 250 ms felt slow.
                try? await Task.sleep(for: .milliseconds(80))
                if !Task.isCancelled { state?.cue = cue }
            }
        }
    }
}

/// Acts out a demo once each time its frames change (a setting moved, another control was pointed at, or the
/// stage was clicked), then rests on the last frame with a faint outline where the window started. Nothing
/// loops, so there's nothing to pause. Under Reduce Motion it goes straight to the last frame.
///
/// One composition: the mock screen fills the column down to a compact footer, whose headline says what happens
/// and whose second line reads back the settings that decide it.
struct StagePlayer<Accessory: View>: View {
    let display: DisplayContext
    let settings: TesseraSettings
    let frames: [StageFrame]
    /// The settings behind the demo, read back in one line ("Snap speed Smooth, 0.2 s").
    let detail: String
    /// The form row the demo is about when no control has been pointed at.
    var anchor: String?
    /// Grips the scene puts on the screen, placed with the screen's geometry.
    var overlay: ((StageGeometry) -> AnyView)?
    /// A small picture in the footer, only where it adds something the screen can't show (cycle steps, a time bar).
    @ViewBuilder let accessory: (Int) -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DemoCueState.self) private var cues: DemoCueState?
    @State private var index = 0
    @State private var replays = 0

    private var shown: Int { min(index, max(frames.count - 1, 0)) }

    var body: some View {
        let frame = frames.isEmpty ? StageFrame(windows: [], caption: "") : frames[shown]
        ZStack(alignment: .bottom) {
            MockDesktop(display: display, settings: settings, frame: frame, ghost: ghost, overlay: overlay)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { replays += 1 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Demo")
                .accessibilityValue("\(frame.caption) \(detail)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Plays it again.")
                .accessibilityAction { replays += 1 }
            StageFooter(headline: frame.caption, detail: detail) { accessory(shown) }
        }
        .task(id: Replay(frames: frames, replays: replays)) { await play() }
        // Pointing at the stage lights the form row it is acting out: the link runs both ways.
        .onHover { inside in cues?.spotlight = inside ? cues?.cue?.anchor ?? anchor : nil }
    }

    /// Where the live window started, outlined once it has moved.
    private var ghost: CGRect? {
        guard shown > 0, let start = frames.first?.windows.first(where: \.live)?.frame,
              let now = frames[shown].windows.first(where: \.live)?.frame, start != now else { return nil }
        return start
    }

    private func play() async {
        guard frames.count > 1, !reduceMotion, cues?.editing != true else {
            index = max(frames.count - 1, 0)
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { index = 0 }
        for next in 1..<frames.count {
            // The first step starts almost at once, so pointing at a control answers immediately; later steps keep
            // a pace the eye can follow.
            try? await Task.sleep(for: .milliseconds(next == 1 ? 150 : 750))
            guard !Task.isCancelled else { return }
            let animation: Animation? = if let seconds = frames[next].seconds {
                seconds > 0 ? .easeInOut(duration: seconds) : nil
            } else {
                .smooth(duration: 0.35)
            }
            withAnimation(animation) { index = next }
        }
    }

    private struct Replay: Equatable {
        let frames: [StageFrame]
        let replays: Int
    }
}

extension StagePlayer where Accessory == EmptyView {
    init(display: DisplayContext, settings: TesseraSettings, frames: [StageFrame], detail: String, anchor: String? = nil,
         overlay: ((StageGeometry) -> AnyView)? = nil) {
        self.init(display: display, settings: settings, frames: frames, detail: detail, anchor: anchor,
                  overlay: overlay) { _ in EmptyView() }
    }
}

/// The footer under the screen: an optional picture, the outcome as a headline, the settings behind it.
/// Near-opaque glass, so the text reads on any wallpaper and under Reduce Transparency.
private struct StageFooter<Accessory: View>: View {
    let headline: String
    let detail: String
    @ViewBuilder let accessory: Accessory
    /// The window's scheme, read outside the glass: Liquid Glass picks its own scheme from what is behind it,
    /// which over a light wallpaper in a dark window gave dark text on the dark tint.
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink: Color = scheme == .dark ? .white : .black
        VStack(alignment: .leading, spacing: 10) {
            accessory
            Text(headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Text(detail)
                .font(.callout)
                .foregroundStyle(ink.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .environment(\.colorScheme, scheme)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(height: 190, alignment: .top)
        .stageGlass(cornerRadius: 0, opaque: true)
        .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 1) }
        .accessibilityHidden(true)
    }
}
