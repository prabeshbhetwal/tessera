import SwiftUI
import TesseraCore

struct DisplaysPane: View {
    @Bindable var model: SettingsModel
    let displays: [DisplayContext]

    var body: some View {
        Form {
            if displays.isEmpty {
                Section { Caption("No displays detected yet.") }
            }
            ForEach(displays, id: \.id) { display in
                DisplayRow(model: model, display: display)
            }

            Section("Defaults for displays without an override") {
                SliderRow(title: "Gap", value: $model.settings.defaultGap, range: 0...40)
                SliderRow(title: "Padding", value: $model.settings.defaultPadding, range: 0...40)
            }

            Section {
                DisclosureGroup("Advanced") {
                    sizingControls
                }
            }

            ResetSection {
                model.settings.displayOverrides = [:]
                model.settings.sizing = .default
                model.settings.defaultGap = TesseraSettings.defaults.defaultGap
                model.settings.defaultPadding = TesseraSettings.defaults.defaultPadding
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var sizingControls: some View {
        let s = $model.settings.sizing
        let v = model.settings.sizing
        SliderRow(title: "Narrowest column", value: s.minColumnWidth, range: 200...max(201, v.idealColumnWidth), step: 8)
        SliderRow(
            title: "Ideal column", value: s.idealColumnWidth,
            range: v.minColumnWidth...max(v.minColumnWidth + 1, v.maxColumnWidth), step: 8
        )
        SliderRow(title: "Widest column", value: s.maxColumnWidth, range: v.idealColumnWidth...max(v.idealColumnWidth + 1, 3000), step: 8)
        SliderRow(title: "Shortest row", value: s.minRowHeight, range: 200...1200, step: 8)
        StepperRow(title: "Most columns", value: s.maxColumns, range: 1...16)
        Caption("Narrowest ≤ ideal ≤ widest. Column ranges update when displays are next re-read.")
    }
}

private struct DisplayRow: View {
    @Bindable var model: SettingsModel
    let display: DisplayContext

    private var key: String { display.id.storageKey }
    private var override: DisplayProfile? { model.settings.displayOverrides[key] }
    private var range: ColumnRange { display.range }

    /// The override if one exists, otherwise what the automatic rule gives.
    private var profile: DisplayProfile {
        override ?? DisplayProfile(
            columns: range.defaultCols, gap: model.settings.defaultGap, padding: model.settings.defaultPadding
        )
    }

    private var name: String {
        let center = CGPoint(x: display.visibleFrame.midX, y: display.visibleFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }?.localizedName ?? "Display"
    }

    var body: some View {
        Section(name) {
            VStack(spacing: 6) {
                MiniGrid(display: DisplayContext(
                    id: display.id, visibleFrame: display.visibleFrame, range: range, profile: profile
                ))
                .frame(height: 96)
                Text("\(Int(display.visibleFrame.width)) × \(Int(display.visibleFrame.height)) usable · \(profile.columns) \(range.isPortrait ? "rows" : "columns")\(override == nil ? " (automatic)" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            StepperRow(title: range.isPortrait ? "Rows" : "Columns", value: binding(\.columns), range: range.minCols...range.maxCols)
                .disabled(range.minCols == range.maxCols)
            if range.minCols == range.maxCols {
                Caption("This display only fits \(range.minCols) with the current sizing constants.")
            }
            SliderRow(title: "Gap", value: binding(\.gap), range: 0...40)
            SliderRow(title: "Padding", value: binding(\.padding), range: 0...40)

            HStack {
                Spacer()
                Button("Reset to auto") { model.settings.displayOverrides[key] = nil }
                    .disabled(override == nil)
            }
            if override == nil {
                Caption("Using the automatic grid. Any change here saves an override for this display.")
            }
        }
    }

    private func binding<T>(_ field: WritableKeyPath<DisplayProfile, T>) -> Binding<T> {
        Binding(
            get: { profile[keyPath: field] },
            set: { newValue in
                var p = profile
                p[keyPath: field] = newValue
                p.isUserOverride = true
                model.settings.displayOverrides[key] = p
            }
        )
    }
}

/// Scaled-down drawing of a display and its columns.
struct MiniGrid: View {
    let display: DisplayContext

    var body: some View {
        Canvas { context, size in
            let visible = display.visibleFrame
            guard visible.width > 0, visible.height > 0 else { return }
            let scale = min(size.width / visible.width, size.height / visible.height)
            let origin = CGPoint(
                x: (size.width - visible.width * scale) / 2, y: (size.height - visible.height * scale) / 2
            )
            // AppKit y-up -> Canvas y-down.
            func map(_ r: CGRect) -> CGRect {
                CGRect(
                    x: origin.x + (r.minX - visible.minX) * scale, y: origin.y + (visible.maxY - r.maxY) * scale,
                    width: r.width * scale, height: r.height * scale
                )
            }
            context.fill(Path(roundedRect: map(visible), cornerRadius: 4), with: .color(.secondary.opacity(0.15)))
            for c in 0..<max(1, display.profile.columns) {
                let cell = map(GridGeometry.frame(for: ColumnSpan(columns: c...c, band: .full), display: display))
                context.fill(Path(roundedRect: cell, cornerRadius: 2), with: .color(.accentColor.opacity(0.4)))
                if cell.width > 18, cell.height > 14 {
                    context.draw(
                        Text("\(c + 1)").font(.caption2.weight(.medium).monospacedDigit()).foregroundStyle(.primary.opacity(0.7)),
                        at: CGPoint(x: cell.midX, y: cell.midY)
                    )
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Grid preview, \(display.profile.columns) \(display.range.isPortrait ? "rows" : "columns")")
    }
}

#Preview {
    let id = DisplayID(vendor: 1, model: 2, serial: 3, uuid: nil)
    let range = ColumnRange(minCols: 3, maxCols: 6, defaultCols: 5, maxRows: 2, isPortrait: false)
    let display = DisplayContext(
        id: id, visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 1047), range: range,
        profile: DisplayProfile(columns: 5)
    )
    return DisplaysPane(model: SettingsModel(), displays: [display])
}
