// Appended to the unmodified production InputService.swift for access to its confined tap-session type.
private final class InputOutputs: Sendable {
    let values = OSAllocatedUnfairLock(initialState: [TriggerOutput]())
    func append(_ output: TriggerOutput) { values.withLock { $0.append(output) } }
}

@main private struct VerifyInputReliability {
    static func main() {
        let outputs = InputOutputs()
        let service = InputService(chord: TriggerChord(keyCodes: [59]), onOutput: outputs.append)
        let current = service.currentConfig()
        let tap = TapSession(service: service, config: current.config, generation: current.generation)
        service.setFrontmostExcluded(true)
        service.updateHotkeys([HotkeyBinding(id: "undo", hotkey: Hotkey(keyCode: 6, modifiers: [.control,.option]), command: .undo)], ringKeyNavigation: true)
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)!
        event.flags = [.maskControl,.maskAlternate]
        precondition(!tap.handle(.keyDown, event), "Rebuild bypassed the excluded-app policy")
        precondition(outputs.values.withLock { $0.isEmpty })
        print("PASS: Exclusion survives configuration rebuild")
        service.setFrontmostExcluded(false)
        let flags = CGEvent(source: nil)!
        flags.flags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 1)
        _ = tap.handle(.flagsChanged, flags)
        service.abortSession()
        let arrow = CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: true)!
        precondition(!tap.handle(.keyDown, arrow), "Aborted session still captures navigation")
        print("PASS: Aborted sessions release keyboard capture")
    }
}
