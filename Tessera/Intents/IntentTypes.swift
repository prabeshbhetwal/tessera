import AppIntents
import TesseraCore

/// Runs a command for an intent and turns a failed result into a thrown, user-readable error.
enum IntentRunner {
    @MainActor
    static func run(_ command: Command) async throws -> CommandResult {
        let result = await CommandBridge.execute(command)
        guard result.ok else { throw TesseraIntentError(message: result.message ?? "Tessera couldn't do that.") }
        return result
    }
}

struct TesseraIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

/// `WindowAction` for Shortcuts. Display strings are literals because App Intents metadata is extracted at build time.
enum WindowActionAppEnum: String, AppEnum {
    case maximize, center, leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Window Action"
    static let caseDisplayRepresentations: [WindowActionAppEnum: DisplayRepresentation] = [
        .maximize: "maximize",
        .center: "center",
        .leftHalf: "left half",
        .rightHalf: "right half",
        .topHalf: "top half",
        .bottomHalf: "bottom half",
        .topLeftQuarter: "top-left quarter",
        .topRightQuarter: "top-right quarter",
        .bottomLeftQuarter: "bottom-left quarter",
        .bottomRightQuarter: "bottom-right quarter",
    ]

    var action: WindowAction { WindowAction(rawValue: rawValue) ?? .maximize }
}

enum BandAppEnum: String, AppEnum {
    case full, top, bottom

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Band"
    static let caseDisplayRepresentations: [BandAppEnum: DisplayRepresentation] = [
        .full: "full height",
        .top: "top half",
        .bottom: "bottom half",
    ]

    var band: Band { Band(rawValue: rawValue) ?? .full }
}

enum DisplayDirectionAppEnum: String, AppEnum {
    case next, previous

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [DisplayDirectionAppEnum: DisplayRepresentation] = [
        .next: "next",
        .previous: "previous",
    ]
}

/// A connected display, so Shortcuts can pick one.
struct DisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static let defaultQuery = DisplayQuery()

    /// `DisplayID.storageKey`.
    let id: String
    let name: String
    /// 1-based, left to right.
    let index: Int
    let columns: Int

    init(_ info: DisplayInfo) {
        id = info.id
        name = info.name ?? "Display \(info.index)"
        index = info.index
        columns = info.columns
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Display \(index), \(columns) columns")
    }
}

/// Backed by the `listDisplays` command, so it always reflects what the app sees right now.
struct DisplayQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DisplayEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DisplayEntity] {
        try await all()
    }

    private func all() async throws -> [DisplayEntity] {
        try await IntentRunner.run(.listDisplays).displays?.map(DisplayEntity.init) ?? []
    }
}

extension Optional where Wrapped == DisplayEntity {
    /// No display picked means the display of the front window.
    var selector: DisplaySelector { map { .id($0.id) } ?? .current }
}
