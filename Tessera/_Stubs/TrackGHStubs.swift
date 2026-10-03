// TEMPORARY STUB — coordinator deletes at merge
// Signatures copied from the M2 plan (Tracks G and H). Bodies are placeholders only.

import CoreGraphics
import Foundation
import TesseraCore

// MARK: - Track G

enum CommandParseError: Error, Equatable {
    case invalid(String)
}

enum CommandParser {
    static func parse(url: URL) throws -> Command { throw CommandParseError.invalid("stub") }
    static func parse(arguments: [String]) throws -> Command { throw CommandParseError.invalid("stub") }
    static let usage = ""
}

enum DisplayResolver {
    static func ordered(_ displays: [DisplayContext]) -> [DisplayContext] {
        displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    static func resolve(_ s: DisplaySelector, displays: [DisplayContext], windowFrame: CGRect?, cursor: CGPoint) -> DisplayContext? {
        displays.first
    }

    static func step(_ s: DisplayStep, from: DisplayContext, displays: [DisplayContext]) -> DisplayContext? {
        from
    }
}

enum TargetResolver {
    static func span(for target: Target, display: DisplayContext) -> ColumnSpan? { nil }

    static func frame(for target: Target, display: DisplayContext, current: CGRect) -> CGRect { current }

    static func relocate(span: ColumnSpan, from: DisplayContext, to: DisplayContext) -> ColumnSpan { span }
}

// MARK: - Track H

struct NavState: Equatable, Sendable {
    var displayIndex: Int
    var columns: ClosedRange<Int>
    var band: Band
}

enum KeyNavigator {
    static func start(windowFrame: CGRect?, displays: [DisplayContext]) -> NavState? {
        displays.isEmpty ? nil : NavState(displayIndex: 0, columns: 0...0, band: .full)
    }

    static func reduce(_ s: NavState, _ key: NavKey, displays: [DisplayContext]) -> NavState { s }

    static func selection(_ s: NavState, displays: [DisplayContext]) -> Selection { .none }
}

struct CycleTracker: Sendable {
    init(timeout: TimeInterval = 2) {}

    mutating func step(cycle: String, windowKey: String, stepCount: Int, now: Date) -> Int { 0 }
}

extension TriggerMachine {
    init(chord: TriggerChord, hotkeys: [HotkeyBinding], ringKeyNavigation: Bool) {
        self.init(chord: chord)
    }
}
