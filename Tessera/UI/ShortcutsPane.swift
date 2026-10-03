import SwiftUI
import TesseraCore

/// Global hotkeys and ring keyboard navigation (M2 spec §3, §4, §6).
struct ShortcutsPane: View {
    @Bindable var model: SettingsModel
    @State private var systemHotkeys: Set<Hotkey> = []

    private static let placeholder = HotkeyBinding(id: "", hotkey: .none, command: .undo, enabled: false)

    var body: some View {
        let recorded = model.settings.hotkeys.filter { !$0.hotkey.isNone }
        let conflicts = HotkeyTable.conflicts(recorded, chord: model.settings.trigger, systemHotkeys: systemHotkeys)
        let cycleNames = model.settings.cycles.map(\.name)
        Form {
            Section {
                Toggle("Use global hotkeys", isOn: $model.settings.hotkeysEnabled)
                Group {
                    ForEach(model.settings.hotkeys) { item in
                        HotkeyRow(
                            binding: binding(for: item.id),
                            conflict: conflicts[item.id],
                            cycleNames: cycleNames,
                            remove: { model.settings.hotkeys.removeAll { $0.id == item.id } }
                        )
                    }
                    Button("Add Hotkey", action: addHotkey)
                }
                .disabled(!model.settings.hotkeysEnabled)
            } header: {
                Text("Hotkeys")
            } footer: {
                Footer(model.settings.hotkeysEnabled
                    ? "Click a shortcut, or select it and press Space, then type the new one. Esc cancels, Delete clears. A warning doesn't stop a hotkey from working."
                    : "All hotkeys are off; each keeps its own setting for when you turn them back on. The ring still works.")
            }

            Section("Ring keyboard") {
                Toggle("Navigate the open ring with the keyboard", isOn: $model.settings.ringKeyNavigation)
                Toggle("Announce the selection with VoiceOver", isOn: $model.settings.announceSelection)
                DisclosureGroup("Keys while the ring is open") {
                    ForEach(Self.ringKeys, id: \.key) { row in
                        LabeledContent(row.key, value: row.effect)
                    }
                }
                .disabled(!model.settings.ringKeyNavigation)
            }

            ResetSection(keeps: "Keeps hotkeys you added.") {
                let defaultIDs = Set(HotkeyBinding.defaults.map(\.id))
                model.settings.hotkeys = HotkeyBinding.defaults + model.settings.hotkeys.filter { !defaultIDs.contains($0.id) }
                model.settings.ringKeyNavigation = true
                model.settings.announceSelection = true
                model.settings.hotkeysEnabled = true
            }
        }
        .formStyle(.grouped)
        .onAppear { systemHotkeys = SystemHotkeys.enabled() }
    }

    static let ringKeys: [(key: String, effect: String)] = [
        ("← / →", "Move one column"),
        ("⇧← / ⇧→", "Extend the span"),
        ("↑ / ↓", "Bottom, full, top band"),
        ("1 – 9", "Jump to that column"),
        ("= / −", "One more or one fewer column"),
        ("⇥ / ⇧⇥", "Next or previous display"),
        ("↩", "Apply and close"),
        ("⎋", "Cancel"),
    ]

    /// Looks the binding up by id so a row never indexes past a removal.
    private func binding(for id: String) -> Binding<HotkeyBinding> {
        Binding(
            get: { model.settings.hotkeys.first { $0.id == id } ?? Self.placeholder },
            set: { new in
                if let i = model.settings.hotkeys.firstIndex(where: { $0.id == id }) { model.settings.hotkeys[i] = new }
            }
        )
    }

    private func addHotkey() {
        model.settings.hotkeys.append(HotkeyBinding(
            id: UUID().uuidString, hotkey: .none, command: .apply(.action(.maximize), display: .current), enabled: false
        ))
    }
}

private struct HotkeyRow: View {
    @Binding var binding: HotkeyBinding
    let conflict: String?
    let cycleNames: [String]
    let remove: () -> Void

    var body: some View {
        let summary = binding.command.summary
        DisclosureGroup {
            CommandEditor(command: $binding.command, cycleNames: cycleNames)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Toggle("Enabled", isOn: $binding.enabled)
                        .labelsHidden()
                        .disabled(binding.hotkey.isNone)
                        .accessibilityLabel("Enable \(summary)")
                    Text(summary)
                    Spacer()
                    if conflict != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    HotkeyRecorder(title: "Shortcut for \(summary)", hotkey: Binding(
                        get: { binding.hotkey },
                        set: { binding.hotkey = $0; binding.enabled = !$0.isNone }
                    ))
                    Button(action: remove) { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(summary)")
                }
                if let conflict {
                    Caption(conflict).accessibilityLabel("Warning: \(conflict)")
                }
            }
        }
    }
}

/// Edits any `Command` with its parameters. Only commands that make sense on a key are offered;
/// queries and file commands belong to the CLI and are kept if a file already has them.
struct CommandEditor: View {
    @Binding var command: Command
    let cycleNames: [String]

    private enum Kind: String, CaseIterable, Identifiable {
        case apply = "Move window", cycle = "Run cycle", columns = "Change columns", move = "Move to display"
        case tile = "Tile all windows"
        case undo = "Undo last move", openSettings = "Open Settings", listDisplays = "List displays"
        case describeWindow = "Describe window", exportSettings = "Export settings", importSettings = "Import settings"
        var id: Self { self }

        static let offered: [Kind] = [.apply, .cycle, .tile, .columns, .move, .undo, .openSettings]
    }

    private var kind: Kind {
        switch command {
        case .apply: .apply
        case .cycle: .cycle
        case .columns: .columns
        case .moveToDisplay: .move
        case .tileWindows: .tile
        case .undo: .undo
        case .openSettings: .openSettings
        case .listDisplays: .listDisplays
        case .describeWindow: .describeWindow
        case .exportSettings: .exportSettings
        case .importSettings: .importSettings
        }
    }

    private func defaultCommand(_ kind: Kind) -> Command {
        switch kind {
        case .apply: .apply(.action(.maximize), display: .current)
        case .cycle: .cycle(name: cycleNames.first ?? "left")
        case .columns: .columns(.delta(1), display: .current)
        case .move: .moveToDisplay(.next)
        case .tile: .tileWindows(display: .current)
        case .undo: .undo
        case .openSettings: .openSettings
        case .listDisplays: .listDisplays
        case .describeWindow: .describeWindow
        case .exportSettings: .exportSettings(path: "~/Tessera Settings.json")
        case .importSettings: .importSettings(path: "~/Tessera Settings.json")
        }
    }

    var body: some View {
        Picker("Command", selection: Binding.choice(kind) { command = defaultCommand($0) }) {
            ForEach(Kind.offered.contains(kind) ? Kind.offered : Kind.offered + [kind]) { Text($0.rawValue).tag($0) }
        }
        parameters
    }

    @ViewBuilder private var parameters: some View {
        switch command {
        case .apply(let target, let display):
            LabeledContent("Target") {
                TargetEditor(target: Binding(get: { target }, set: { command = .apply($0, display: display) }))
            }
            DisplaySelectorEditor(title: "Display", selector: Binding(get: { display }, set: { command = .apply(target, display: $0) }))
        case .cycle(let name):
            Picker("Cycle", selection: Binding(get: { name }, set: { command = .cycle(name: $0) })) {
                ForEach(cycleNames.contains(name) ? cycleNames : cycleNames + [name], id: \.self) { Text($0).tag($0) }
            }
        case .columns(let change, let display):
            columnsEditor(change, display)
        case .moveToDisplay(let step):
            moveEditor(step)
        case .tileWindows(let display):
            DisplaySelectorEditor(title: "Display", selector: Binding(get: { display }, set: { command = .tileWindows(display: $0) }))
        case .exportSettings(let path):
            TextField("File path", text: Binding(get: { path }, set: { command = .exportSettings(path: $0) }))
        case .importSettings(let path):
            TextField("File path", text: Binding(get: { path }, set: { command = .importSettings(path: $0) }))
        case .undo, .openSettings, .listDisplays, .describeWindow:
            EmptyView()
        }
    }

    @ViewBuilder private func columnsEditor(_ change: ColumnChange, _ display: DisplaySelector) -> some View {
        let isSet = if case .set = change { true } else { false }
        Picker("Change", selection: Binding.choice(isSet) { s in
            command = .columns(s ? .set(4) : .delta(1), display: display)
        }) {
            Text("Set the count").tag(true)
            Text("Add or remove").tag(false)
        }
        switch change {
        case .set(let n):
            StepperRow(title: "Columns", value: Binding(get: { n }, set: { command = .columns(.set($0), display: display) }), range: 1...16)
        case .delta(let d):
            StepperRow(
                title: "By", value: Binding(get: { d }, set: { command = .columns(.delta($0), display: display) }),
                range: -8...8, format: { $0 > 0 ? "+\($0)" : "\($0)" }
            )
        }
        DisplaySelectorEditor(title: "Display", selector: Binding(get: { display }, set: { command = .columns(change, display: $0) }))
    }

    @ViewBuilder private func moveEditor(_ step: DisplayStep) -> some View {
        let tag = switch step {
        case .next: 0
        case .previous: 1
        case .index: 2
        }
        Picker("Move to", selection: Binding.choice(tag) { t in
            command = .moveToDisplay(t == 0 ? .next : t == 1 ? .previous : .index(1))
        }) {
            Text("Next display").tag(0)
            Text("Previous display").tag(1)
            Text("Display number").tag(2)
        }
        if case .index(let n) = step {
            StepperRow(title: "Display", value: Binding(get: { n }, set: { command = .moveToDisplay(.index($0)) }), range: 1...16)
        }
    }
}

extension Command {
    /// Short human description, used for rows, accessibility labels and intent dialogs.
    var summary: String {
        func on(_ d: DisplaySelector) -> String { d == .current ? "" : " on \(d.summary)" }
        switch self {
        case .apply(let target, let display): return target.summary + on(display)
        case .cycle(let name): return "Cycle “\(name)”"
        case .columns(.set(let n), let display): return "Set \(n) columns" + on(display)
        case .columns(.delta(let d), let display):
            return "\(abs(d)) \(d >= 0 ? "more" : "fewer") column\(abs(d) == 1 ? "" : "s")" + on(display)
        case .moveToDisplay(.next): return "Move to next display"
        case .moveToDisplay(.previous): return "Move to previous display"
        case .moveToDisplay(.index(let n)): return "Move to display \(n)"
        case .tileWindows(let display): return "Tile all windows" + on(display)
        case .undo: return "Undo last move"
        case .openSettings: return "Open Settings"
        case .listDisplays: return "List displays"
        case .describeWindow: return "Describe window"
        case .exportSettings(let path): return "Export settings to \(path)"
        case .importSettings(let path): return "Import settings from \(path)"
        }
    }
}
