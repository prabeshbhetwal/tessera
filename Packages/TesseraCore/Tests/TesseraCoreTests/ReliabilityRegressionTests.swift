import CoreGraphics
import Testing
@testable import TesseraCore

@Suite struct ReliabilityRegressionTests {
    @Test func columnCapWinsOverMinimumWidth() {
        var constants = SizingConstants()
        constants.maxColumns = 1
        let range = SizingRule.range(for: CGSize(width: 3840, height: 1080), constants: constants)
        #expect(range.minCols == 1)
        #expect(range.maxCols == 1)
        #expect(range.defaultCols == 1)
    }

    @Test func importedTinyWidthsCannotCreateThousandsOfColumns() {
        var constants = SizingConstants()
        constants.minColumnWidth = 0.001
        constants.idealColumnWidth = 0.001
        constants.maxColumnWidth = 0.001
        let range = SizingRule.range(for: CGSize(width: 3840, height: 1080), constants: constants)
        #expect(range.maxCols == 8)
        #expect(range.minCols <= 8)
    }

    @Test func openingRingDuringDragPreservesTheRelease() {
        var machine = TriggerMachine(chord: TriggerChord(keyCodes: [59]))
        #expect(!machine.handle(.leftMouseDown(.zero)).suppress)
        _ = machine.handle(.flagsChanged(pressedModifiers: [59], location: .zero))
        #expect(!machine.handle(.leftMouseUp(.zero)).suppress)
    }

    @Test func importRejectsBareTypingShortcut() {
        var settings = TesseraSettings.defaults
        settings.hotkeys = [HotkeyBinding(id: "typing", hotkey: Hotkey(keyCode: 0, modifiers: []), command: .undo)]
        #expect(throws: SettingsError.self) { try SettingsValidation.validate(settings) }
    }

    @Test func importRejectsLetterTrigger() {
        var settings = TesseraSettings.defaults
        settings.trigger = TriggerChord(keyCodes: [0])
        #expect(throws: SettingsError.self) { try SettingsValidation.validate(settings) }
    }

    @Test func importRejectsDuplicateCycleNames() {
        var settings = TesseraSettings.defaults
        settings.cycles = [Cycle(name: "work", steps: [.action(.leftHalf)]), Cycle(name: "work", steps: [.action(.rightHalf)])]
        #expect(throws: SettingsError.self) { try SettingsValidation.validate(settings) }
    }

    @Test func ringNavigationCollisionIsExplained() {
        let binding = HotkeyBinding(id: "shadow", hotkey: Hotkey(keyCode: 123, modifiers: [.control, .option, .command]), command: .undo)
        #expect(HotkeyTable.conflicts([binding], chord: TriggerChord(keyCodes: [59,58,55]), systemHotkeys: []) ["shadow"] != nil)
    }
    @Test func portraitFeedbackUsesRowsWithoutHeightBands() {
        let id = DisplayID(vendor: 1, model: 1, serial: 1, uuid: nil)
        let feedback = RingFeedback.make(selection: .span(display: id, span: ColumnSpan(columns: 0...1, band: .top)),
                                         ring: .default, keyboard: true, keyboardEnabled: true,
                                         tapToTile: false, cancelling: false, portrait: true)
        #expect(feedback.title == "Rows 1–2")
    }

}
