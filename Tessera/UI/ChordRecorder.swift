import SwiftUI
import TesseraCore

/// Records a modifier chord: hold the keys, then release them all.
struct ChordRecorder: View {
    @Binding var chord: TriggerChord
    /// Owned by the pane so its footer can explain what to do while recording.
    @Binding var recording: Bool
    @State private var peak: Set<UInt16> = []
    @State private var monitor: Any?

    var body: some View {
        Group {
            LabeledContent("Chord") {
                RecorderField(
                    title: "Trigger chord",
                    text: recording ? (peak.isEmpty ? "Hold keys…" : ModifierKey.describe(peak)) : ModifierKey.describe(chord.keyCodes),
                    recording: recording,
                    start: start,
                    clear: { chord = .default }
                )
            }
        }
        .onDisappear { stop() }
        // Recording pauses Tessera's trigger and hotkeys system-wide; never leave it on when focus goes elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stop() }
    }

    private func start() {
        peak = []
        recording = true
        NotificationCenter.default.post(name: .tesseraRecorderActive, object: nil, userInfo: ["active": true])
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { stop() }
                return nil
            }
            let held = ModifierKey.pressed(in: event.modifierFlags)
            peak.formUnion(held)
            if held.isEmpty, !peak.isEmpty {
                chord = TriggerChord(keyCodes: peak)
                stop()
            }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if recording {
            NotificationCenter.default.post(name: .tesseraRecorderActive, object: nil, userInfo: ["active": false])
        }
        monitor = nil
        recording = false
    }
}
