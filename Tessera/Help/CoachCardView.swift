import AppKit
import SwiftUI
import TesseraCore

/// The coach card: what happened, the step's buttons (the first is primary), and a footer that offers to stop tips.
/// Opened on request (`keyable`) it also browses earlier and later tips, with ← and →, and Esc closes it.
struct CoachCardView: View {
    let step: CoachStep
    let index: Int
    let count: Int
    let keyable: Bool
    let onAction: (CoachAction) -> Void
    let onBrowse: (Int) -> Void
    let onDontShow: () -> Void
    let onClose: () -> Void
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(step.title).font(.headline)
                Spacer(minLength: 0)
                if count > 1 {
                    Text("\(index + 1) of \(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text(step.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            .padding(.top, 4)
            footer
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        // The auto card is never key; keep the primary button in the accent rather than the inactive grey.
        .environment(\.controlActiveState, keyable ? activeState : .key)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(step.title)
    }

    @ViewBuilder private var buttons: some View {
        ForEach(Array(step.actions.enumerated()), id: \.offset) { offset, action in
            if offset == 0 {
                Button(action.label) { onAction(action) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(action.label) { onAction(action) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if keyable {
                Button { onBrowse(-1) } label: { Label("Earlier", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Earlier tip")
                Button { onBrowse(1) } label: { Label("Later", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Later tip")
                Spacer(minLength: 8)
            }
            Button("Don’t show tips", action: onDontShow)
                .controlSize(.small)
                .foregroundStyle(.secondary)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .background {
            // Esc as a key equivalent, so it closes the key card even if `cancelOperation` never reaches the panel.
            if keyable {
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Takes the first click on the card even though its panel is not key.
final class CoachHostingView: NSHostingView<CoachCardView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The card's window: takes clicks without activating Tessera, and becomes key only when the coach was opened on
/// request (`keyable`). Esc while key and the pointer entering the card are reported through the callbacks.
final class CoachCardPanel: NSPanel {
    var keyable = false
    var onCancel: (() -> Void)?
    var onHover: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Tessera tip"
        level = .popUpMenu
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false  // Tessera is an accessory app and is never active.
        animationBehavior = .none
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.masksToBounds = true
        material.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        contentView = material
    }

    required init?(coder: NSCoder) { fatalError("CoachCardPanel is built in code") }

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
}
