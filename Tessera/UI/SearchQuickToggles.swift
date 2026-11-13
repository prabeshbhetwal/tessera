import TesseraCore

/// On/off settings a search result can flip in place, keyed by catalog entry id, each with the condition its pane
/// puts on changing it. Only switches the pane binds straight to the setting: ones with side effects (Launch at
/// login, a custom theme's preview options) open their pane instead.
@MainActor
enum SearchQuickToggles {
    struct Switch {
        let path: WritableKeyPath<TesseraSettings, Bool>
        /// Whether the pane would let it change now; when not, the result's switch is dimmed.
        var enabled: (TesseraSettings) -> Bool = { _ in true }
    }

    static func `switch`(for entry: SettingsEntry) -> Switch? { all[entry.id] }

    private static let menuBar: (TesseraSettings) -> Bool = { $0.showMenuBarIcon }
    private static let learning: (TesseraSettings) -> Bool = { $0.learnSplits }
    private static let ringShown: (TesseraSettings) -> Bool = { $0.ring.showRing }
    private static let pointing: (TesseraSettings) -> Bool = { $0.ring.pointing }

    private static let all: [String: Switch] = {
        let all: [String: Switch] = [
            "general/Apple Intelligence search": Switch(path: \.searchUsesAppleIntelligence),
            "general/Show the menu bar icon": Switch(path: \.showMenuBarIcon),
            "general/Show each item’s shortcut": Switch(path: \.menuBarItems.shortcutKeys, enabled: menuBar),
            "general/Status line (how to snap)": Switch(path: \.menuBarItems.statusLine, enabled: menuBar),
            "general/What Just Happened?": Switch(path: \.menuBarItems.explain, enabled: menuBar),
            "general/Snap Front Window submenu": Switch(path: \.menuBarItems.snapSubmenu, enabled: menuBar),
            "general/Columns submenu": Switch(path: \.menuBarItems.columnsSubmenu, enabled: menuBar),
            "general/Shortcuts…": Switch(path: \.menuBarItems.shortcuts, enabled: menuBar),
            "general/Undo Last Move": Switch(path: \.menuBarItems.undo, enabled: menuBar),
            "general/Check for Updates…": Switch(path: \.menuBarItems.checkForUpdates, enabled: menuBar),
            "general/Show messages": Switch(path: \.showHUD),
            "general/Show tips on their own": Switch(path: \.help.autoShow),
            "general/Dim the screen behind tips": Switch(path: \.help.dimScreen),
            "shortcuts/Use global hotkeys": Switch(path: \.hotkeysEnabled),
            "shortcuts/Navigate the open ring with the keyboard": Switch(path: \.ringKeyNavigation),
            "shortcuts/Announce the selection with VoiceOver": Switch(path: \.announceSelection),
            "splits/Learn from my adjustments": Switch(path: \.learnSplits),
            "splits/Resize neighbours to fill the display": Switch(path: \.splitReflowsNeighbours, enabled: learning),
            "splits/Fill the space when a window closes": Switch(path: \.splitFillsClosedGap, enabled: learning),
            "splits/Make room when a window opens": Switch(path: \.splitTilesNewWindow, enabled: learning),
            "ring/Directions: flick towards a layout": Switch(path: \.ring.directions),
            "ring/Pointing: a longer move picks a column of the grid": Switch(path: \.ring.pointing),
            "ring/Click while pointing to span several columns": Switch(path: \.ring.clickToSpan, enabled: pointing),
            "ring/Scroll while holding to change the column count": Switch(path: \.ring.scrollChangesColumns),
            "ring/Press and release without moving to tile all windows": Switch(path: \.ring.tapTilesWindows),
            "overlay/Show the ring": Switch(path: \.ring.showRing),
            "overlay/Action name and input hints": Switch(path: \.ring.showActionLabels, enabled: ringShown),
            "overlay/Dashed circle where pointing begins": Switch(path: \.ring.showBoundary, enabled: {
                $0.ring.showRing && $0.ring.directions && $0.ring.pointing
            }),
            "overlay/Frosted background": Switch(path: \.ring.frosted, enabled: ringShown),
            "overlay/Grid lines while picking a column": Switch(path: \.ring.showGrid),
            "overlay/Number the grid’s columns": Switch(path: \.ring.showColumnNumbers, enabled: { $0.ring.showGrid }),
            "overlay/Pointing hint": Switch(path: \.ring.showPointingHint, enabled: pointing),
            "motion/Animate the preview between selections": Switch(path: \.preview.morph),
            "updates/Check for updates automatically": Switch(path: \.updates.checkAutomatically),
            "updates/Download and install automatically": Switch(path: \.updates.installAutomatically, enabled: {
                $0.updates.checkAutomatically
            }),
            "updates/Include beta versions": Switch(path: \.updates.includeBetas),
        ]
        // A renamed catalog entry would silently lose its switch.
        assert(Set(all.keys).isSubset(of: SettingsCatalog.entries.map(\.id)), "quick toggle id not in SettingsCatalog")
        return all
    }()
}
