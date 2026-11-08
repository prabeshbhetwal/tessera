import SwiftUI
import TesseraCore

/// Edits any `Command` with its parameters. Only commands that make sense on a key are offered;
/// queries and file commands belong to the CLI and are kept if a file already has them.
struct CommandEditor: View {
    @Binding var command: Command
    let cycleNames: [String]

    private enum Kind: String, CaseIterable, Identifiable {
        case apply = "Move Window", cycle = "Run Cycle", columns = "Change Columns", move = "Move to Display"
        case tile = "Tile All Windows", tileEvenly = "Tile Evenly", remember = "Remember Split"
        case forgetSplit = "Forget This Split", explain = "What Just Happened?"
        case undo = "Undo Last Move", openSettings = "Open Settings", listDisplays = "List Displays"
        case describeWindow = "Describe Window", exportSettings = "Export Settings", importSettings = "Import Settings"
        var id: Self { self }

        static let offered: [Kind] = [.apply, .cycle, .tile, .tileEvenly, .remember, .forgetSplit, .explain, .columns, .move, .undo, .openSettings]
    }

    private var kind: Kind {
        switch command {
        case .apply: .apply
        case .cycle: .cycle
        case .columns: .columns
        case .moveToDisplay: .move
        case .tileWindows: .tile
        case .tileEvenly: .tileEvenly
        case .rememberSplit: .remember
        case .forgetSplit: .forgetSplit
        case .explain: .explain
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
        case .tileEvenly: .tileEvenly(display: .current)
        case .remember: .rememberSplit(display: .current)
        case .forgetSplit: .forgetSplit(display: .current)
        case .explain: .explain
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
        case .tileEvenly(let display):
            DisplaySelectorEditor(title: "Display", selector: Binding(get: { display }, set: { command = .tileEvenly(display: $0) }))
        case .rememberSplit(let display):
            DisplaySelectorEditor(title: "Display", selector: Binding(get: { display }, set: { command = .rememberSplit(display: $0) }))
        case .forgetSplit(let display):
            DisplaySelectorEditor(title: "Display", selector: Binding(get: { display }, set: { command = .forgetSplit(display: $0) }))
        case .exportSettings(let path):
            TextField("File path", text: Binding(get: { path }, set: { command = .exportSettings(path: $0) }))
        case .importSettings(let path):
            TextField("File path", text: Binding(get: { path }, set: { command = .importSettings(path: $0) }))
        case .undo, .openSettings, .listDisplays, .describeWindow, .explain:
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
        .pickerStyle(.segmented)
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
        .pickerStyle(.radioGroup)
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
            return "\(d.magnitude) \(d >= 0 ? "more" : "fewer") column\(d.magnitude == 1 ? "" : "s")" + on(display)
        case .moveToDisplay(.next): return "Move to Next Display"
        case .moveToDisplay(.previous): return "Move to Previous Display"
        case .moveToDisplay(.index(let n)): return "Move to Display \(n)"
        case .tileWindows(let display): return "Tile All Windows" + on(display)
        case .tileEvenly(let display): return "Tile Evenly" + on(display)
        case .rememberSplit(let display): return "Remember Split" + on(display)
        case .forgetSplit(let display): return "Forget This Split" + on(display)
        case .explain: return "What Just Happened?"
        case .undo: return "Undo Last Move"
        case .openSettings: return "Open Settings"
        case .listDisplays: return "List Displays"
        case .describeWindow: return "Describe Window"
        case .exportSettings(let path): return "Export Settings to \(path)"
        case .importSettings(let path): return "Import Settings from \(path)"
        }
    }
}

/// Section a hotkey is listed under in Shortcuts, derived from its command.
enum HotkeyGroup: String, CaseIterable {
    case windows = "Windows", columns = "Columns", displays = "Displays", cycles = "Cycles", other = "Other"
}

extension Command {
    var hotkeyGroup: HotkeyGroup {
        switch self {
        case .apply, .tileWindows, .tileEvenly, .undo: .windows
        case .columns: .columns
        case .moveToDisplay, .listDisplays: .displays
        case .cycle: .cycles
        case .rememberSplit, .forgetSplit, .explain, .openSettings, .describeWindow, .exportSettings, .importSettings: .other
        }
    }
}
