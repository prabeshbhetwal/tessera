import AppKit
import SwiftUI
import TesseraCore

extension RingSettings {
    /// The largest radius the ring can have: its outer edge (radius + thickness / 2) stays inside the point threshold,
    /// which saving requires while pointing is on. Shared by the Ring pane's slider and the stage's handle.
    var radiusCap: Double { max(20, min(150, flickDistance - thickness / 2)) }
    /// The thickest the ring can be, for the same reason, and never more than twice its radius.
    var thicknessCap: Double { max(4, min(80, radius * 2, (flickDistance - radius) * 2)) }
}

/// Which ring size the stage's handle edits: the cued slider's.
enum RingHandle: Equatable {
    case radius, thickness
}

/// The grab handle on the ring's outer edge, on its right. Dragging sideways resizes the ring live, in the stage's
/// ring scale, within the same limits as the form's slider; Esc during the drag puts back the size it started with.
/// The form stays the way in for the keyboard and VoiceOver, so the handle is hidden from both.
struct StageRingHandleView: View {
    let handle: RingHandle
    let ring: RingSettings
    let scale: CGFloat
    let edit: (RingSettings) -> Void
    @Environment(DemoCueState.self) private var cues: DemoCueState?
    @State private var start: RingSettings?
    @State private var escape: Any?
    @State private var cancelled = false

    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .scaleEffect(start == nil ? 1 : 1.2)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if start == nil { begin() }
                    guard let start, !cancelled else { return }
                    edit(resized(start, by: drag.translation.width / scale))
                }
                .onEnded { _ in finish() })
            .accessibilityHidden(true)
    }

    private func resized(_ ring: RingSettings, by points: Double) -> RingSettings {
        var ring = ring
        switch handle {
        case .radius:
            ring.radius = min(max(ring.radius + points, 20), max(21, ring.radiusCap)).rounded()
        case .thickness:
            // The handle sits on the outer edge, which moves by half of any change in thickness.
            ring.thickness = min(max(ring.thickness + points * 2, 4), max(5, ring.thicknessCap)).rounded()
        }
        return ring
    }

    private func begin() {
        start = ring
        cancelled = false
        cues?.editing = true
        let original = ring
        let edit = edit
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread.
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                cancelled = true
                edit(original)
            }
            return nil
        }
    }

    private func finish() {
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
        start = nil
        cues?.editing = false
    }
}
