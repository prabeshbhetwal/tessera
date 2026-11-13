import TesseraCore

enum WindowLayoutPolicy {
    static func matches(_ a: TesseraSettings, _ b: TesseraSettings, display: String) -> Bool {
        a.learnSplits == b.learnSplits && a.splitFillsClosedGap == b.splitFillsClosedGap
            && a.splitOnMinimise == b.splitOnMinimise && a.splitOnCloseKeepsRunning == b.splitOnCloseKeepsRunning
            && a.splitTilesNewWindow == b.splitTilesNewWindow && a.splitNewWindowScope == b.splitNewWindowScope
            && a.splitNewWindowWait == b.splitNewWindowWait && a.splitRestoresOrder == b.splitRestoresOrder
            && a.splitGapPlacement == b.splitGapPlacement && a.splitGapWhenGrowing == b.splitGapWhenGrowing
            && Set(a.excludedBundleIDs) == Set(b.excludedBundleIDs)
            && a.defaultGap == b.defaultGap && a.defaultPadding == b.defaultPadding && a.sizing == b.sizing
            && a.displayOverrides[display] == b.displayOverrides[display]
            && a.learnedSplits.filter { $0.key.display == display } == b.learnedSplits.filter { $0.key.display == display }
    }
}
