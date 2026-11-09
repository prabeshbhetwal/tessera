import SwiftUI
import TesseraCore

/// Learned splits (window arrangements remembered per display): how they are learned, and a list to forget.
struct SplitsPane: View {
    @Bindable var model: SettingsModel
    let displays: [DisplayContext]
    @State private var confirmingForgetAll = false

    var body: some View {
        Form {
            Section {
                Toggle("Learn from my adjustments", isOn: $model.settings.learnSplits).settingAnchor("Learn from my adjustments")
                Toggle("Resize neighbours to fill the display", isOn: $model.settings.splitReflowsNeighbours).settingAnchor("Resize neighbours to fill the display")
                    .disabled(!model.settings.learnSplits)
                Toggle("Fill the space when a window closes", isOn: $model.settings.splitFillsClosedGap).settingAnchor("Fill the space when a window closes")
                    .disabled(!model.settings.learnSplits)
                Picker("When a window is minimised", selection: $model.settings.splitOnMinimise) {
                    Text("Re-tile remaining windows").tag(SplitMinimiseAction.retile)
                    Text("Leave the space empty").tag(SplitMinimiseAction.leaveSpace)
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.settings.learnSplits || !model.settings.splitFillsClosedGap)
                .settingAnchor("When a window is minimised")
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
                Toggle("Restore last order", isOn: $model.settings.splitRestoresOrder).settingAnchor("Restore last order")
                Picker("Empty space when order changes", selection: $model.settings.splitGapPlacement) {
                    Text("Stays in place").tag(SplitGapPlacement.staysInPlace)
                    Text("Follows its neighbour").tag(SplitGapPlacement.followsNeighbour)
                }
                .pickerStyle(.radioGroup)
                .settingAnchor("Empty space when order changes")
            } header: {
                InfoHeader("Learning", info: "Tessera remembers how you arrange the same apps on each display and reuses it when windows open, close or get tiled. A minimised window counts as closed; restoring it fits it back in unless its space is left empty. Most options here need Learn from my adjustments.")
            }

            let groups = displayGroups
            if groups.isEmpty {
                Section {
                    Caption("Nothing learned yet. Adjust tiled windows by hand, or choose Remember Split in the menu bar.")
                }
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.splits, id: \.key) { split in
                        SplitRow(split: split) { forget(split) }
                    }
                }
            }
            if !groups.isEmpty {
                Section {
                    Button("Forget All…", role: .destructive) { confirmingForgetAll = true }.settingAnchor("Forget All…")
                }
            }

            ResetSection(keeps: "Keeps your learned splits.") {
                let defaults = TesseraSettings.defaults
                model.settings.learnSplits = defaults.learnSplits
                model.settings.splitReflowsNeighbours = defaults.splitReflowsNeighbours
                model.settings.splitFillsClosedGap = defaults.splitFillsClosedGap
                model.settings.splitOnMinimise = defaults.splitOnMinimise
                model.settings.splitTilesNewWindow = defaults.splitTilesNewWindow
                model.settings.splitNewWindowScope = defaults.splitNewWindowScope
                model.settings.splitRestoresOrder = defaults.splitRestoresOrder
                model.settings.splitGapPlacement = defaults.splitGapPlacement
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Forget all learned splits? Tile All Windows will use equal shares again.",
            isPresented: $confirmingForgetAll, titleVisibility: .visible
        ) {
            Button("Forget All", role: .destructive) { model.settings.learnedSplits = [] }
        }
    }

    private func forget(_ split: LearnedSplit) {
        model.settings.learnedSplits = SplitMemory.forget(split.key, in: model.settings.learnedSplits)
    }

    /// One display's splits, newest first, titled with the display's name.
    private struct DisplayGroup: Identifiable {
        let id: String
        let title: String
        let splits: [LearnedSplit]
    }

    /// Connected displays first in system order, then disconnected ones sorted by key.
    private var displayGroups: [DisplayGroup] {
        let byDisplay = Dictionary(grouping: model.settings.learnedSplits, by: \.key.display)
        var seen = Set<String>()
        let connected = displays.map(\.id.storageKey).filter { seen.insert($0).inserted }
        let order = connected.filter { byDisplay[$0] != nil }
            + byDisplay.keys.filter { !connected.contains($0) }.sorted()
        return order.compactMap { id in
            guard let splits = byDisplay[id]?.sorted(by: { $0.updated > $1.updated }), let first = splits.first else { return nil }
            return DisplayGroup(id: id, title: SplitLabel.display(first.key, displays: displays), splits: splits)
        }
    }
}

/// One learned split: its apps, when it was learned, and a button to forget it.
private struct SplitRow: View {
    let split: LearnedSplit
    let forget: () -> Void

    var body: some View {
        let apps = SplitLabel.apps(split.key)
        LabeledContent {
            Button("Forget", action: forget)
                .accessibilityLabel("Forget \(apps)")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(apps)
                Text("Learned \(split.updated, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SplitsPane(model: SettingsModel(), displays: [])
}
