import CoreGraphics
import Testing

@testable import TesseraCore

private let chord: Set<UInt16> = [59, 58, 55]
private let chordMods: Modifiers = [.control, .option, .command]
private let co: Modifiers = [.control, .option]
private let here = CGPoint(x: 100, y: 200)

private let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124, downArrow: UInt16 = 125, upArrow: UInt16 = 126
private let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

private func key(_ code: UInt16, _ mods: Modifiers = chordMods) -> InputEvent {
    .keyDown(keyCode: code, modifiers: mods, location: here)
}

private func hotkey(_ id: String, _ code: UInt16, _ mods: Modifiers, _ command: Command, enabled: Bool = true) -> HotkeyBinding {
    HotkeyBinding(id: id, hotkey: Hotkey(keyCode: code, modifiers: mods), command: command, enabled: enabled)
}

private let bindings = [
    hotkey("cycle-left", leftArrow, co, .cycle(name: "left")),
    hotkey("undo", 6, co, .undo),
    hotkey("open-settings", 43, chordMods, .openSettings),
    hotkey("off", 7, co, .listDisplays, enabled: false),
    // Same key and modifiers as the ring's left-arrow nav key: nav must win while the ring is open.
    hotkey("shadowed", leftArrow, chordMods, .describeWindow),
]

private func machine(nav: Bool = true, hotkeys: [HotkeyBinding] = bindings) -> TriggerMachine {
    TriggerMachine(chord: .default, hotkeys: hotkeys, ringKeyNavigation: nav)
}

private func opened(nav: Bool = true, hotkeys: [HotkeyBinding] = bindings) -> TriggerMachine {
    var m = machine(nav: nav, hotkeys: hotkeys)
    _ = m.handle(.flagsChanged(pressedModifiers: chord, location: here))
    return m
}

@Suite struct TriggerMachineKeyboardTests {
    // MARK: Ring open: nav keys

    private static let navCases: [(UInt16, Modifiers, NavKey)] = {
        var list: [(UInt16, Modifiers, NavKey)] = [
            (leftArrow, chordMods, .left), (rightArrow, chordMods, .right),
            (leftArrow, chordMods.union(.shift), .extendLeft), (rightArrow, chordMods.union(.shift), .extendRight),
            (upArrow, chordMods, .bandUp), (downArrow, chordMods, .bandDown),
            (24, chordMods, .columnsPlus), (27, chordMods, .columnsMinus),
            (48, chordMods, .nextDisplay), (48, chordMods.union(.shift), .previousDisplay),
        ]
        for (i, code) in digitKeyCodes.enumerated() { list.append((code, chordMods, .column(i + 1))) }
        return list
    }()

    @Test(arguments: navCases)
    func navKeysProduceNavAndAreSuppressed(code: UInt16, mods: Modifiers, expected: NavKey) {
        var m = opened()
        let r = m.handle(key(code, mods))
        #expect(r.outputs == [.nav(expected)])
        #expect(r.suppress)
        #expect(m.isOpen)
    }

    @Test(arguments: [UInt16(36), UInt16(76)])
    func returnAndKeypadEnterApplyAndClose(code: UInt16) {
        var m = opened()
        let r = m.handle(key(code))
        #expect(r.outputs == [.nav(.apply)])
        #expect(r.suppress)
        #expect(!m.isOpen)
        // The ring is closed: releasing the chord must not apply a second time, and no reopen until released.
        #expect(m.handle(.flagsChanged(pressedModifiers: [59, 58], location: here)).outputs.isEmpty)
        #expect(m.handle(.flagsChanged(pressedModifiers: chord, location: here)).outputs.isEmpty)
        #expect(m.handle(.flagsChanged(pressedModifiers: [], location: here)).outputs.isEmpty)
    }

    @Test func escapeStillCancelsSuppressed() {
        var m = opened()
        let r = m.handle(key(53))
        #expect(r.outputs == [.cancel] && r.suppress)
        #expect(!m.isOpen)
    }

    @Test func navKeysTakePrecedenceOverAHotkeyOnTheSameKey() {
        var m = opened()
        #expect(m.handle(key(leftArrow)).outputs == [.nav(.left)])
    }

    @Test func manyNavKeysInARowKeepTheRingOpen() {
        var m = opened()
        for k in [leftArrow, rightArrow, upArrow, downArrow, 24, 27] { _ = m.handle(key(k)) }
        #expect(m.isOpen)
        #expect(m.handle(.flagsChanged(pressedModifiers: [], location: here)).outputs == [.apply])
    }

    // MARK: Ring open: any other key

    @Test func otherKeyMatchingAHotkeyCancelsRunsAndSwallows() {
        var m = opened()
        let r = m.handle(key(43, chordMods))
        #expect(r.outputs == [.cancel, .command(.openSettings)])
        #expect(r.suppress)
        #expect(!m.isOpen)
        // Chord still held: no apply on release and no reopen.
        #expect(m.handle(.flagsChanged(pressedModifiers: [], location: here)).outputs.isEmpty)
    }

    // Review Focus 3
    @Test func otherKeyWithAnExtraModifierDoesNotRunTheHotkey() {
        var m = opened()
        let r = m.handle(key(43, chordMods.union(.shift)))
        #expect(r.outputs == [.cancel])
        #expect(!r.suppress)
        #expect(!m.isOpen)
    }

    @Test func otherKeyWithoutAHotkeyCancelsAndPassesThrough() {
        var m = opened()
        let r = m.handle(key(0))
        #expect(r.outputs == [.cancel])
        #expect(!r.suppress)
        #expect(!m.isOpen)
    }

    @Test func disabledHotkeyIsNotRunFromAnOpenRing() {
        let list = [hotkey("off", 7, chordMods, .listDisplays, enabled: false)]
        var m = opened(hotkeys: list)
        #expect(m.handle(key(7)).outputs == [.cancel])
    }

    // MARK: Ring closed

    @Test func closedRingRunsAMatchingHotkeyAndSwallowsTheKey() {
        var m = machine()
        let r = m.handle(key(leftArrow, co))
        #expect(r.outputs == [.command(.cycle(name: "left"))])
        #expect(r.suppress)
        #expect(!m.isOpen)
    }

    // Review Focus 3
    @Test func extraModifierDoesNotTriggerTheHotkeyWhileClosed() {
        var m = machine()
        let r = m.handle(key(leftArrow, [.control, .option, .shift]))
        #expect(r == TriggerResult(outputs: [], suppress: false))
        let r2 = m.handle(key(leftArrow, [.control, .option, .function]))
        #expect(r2 == TriggerResult(outputs: [], suppress: false))
    }

    @Test func closedRingIgnoresUnmatchedAndDisabledKeys() {
        var m = machine()
        for e in [key(0, co), key(7, co), key(53, []), key(leftArrow, [])] {
            #expect(m.handle(e) == TriggerResult(outputs: [], suppress: false))
        }
    }

    @Test func defaultHotkeysWorkWhenClosed() {
        var m = TriggerMachine(chord: .default, hotkeys: HotkeyBinding.defaults)
        for b in HotkeyBinding.defaults {
            let r = m.handle(key(b.hotkey.keyCode, b.hotkey.modifiers))
            #expect(r.outputs == [.command(b.command)] && r.suppress, "\(b.id)")
        }
    }

    @Test func machineWithoutHotkeysBehavesAsBefore() {
        var m = TriggerMachine(chord: .default)
        #expect(m.handle(key(leftArrow, co)) == TriggerResult(outputs: [], suppress: false))
    }

    // MARK: ringKeyNavigation off

    @Test func withNavigationOffRingKeysBehaveAsM1() {
        var m = opened(nav: false)
        let r = m.handle(key(leftArrow))
        #expect(r.outputs == [.cancel])
        #expect(!r.suppress)
        #expect(!m.isOpen)

        var again = opened(nav: false)
        let enter = again.handle(key(36))
        #expect(enter.outputs == [.cancel] && !enter.suppress)

        var esc = opened(nav: false)
        let e = esc.handle(key(53))
        #expect(e.outputs == [.cancel] && e.suppress)
    }

    @Test func withNavigationOffAHotkeyIsNotRunFromAnOpenRing() {
        var m = opened(nav: false)
        let r = m.handle(key(43, chordMods))
        #expect(r.outputs == [.cancel])
        #expect(!r.suppress)
    }

    @Test func withNavigationOffClosedRingHotkeysStillWork() {
        var m = machine(nav: false)
        let r = m.handle(key(6, co))
        #expect(r.outputs == [.command(.undo)] && r.suppress)
    }
}
