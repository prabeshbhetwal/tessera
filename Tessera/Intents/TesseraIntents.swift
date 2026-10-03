import AppIntents
import TesseraCore

// One intent per command (M2 spec §5). All run in-process through `CommandBridge`.

struct ApplyColumnsIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Columns"
    static let description = IntentDescription("Moves the front window to a span of grid columns. Negative numbers count from the right: -1 is the last column.")
    static let openAppWhenRun = false

    @Parameter(title: "From column", default: 1) var from: Int
    @Parameter(title: "To column", default: 1) var to: Int
    @Parameter(title: "Band", default: .full) var band: BandAppEnum
    @Parameter(title: "Display") var display: DisplayEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Move the front window to columns \(\.$from) to \(\.$to)") {
            \.$band
            \.$display
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard from != 0, to != 0 else { throw TesseraIntentError(message: "Columns start at 1, or -1 for the last column. 0 isn't a column.") }
        guard (from > 0) == (to > 0) else {
            throw TesseraIntentError(message: "Use two positive column numbers, or two negative ones counting from the right.")
        }
        let command = Command.apply(.span(columns: min(from, to)...max(from, to), band: band.band), display: display.selector)
        let result = try await IntentRunner.run(command)
        return .result(dialog: "\(result.message ?? command.summary)")
    }
}

struct PerformActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Perform Action"
    static let description = IntentDescription("Snaps the front window to a half, quarter, the centre or the full screen.")
    static let openAppWhenRun = false

    @Parameter(title: "Action", default: .maximize) var action: WindowActionAppEnum
    @Parameter(title: "Display") var display: DisplayEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) the front window") { \.$display }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let command = Command.apply(.action(action.action), display: display.selector)
        let result = try await IntentRunner.run(command)
        return .result(dialog: "\(result.message ?? command.summary)")
    }
}

struct RunCycleIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Cycle"
    static let description = IntentDescription("Runs the next step of a named cycle, such as left or right.")
    static let openAppWhenRun = false

    @Parameter(title: "Cycle", default: "left") var name: String

    static var parameterSummary: some ParameterSummary { Summary("Run the \(\.$name) cycle") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let command = Command.cycle(name: name)
        let result = try await IntentRunner.run(command)
        return .result(dialog: "\(result.message ?? command.summary)")
    }
}

struct SetColumnsIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Columns"
    static let description = IntentDescription("Sets a display's column count. It's kept within what the display fits.")
    static let openAppWhenRun = false

    @Parameter(title: "Columns", default: 4, inclusiveRange: (1, 16)) var count: Int
    @Parameter(title: "Display") var display: DisplayEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$count) columns") { \.$display }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let command = Command.columns(.set(count), display: display.selector)
        let result = try await IntentRunner.run(command)
        return .result(dialog: "\(result.message ?? command.summary)")
    }
}

struct ChangeColumnsIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Columns"
    static let description = IntentDescription("Adds or removes columns on a display. Use a negative number to remove.")
    static let openAppWhenRun = false

    @Parameter(title: "By", default: 1, inclusiveRange: (-8, 8)) var delta: Int
    @Parameter(title: "Display") var display: DisplayEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Change columns by \(\.$delta)") { \.$display }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let command = Command.columns(.delta(delta), display: display.selector)
        let result = try await IntentRunner.run(command)
        return .result(dialog: "\(result.message ?? command.summary)")
    }
}

struct MoveToDisplayIntent: AppIntent {
    static let title: LocalizedStringResource = "Move to Display"
    static let description = IntentDescription("Moves the front window to another display, keeping its columns and band. Pick a display to go straight to it.")
    static let openAppWhenRun = false

    @Parameter(title: "Direction", default: .next) var direction: DisplayDirectionAppEnum
    @Parameter(title: "Display") var display: DisplayEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Move the front window to the \(\.$direction) display") { \.$display }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let step: DisplayStep = if let display { .index(display.index) } else { direction == .next ? .next : .previous }
        let command = Command.moveToDisplay(step)
        let result = try await IntentRunner.run(command)
        return .result(dialog: "\(result.message ?? command.summary)")
    }
}

struct UndoIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Move"
    static let description = IntentDescription("Puts the last window Tessera moved back where it was.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await IntentRunner.run(.undo)
        return .result(dialog: "\(result.message ?? "Undone.")")
    }
}

struct ListDisplaysIntent: AppIntent {
    static let title: LocalizedStringResource = "List Displays"
    static let description = IntentDescription("Returns the connected displays, left to right.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[DisplayEntity]> & ProvidesDialog {
        let displays = try await IntentRunner.run(.listDisplays).displays?.map(DisplayEntity.init) ?? []
        let text = displays.map { "\($0.index). \($0.name), \($0.columns) columns" }.joined(separator: "\n")
        return .result(value: displays, dialog: "\(displays.isEmpty ? "No displays found." : text)")
    }
}

struct DescribeWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Describe Window"
    static let description = IntentDescription("Returns the front window's app and frame.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let window = try await IntentRunner.run(.describeWindow).window else {
            throw TesseraIntentError(message: "There's no front window.")
        }
        let f = window.frame
        let display = window.displayIndex.map { " on display \($0)" } ?? ""
        let text = "\(window.app ?? "Unknown app"): \(Int(f.width))×\(Int(f.height)) at \(Int(f.minX)), \(Int(f.minY))\(display)"
        return .result(value: text, dialog: "\(text)")
    }
}

struct OpenSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Settings"
    static let description = IntentDescription("Opens Tessera's Settings window.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await IntentRunner.run(.openSettings)
        return .result()
    }
}

/// Spotlight and Siri phrases. Only enum and entity parameters may appear in phrases.
struct TesseraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PerformActionIntent(),
            phrases: ["\(.applicationName) \(\.$action)", "\(\.$action) with \(.applicationName)"],
            shortTitle: "Snap Window",
            systemImageName: "rectangle.split.2x1"
        )
        AppShortcut(
            intent: MoveToDisplayIntent(),
            phrases: ["\(.applicationName) \(\.$direction) display", "Move window to \(\.$direction) display with \(.applicationName)"],
            shortTitle: "Move to Display",
            systemImageName: "display.2"
        )
        AppShortcut(
            intent: RunCycleIntent(),
            phrases: ["Run \(.applicationName) cycle"],
            shortTitle: "Run Cycle",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: UndoIntent(),
            phrases: ["\(.applicationName) undo", "Undo \(.applicationName) move"],
            shortTitle: "Undo Move",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: ListDisplaysIntent(),
            phrases: ["List \(.applicationName) displays"],
            shortTitle: "List Displays",
            systemImageName: "display"
        )
        AppShortcut(
            intent: DescribeWindowIntent(),
            phrases: ["Describe window with \(.applicationName)"],
            shortTitle: "Describe Window",
            systemImageName: "macwindow"
        )
        AppShortcut(
            intent: OpenSettingsIntent(),
            phrases: ["Open \(.applicationName) settings"],
            shortTitle: "Open Settings",
            systemImageName: "gearshape"
        )
    }
}
