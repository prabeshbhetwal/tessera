import TesseraCore

/// Runs a `Command` and returns its result. Implemented by `CommandExecutor` (M2 Track I).
@MainActor
protocol CommandExecuting: AnyObject {
    func execute(_ command: Command, source: CommandSource) async -> CommandResult
}

/// Single entry point every automation surface uses (hotkeys, URL, CLI socket, AppleScript, App Intents).
@MainActor
enum CommandBridge {
    static var executor: (any CommandExecuting)?

    static func execute(_ command: Command, source: CommandSource = .automation) async -> CommandResult {
        let deadline = ContinuousClock.now + .seconds(3)
        while executor == nil, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return .failure("Command cancelled while Tessera was starting up.") }
        }
        guard let executor else { return .failure("Tessera is still starting up.") }
        return await executor.execute(command, source: source)
    }
}
