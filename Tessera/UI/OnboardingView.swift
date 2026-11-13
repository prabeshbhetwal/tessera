import os
import SwiftUI
import TesseraCore

/// Five-step first-run flow (spec §6.2): welcome, Accessibility, optional Screen Recording, tiling, try it.
struct OnboardingView: View {
    static let stepCount = 5
    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "onboarding")

    let chord: TriggerChord
    let onFinish: () -> Void
    @State private var step: Int
    @State private var axTrusted = Permissions.isAccessibilityTrusted
    @State private var axObserver: NSObjectProtocol?
    @State private var showFix = false
    @State private var fixTimer: Task<Void, Never>?
    @State private var fixFailed = false
    /// Set by the app delegate when Accessibility reads as granted but the event tap can't be created.
    static var tapFailed = false
    @State private var tapFailed = OnboardingView.tapFailed
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
                case 3: OnboardingTilingStep()
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
                tapFailed = false
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
                Text("Hold the trigger, then move towards an edge for a half, a corner for a quarter, or up to fill the screen. Keep going further out to point at a column of your display's grid instead.")
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
            symbol: "accessibility", title: "Allow Accessibility",
            text: "Tessera moves and resizes other apps' windows through macOS Accessibility. The trigger does nothing until it's allowed."
        ) {
            PermissionRow(title: "Accessibility", granted: axTrusted, actionTitle: "Grant…") {
                Permissions.promptAccessibility()
                startFixTimer()
            }
            if (showFix && !axTrusted) || tapFailed {
                VStack(spacing: 8) {
                    Caption(tapFailed
                        ? "Allowed, but macOS won’t let Tessera read input. An older build may hold a stale entry. Reset it, then grant again."
                        : "Still not granted? An older build may hold a stale entry. Reset it, then grant again.")
                        .multilineTextAlignment(.center)
                    Button("Fix permission", action: resetPermission)
                        .controlSize(.regular)
                    if fixFailed {
                        Caption("Tessera couldn't reset the permission. Open System Settings, remove Tessera from Accessibility, then grant it again.")
                            .multilineTextAlignment(.center)
                        Button("Open System Settings") { Permissions.openPrivacyPane("Privacy_Accessibility") }
                            .controlSize(.regular)
                    }
                }
                .frame(maxWidth: 440)
            }
        }
    }

    private var screenRecording: some View {
        StepPage(
            symbol: "rectangle.dashed.badge.record", title: "Window snapshots",
            text: "Optional, and only used by the Window snapshot preview style. The preview is a tinted box by default; with Screen Recording allowed you can switch it to show a picture of the window you're moving. Tessera takes one still snapshot per gesture and never records or saves anything."
        ) {
            PermissionRow(title: "Screen Recording", granted: screenAllowed, actionTitle: "Allow…") {
                Permissions.requestScreenCapture()
                screenAllowed = Permissions.isScreenCaptureAllowed
            }
            Caption("Lets the preview show real windows. macOS then asks you to reopen Tessera.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }

    private var tryIt: some View {
        StepPage(
            symbol: "hand.point.up.left.fill", title: "Try it",
            text: "Click another app's window, then hold \(ModifierKey.describe(chord.keyCodes))."
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                GestureHint("arrow.up.left.and.arrow.down.right", "Move a little: an edge is a half, a corner a quarter, up maximises.")
                GestureHint("rectangle.split.3x1", "Keep going further out to point at a column. Click to span several.")
                GestureHint("scroll", "Scroll while holding to change how many columns the display has.")
                GestureHint("return", "Release to snap. To cancel, release in the middle, press Esc or right-click.")
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
            fixFailed = false
            startFixTimer()
        } catch {
            Self.log.error("tccutil reset failed: \(error.localizedDescription, privacy: .private)")
            fixFailed = true
        }
    }
}

// MARK: - Building blocks

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
        .padding(16)
        .frame(maxWidth: 440)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Progress bar: one short capsule per step.
private struct StepIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
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

#Preview {
    OnboardingView {}
}
