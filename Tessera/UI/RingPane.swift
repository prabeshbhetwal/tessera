import SwiftUI
import TesseraCore

struct RingPane: View {
    @Bindable var model: SettingsModel

    static let directions = ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left"]

    var body: some View {
        let ring = $model.settings.ring
        let r = model.settings.ring
        Form {
            Section("Two ways to snap") {
                ZoneDiagram(ring: r)
                    .frame(height: 220)
                VStack(alignment: .leading, spacing: 6) {
                    Label("**Direction** — move a little toward an edge or corner. The wedge you head for lights up and shows its layout.", systemImage: "arrow.up.right.circle")
                    Label("**Point** — keep going past the dashed circle and the ring fades. Point at a column of the grid; click to span several.", systemImage: "rectangle.split.3x1")
                    Label("Come back inside the dashed circle to return to directions. Release the trigger to snap.", systemImage: "arrow.uturn.backward.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Zones") {
                SliderRow(title: "Nothing picked within", value: ring.deadZone, range: 0...max(1, r.flickDistance - 1))
                SliderRow(title: "Pointing starts at", value: ring.flickDistance, range: (r.deadZone + 1)...max(r.deadZone + 2, 400))
                Caption("The dashed circle on screen sits at \"Pointing starts at\". Make it bigger if you slip into pointing by accident.")
            }

            Section("Wedges") {
                ForEach(r.wedges.indices, id: \.self) { i in
                    Picker(Self.directions[i % Self.directions.count], selection: ring.wedges[i]) {
                        ForEach(WindowAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                }
            }

            Section("Pointing rows") {
                SliderRow(title: "Top band", value: ring.topBand, range: 0.1...max(0.11, 0.9 - r.bottomBand), step: 0.05, format: SliderRow.percent)
                SliderRow(title: "Bottom band", value: ring.bottomBand, range: 0.1...max(0.11, 0.9 - r.topBand), step: 0.05, format: SliderRow.percent)
                Caption("While pointing, the top and bottom bands of a column snap to half height; the middle is full height.")
            }

            Section {
                Caption("The ring's size and colours are in Appearance.")
            }

            ResetSection {
                let d = RingSettings.default
                model.settings.ring.deadZone = d.deadZone
                model.settings.ring.flickDistance = d.flickDistance
                model.settings.ring.wedges = d.wedges
                model.settings.ring.topBand = d.topBand
                model.settings.ring.bottomBand = d.bottomBand
            }
        }
        .formStyle(.grouped)
    }
}

/// Dead zone, direction zone (with the dashed pointing boundary) and wedge boundaries, scaled to fit.
private struct ZoneDiagram: View {
    let ring: RingSettings

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = (min(size.width, size.height) / 2 - 24) / CGFloat(max(ring.flickDistance, 1))
            let flick = CGFloat(ring.flickDistance) * scale
            let dead = CGFloat(ring.deadZone) * scale

            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            context.fill(circle(flick), with: .color(.accentColor.opacity(0.12)))
            context.stroke(circle(flick), with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
            context.fill(circle(dead), with: .color(.secondary.opacity(0.35)))

            var spokes = Path()
            for k in 0..<8 {
                // Boundaries sit at 22.5° + k·45° clockwise from up; Canvas is y-down.
                let a = CGFloat((22.5 + Double(k) * 45) * .pi / 180)
                spokes.move(to: CGPoint(x: center.x + sin(a) * dead, y: center.y - cos(a) * dead))
                spokes.addLine(to: CGPoint(x: center.x + sin(a) * flick, y: center.y - cos(a) * flick))
            }
            context.stroke(spokes, with: .color(.secondary), lineWidth: 1)

            context.draw(Text("Point beyond").font(.caption), at: CGPoint(x: center.x + flick + 4, y: center.y - flick + 8), anchor: .leading)
            context.draw(Text("Direction").font(.caption2), at: CGPoint(x: center.x, y: center.y - (flick + dead) / 2))
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Zone diagram: nothing picked within \(Int(ring.deadZone)) points, directions up to \(Int(ring.flickDistance)) points, pointing beyond.")
    }
}

#Preview {
    RingPane(model: SettingsModel())
}
