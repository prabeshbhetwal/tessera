import SwiftUI
import TesseraCore

/// Four-step first-run flow (spec §6.2): welcome, Accessibility, optional Screen Recording, try it.
struct OnboardingView: View {
    static let stepCount = 4

    let chord: TriggerChord
    let onFinish: () -> Void
    @State private var step: Int
    @State private var axTrusted = Permissions.isAccessibilityTrusted
    @State private var axObserver: NSObjectProtocol?
    @State private var showFix = false
    @State private var fixTimer: Task<Void, Never>?
    @State private var fixError: String?
    @State private var screenAllowed = Permissions.isScreenCaptureAllowed

    init(startStep: Int = 0, chord: TriggerChord = .default, onFinish: @escaping () -> Void) {
        _step = State(initialValue: min(max(startStep, 0), Self.stepCount - 1))
        self.chord = chord
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch step {
                case 0: welcome
                case 1: accessibility
                case 2: screenRecording
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<Self.stepCount, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(step + 1) of \(Self.stepCount)")
                Spacer()
                if step == Self.accessibilityStep && !axTrusted {
                    Button("Quit Tessera") { NSApplication.shared.terminate(nil) }
                }
                if step > 0 { Button("Back") { step -= 1 } }
                if step < Self.stepCount - 1 {
                    Button(nextTitle) { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBlocked)
                } else {
                    Button("Done", action: onFinish)
                        .keyboardShortcut(.defaultAction)
                }
                // Esc skips the current step; on the last step it closes, like Done.
                KeyCommand(.cancelAction) {
                    guard !isBlocked else { return }
                    if step < Self.stepCount - 1 { step += 1 } else { onFinish() }
                }
            }
        }
        .padding(28)
        .frame(width: 540, height: 420)
        .onAppear {
            axObserver = Permissions.observeAccessibility { trusted in
                axTrusted = trusted
                guard trusted else { return }
                showFix = false
                // Granted: move on by itself instead of making the user find the button.
                if step == Self.accessibilityStep { step += 1 }
            }
        }
        .onDisappear {
            if let axObserver { DistributedNotificationCenter.default().removeObserver(axObserver) }
            axObserver = nil
            fixTimer?.cancel()
        }
    }

    static let accessibilityStep = 1

    /// Accessibility is required: nothing past its step is reachable until it's granted.
    private var isBlocked: Bool { step == Self.accessibilityStep && !axTrusted }

    private var nextTitle: String {
        switch step {
        case 2 where !screenAllowed: "Skip"
        default: "Continue"
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Tessera").font(.largeTitle.bold())
            Text("Hold \(ModifierKey.describe(chord.keyCodes)), then flick a short way to snap the front window to a half, quarter or full screen. Move further to point at a column of your display's grid.")
            FlickDemo()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allow Accessibility").font(.title.bold())
            Text("Tessera moves and resizes windows through macOS Accessibility. Without it, the trigger does nothing.")
            HStack {
                Button("Grant Accessibility") {
                    Permissions.promptAccessibility()
                    startFixTimer()
                }
                .disabled(axTrusted)
                Label(axTrusted ? "Granted" : "Not granted yet", systemImage: axTrusted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(axTrusted ? .green : .secondary)
            }
            if showFix && !axTrusted {
                Caption("Still not granted? An older Tessera build may hold a stale entry. Reset it, then grant again.")
                Button("Fix permission", action: resetPermission)
                if let fixError { Caption(fixError) }
            }
        }
    }

    private var screenRecording: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window thumbnails (optional)").font(.title.bold())
            Text("With Screen Recording allowed, the snap preview shows a live picture of the window you're moving. Tessera takes one still snapshot per gesture and never records or saves anything.")
            Text("Skip it and the preview uses a tinted rectangle. You can turn it on later in Settings › Preview.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Enable") {
                    Permissions.requestScreenCapture()
                    screenAllowed = Permissions.isScreenCaptureAllowed
                }
                .disabled(screenAllowed)
                Label(screenAllowed ? "Allowed" : "Not allowed", systemImage: screenAllowed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(screenAllowed ? .green : .secondary)
            }
            Caption("macOS may ask you to reopen Tessera before the change takes effect.")
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it").font(.title.bold())
            Text("Click any other app's window (Tessera can't move its own), then hold \(ModifierKey.describe(chord.keyCodes)) and:")
            VStack(alignment: .leading, spacing: 6) {
                Label("Flick left or right for a half.", systemImage: "arrow.left.and.right")
                Label("Flick up to maximize, diagonally for a quarter.", systemImage: "arrow.up.right")
                Label("Move further to point at a column; click to span several.", systemImage: "rectangle.split.3x1")
                Label("Scroll while holding to change the column count.", systemImage: "scroll")
                Label("Release to snap, press Esc to cancel.", systemImage: "return")
                Label("Or, while holding, use the arrow keys and press Return.", systemImage: "keyboard")
            }
            if !axTrusted {
                Caption("Accessibility isn't granted yet, so the gesture won't move this window. Go back a step to grant it.")
            }
        }
    }

    // MARK: Permission repair

    private func startFixTimer() {
        fixTimer?.cancel()
        fixTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            showFix = !Permissions.isAccessibilityTrusted
        }
    }

    /// Runs `tccutil reset Accessibility <bundle>` and prompts again once it exits.
    private func resetPermission() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.prabeshbhetwal.Tessera"]
        process.terminationHandler = { _ in
            Task { @MainActor in Permissions.promptAccessibility() }
        }
        do {
            try process.run()
            fixError = nil
            startFixTimer()
        } catch {
            fixError = "Couldn't reset the permission: \(error.localizedDescription)"
        }
    }
}

/// Looping sketch of a flick: a cursor dot leaves the centre and lights the wedge it heads for.
private struct FlickDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sequence = [6, 2, 0, 3, 7]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
                let cycle = Int(t / 1.6)
                let phase = CGFloat(min(1, (t.truncatingRemainder(dividingBy: 1.6)) / 0.8))
                let wedge = sequence[cycle % sequence.count]
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2 - 8
                let inner = outer * 0.55

                for i in 0..<8 {
                    // RingLayer draws in y-up space; flip vertically for Canvas.
                    let path = Path(RingLayer.wedgePath(index: i, center: .zero, inner: inner, outer: outer))
                        .applying(CGAffineTransform(scaleX: 1, y: -1))
                        .offsetBy(dx: center.x, dy: center.y)
                    let lit = i == wedge && phase > 0.5
                    context.fill(path, with: .color(lit ? .accentColor : .secondary.opacity(0.25)))
                }
                let angle = CGFloat(wedge) * .pi / 4
                let distance = (inner + outer) / 2 * phase
                let dot = CGPoint(x: center.x + sin(angle) * distance, y: center.y - cos(angle) * distance)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Animation: the cursor flicks outward and the ring highlights the wedge it points at.")
    }
}

#Preview {
    OnboardingView {}
}
