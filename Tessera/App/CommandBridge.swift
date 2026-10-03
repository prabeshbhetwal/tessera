import TesseraCore

/// Runs a `Command` and returns its result. Implemented by `CommandExecutor` (M2 Track I).
@MainActor
protocol CommandExecuting: AnyObject {
    func execute(_ command: Command) async -> CommandResult
}

/// Single entry point every automation surface uses (hotkeys, URL, CLI socket, AppleScript, App Intents).
@MainActor
enum CommandBridge {
    static var executor: (any CommandExecuting)?

    static func execute(_ command: Command) async -> CommandResult {
        guard let executor else { return .failure("Tessera is still starting up.") }
        return await executor.execute(command)
    }
}
