import SwiftUI
import TesseraCore

/// Shortcuts pane stage: point at a shortcut in the list and the window goes where it sends it
/// (`TargetResolver`). Before anything is pointed at, the first shortcut that moves a window plays.
struct ShortcutsDemo: View {
    let settings: TesseraSettings
    @Environment(DemoCueState.self) private var cues: DemoCueState?

    var body: some View {
        let display = DemoDisplay.context(DemoDisplay.stage, settings: settings)
        let items = settings.hotkeys.filter { !$0.hotkey.isNone }
        let cued: HotkeyBinding? = if case .hotkey(let id) = cues?.cue { items.first { $0.id == id } } else { nil }
        let binding = cued ?? items.first { $0.target(cycles: settings.cycles) != nil }
        let detail = settings.hotkeysEnabled ? "Point at a shortcut on the left to play it." : "All hotkeys are off."
        StagePlayer(display: display, settings: settings, frames: frames(binding, display: display), detail: detail) { index in
            // Which shortcut is playing; pressed in on the step it runs.
            if let binding {
                HStack(spacing: 4) {
                    ForEach(Array(binding.hotkey.keycaps.enumerated()), id: \.offset) { _, key in Keycap(key) }
                }
                .scaleEffect(index == 1 ? 0.96 : 1)
            }
        }
    }

    private func frames(_ binding: HotkeyBinding?, display: DisplayContext) -> [StageFrame] {
        let start = DemoDisplay.loose(on: display)
        let resting = [DemoWindow(id: 0, frame: start, live: true)]
        guard let binding else { return [StageFrame(windows: resting, caption: "No shortcuts are set.")] }
        let keys = binding.hotkey.displayString
        let name = binding.command.summary
        let before = StageFrame(windows: resting, caption: "Press \(keys).")
        if !settings.hotkeysEnabled { return [StageFrame(windows: resting, caption: "All hotkeys are off, so \(keys) does nothing.")] }
        if !binding.enabled { return [StageFrame(windows: resting, caption: "\(name) is turned off.")] }
        guard let target = binding.target(cycles: settings.cycles) else {
            return [StageFrame(windows: resting, caption: "\(keys): \(name). It doesn’t move the window on this screen.")]
        }
        let end = TargetResolver.frame(for: target, display: display, current: start)
        return [before, StageFrame(windows: [DemoWindow(id: 0, frame: end, live: true)], caption: "\(keys): \(name).")]
    }
}

extension HotkeyBinding {
    /// Where the command puts the front window, when it puts it somewhere on the same display.
    /// A cycle shows its first step.
    func target(cycles: [Cycle]) -> Target? {
        switch command {
        case .apply(let target, _): target
        case .cycle(let name): cycles.first { $0.name == name }?.steps.first
        default: nil
        }
    }
}

extension Hotkey {
    /// One keycap per modifier, then the key.
    var keycaps: [String] {
        isNone ? [] : modifiers.symbols.split(separator: " ").flatMap { part in
            part == "fn" ? [String(part)] : part.map(String.init)
        } + [KeyNames.name(for: keyCode)]
    }
}
