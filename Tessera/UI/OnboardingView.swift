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
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: accessibility
                case 2: screenRecording
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 24)

            Divider()
            footer
        }
        .frame(width: 600, height: 500)
        .onChange(of: step, initial: true) { _, now in Self.saveStep(now) }
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

    /// Step of a setup still in progress, kept across a relaunch. Cleared when the window closes.
    private static let savedStepKey = "onboardingStep"
    static var savedStep: Int? { UserDefaults.standard.object(forKey: savedStepKey) as? Int }
    static func saveStep(_ step: Int?) {
        if let step { UserDefaults.standard.set(step, forKey: savedStepKey) } else {
            UserDefaults.standard.removeObject(forKey: savedStepKey)
        }
    }

    /// Accessibility is required: nothing past its step is reachable until it's granted.
    private var isBlocked: Bool { step == Self.accessibilityStep && !axTrusted }

    private var nextTitle: String {
        switch step {
        case 2 where !screenAllowed: "Skip"
        default: "Continue"
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            StepIndicator(count: Self.stepCount, current: step)
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
            // Esc closes the window, as it does everywhere else. Setup reopens until Accessibility is granted.
            KeyCommand(.cancelAction) {
                guard !isBlocked else { return }
                onFinish()
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            FlickDemo()
                .frame(height: 160)
            VStack(spacing: 8) {
                Text("Snap windows with the ring").font(.largeTitle.weight(.bold))
                Text("Hold the trigger, then move toward an edge for a half, a corner for a quarter, or up to fill the screen. Keep going further out to point at a column of your display's grid instead.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            KeycapRow(keys: ModifierKey.names(chord.keyCodes), prominent: true)
        }
    }

    private var accessibility: some View {
        StepPage(
            symbol: "accessibility", tint: .blue, title: "Allow Accessibility",
            text: "Tessera moves and resizes other apps' windows through macOS Accessibility. The trigger does nothing until it's allowed."
        ) {
            PermissionRow(title: "Accessibility", granted: axTrusted, actionTitle: "Grant…") {
                Permissions.promptAccessibility()
                startFixTimer()
            }
            if showFix && !axTrusted {
                VStack(spacing: 8) {
                    Caption("Still not granted? An older Tessera build may hold a stale entry. Reset it, then grant again.")
                        .multilineTextAlignment(.center)
                    Button("Fix permission", action: resetPermission)
                        .controlSize(.regular)
                    if let fixError { Caption(fixError) }
                }
                .frame(maxWidth: 440)
            }
        }
    }

    private var screenRecording: some View {
        StepPage(
            symbol: "rectangle.dashed.badge.record", tint: .teal, title: "Live window thumbnails",
            text: "Optional, and only used by the Window snapshot preview style. The preview is a tinted box by default; with Screen Recording allowed you can switch it to show a picture of the window you're moving. Tessera takes one still snapshot per gesture and never records or saves anything."
        ) {
            PermissionRow(title: "Screen Recording", granted: screenAllowed, actionTitle: "Allow…") {
                Permissions.requestScreenCapture()
                screenAllowed = Permissions.isScreenCaptureAllowed
            }
            Caption("Allowing it doesn't change the preview by itself: pick Window snapshot in Settings › Overlay › Preview. After you allow it, macOS asks to quit and reopen Tessera; setup continues here.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }

    private var tryIt: some View {
        StepPage(
            symbol: "hand.point.up.left.fill", tint: .indigo, title: "Try it",
            text: "Click another app's window, then hold \(ModifierKey.describe(chord.keyCodes))."
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                GestureHint("arrow.up.left.and.arrow.down.right", "Move a little: an edge is a half, a corner a quarter, up is full screen.")
                GestureHint("rectangle.split.3x1", "Keep going further out to point at a column. Click to span several.")
                GestureHint("xmark.circle", "Changed your mind? Release in the middle, press Esc or right-click.")
                GestureHint("scroll", "Scroll while holding to change how many columns the display has.")
                GestureHint("return", "Release to snap. Arrow keys and Return work too.")
            }
            .frame(maxWidth: 480)
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
            Task { @MainActor in Permissions.promptAccessibility(freshPrompt: true) }
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

// MARK: - Building blocks

/// Centred step layout: icon tile, title, body, then the step's controls.
private struct StepPage<Extra: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title).font(.title.weight(.bold))
                Text(text)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            extra
        }
        .frame(maxWidth: .infinity)
    }
}

/// One permission: symbol, name, granted or not, and the button that asks for it.
private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(granted ? "Granted" : "Not granted yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .disabled(granted)
        }
        .padding(14)
        .frame(width: 440)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Symbol in a tinted circle next to one gesture description.
private struct GestureHint: View {
    let symbol: String
    let text: String

    init(_ symbol: String, _ text: String) {
        self.symbol = symbol
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.tint.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Progress bar: one short capsule per step.
private struct StepIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : i < current ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25))
                    .frame(width: i == current ? 22 : 8, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Looping sketch of a flick: a cursor dot leaves the centre and lights the wedge it heads for.
private struct FlickDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sequence = [6, 2, 0, 3, 7]

    var body: some View {
        // 30 fps is plenty for a decorative demo; the default follows the display (120 Hz on ProMotion)
        // and cost ~25% CPU for as long as onboarding stayed open.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
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
        .accessibilityLabel("Animation: the cursor moves outward and the ring highlights the wedge it heads for.")
    }
}

#Preview {
    OnboardingView {}
}
