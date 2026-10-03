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
                    Label("**Cancel** — release in the ring's empty middle (✕), press Esc, or right-click. Nothing moves.", systemImage: "xmark.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Zones") {
                let pointMin = max(r.outerRadius, r.deadZone + 1).rounded(.up)
                SliderRow(title: "Pointing starts at", value: ring.flickDistance, range: pointMin...max(pointMin + 1, 400))
                Caption("The dashed circle on screen sits here. Make it bigger if you slip into pointing by accident.")
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

            Section("Size") {
                SliderRow(title: "Radius", value: ring.radius, range: 20...max(21, min(150, r.flickDistance - r.thickness / 2)))
                SliderRow(title: "Thickness", value: ring.thickness,
                          range: 4...max(5, min(80, r.radius * 2, (r.flickDistance - r.radius) * 2)))
                Caption("The ring's empty middle is the cancel area (\(Int(r.cancelRadius)) pt). The ring always stays inside the dashed circle.")
            }

            ResetSection {
                let d = RingSettings.default
                model.settings.ring.deadZone = d.deadZone
                model.settings.ring.flickDistance = d.flickDistance
                model.settings.ring.wedges = d.wedges
                model.settings.ring.radius = d.radius
                model.settings.ring.thickness = d.thickness
            }
        }
        .formStyle(.grouped)
    }
}

/// Cancel area, direction zone (with the dashed pointing boundary) and wedge boundaries, scaled to fit.
private struct ZoneDiagram: View {
    let ring: RingSettings

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = (min(size.width, size.height) / 2 - 24) / CGFloat(max(ring.flickDistance, 1))
            let flick = CGFloat(ring.flickDistance) * scale
            let dead = CGFloat(ring.cancelRadius) * scale

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
            context.draw(Text("✕ Cancel").font(.caption2.weight(.semibold)), at: center)
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Zone diagram: cancel within \(Int(ring.cancelRadius)) points, directions up to \(Int(ring.flickDistance)) points, pointing beyond.")
    }
}

#Preview {
    RingPane(model: SettingsModel())
}
