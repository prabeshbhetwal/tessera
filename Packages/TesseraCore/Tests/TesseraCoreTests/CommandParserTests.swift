import Foundation
import Testing
@testable import TesseraCore

@Suite struct CommandParserTests {
    static func url(_ s: String) throws -> Command {
        try CommandParser.parse(url: URL(string: s)!)   // test-only force unwrap of literal URLs
    }

    static func cli(_ s: String) throws -> Command {
        try CommandParser.parse(arguments: s.split(separator: " ").map(String.init))
    }

    /// Asserts the call throws `.invalid` and that the message names `part`.
    static func expectInvalid(_ part: String, sourceLocation: SourceLocation = #_sourceLocation,
                              _ body: () throws -> Command) {
        do {
            let c = try body()
            Issue.record("expected .invalid(\(part)), got \(c)", sourceLocation: sourceLocation)
        } catch let CommandParseError.invalid(message) {
            #expect(message.contains(part), "message \"\(message)\" should name \"\(part)\"", sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: URL, every spec example

    @Test func urlApply() throws {
        #expect(try Self.url("tessera://apply?cols=2-4&band=top&display=cursor")
            == .apply(.span(columns: 2...4, band: .top), display: .cursor))
    }

    @Test func tileCommand() throws {
        #expect(try Self.cli("tile") == .tileWindows(display: .current))
        #expect(try Self.cli("tile --display 2") == .tileWindows(display: .index(2)))
        #expect(try Self.url("tessera://tile?display=cursor") == .tileWindows(display: .cursor))
        Self.expectInvalid("unexpected argument") { try Self.cli("tile now") }
    }

    @Test func rememberCommand() throws {
        #expect(try Self.cli("remember") == .rememberSplit(display: .current))
        #expect(try Self.cli("remember --display 2") == .rememberSplit(display: .index(2)))
        #expect(try Self.url("tessera://remember?display=cursor") == .rememberSplit(display: .cursor))
        Self.expectInvalid("unexpected argument") { try Self.cli("remember now") }
    }

    @Test func urlApplyDefaults() throws {
        #expect(try Self.url("tessera://apply?cols=3") == .apply(.span(columns: 3...3, band: .full), display: .current))
    }

    @Test func urlColumnForms() throws {
        #expect(try Self.url("tessera://apply?cols=2..4") == .apply(.span(columns: 2...4, band: .full), display: .current))
        #expect(try Self.url("tessera://apply?cols=-1") == .apply(.span(columns: -1 ... -1, band: .full), display: .current))
        #expect(try Self.url("tessera://apply?cols=-2..-1") == .apply(.span(columns: -2 ... -1, band: .full), display: .current))
    }

    @Test func urlAction() throws {
        #expect(try Self.url("tessera://action/leftHalf") == .apply(.action(.leftHalf), display: .current))
        #expect(try Self.url("tessera://action/maximize?display=2") == .apply(.action(.maximize), display: .index(2)))
    }

    @Test func urlCycle() throws {
        #expect(try Self.url("tessera://cycle/left") == .cycle(name: "left"))
    }

    @Test func urlColumns() throws {
        #expect(try Self.url("tessera://columns?set=6&display=2") == .columns(.set(6), display: .index(2)))
        #expect(try Self.url("tessera://columns?delta=-1") == .columns(.delta(-1), display: .current))
    }

    @Test func urlMove() throws {
        #expect(try Self.url("tessera://move?display=next") == .moveToDisplay(.next))
        #expect(try Self.url("tessera://move?display=previous") == .moveToDisplay(.previous))
        #expect(try Self.url("tessera://move?display=3") == .moveToDisplay(.index(3)))
    }

    @Test func urlUndoAndSettings() throws {
        #expect(try Self.url("tessera://undo") == .undo)
        #expect(try Self.url("tessera://settings/open") == .openSettings)
    }

    @Test func urlDisplayById() throws {
        #expect(try Self.url("tessera://apply?cols=1&display=id:1-2-3") == .apply(.span(columns: 1...1, band: .full), display: .id("1-2-3")))
        // Percent-encoded colon decodes.
        #expect(try Self.url("tessera://apply?cols=1&display=id%3Auuid%3Aabc")
            == .apply(.span(columns: 1...1, band: .full), display: .id("uuid:abc")))
    }

    @Test func urlVerbAndSchemeAreCaseInsensitive() throws {
        #expect(try Self.url("TESSERA://UNDO") == .undo)
    }

    // MARK: URL errors (Review Focus 2)

    @Test func urlUnknownVerb() {
        Self.expectInvalid("frobnicate") { try Self.url("tessera://frobnicate") }
    }

    @Test func urlWrongScheme() {
        Self.expectInvalid("https") { try Self.url("https://apply?cols=1") }
    }

    @Test func urlMalformedColumns() {
        Self.expectInvalid("a-b") { try Self.url("tessera://apply?cols=a-b") }
        Self.expectInvalid("cols") { try Self.url("tessera://apply?band=top") }          // missing
        Self.expectInvalid("cols") { try Self.url("tessera://apply?cols=") }             // empty value
        Self.expectInvalid("4-2") { try Self.url("tessera://apply?cols=4-2") }           // reversed
        Self.expectInvalid("2..-1") { try Self.url("tessera://apply?cols=2..-1") }       // mixed sign
        Self.expectInvalid("x") { try Self.url("tessera://apply?cols=1..x") }
    }

    @Test func urlBadBand() {
        Self.expectInvalid("middle") { try Self.url("tessera://apply?cols=1&band=middle") }
    }

    @Test func urlBadDisplay() {
        Self.expectInvalid("0") { try Self.url("tessera://apply?cols=1&display=0") }
        Self.expectInvalid("sideways") { try Self.url("tessera://apply?cols=1&display=sideways") }
        Self.expectInvalid("id") { try Self.url("tessera://apply?cols=1&display=id:") }
        Self.expectInvalid("sideways") { try Self.url("tessera://move?display=sideways") }
    }

    @Test func urlUnknownParameterAndDuplicate() {
        Self.expectInvalid("foo") { try Self.url("tessera://apply?cols=1&foo=1") }
        Self.expectInvalid("cols") { try Self.url("tessera://apply?cols=1&cols=2") }
    }

    @Test func urlActionAndCycleErrors() {
        Self.expectInvalid("nope") { try Self.url("tessera://action/nope") }
        Self.expectInvalid("action") { try Self.url("tessera://action") }
        Self.expectInvalid("cycle") { try Self.url("tessera://cycle") }
    }

    @Test func urlColumnsNeedsExactlyOneChange() {
        Self.expectInvalid("set") { try Self.url("tessera://columns") }
        Self.expectInvalid("delta") { try Self.url("tessera://columns?set=3&delta=1") }
        Self.expectInvalid("abc") { try Self.url("tessera://columns?set=abc") }
    }

    @Test func urlCannotReadOrWriteFiles() {
        Self.expectInvalid("URL") { try Self.url("tessera://settings/export?path=/tmp/x.json") }
        Self.expectInvalid("URL") { try Self.url("tessera://settings/import?path=/tmp/x.json") }
        Self.expectInvalid("URL") { try Self.url("tessera://displays") }
    }

    // MARK: CLI, every spec example

    @Test func cliApply() throws {
        #expect(try Self.cli("apply --cols 2-4 --band top --display cursor")
            == .apply(.span(columns: 2...4, band: .top), display: .cursor))
        #expect(try Self.cli("apply --cols=2-4 --band=bottom") == .apply(.span(columns: 2...4, band: .bottom), display: .current))
    }

    @Test func cliNegativeValuesAreValuesNotFlags() throws {
        #expect(try Self.cli("apply --cols -2..-1") == .apply(.span(columns: -2 ... -1, band: .full), display: .current))
        #expect(try Self.cli("columns --delta -1") == .columns(.delta(-1), display: .current))
    }

    @Test func cliAction() throws {
        #expect(try Self.cli("action leftHalf") == .apply(.action(.leftHalf), display: .current))
        #expect(try Self.cli("action topLeftQuarter --display 2") == .apply(.action(.topLeftQuarter), display: .index(2)))
    }

    @Test func cliCycleColumnsMoveUndo() throws {
        #expect(try Self.cli("cycle left") == .cycle(name: "left"))
        #expect(try Self.cli("columns --set 6 --display 2") == .columns(.set(6), display: .index(2)))
        #expect(try Self.cli("move next") == .moveToDisplay(.next))
        #expect(try Self.cli("move 2") == .moveToDisplay(.index(2)))
        #expect(try Self.cli("undo") == .undo)
    }

    @Test func cliQueriesAcceptJsonFlag() throws {
        #expect(try Self.cli("displays") == .listDisplays)
        #expect(try Self.cli("displays --json") == .listDisplays)
        #expect(try Self.cli("window") == .describeWindow)
        #expect(try Self.cli("window --json") == .describeWindow)
        #expect(try Self.cli("--json displays") == .listDisplays)
    }

    @Test func cliSettings() throws {
        #expect(try Self.cli("settings open") == .openSettings)
        #expect(try Self.cli("settings export /tmp/out.json") == .exportSettings(path: "/tmp/out.json"))
        #expect(try Self.cli("settings import /tmp/in.json") == .importSettings(path: "/tmp/in.json"))
    }

    // MARK: CLI errors (Review Focus 2)

    @Test func cliUnknownVerbAndEmpty() {
        Self.expectInvalid("frobnicate") { try Self.cli("frobnicate") }
        Self.expectInvalid("no command") { try CommandParser.parse(arguments: []) }
    }

    @Test func cliMissingValue() {
        Self.expectInvalid("--cols") { try Self.cli("apply --cols") }
        Self.expectInvalid("--cols") { try Self.cli("apply --cols --band top") }
        Self.expectInvalid("--band") { try Self.cli("apply --cols 1 --band") }
    }

    @Test func cliMalformedValues() {
        Self.expectInvalid("a-b") { try Self.cli("apply --cols a-b") }
        Self.expectInvalid("middle") { try Self.cli("apply --cols 1 --band middle") }
        Self.expectInvalid("cols") { try Self.cli("apply --band top") }
    }

    @Test func cliUnknownOptionAndExtraArguments() {
        Self.expectInvalid("--wat") { try Self.cli("undo --wat") }
        Self.expectInvalid("extra") { try Self.cli("undo extra") }
        Self.expectInvalid("action") { try Self.cli("action") }
        Self.expectInvalid("path") { try Self.cli("settings export") }
        Self.expectInvalid("bogus") { try Self.cli("settings bogus") }
        Self.expectInvalid("sideways") { try Self.cli("move sideways") }
    }

    @Test func usageListsEveryVerb() {
        for verb in ["apply", "action", "cycle", "columns", "move", "undo", "displays", "window", "settings"] {
            #expect(CommandParser.usage.contains(verb))
        }
    }
}
