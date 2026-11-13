import SwiftUI

/// The Settings window's right-hand column: a live demo of what the pane's settings do, beside the form.
struct DemoColumn<Content: View>: View {
    static var width: CGFloat { 280 }

    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Plays a demo scene step by step: every 1.6 s while playing, or one step per click on Step.
/// Under Reduce Motion it starts paused and steps change without animating. The scene is one VoiceOver
/// element labelled "<title> demo" whose value is the step's description, shown as a caption too.
struct DemoPlayer<Scene: View>: View {
    let title: String
    /// Steps in the loop; 1 makes a still scene with no controls.
    let count: Int
    /// What step `n` shows, in a few words. Caption and VoiceOver value.
    let describe: (Int) -> String
    /// Shows the description under the scene. Off when the scene labels itself; VoiceOver still reads it.
    var caption = true
    /// How a step change moves the scene; nil jumps.
    var animation: Animation? = .smooth(duration: 0.45)
    @ViewBuilder let scene: (Int) -> Scene

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    /// Nil until the person presses Play or Pause: then it plays unless Reduce Motion is on.
    @State private var chosen: Bool?

    private var playing: Bool { count > 1 && (chosen ?? !reduceMotion) }
    private var current: Int { step % max(count, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            scene(current)
                .animation(reduceMotion ? nil : animation, value: current)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) demo")
                .accessibilityValue(describe(current))
            if caption {
                Text(describe(current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if count > 1 { controls }
        }
        .task(id: playing) {
            while playing, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                step += 1
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { chosen = !playing } label: {
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            Button { step += 1 } label: { Label("Step", systemImage: "forward.frame.fill") }
                .disabled(playing)
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }
}
