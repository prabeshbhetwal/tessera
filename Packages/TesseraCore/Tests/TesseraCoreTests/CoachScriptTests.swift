import CoreGraphics
import Foundation
import Testing
@testable import TesseraCore

@Suite struct CoachScriptTests {
    static let usable = CGRect(x: 0, y: 0, width: 3840, height: 1050)

    static func event(
        _ kind: HelpEventKind,
        apps: [String] = ["Dia", "Claude", "Codex"],
        fractions: [Double] = [1.0 / 2, 1.0 / 4, 1.0 / 4],
        withSplit: Bool = true
    ) -> HelpEvent {
        var x = 0.0
        let frames = fractions.map { f -> CGRect in
            defer { x += f * usable.width }
            return CGRect(x: x, y: 0, width: f * usable.width, height: usable.height)
        }
        let key = SplitKey(display: "d", bundleIDs: apps)
        let split = LearnedSplit(
            key: key,
            slots: apps.map { Slot(bundleID: $0, rect: UnitRect(x: 0, y: 0, width: 1, height: 1)) },
            updated: Date(timeIntervalSince1970: 1_794_052_800))
        return HelpEvent(
            kind: kind, source: .hotkey, displayKey: "d", displayName: "CHG90",
            apps: apps, frames: frames, usable: usable, portrait: false,
            key: key, split: withSplit ? split : nil, previousSplit: nil)
    }

    @Test func tiledWithSplitCopyAndSteps() {
        let steps = CoachScript.steps(for: Self.event(.tiled(usedSplit: true)))
        #expect(steps.count == 3)
        #expect(steps[0].title == "Tiled with your split")
        #expect(steps[0].body == "You taught Tessera this split for Dia, Claude and Codex on 7 Nov: Dia half, the others a quarter each. Without it, each would get a third.")
        #expect(steps[0].actions == [.next, .tileEvenly, .done])
        #expect(steps[1].waitsForLearn)
        #expect(steps[1].spotlight == .seam)
        #expect(steps[1].body == "Make Dia narrower. Claude and Codex will move with it.")
        #expect(steps[2].title == "Claude and Codex followed")
        #expect(steps[2].actions == [.done, .undoSplitChange])
        #expect(steps[2].body.hasPrefix("Tessera saved this as your new split for these 3 apps."))
    }

    @Test func tiledWithSplitButNoSplitFallsBackToEqualCopy() {
        let steps = CoachScript.steps(for: Self.event(.tiled(usedSplit: true), withSplit: false))
        #expect(steps[0].title == "Tiled in equal shares")
        #expect(steps.count == 3)
    }

    @Test func tiledEqualSteps() {
        let steps = CoachScript.steps(for: Self.event(.tiled(usedSplit: false)))
        #expect(steps[0].body == "Tessera has no split for Dia, Claude and Codex on CHG90 yet, so each got a third.")
        #expect(steps[0].actions == [.next, .done])
        #expect(steps[2].body.hasPrefix("Tessera saved this as your split for these 3 apps."))
    }

    @Test func oneWindowTileHasOneStep() {
        for used in [true, false] {
            let e = Self.event(.tiled(usedSplit: used), apps: ["Dia"], fractions: [1])
            let steps = CoachScript.steps(for: e)
            #expect(steps.count == 1)
            #expect(steps[0].actions == [.done])
        }
    }

    @Test func otherMoments() {
        let evenlyKept = CoachScript.steps(for: Self.event(.tiledEvenly(hasSplit: true)))
        #expect(evenlyKept.count == 1 && evenlyKept[0].actions == [.done])
        let evenly = CoachScript.steps(for: Self.event(.tiledEvenly(hasSplit: false)))[0]
        #expect(evenly.title == "Tiled evenly")
        #expect(evenly.body == "Each window got a third. Tile Evenly doesn't save what you change afterwards.")
        let learned = CoachScript.steps(for: Self.event(.splitLearned))[0]
        #expect(learned.actions == [.done, .forgetSplit])
        #expect(learned.body == "Next time Dia, Claude and Codex are on CHG90, Tile All Windows (⌃⌥T) puts them back like this.")
        let notLearned = CoachScript.steps(for: Self.event(.splitNotLearned(reason: "Windows overlap")))[0]
        #expect(notLearned.body.hasPrefix("Windows overlap."))
        #expect(notLearned.actions == [.tileAll, .done])
        let partial = CoachScript.steps(for: Self.event(.tilePartial(moved: 2, total: 3, stuck: ["Codex"])))[0]
        #expect(partial.actions == [.undoMove, .done])
        let follow = CoachScript.steps(for: Self.event(.neighboursFollowed(changed: "Dia", followers: ["Claude", "Codex"])))[0]
        #expect(follow.actions == [.done, .undoMove, .openSplitsSettings])
        let gone = CoachScript.steps(for: Self.event(.splitForgotten))
        #expect(gone.count == 1 && gone[0].actions == [.undoSplitChange, .done])
        #expect(CoachScript.forgotten(Self.event(.splitForgotten)) == gone[0])
    }

    @Test func noExclamationMarksAnywhere() {
        let kinds: [HelpEventKind] = [
            .tiled(usedSplit: true), .tiled(usedSplit: false),
            .tiledEvenly(hasSplit: true), .tiledEvenly(hasSplit: false),
            .tilePartial(moved: 1, total: 3, stuck: ["A", "B"]), .tilePartial(moved: 1, total: 2, stuck: []),
            .neighboursFollowed(changed: "Dia", followers: ["Claude"]),
            .splitLearned, .splitNotLearned(reason: "Windows overlap"), .splitForgotten,
        ]
        for kind in kinds {
            for step in CoachScript.steps(for: Self.event(kind)) {
                #expect(!step.title.contains("!") && !step.body.contains("!"))
            }
        }
    }

    @Test func actionLabels() {
        #expect(CoachAction.undoMove.label == "Undo")
        #expect(CoachAction.undoSplitChange.label == "Undo")
        #expect(CoachAction.next.label == "Show Me More")
    }

    // MARK: CoachCopy

    @Test func listJoins() {
        #expect(CoachCopy.list([]) == "")
        #expect(CoachCopy.list(["A"]) == "A")
        #expect(CoachCopy.list(["A", "B"]) == "A and B")
        #expect(CoachCopy.list(["Chrome", "Chrome", "Codex"]) == "Chrome, Chrome and Codex")
    }

    @Test func shareWords() {
        #expect(CoachCopy.share(0.5) == "half")
        #expect(CoachCopy.share(0.34) == "a third")
        #expect(CoachCopy.share(0.41) == "41%")
        #expect(CoachCopy.share(0.25) == "a quarter")
        #expect(CoachCopy.share(2.0 / 3) == "two thirds")
        #expect(CoachCopy.share(0.75) == "three quarters")
        #expect(CoachCopy.equalShare(2) == "half")
        #expect(CoachCopy.equalShare(6) == "a sixth")
        #expect(CoachCopy.equalShare(7) == "an equal share")
    }

    @Test func mixedShares() {
        let e = Self.event(.splitLearned, fractions: [1.0 / 2, 1.0 / 3, 1.0 / 6])
        #expect(CoachCopy.shares(apps: e.apps, frames: e.frames, usable: e.usable, portrait: false)
            == "Dia half, Claude a third, Codex 17%")
    }

    @Test func portraitUsesHeight() {
        let usable = CGRect(x: 0, y: 0, width: 1000, height: 2000)
        let frames = [CGRect(x: 0, y: 0, width: 1000, height: 1000), CGRect(x: 0, y: 1000, width: 1000, height: 1000)]
        #expect(CoachCopy.shares(apps: ["A", "B"], frames: frames, usable: usable, portrait: true) == "A half, B half")
    }

    @Test func dayHasNoPeriod() {
        #expect(CoachCopy.day(Date(timeIntervalSince1970: 1_794_052_800)) == "7 Nov")
    }
}
