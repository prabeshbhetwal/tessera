import CoreGraphics
import Testing

@testable import TesseraCore

private let ctrl: UInt16 = 59
private let opt: UInt16 = 58
private let cmd: UInt16 = 55
private let shift: UInt16 = 56
private let chord: Set<UInt16> = [ctrl, opt, cmd]
private let here = CGPoint(x: 100, y: 200)

private func flags(_ keys: Set<UInt16>, at p: CGPoint = here) -> InputEvent {
    .flagsChanged(pressedModifiers: keys, location: p)
}

private func newMachine() -> TriggerMachine { TriggerMachine(chord: TriggerChord.default) }

/// Press all three chord keys; returns the machine in the open state.
private func opened() -> TriggerMachine {
    var m = newMachine()
    _ = m.handle(flags([ctrl]))
    _ = m.handle(flags([ctrl, opt]))
    _ = m.handle(flags(chord))
    return m
}

@Suite struct TriggerMachineTests {
    // Review Focus 2
    @Test(arguments: [
        [ctrl, opt, cmd], [ctrl, cmd, opt], [opt, ctrl, cmd],
        [opt, cmd, ctrl], [cmd, ctrl, opt], [cmd, opt, ctrl],
    ])
    func testOpensOnlyWhenFullChord(order: [UInt16]) {
        var m = newMachine()
        var held: Set<UInt16> = []
        var opens = 0
        for key in order {
            held.insert(key)
            let r = m.handle(flags(held))
            #expect(!r.suppress)
            opens += r.outputs.filter { $0 == .open(origin: here) }.count
            #expect(r.outputs.count <= 1)
        }
        #expect(opens == 1)
        #expect(m.isOpen)
        // Re-sending the same full-chord state does not reopen.
        #expect(m.handle(flags(chord)).outputs.isEmpty)
    }

    @Test func testOpenCarriesOriginAndPartialDoesNotOpen() {
        var m = newMachine()
        #expect(m.handle(flags([ctrl, opt])).outputs.isEmpty)
        #expect(!m.isOpen)
        let r = m.handle(flags(chord, at: CGPoint(x: 7, y: 9)))
        #expect(r.outputs == [.open(origin: CGPoint(x: 7, y: 9))])
        #expect(m.isOpen)
    }

    // Review Focus 2
    @Test(arguments: [ctrl, opt, cmd])
    func testPartialReleaseApplies(released: UInt16) {
        var m = opened()
        let r = m.handle(flags(chord.subtracting([released])))
        #expect(r.outputs == [.apply])
        #expect(!r.suppress)
        #expect(!m.isOpen)
        // Releasing the rest produces nothing further.
        #expect(m.handle(flags([])).outputs.isEmpty)
    }

    @Test func testReleaseAllAtOnceAppliesOnce() {
        var m = opened()
        #expect(m.handle(flags([])).outputs == [.apply])
        #expect(m.handle(flags([])).outputs.isEmpty)
    }

    // Review Focus 2
    @Test func testNoReopenUntilAllReleased() {
        var m = opened()
        #expect(m.handle(flags([ctrl, opt])).outputs == [.apply])
        // Command pressed again while Control and Option are still held: must not reopen.
        #expect(m.handle(flags(chord)).outputs.isEmpty)
        #expect(!m.isOpen)
        // Same for any partial release/re-press cycle.
        #expect(m.handle(flags([ctrl])).outputs.isEmpty)
        #expect(m.handle(flags(chord)).outputs.isEmpty)
        // Release everything, then the full chord opens again.
        #expect(m.handle(flags([])).outputs.isEmpty)
        #expect(m.handle(flags(chord)).outputs == [.open(origin: here)])
        #expect(m.isOpen)
    }

    @Test func testNoReopenAfterEscUntilAllReleased() {
        var m = opened()
        #expect(m.handle(.keyDown(keyCode: 53, modifiers: [], location: here)).outputs == [.cancel])
        #expect(!m.isOpen)
        #expect(m.handle(flags(chord)).outputs.isEmpty)
        // Releasing the chord after a cancel must not apply.
        #expect(m.handle(flags([])).outputs.isEmpty)
        #expect(m.handle(flags(chord)).outputs == [.open(origin: here)])
    }

    @Test func testEscCancelsSuppressed() {
        var m = opened()
        let r = m.handle(.keyDown(keyCode: 53, modifiers: [], location: here))
        #expect(r.outputs == [.cancel])
        #expect(r.suppress)
        #expect(!m.isOpen)
    }

    @Test func testOtherKeyPassesThrough() {
        var m = opened()
        let r = m.handle(.keyDown(keyCode: 0, modifiers: [], location: here))
        #expect(r.outputs == [.cancel])
        #expect(!r.suppress)
        #expect(!m.isOpen)
    }

    @Test func testClickAnchorsSuppressed() {
        var m = opened()
        let p = CGPoint(x: 3, y: 4)
        let r = m.handle(.leftMouseDown(p))
        #expect(r.outputs == [.anchor(p)])
        #expect(r.suppress)
        #expect(m.isOpen)
    }

    @Test func testMouseMoveForwardedNotSuppressed() {
        var m = opened()
        let p = CGPoint(x: 5, y: 6)
        let r = m.handle(.mouseMoved(p))
        #expect(r.outputs == [.move(p)])
        #expect(!r.suppress)
    }

    @Test func testScrollSteps() {
        let notch = TriggerMachine.scrollStepPoints
        var m = opened()
        let up = m.handle(.scroll(deltaY: notch))
        let down = m.handle(.scroll(deltaY: -notch))
        let zero = m.handle(.scroll(deltaY: 0))
        #expect(up.outputs == [.step(1)] && up.suppress)
        #expect(down.outputs == [.step(-1)] && down.suppress)
        #expect(zero.outputs.isEmpty && zero.suppress)  // swallowed while open
        #expect(m.isOpen)
    }

    @Test func testTrackpadScrollAccumulates() {
        var m = opened()
        var steps: [TriggerOutput] = []
        for _ in 0..<12 { steps += m.handle(.scroll(deltaY: 10)).outputs }  // 120 pt of swipe
        #expect(steps == [.step(1), .step(1)])
    }

    @Test func testMouseUpAfterAnchorSwallowed() {
        var m = opened()
        _ = m.handle(.leftMouseDown(here))
        _ = m.handle(flags([]))  // ring applies before the button is released
        let up = m.handle(.leftMouseUp(here))
        #expect(up.suppress && up.outputs.isEmpty)
        #expect(!m.handle(.leftMouseUp(here)).suppress)  // only the paired one
    }

    @Test func testResetCancelsOpenRing() {
        var m = opened()
        #expect(m.reset() == [.cancel])
        #expect(!m.isOpen)
        #expect(m.reset().isEmpty)
        #expect(m.handle(flags(chord)).outputs == [.open(origin: here)])  // usable again
    }

    @Test func testExtraModifierStillOpens() {
        var m = newMachine()
        let r = m.handle(flags(chord.union([shift])))
        #expect(r.outputs == [.open(origin: here)])
        // Releasing only the extra modifier keeps the menu open.
        #expect(m.handle(flags(chord)).outputs.isEmpty)
        #expect(m.isOpen)
    }

    @Test func testClosedMachineIgnoresEverythingElse() {
        var m = newMachine()
        let events: [InputEvent] = [
            .keyDown(keyCode: 53, modifiers: [], location: here), .keyDown(keyCode: 0, modifiers: [], location: here),
            .mouseMoved(here), .leftMouseDown(here), .leftMouseUp(here), .scroll(deltaY: 5),
        ]
        for e in events {
            let r = m.handle(e)
            #expect(r == TriggerResult(outputs: [], suppress: false))
        }
        #expect(!m.isOpen)
    }

    @Test func testEmptyChordNeverOpens() {
        var m = TriggerMachine(chord: TriggerChord(keyCodes: []))
        #expect(m.handle(flags([ctrl, opt, cmd])).outputs.isEmpty)
        #expect(!m.isOpen)
    }

    @Test func testCustomChord() {
        var m = TriggerMachine(chord: TriggerChord(keyCodes: [59, 56]))
        #expect(m.handle(flags([59])).outputs.isEmpty)
        #expect(m.handle(flags([59, 56])).outputs == [.open(origin: here)])
        #expect(m.handle(flags([56])).outputs == [.apply])
    }
}
