import Foundation
import OSLog
import TesseraCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a search written as a sentence ("stop the windows touching each other") with Apple's on-device
/// model and names the settings it means. Runs only on Macs with Apple Intelligence on; nothing leaves the
/// Mac. Elsewhere it does nothing and the local `SettingsSearch` results stand alone.
enum SettingsAssistant {
    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "settings-search")

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Worth asking when the search reads like a sentence, or when local matching found nothing.
    static func shouldAsk(_ query: String, localResults: Int) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).count
        return words >= 3 || (localResults == 0 && query.count >= 4)
    }

    /// Up to three catalog entries, best first; empty when the model is unavailable, unsure or fails.
    static func suggest(for query: String) async -> [SettingsEntry] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let byID = Dictionary(SettingsCatalog.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let session = LanguageModelSession(instructions: instructions)
            do {
                let reply = try await session.respond(to: "Search: \(query)", generating: SettingPicks.self)
                // The model can only point at real settings: anything not in the catalog is dropped.
                return Array(reply.content.ids.compactMap { byID[$0] }.prefix(3))
            } catch is CancellationError {
                return []
            } catch {
                log.error("On-device settings search failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        #endif
        return []
    }

    private static let instructions: String = {
        // Short lines keep the list well inside the model's context: the id already names the pane.
        let lines = SettingsCatalog.entries.map { e in e.id.hasSuffix("/\(e.title)") ? e.id : "\(e.id) | \(e.title)" }
        return """
        You help people find a setting in Tessera, a macOS window tiling app. Windows snap into columns on each \
        display; a ring appears while the trigger keys are held. Read the search, work out which setting the \
        person wants to change, and answer with the ids of the best matches from this list, best first, at most \
        three. Use only ids from the list, copied exactly. If nothing fits, answer with no ids.

        \(lines.joined(separator: "\n"))
        """
    }()
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct SettingPicks {
    @Guide(description: "Ids of the matching settings, best first, at most three, copied exactly from the list")
    var ids: [String]
}
#endif
