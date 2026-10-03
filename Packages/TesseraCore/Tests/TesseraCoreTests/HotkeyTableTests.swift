import Testing

@testable import TesseraCore

private let leftArrow: UInt16 = 123
private let co: Modifiers = [.control, .option]

private func binding(_ id: String, _ key: UInt16, _ mods: Modifiers, _ command: Command = .undo,
                     enabled: Bool = true) -> HotkeyBinding {
    HotkeyBinding(id: id, hotkey: Hotkey(keyCode: key, modifiers: mods), command: command, enabled: enabled)
}

@Suite struct HotkeyTableTests {
    @Test func matchesExactModifiers() {
        let t = HotkeyTable([binding("cycle-left", leftArrow, co, .cycle(name: "left"))])
        #expect(t.match(keyCode: leftArrow, modifiers: co) == .cycle(name: "left"))
    }

    // Review Focus 3
    @Test func extraModifierDoesNotMatch() {
        let t = HotkeyTable([binding("cycle-left", leftArrow, co, .cycle(name: "left"))])
        #expect(t.match(keyCode: leftArrow, modifiers: [.control, .option, .shift]) == nil)
        #expect(t.match(keyCode: leftArrow, modifiers: [.control, .option, .command]) == nil)
        #expect(t.match(keyCode: leftArrow, modifiers: [.control, .option, .function]) == nil)
    }

    @Test func missingModifierDoesNotMatch() {
        let t = HotkeyTable([binding("cycle-left", leftArrow, co, .cycle(name: "left"))])
        #expect(t.match(keyCode: leftArrow, modifiers: [.control]) == nil)
        #expect(t.match(keyCode: leftArrow, modifiers: []) == nil)
    }

    @Test func wrongKeyDoesNotMatch() {
        let t = HotkeyTable([binding("cycle-left", leftArrow, co)])
        #expect(t.match(keyCode: 124, modifiers: co) == nil)
    }

    @Test func shiftedBindingIsIndependentOfUnshifted() {
        let t = HotkeyTable([
            binding("plain", leftArrow, co, .undo),
            binding("shifted", leftArrow, co.union(.shift), .openSettings),
        ])
        #expect(t.match(keyCode: leftArrow, modifiers: co) == .undo)
        #expect(t.match(keyCode: leftArrow, modifiers: co.union(.shift)) == .openSettings)
    }

    @Test func disabledBindingsNeverMatch() {
        let t = HotkeyTable([binding("off", leftArrow, co, .undo, enabled: false)])
        #expect(t.match(keyCode: leftArrow, modifiers: co) == nil)
    }

    @Test func duplicateHotkeyFirstEnabledWins() {
        let t = HotkeyTable([
            binding("disabled", 6, co, .openSettings, enabled: false),
            binding("first", 6, co, .undo),
            binding("second", 6, co, .listDisplays),
        ])
        #expect(t.match(keyCode: 6, modifiers: co) == .undo)
    }

    @Test func defaultsAllMatchTheirOwnHotkey() {
        let t = HotkeyTable(HotkeyBinding.defaults)
        for b in HotkeyBinding.defaults {
            #expect(t.match(keyCode: b.hotkey.keyCode, modifiers: b.hotkey.modifiers) == b.command, "\(b.id)")
        }
    }

    @Test func defaultsDoNotMatchWithAnExtraModifier() {
        let t = HotkeyTable(HotkeyBinding.defaults)
        for b in HotkeyBinding.defaults {
            #expect(t.match(keyCode: b.hotkey.keyCode, modifiers: b.hotkey.modifiers.union(.shift)) == nil, "\(b.id)")
        }
    }

    @Test func emptyTableMatchesNothing() {
        #expect(HotkeyTable([]).match(keyCode: 0, modifiers: []) == nil)
    }

    // MARK: Conflicts

    private let chord = TriggerChord.default  // ⌃⌥⌘ (left)

    @Test func defaultsHaveNoConflicts() {
        #expect(HotkeyTable.conflicts(HotkeyBinding.defaults, chord: chord, systemHotkeys: []) == [:])
    }

    @Test func duplicatesAreFlaggedOnBothBindings() {
        let list = [binding("a", 6, co), binding("b", 6, co), binding("c", 7, co)]
        let c = HotkeyTable.conflicts(list, chord: chord, systemHotkeys: [])
        #expect(Set(c.keys) == ["a", "b"])
        #expect(c["a"]?.contains("b") == true)
        #expect(c["b"]?.contains("a") == true)
    }

    @Test func disabledBindingsAreNotConflicts() {
        let list = [binding("a", 6, co), binding("b", 6, co, enabled: false)]
        #expect(HotkeyTable.conflicts(list, chord: chord, systemHotkeys: []) == [:])
    }

    @Test func systemHotkeyMatchIsFlagged() {
        let sys = Hotkey(keyCode: 123, modifiers: [.control])  // Mission Control: ⌃←
        let list = [binding("mine", 123, [.control]), binding("other", 123, co)]
        let c = HotkeyTable.conflicts(list, chord: chord, systemHotkeys: [sys])
        #expect(Set(c.keys) == ["mine"])
        #expect(c["mine"]?.localizedCaseInsensitiveContains("system") == true)
    }

    @Test func disabledBindingMatchingSystemHotkeyIsNotFlagged() {
        let sys = Hotkey(keyCode: 123, modifiers: [.control])
        let list = [binding("mine", 123, [.control], enabled: false)]
        #expect(HotkeyTable.conflicts(list, chord: chord, systemHotkeys: [sys]) == [:])
    }

    @Test func chordWithNoKeyIsFlagged() {
        // A "hotkey" that is just the chord (a modifier keycode with the chord's modifiers) can never
        // fire as a key press and collides with the trigger itself.
        let list = [binding("clash", 55, [.control, .option, .command]), binding("fine", 43, co)]
        let c = HotkeyTable.conflicts(list, chord: chord, systemHotkeys: [])
        #expect(Set(c.keys) == ["clash"])
        #expect(c["clash"]?.localizedCaseInsensitiveContains("chord") == true)
    }

    @Test func realKeyWithTheChordsModifiersIsNotAConflict() {
        // ⌃⌥⌘, is a default: it fires through the ring-open path on purpose.
        let list = [binding("open-settings", 43, [.control, .option, .command])]
        #expect(HotkeyTable.conflicts(list, chord: chord, systemHotkeys: []) == [:])
    }

    @Test func oneBindingCanCarryAllMessages() {
        let all: Modifiers = [.control, .option, .command]
        let sys = Hotkey(keyCode: 55, modifiers: all)
        let list = [binding("a", 55, all), binding("b", 55, all)]
        let c = HotkeyTable.conflicts(list, chord: chord, systemHotkeys: [sys])
        #expect(Set(c.keys) == ["a", "b"])
        let message = c["a"] ?? ""
        #expect(message.contains("b") && message.localizedCaseInsensitiveContains("system")
            && message.localizedCaseInsensitiveContains("chord"))
    }
}
