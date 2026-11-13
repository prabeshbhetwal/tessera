import SwiftUI
import TesseraCore

/// Learned splits (window arrangements remembered per display): how they are learned, and a list to forget.
struct SplitsPane: View {
    private static let waitInfo = "A window opened next to tiled windows waits this many seconds and is tiled in "
        + "equal shares only if it’s still open, so an app you open for a moment (Wispr Flow, Finder) is left alone. "
        + "Apps you’ve arranged together before get their split straight away. 0 tiles right away."
    @Bindable var model: SettingsModel
    let displays: [DisplayContext]
    @State private var confirmingForgetAll = false
    /// Key of the display whose splits sheet is open.
    @State private var managing: String?

    var body: some View {
        Form {
            Section {
                Toggle("Learn from my adjustments", isOn: $model.settings.learnSplits).settingAnchor("Learn from my adjustments")
                Toggle("Resize neighbours to fill the display", isOn: $model.settings.splitReflowsNeighbours).settingAnchor("Resize neighbours to fill the display").demoCue(.reflow)
                    .disabled(!model.settings.learnSplits)
                Toggle("Fill the space when a window closes", isOn: $model.settings.splitFillsClosedGap).settingAnchor("Fill the space when a window closes").demoCue(.fillGap)
                    .disabled(!model.settings.learnSplits)
                Picker("When a window is minimised", selection: $model.settings.splitOnMinimise) {
                    Text("Re-tile remaining windows").tag(SplitMinimiseAction.retile)
                    Text("Leave the space empty").tag(SplitMinimiseAction.leaveSpace)
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.settings.learnSplits || !model.settings.splitFillsClosedGap)
                .settingAnchor("When a window is minimised")
                Picker("When a window closes but its app keeps running", selection: $model.settings.splitOnCloseKeepsRunning) {
                    Text("Re-tile remaining windows").tag(SplitMinimiseAction.retile)
                    Text("Leave the space empty").tag(SplitMinimiseAction.leaveSpace)
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.settings.learnSplits || !model.settings.splitFillsClosedGap)
                .settingAnchor("When a window closes but its app keeps running")
                Toggle("Make room when a window opens", isOn: $model.settings.splitTilesNewWindow)
                    .disabled(!model.settings.learnSplits)
                    .settingAnchor("Make room when a window opens")
                Picker("Make room on", selection: $model.settings.splitNewWindowScope) {
                    Text("Displays already tiled").tag(SplitNewWindowScope.tiledDisplays)
                    Text("Also wherever the apps have a split").tag(SplitNewWindowScope.rememberedSplits)
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.settings.learnSplits || !model.settings.splitTilesNewWindow)
                .settingAnchor("Make room on")
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField("Seconds", value: $model.settings.splitNewWindowWait, format: .number)
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 44)
                        Stepper("Seconds", value: $model.settings.splitNewWindowWait,
                                in: 0...TesseraSettings.maxNewWindowWait).labelsHidden()
                        Text("s")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Wait before tiling a new app")
                        InfoButton(topic: "Wait before tiling a new app", text: Self.waitInfo)
                    }
                }
                .disabled(!model.settings.learnSplits || !model.settings.splitTilesNewWindow)
                .settingAnchor("Wait before tiling a new app")
                Toggle("Restore last order", isOn: $model.settings.splitRestoresOrder).settingAnchor("Restore last order")
                Picker("Empty space when order changes", selection: $model.settings.splitGapPlacement) {
                    Text("Stays in place").tag(SplitGapPlacement.staysInPlace)
                    Text("Follows its neighbour").tag(SplitGapPlacement.followsNeighbour)
                }
                .pickerStyle(.radioGroup)
                .settingAnchor("Empty space when order changes")
            } header: {
                InfoHeader("Learning", info: "Tessera remembers how you arrange the same apps on each display and reuses it when windows open, close or get tiled. A minimised window counts as closed; restoring it fits it back in unless its space is left empty. Most options here need Learn from my adjustments.")
            } footer: {
                if model.settings.learnSplits && !model.settings.splitFillsClosedGap {
                    Footer("The minimise and close choices need \u{201C}Fill the space when a window closes\u{201D}.")
                }
            }

            // One short row per display, so the pane stays short with any number of displays; each display's
            // splits are listed, searched and forgotten in its own sheet.
            let groups = displayGroups
            Section {
                ForEach(groups) { group in
                    DisplaySplitsRow(group: group) { managing = group.id }
                }
                if !groups.isEmpty {
                    HStack {
                        Spacer()
                        Button("Forget All…", role: .destructive) { confirmingForgetAll = true }.settingAnchor("Forget All…")
                    }
                }
            } header: {
                InfoHeader("Learned splits", info: "Window layouts Tessera remembers, for each display. "
                    + "Forget one and Tessera uses equal shares for those apps until it learns them again.")
            } footer: {
                if groups.isEmpty {
                    Footer("Nothing learned yet. Adjust tiled windows by hand, or choose Remember Split in the menu bar.")
                }
            }

            ResetSection(keeps: "Keeps your learned splits.") {
                let defaults = TesseraSettings.defaults
                model.settings.learnSplits = defaults.learnSplits
                model.settings.splitReflowsNeighbours = defaults.splitReflowsNeighbours
                model.settings.splitFillsClosedGap = defaults.splitFillsClosedGap
                model.settings.splitOnMinimise = defaults.splitOnMinimise
                model.settings.splitOnCloseKeepsRunning = defaults.splitOnCloseKeepsRunning
                model.settings.splitTilesNewWindow = defaults.splitTilesNewWindow
                model.settings.splitNewWindowScope = defaults.splitNewWindowScope
                model.settings.splitNewWindowWait = defaults.splitNewWindowWait
                model.settings.splitRestoresOrder = defaults.splitRestoresOrder
                model.settings.splitGapPlacement = defaults.splitGapPlacement
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { managing != nil }, set: { if !$0 { managing = nil } })) {
            let group = displayGroups.first { $0.id == managing }
            LearnedSplitsSheet(title: group?.title ?? "", splits: group?.splits ?? []) { keys in
                model.settings.learnedSplits = keys.reduce(model.settings.learnedSplits) { SplitMemory.forget($1, in: $0) }
            }
        }
        .confirmationDialog(
            "Forget all learned splits? Tile All Windows will use equal shares again.",
            isPresented: $confirmingForgetAll, titleVisibility: .visible
        ) {
            Button("Forget All", role: .destructive) { model.settings.learnedSplits = [] }
        }
    }

    /// One display's splits, newest first, titled with the display's name.
    struct DisplayGroup: Identifiable {
        let id: String
        let title: String
        let connected: Bool
        let splits: [LearnedSplit]
    }

    /// Connected displays first in system order, then disconnected ones sorted by key.
    private var displayGroups: [DisplayGroup] {
        let byDisplay = Dictionary(grouping: model.settings.learnedSplits, by: \.key.display)
        var seen = Set<String>()
        let connected = displays.map(\.id.storageKey).filter { seen.insert($0).inserted }
        let order = connected.filter { byDisplay[$0] != nil }
            + byDisplay.keys.filter { !connected.contains($0) }.sorted()
        let rows: [(id: String, splits: [LearnedSplit])] = order.compactMap { id in
            guard let splits = byDisplay[id]?.sorted(by: { $0.updated > $1.updated }), !splits.isEmpty else { return nil }
            return (id, splits)
        }
        // Several disconnected displays would all be "Not connected", and two monitors can share a name; number them apart.
        let titles = SplitLabel.numbered(rows.map { SplitLabel.display($0.splits[0].key, displays: displays) })
        return zip(rows, titles).map { row, title in
            DisplayGroup(id: row.id, title: title, connected: connected.contains(row.id), splits: row.splits)
        }
    }
}

/// One display in the Learned splits list: its name, whether it's connected, how many splits, and Manage….
private struct DisplaySplitsRow: View {
    let group: SplitsPane.DisplayGroup
    let manage: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                Text(LearnedSplitsSheet.count(group.splits.count))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Manage\u{2026}", action: manage)
                    .accessibilityLabel("Manage splits on \(group.title)")
            }
        } label: {
            Label {
                Text(group.title)
            } icon: {
                Image(systemName: "display")
                    .foregroundStyle(group.connected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }
        }
    }
}

#Preview {
    SplitsPane(model: SettingsModel(), displays: [])
}
