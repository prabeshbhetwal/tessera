import TesseraCore

extension SettingsModel {
    /// Keeps name-based shortcuts valid during a rename; removed cycles remain visible as disabled bindings.
    func updateCycles(_ cycles: [Cycle]) {
        var next = settings
        var renames: [String: String] = [:]
        if cycles.count == settings.cycles.count {
            for (old, new) in zip(settings.cycles, cycles) where old.name != new.name
                && old.steps == new.steps && old.display == new.display {
                renames[old.name] = new.name
            }
        }
        next.cycles = cycles
        let names = Set(cycles.map(\.name))
        for index in next.hotkeys.indices {
            guard case let .cycle(name) = next.hotkeys[index].command else { continue }
            let resolvedName = renames[name] ?? name
            next.hotkeys[index].command = .cycle(name: resolvedName)
            if !names.contains(resolvedName) { next.hotkeys[index].enabled = false }
        }
        settings = next
    }
}
