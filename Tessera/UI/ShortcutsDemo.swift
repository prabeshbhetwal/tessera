import SwiftUI
import TesseraCore

/// Shortcuts pane demo: pick a shortcut and watch a mock window go where it sends it (`TargetResolver`).
struct ShortcutsDemo: View {
    let settings: TesseraSettings
    @State private var selected: String?

    var body: some View {
        let items = settings.hotkeys.filter { !$0.hotkey.isNone }
        let binding = items.first { $0.id == selected } ?? items.first { $0.target(cycles: settings.cycles) != nil }
        let display = DemoDisplay.context(DemoDisplay.laptop, settings: settings)
        let start = DemoDisplay.loose(on: display)
        let end = binding?.target(cycles: settings.cycles).map { TargetResolver.frame(for: $0, display: display, current: start) }
        DemoColumn(title: "Press") {
            Picker("Shortcut", selection: Binding(get: { binding?.id }, set: { selected = $0 })) {
                ForEach(items) { item in
                    Text("\(item.hotkey.displayString)  \(item.command.summary)").tag(Optional(item.id))
                }
            }
            .labelsHidden()
            .accessibilityLabel("Shortcut to demonstrate")
            if let binding {
                DemoPlayer(title: "Shortcut", count: end == nil ? 1 : 2, describe: { step in
                    let keys = "\(binding.hotkey.displayString), \(binding.command.summary)"
                    if !settings.hotkeysEnabled { return "All hotkeys are off, so \(keys) does nothing." }
                    if !binding.enabled { return "\(keys) is turned off." }
                    if end == nil { return "\(keys). It doesn't move the window, so there's nothing to show." }
                    return step == 0 ? "Before pressing \(binding.hotkey.displayString)." : "After: \(binding.command.summary)."
                }) { step in
                    let moved = settings.hotkeysEnabled && binding.enabled && step == 1
                    MockDesktop(display: display, windows: [DemoWindow(id: 0, frame: moved ? end ?? start : start, live: true)])
                        .overlay(alignment: .bottom) {
                            Text(binding.hotkey.displayString)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .opacity(step == 1 ? 1 : 0.35)
                                .padding(6)
                        }
                }
                .id(binding.id)
            }
        }
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
