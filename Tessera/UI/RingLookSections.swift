import SwiftUI
import TesseraCore

/// The ring's look, shown in Appearance: whether it shows, its icons and hints, and the grid while pointing.
/// How the ring behaves is in the Ring pane; its colours are in Appearance › Ring colours.
struct RingLookSections: View {
    @Bindable var model: SettingsModel

    var body: some View {
        let ring = $model.settings.ring
        let r = model.settings.ring
        Section {
            Toggle("Show the ring", isOn: ring.showRing).settingAnchor("Show the ring")
            Group {
                Toggle("Action name and input hints", isOn: ring.showActionLabels).settingAnchor("Action name and input hints")
                Picker("Layout icons", selection: ring.iconStyle) {
                    ForEach(RingIconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .settingAnchor("Layout icons")
                Toggle("Dashed circle where pointing begins", isOn: ring.showBoundary).settingAnchor("Dashed circle where pointing begins")
                    .disabled(!(r.directions && r.pointing))
                Toggle("Frosted background", isOn: ring.frosted).settingAnchor("Frosted background")
            }
            .disabled(!r.showRing)
        } header: {
            Text("Ring")
        } footer: {
            if !r.showRing {
                Footer("The ring is hidden, but gestures still work. The preview shows where the window will go.")
            }
        }

        Section {
            // Not tied to Pointing: the arrow keys pick columns too, and show the grid while they do.
            Toggle("Grid lines while picking a column", isOn: ring.showGrid).settingAnchor("Grid lines while picking a column")
            Toggle("Number the grid’s columns", isOn: ring.showColumnNumbers).settingAnchor("Number the grid’s columns")
                .disabled(!r.showGrid)
            Toggle("Show \u{201C}click to add columns\u{201D} the first few times", isOn: ring.showPointingHint)
                .disabled(!r.pointing)
                .settingAnchor("Pointing hint")
            Button("Show the hint again") { model.settings.ring.pointingHintsSeen = nil }
                .disabled(!r.pointing || !r.showPointingHint || r.pointingHintDue)
        } header: {
            InfoHeader("Grid and hints", info: "The grid shows while you point at a column, and when the arrow keys pick one.")
        }
    }
}

extension RingSettings {
    /// Copies the switches Appearance owns, so the Ring pane's Restore Defaults leaves them alone and
    /// Appearance's resets only them (`takeLook(from: .default)`).
    mutating func takeLook(from other: RingSettings) {
        showRing = other.showRing
        showActionLabels = other.showActionLabels
        iconStyle = other.iconStyle
        boundary = other.boundary
        frosted = other.frosted
        showGrid = other.showGrid
        columnNumbers = other.columnNumbers
        pointingHint = other.pointingHint
        pointingHintsSeen = other.pointingHintsSeen
    }
}

private extension RingIconStyle {
    var title: String {
        switch self {
        case .layouts: "Layout pictures"
        case .arrows: "Arrows"
        }
    }
}
