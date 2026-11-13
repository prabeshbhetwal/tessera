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

private struct DemoCueModifier: ViewModifier {
    let cue: DemoCue
    @Environment(DemoCueState.self) private var state: DemoCueState?

    func body(content: Content) -> some View {
        content.onHover { inside in if inside, state?.cue != cue { state?.cue = cue } }
    }
}

/// Acts out a demo once each time its frames change (a setting moved, another control was pointed at, or the
/// stage was clicked), then rests on the last frame with a faint outline where the window started. Nothing
/// loops, so there's nothing to pause. Under Reduce Motion it goes straight to the last frame.
struct StagePlayer<Sheet: View>: View {
    let display: DisplayContext
    let settings: TesseraSettings
    let frames: [StageFrame]
    /// The "you do" half under the desktop, for the frame showing.
    @ViewBuilder let sheet: (Int) -> Sheet

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var replays = 0

    private var shown: Int { min(index, max(frames.count - 1, 0)) }

    var body: some View {
        let frame = frames.isEmpty ? StageFrame(windows: [], caption: "") : frames[shown]
        VStack(spacing: 0) {
            MockDesktop(display: display, settings: settings, frame: frame, ghost: ghost)
                .contentShape(Rectangle())
                .onTapGesture { replays += 1 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Demo")
                .accessibilityValue(frame.caption)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Plays it again.")
                .accessibilityAction { replays += 1 }
            StageSheet(caption: frame.caption) { sheet(shown) }
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

/// The glass sheet under the desktop: what the person does, and a caption saying what happens.
private struct StageSheet<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            Text(caption)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .stageGlass(cornerRadius: 0, tint: 0.45)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.4)).frame(height: 0.5) }
    }
}
