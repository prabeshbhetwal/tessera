import SwiftUI
import TesseraCore

struct RingPane: View {
    @Bindable var model: SettingsModel

    static let directions = ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left"]

    var body: some View {
        let ring = $model.settings.ring
        let r = model.settings.ring
        Form {
            Section("Zones") {
                ZoneDiagram(ring: r)
                    .frame(height: 220)
                SliderRow(title: "Dead zone", value: ring.deadZone, range: 0...max(1, r.flickDistance - 1))
                SliderRow(title: "Flick distance", value: ring.flickDistance, range: (r.deadZone + 1)...max(r.deadZone + 2, 400))
                Caption("Inside the dead zone nothing is selected. Between the two, the direction picks a wedge. Beyond the flick distance you point at the grid.")
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
                SliderRow(title: "Radius", value: ring.radius, range: 20...150)
                SliderRow(title: "Thickness", value: ring.thickness, range: 4...max(5, min(80, r.radius * 2)))
                Caption("Thickness can't exceed twice the radius.")
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

/// Dead zone, flick ring and wedge boundaries, scaled to fit.
private struct ZoneDiagram: View {
    let ring: RingSettings

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = (min(size.width, size.height) / 2 - 24) / max(ring.flickDistance, 1)
            let flick = ring.flickDistance * scale
            let dead = ring.deadZone * scale

            func circle(_ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            context.fill(circle(flick), with: .color(.accentColor.opacity(0.12)))
            context.stroke(circle(flick), with: .color(.accentColor), lineWidth: 1.5)
            context.fill(circle(dead), with: .color(.secondary.opacity(0.35)))

            var spokes = Path()
            for k in 0..<8 {
                // Boundaries sit at 22.5° + k·45° clockwise from up; Canvas is y-down.
                let a = (22.5 + Double(k) * 45) * .pi / 180
                spokes.move(to: CGPoint(x: center.x + sin(a) * dead, y: center.y - cos(a) * dead))
                spokes.addLine(to: CGPoint(x: center.x + sin(a) * flick, y: center.y - cos(a) * flick))
            }
            context.stroke(spokes, with: .color(.secondary), lineWidth: 1)

            context.draw(Text("Point").font(.caption), at: CGPoint(x: center.x + flick + 4, y: center.y - flick + 8), anchor: .leading)
            context.draw(Text("Flick").font(.caption2), at: CGPoint(x: center.x, y: center.y - (flick + dead) / 2))
        }
        .accessibilityElement()
        .accessibilityLabel("Zone diagram: dead zone \(Int(ring.deadZone)) points, flick up to \(Int(ring.flickDistance)) points, point mode beyond.")
    }
}

#Preview {
    RingPane(model: SettingsModel())
}
