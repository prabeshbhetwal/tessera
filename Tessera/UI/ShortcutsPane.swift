import SwiftUI
import TesseraCore

/// Global hotkeys and ring keyboard navigation (M2 spec §3, §4, §6).
struct ShortcutsPane: View {
    @Bindable var model: SettingsModel
    @State private var systemHotkeys: Set<Hotkey> = []

    private static let placeholder = HotkeyBinding(id: "", hotkey: .none, command: .undo, enabled: false)

    private var conflicts: [String: String] {
        let recorded = model.settings.hotkeys.filter { !$0.hotkey.isNone }
        var conflicts = HotkeyTable.conflicts(recorded, chord: model.settings.trigger, systemHotkeys: systemHotkeys)
        for binding in model.settings.hotkeys {
            if case let .cycle(name) = binding.command, !model.settings.cycles.contains(where: { $0.name == name }) {
                conflicts[binding.id] = "Cycle \(name) is missing. Choose another cycle or remove this shortcut."
            }
        }
        return conflicts
    }

    var body: some View {
        let cycleNames = model.settings.cycles.map(\.name)
        Form {
            Section {
                Toggle("Use global hotkeys", isOn: $model.settings.hotkeysEnabled).settingAnchor("Use global hotkeys")
            } header: {
                InfoHeader("Hotkeys", info: "Click a shortcut, or select it and press Space, then type the new one. Esc cancels, Delete clears. Warnings identify shortcuts that may be intercepted. With duplicates, only the first enabled action runs.")
            } footer: {
                if !model.settings.hotkeysEnabled {
                    Footer("All hotkeys are off. The ring still works; set its trigger in Ring › Trigger.")
                }
            }

            ForEach(HotkeyGroup.allCases, id: \.self) { group in
                let items = model.settings.hotkeys.filter { $0.command.hotkeyGroup == group }
                if !items.isEmpty {
                    Section(group.rawValue) {
                        ForEach(items) { item in
                            HotkeyRow(
                                binding: binding(for: item.id),
                                conflict: conflicts[item.id],
                                cycleNames: cycleNames,
                                remove: { model.settings.hotkeys.removeAll { $0.id == item.id } }
                            )
                        }
                    }
                    .disabled(!model.settings.hotkeysEnabled)
                }
            }

            Section {
                Button("Add Hotkey", action: addHotkey).settingAnchor("Add Hotkey")
            }
            .disabled(!model.settings.hotkeysEnabled)

            Section("Ring keyboard") {
                Toggle("Navigate the open ring with the keyboard", isOn: $model.settings.ringKeyNavigation).settingAnchor("Navigate the open ring with the keyboard")
                Toggle("Announce the selection with VoiceOver", isOn: $model.settings.announceSelection).settingAnchor("Announce the selection with VoiceOver")
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
