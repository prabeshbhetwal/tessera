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
                Toggle("Learn from my adjustments", isOn: $model.settings.learnSplits)
                Toggle("Restore last order", isOn: $model.settings.splitRestoresOrder)
                Picker("Empty space when order changes", selection: $model.settings.splitGapPlacement) {
                    Text("Stays in place").tag(SplitGapPlacement.staysInPlace)
                    Text("Follows its neighbour").tag(SplitGapPlacement.followsNeighbour)
                }
            } header: {
                Text("Learning")
            } footer: {
                Footer("Off: windows keep their current order and take their app's learned size.")
            }

            let groups = displayGroups
            if groups.isEmpty {
                Section {
                    Caption("Nothing learned yet. Tile a display and adjust the windows by hand, or choose Remember Split from the menu bar.")
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
                    Button("Forget All…", role: .destructive) { confirmingForgetAll = true }
                }
            }

            ResetSection(keeps: "Keeps your learned splits.") {
                let defaults = TesseraSettings.defaults
                model.settings.learnSplits = defaults.learnSplits
                model.settings.splitRestoresOrder = defaults.splitRestoresOrder
                model.settings.splitGapPlacement = defaults.splitGapPlacement
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Forget all learned splits? Tile will use equal shares again.",
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
