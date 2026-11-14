import AppKit
import SwiftUI

/// The Settings window's motion in one place (docs/DESIGN.md › Motion). Motion confirms, orients or bridges a change;
/// it never decorates. Arrivals animate and departures are instant, so nothing waits on an old view leaving. Under
/// Reduce Motion nothing moves or scales: changes fade or happen at once.
enum SettingsMotion {
    /// Hover plates, strokes and colour changes, a press letting go.
    static let quick: Animation = .easeOut(duration: 0.15)
    /// A pane's content arriving; the icon rail's selection moving to another icon.
    static let settle: Animation = .smooth(duration: 0.22)
    /// The sidebar between names and icons.
    static let glide: Animation = .smooth(duration: 0.3)
    /// The stage's windows going back to where the story starts, when the stage is clicked to play it again.
    static let rewind: Animation = .smooth(duration: 0.2)

    /// True while a key press is being handled. Keyboard navigation (⌘1, ↑ ↓ through the panes) switches at once,
    /// as fast as the keys are pressed; the pointer gets the transition.
    @MainActor static var fromKeyboard: Bool { NSApp.currentEvent?.type == .keyDown }

    /// How a pane change arrives: `settle`, a plain fade under Reduce Motion, nothing from the keyboard.
    @MainActor static func paneChange(reduceMotion: Bool) -> Animation? {
        fromKeyboard ? nil : reduceMotion ? quick : settle
    }

    /// A pane's header and form arriving: a fade and a 6 pt rise (a fade only under Reduce Motion). Leaves at once.
    static func arrival(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)), removal: .identity)
    }

    /// The search results dropping from the field: a short fall and grow from under it. A fade with Reduce Motion.
    static func drop(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -6))
    }

    static func dropAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.28, bounce: 0.12)
    }
}

/// Feedback for Tessera's own picture buttons (thumbnails, rail icons, the sidebar's foot): the label sinks to 97 %
/// while pressed and springs back as it lets go. Under Reduce Motion it dims instead. System buttons keep their own.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PressableLabel<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(pressed && reduceMotion ? 0.8 : 1)
            // In at once, so the press registers on contact; out over `quick`.
            .animation(pressed ? nil : SettingsMotion.quick, value: pressed)
    }
}
