import Foundation
import TesseraCore

/// AppleScript commands from `Tessera.sdef` (M2 spec §5). Each one builds a `Command`, runs it through
/// `CommandBridge`, and resumes the suspended script with the result.
class TesseraScriptCommand: NSScriptCommand {
    struct InvalidInput: Error { let message: String }

    /// Subclasses build the command from their arguments.
    func makeCommand() throws(InvalidInput) -> Command { throw InvalidInput(message: "Not implemented.") }

    /// What the script receives on success. Default: nothing.
    func scriptValue(for result: CommandResult) -> Any? { nil }

    override func performDefaultImplementation() -> Any? {
        let command: Command
        do {
            command = try makeCommand()
        } catch {
            scriptErrorNumber = -50 // paramErr
            scriptErrorString = error.message
            return nil
        }
        suspendExecution()
        // Cocoa scripting runs on the main thread; the script engine stays suspended until we resume.
        nonisolated(unsafe) let scriptCommand = self
        Task { @MainActor in
            let result = await CommandBridge.execute(command)
            if result.ok {
                scriptCommand.resumeExecution(withResult: scriptCommand.scriptValue(for: result))
            } else {
                scriptCommand.scriptErrorNumber = -10000 // errAEEventFailed
                scriptCommand.scriptErrorString = result.message ?? "Tessera couldn't do that."
                scriptCommand.resumeExecution(withResult: nil)
            }
        }
        return nil
    }

    // MARK: Argument helpers

    func text(_ value: Any?) -> String? {
        switch value {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    func requiredText(_ value: Any?, _ what: String) throws(InvalidInput) -> String {
        guard let s = text(value)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else {
            throw InvalidInput(message: "Missing \(what).")
        }
        return s
    }

    /// Reuses the CLI grammar so AppleScript accepts exactly the same columns/display syntax.
    func parse(_ arguments: [String]) throws(InvalidInput) -> Command {
        do {
            return try CommandParser.parse(arguments: arguments)
        } catch let CommandParseError.invalid(message) {
            throw InvalidInput(message: message)
        } catch {
            throw InvalidInput(message: error.localizedDescription)
        }
    }
}

/// `apply columns "2-4" band top display "cursor"`
@objc(TesseraApplyCommand)
final class ApplyScriptCommand: TesseraScriptCommand {
    private static let bands: [FourCharCode: String] = [fourCC("BFul"): "full", fourCC("BTop"): "top", fourCC("BBot"): "bottom"]

    override func makeCommand() throws(InvalidInput) -> Command {
        var args = ["apply", "--cols", try requiredText(directParameter, "columns")]
        if let code = (evaluatedArguments?["band"] as? NSNumber)?.uint32Value {
            guard let band = Self.bands[code] else { throw InvalidInput(message: "Band must be full, top or bottom.") }
            args += ["--band", band]
        }
        if let display = text(evaluatedArguments?["display"]) { args += ["--display", display] }
        return try parse(args)
    }
}

/// `perform action "leftHalf"`
@objc(TesseraPerformActionCommand)
final class PerformActionScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command {
        let name = try requiredText(directParameter, "action name")
        guard let action = WindowAction(rawValue: name) else {
            let known = WindowAction.allCases.map(\.rawValue).joined(separator: ", ")
            throw InvalidInput(message: "Unknown action \"\(name)\". Known actions: \(known).")
        }
        return .apply(.action(action), display: .current)
    }
}

/// `run cycle "left"`
@objc(TesseraRunCycleCommand)
final class RunCycleScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command {
        .cycle(name: try requiredText(directParameter, "cycle name"))
    }
}

/// `set columns 6 display "2"`
@objc(TesseraSetColumnsCommand)
final class SetColumnsScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command {
        var args = ["columns", "--set", try requiredText(directParameter, "column count")]
        if let display = text(evaluatedArguments?["display"]) { args += ["--display", display] }
        return try parse(args)
    }
}

/// `change columns by -1`
@objc(TesseraChangeColumnsCommand)
final class ChangeColumnsScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command {
        guard let delta = (evaluatedArguments?["delta"] as? NSNumber)?.intValue else {
            throw InvalidInput(message: "Missing \"by\" amount, e.g. change columns by -1.")
        }
        return .columns(.delta(delta), display: .current)
    }
}

/// `move to display "next"`
@objc(TesseraMoveToDisplayCommand)
final class MoveToDisplayScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command {
        try parse(["move", try requiredText(directParameter, "display (next, previous or a number)")])
    }
}

/// `undo move`
@objc(TesseraUndoMoveCommand)
final class UndoMoveScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command { .undo }
}

/// `open settings`
@objc(TesseraOpenSettingsCommand)
final class OpenSettingsScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command { .openSettings }
}

/// `list displays` → list of `display info` records.
@objc(TesseraListDisplaysCommand)
final class ListDisplaysScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command { .listDisplays }

    override func scriptValue(for result: CommandResult) -> Any? {
        (result.displays ?? []).map { d -> NSDictionary in
            let record: NSMutableDictionary = [
                "index": d.index, "displayID": d.id, "frame": frameList(d.frame),
                "columnCount": d.columns, "minimumColumns": d.minColumns, "maximumColumns": d.maxColumns,
            ]
            if let name = d.name { record["name"] = name }
            return record
        } as NSArray
    }
}

/// `describe window` → a `window info` record.
@objc(TesseraDescribeWindowCommand)
final class DescribeWindowScriptCommand: TesseraScriptCommand {
    override func makeCommand() throws(InvalidInput) -> Command { .describeWindow }

    override func scriptValue(for result: CommandResult) -> Any? {
        guard let w = result.window else { return nil }
        let record: NSMutableDictionary = ["frame": frameList(w.frame)]
        if let app = w.app { record["applicationName"] = app }
        if let bundleID = w.bundleID { record["bundleIdentifier"] = bundleID }
        if let index = w.displayIndex { record["displayIndex"] = index }
        return record
    }
}

/// `{x, y, width, height}` in points.
private func frameList(_ r: CGRect) -> [Double] {
    [r.origin.x, r.origin.y, r.width, r.height].map(Double.init)
}

private func fourCC(_ s: StaticString) -> FourCharCode {
    s.withUTF8Buffer { $0.reduce(0) { ($0 << 8) | FourCharCode($1) } }
}
