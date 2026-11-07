import AppKit
import TesseraCore

@MainActor
extension SplitWatcher {
    /// Learns how `found` sit on `display` and saves that as the split for these apps there. With `onlyIfChanged`, a
    /// split within a point of the stored one is not written again and comes back with `changed` false.
    func save(_ found: [(window: WindowRef, frame: CGRect)], display: DisplayContext, onlyIfChanged: Bool = false)
        -> Result<(key: SplitKey, changed: Bool), SplitRejection> {
        let usable = GridGeometry.usableFrame(display.visibleFrame, profile: display.profile)
        let frames = found.map { (bundleID: $0.window.bundleID, frame: $0.frame) }
        let learned = SplitLearner.learn(frames, usable: usable, gap: display.profile.gap)
        return learned.map { slots -> (key: SplitKey, changed: Bool) in
            let key = SplitKey(found, on: display)
            if onlyIfChanged, let stored = SplitMemory.lookup(key, in: model.settings.learnedSplits),
               stored.matches(slots, usable: usable) {
                return (key, false)
            }
            let split = LearnedSplit(key: key, slots: slots, updated: Date())
            model.settings.learnedSplits = SplitMemory.upsert(split, into: model.settings.learnedSplits)
            return (key, true)
        }
    }
}
