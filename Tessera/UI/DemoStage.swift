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
}

/// What the person is pointing at in the form, so the stage can act out that control.
enum DemoCue: Hashable {
    case wedge(Int), pointing, tapTiles
    case hotkey(String), cycle(String)
    case reflow, fillGap
}

/// The cue last pointed at. Sticky: it changes only when another cued control is pointed at, so the stage
/// doesn't restart every time the pointer crosses a gap between rows.
@MainActor @Observable
final class DemoCueState {
    var cue: DemoCue?
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
                try? await Task.sleep(for: .milliseconds(250))
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
    /// A small picture in the footer, only where it adds something the screen can't show (cycle steps, a time bar).
    @ViewBuilder let accessory: (Int) -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var replays = 0

    private var shown: Int { min(index, max(frames.count - 1, 0)) }

    var body: some View {
        let frame = frames.isEmpty ? StageFrame(windows: [], caption: "") : frames[shown]
        ZStack(alignment: .bottom) {
            MockDesktop(display: display, settings: settings, frame: frame, ghost: ghost)
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
    }

    /// Where the live window started, outlined once it has moved.
    private var ghost: CGRect? {
        guard shown > 0, let start = frames.first?.windows.first(where: \.live)?.frame,
              let now = frames[shown].windows.first(where: \.live)?.frame, start != now else { return nil }
        return start
    }

    private func play() async {
        guard frames.count > 1, !reduceMotion else {
            index = max(frames.count - 1, 0)
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { index = 0 }
        for next in 1..<frames.count {
            try? await Task.sleep(for: .milliseconds(next == 1 ? 450 : 750))
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
    init(display: DisplayContext, settings: TesseraSettings, frames: [StageFrame], detail: String) {
        self.init(display: display, settings: settings, frames: frames, detail: detail) { _ in EmptyView() }
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
        .stageGlass(cornerRadius: 0, tint: 0.62)
        .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 1) }
        .accessibilityHidden(true)
    }
}
