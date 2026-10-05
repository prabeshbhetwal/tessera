import SwiftUI
import TesseraCore

/// Ordered list of targets per named cycle (spec §6). Steps reorder with ⌘↑ / ⌘↓.
struct CyclesEditor: View {
    @Binding var cycles: [Cycle]
    @FocusState private var focusedStep: StepID?

    private struct StepID: Hashable {
        let cycle: Int
        let step: Int
    }

    var body: some View {
        ForEach(cycles.indices, id: \.self) { c in
            let cycle = cycleBinding(c)
            Section("Cycle “\(cycles[c].name)”") {
                TextField("Name", text: cycle.name)
                DisplaySelectorEditor(title: "Display", selector: cycle.display)
                ForEach(cycles[c].steps.indices, id: \.self) { s in
                    stepRow(cycle: c, step: s)
                }
                HStack {
                    Button("Add Step") { cycles[c].steps.append(.action(.maximize)) }
                    Spacer()
                    Button("Remove Cycle", role: .destructive) { cycles.remove(at: c) }
                }
                if cycles[c].steps.isEmpty { Caption("A cycle with no steps does nothing.") }
            }
        }
        Section {
            Button("Add Cycle", action: addCycle)
        } footer: {
            Footer("Each press of a cycle's hotkey moves the window to its next step. Reorder steps with the arrows, or select a step's number and press ⌘↑ or ⌘↓. Renaming a cycle doesn't update the hotkeys in Shortcuts that run it.")
        }
    }

    private func stepRow(cycle c: Int, step s: Int) -> some View {
        let count = cycles[c].steps.count
        return HStack {
            Text("\(s + 1).")
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                    focusedStep == StepID(cycle: c, step: s) ? Color.accentColor : .clear, lineWidth: 1.5))
                .focusable(interactions: .edit)
                .focusEffectDisabled()
                .focused($focusedStep, equals: StepID(cycle: c, step: s))
                .accessibilityLabel("Step \(s + 1) of \(count): \(cycles[c].steps[s].summary)")
                .accessibilityAction(named: "Move up") { move(cycle: c, step: s, by: -1) }
                .accessibilityAction(named: "Move down") { move(cycle: c, step: s, by: 1) }
            TargetEditor(target: stepBinding(cycle: c, step: s))
            Spacer(minLength: 0)
            Button { move(cycle: c, step: s, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(s == 0)
                .accessibilityLabel("Move step \(s + 1) up")
            Button { move(cycle: c, step: s, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(s == count - 1)
                .accessibilityLabel("Move step \(s + 1) down")
            Button { cycles[c].steps.remove(at: s) } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Remove step \(s + 1)")
        }
        .buttonStyle(.borderless)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            move(cycle: c, step: s, by: press.key == .upArrow ? -1 : 1)
            return .handled
        }
    }

    // Index-checked bindings: a row can be re-evaluated once more after its cycle or step is removed.
    private func cycleBinding(_ c: Int) -> Binding<Cycle> {
        Binding(
            get: { cycles.indices.contains(c) ? cycles[c] : Cycle(name: "", steps: []) },
            set: { if cycles.indices.contains(c) { cycles[c] = $0 } }
        )
    }

    private func stepBinding(cycle c: Int, step s: Int) -> Binding<Target> {
        func valid() -> Bool { cycles.indices.contains(c) && cycles[c].steps.indices.contains(s) }
        return Binding(
            get: { valid() ? cycles[c].steps[s] : .action(.maximize) },
            set: { if valid() { cycles[c].steps[s] = $0 } }
        )
    }

    private func move(cycle c: Int, step s: Int, by delta: Int) {
        let to = s + delta
        guard cycles.indices.contains(c), cycles[c].steps.indices.contains(s), cycles[c].steps.indices.contains(to) else { return }
        cycles[c].steps.swapAt(s, to)
        focusedStep = StepID(cycle: c, step: to)
    }

    private func addCycle() {
        var n = cycles.count + 1
        while cycles.contains(where: { $0.name == "cycle \(n)" }) { n += 1 }
        cycles.append(Cycle(name: "cycle \(n)", steps: [.action(.maximize)]))
    }
}

/// Compact editor for a `Target`: an action, or a 1-based column span (negatives count from the right) and band.
struct TargetEditor: View {
    @Binding var target: Target

    var body: some View {
        HStack {
            Picker("Kind", selection: Binding.choice(target.isAction ? 0 : 1) {
                target = $0 == 0 ? .action(.maximize) : .span(columns: 1...1, band: .full)
            }) {
                Text("Action").tag(0)
                Text("Columns").tag(1)
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Target kind")

            switch target {
            case .action(let action):
                Picker("Action", selection: Binding(get: { action }, set: { target = .action($0) })) {
                    ForEach(WindowAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Action")
            case .span(let columns, let band):
                ColumnStepper(title: "From", value: Binding(
                    get: { columns.lowerBound },
                    set: { target = .span(columns: $0...max($0, columns.upperBound), band: band) }
                ))
                ColumnStepper(title: "to", value: Binding(
                    get: { columns.upperBound },
                    set: { target = .span(columns: min(columns.lowerBound, $0)...$0, band: band) }
                ))
                Picker("Band", selection: Binding(get: { band }, set: { target = .span(columns: columns, band: $0) })) {
                    Text("Full").tag(Band.full)
                    Text("Top").tag(Band.top)
                    Text("Bottom").tag(Band.bottom)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Band")
            }
        }
    }
}

/// Column number stepper that skips 0: 1 … 16 from the left, −1 … −16 from the right.
struct ColumnStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        // Label outside the Stepper: inside a grouped Form a labelled Stepper becomes a full-width
        // label…control row, which pushed step rows wider than the form and clipped them.
        HStack(spacing: 4) {
            Text("\(title) \(value)")
                .monospacedDigit()
                .accessibilityHidden(true)
            Stepper(title) {
                value = value == -1 ? 1 : min(16, value + 1)
            } onDecrement: {
                value = value == 1 ? -1 : max(-16, value - 1)
            }
            .labelsHidden()
            .accessibilityLabel("\(title) column")
            .accessibilityValue(value < 0 ? "\(-value) from the right" : "\(value)")
        }
        .fixedSize()
    }
}

/// Which display a command or cycle acts on.
struct DisplaySelectorEditor: View {
    let title: String
    @Binding var selector: DisplaySelector

    private enum Kind: Hashable { case current, cursor, index, id }

    private var kind: Kind {
        switch selector {
        case .current: .current
        case .cursor: .cursor
        case .index: .index
        case .id: .id
        }
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Picker(title, selection: Binding.choice(kind) { k in
                    switch k {
                    case .current: selector = .current
                    case .cursor: selector = .cursor
                    case .index: selector = .index(1)
                    case .id: selector = .id("")
                    }
                }) {
                    Text("Window's display").tag(Kind.current)
                    Text("Under the cursor").tag(Kind.cursor)
                    Text("Number (left to right)").tag(Kind.index)
                    Text("Specific display").tag(Kind.id)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(title)
                switch selector {
                case .index(let n):
                    Text("\(n)").monospacedDigit().accessibilityHidden(true)
                    Stepper("Display number", value: Binding(get: { n }, set: { selector = .index($0) }), in: 1...16)
                        .labelsHidden()
                        .accessibilityValue("\(n)")
                case .id(let key):
                    TextField("Display ID", text: Binding(get: { key }, set: { selector = .id($0) }))
                        .frame(minWidth: 120)
                default:
                    EmptyView()
                }
            }
        }
    }
}

extension Target {
    var isAction: Bool { if case .action = self { true } else { false } }

    var summary: String {
        switch self {
        case .action(let action):
            return action.displayName
        case .span(let columns, let band):
            let cols = columns.count == 1 ? "Column \(columns.lowerBound)" : "Columns \(columns.lowerBound)…\(columns.upperBound)"
            return band == .full ? cols : "\(cols), \(band.rawValue)"
        }
    }
}

extension DisplaySelector {
    var summary: String {
        switch self {
        case .current: "window's display"
        case .cursor: "display under the cursor"
        case .index(let n): "display \(n)"
        case .id(let key): "display \(key)"
        }
    }
}
