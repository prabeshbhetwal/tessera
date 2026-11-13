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

/// Changes the live settings from the stage: `apply { $0.ring.radius = 60 }`.
typealias SettingsApply = (_ change: (inout TesseraSettings) -> Void) -> Void

/// A grab handle on the stage: a white dot with an accent ring and a resize pointer. It reports how far it has been
/// dragged sideways (view points since the drag began); the caller turns that into a setting or a live picture.
/// Esc during the drag calls `cancel`, so the caller can put back what it started with, and the rest of the drag
/// is ignored. While dragging, the stage holds still instead of replaying. Hidden from VoiceOver and the keyboard:
/// the form is their way in.
struct StageGrip: View {
    var begin: () -> Void = {}
    let change: (CGFloat) -> Void
    let cancel: () -> Void
    var end: () -> Void = {}

    @Environment(DemoCueState.self) private var cues: DemoCueState?
    @State private var dragging = false
    @State private var cancelled = false
    @State private var escape: Any?

    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .scaleEffect(dragging ? 1.2 : 1)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !dragging { start() }
                    if !cancelled { change(drag.translation.width) }
                }
                .onEnded { _ in finish() })
            .accessibilityHidden(true)
    }

    private func start() {
        dragging = true
        cancelled = false
        cues?.editing = true
        begin()
        let cancel = cancel
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            // Local monitors run on the main thread.
            MainActor.assumeIsolated {
                cancelled = true
                cancel()
            }
            return nil
        }
    }

    private func finish() {
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
        dragging = false
        cues?.editing = false
        end()
    }
}

/// The ring's resize handle: a grip on the ring's outer edge that sets the cued size within the slider's limits.
/// The outer edge moves one for one with the radius and by half any change in thickness.
struct StageRingHandle: View {
    let handle: RingHandle
    let ring: RingSettings
    let apply: SettingsApply
    @State private var start: RingSettings?

    var body: some View {
        StageGrip(begin: { start = ring }, change: { dx in
            guard var sized = start else { return }
            let points = dx / MockDesktop.ringScale
            switch handle {
            case .radius: sized.radius = min(max(sized.radius + points, 20), max(21, sized.radiusCap)).rounded()
            case .thickness: sized.thickness = min(max(sized.thickness + points * 2, 4), max(5, sized.thicknessCap)).rounded()
            }
            apply { $0.ring = sized }
        }, cancel: {
            if let start { apply { $0.ring = start } }
        }, end: { start = nil })
    }
}
