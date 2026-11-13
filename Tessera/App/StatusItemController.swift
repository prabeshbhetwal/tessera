import AppKit
import Combine
import TesseraCore

/// The menu bar item, in AppKit.
///
/// SwiftUI's `MenuBarExtra` rebuilt its menu from observed state and dropped every item that read that
/// state once it changed after launch, leaving only Quit; its `isInserted` binding also once looped and
/// froze the app. An `NSStatusItem` whose menu is refreshed each time it opens has neither problem.
///
/// The icon and the optional items come from settings (General › Menu bar); About Tessera, Settings… and Quit always show.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Drives the icon and which items are enabled. Set by the app delegate.
    var accessibilityGranted = Permissions.isAccessibilityTrusted {
        didSet { if accessibilityGranted != oldValue { updateIcon() } }
    }

    /// Mirrors `UpdateService.updateWaiting`, so the badge appears without the menu being opened.
    private var updateWaiting = false {
        didSet { if updateWaiting != oldValue { updateIcon() } }
    }
    private var waitingSubscription: AnyCancellable?

    /// Mirrors Settings › Shortcuts › master switch, so the icon carries a pause badge while hotkeys are paused.
    private var hotkeysOn = true {
        didSet { if hotkeysOn != oldValue { updateIcon() } }
    }

    private let model: SettingsModel
    private let presenter: () -> WindowPresenter?
    private let run: (Command) -> Void
    /// The display the Columns items act on: the front window's, looked up each time the menu opens.
    private let currentDisplay: () async -> DisplayContext?
    private var columnsLookup: Task<Void, Never>?
    private let updates: UpdateService
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var icon: MenuBarIcon = .tiles
    private let aboutItem = NSMenuItem(title: "About Tessera", action: #selector(openAbout), keyEquivalent: "")
    private let status = NSMenuItem()
    private let hotkeysOffItem = NSMenuItem(title: "Hotkeys Off", action: #selector(openShortcuts), keyEquivalent: "")
    private let explainItem = NSMenuItem(title: "What Just Happened?", action: #selector(explain), keyEquivalent: "")
    private let statusSeparator = NSMenuItem.separator()
    private let snapItem = NSMenuItem(title: "Snap Front Window", action: nil, keyEquivalent: "")
    private let columnsItem = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
    private let actionsSeparator = NSMenuItem.separator()
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let shortcutsItem = NSMenuItem(title: "Shortcuts…", action: #selector(openShortcuts), keyEquivalent: "")
    private let undoItem = NSMenuItem(title: "Undo Last Move", action: #selector(undoLastMove), keyEquivalent: "")
    private let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")

    init(model: SettingsModel, updates: UpdateService, presenter: @escaping () -> WindowPresenter?,
         run: @escaping (Command) -> Void, currentDisplay: @escaping () async -> DisplayContext?) {
        self.model = model
        self.updates = updates
        self.presenter = presenter
        self.run = run
        self.currentDisplay = currentDisplay
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        status.isEnabled = false
        for entry in [aboutItem, hotkeysOffItem, explainItem, settingsItem, shortcutsItem, undoItem, checkItem] { entry.target = self }
        snapItem.submenu = Self.submenu(
            [("Tile All Windows", .tileWindows(display: .current)), ("Remember Split", .rememberSplit(display: .current)),
             ("Tile Evenly", .tileEvenly(display: .current))]
                + WindowAction.allCases.map { action in (action.displayName, .apply(.action(action), display: .current)) },
            target: self, separatorsAfter: [2, 4, 8])
        showColumns(for: nil)
        let quit = NSMenuItem(title: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for entry in [aboutItem, .separator(), status, hotkeysOffItem, explainItem, statusSeparator, snapItem, columnsItem,
                      actionsSeparator, settingsItem, shortcutsItem, undoItem, checkItem, .separator(), quit] {
            menu.addItem(entry)
        }
        item.menu = menu
        item.autosaveName = "TesseraStatusItem"
        updateIcon()
        // `@Published` emits before the property changes, so take the emitted value rather than reading it back.
        waitingSubscription = updates.$updateWaiting.sink { [weak self] in self?.updateWaiting = $0 }
    }

    /// One-way from settings: AppKit's own hiding (crowded or notched menu bars) is never written back.
    func apply(_ settings: TesseraSettings) {
        if item.isVisible != settings.showMenuBarIcon { item.isVisible = settings.showMenuBarIcon }
        hotkeysOn = settings.hotkeysEnabled
        if icon != settings.menuBarIcon {
            icon = settings.menuBarIcon
            updateIcon()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let granted = accessibilityGranted
        let s = model.settings
        let items = s.menuBarItems
        status.title = granted
            ? "Hold \(ModifierKey.describe(s.trigger.keyCodes)) to snap"
            : "Accessibility not granted"
        // The status line always shows when setup is unfinished: it says why the rest is greyed out.
        status.isHidden = granted && !items.statusLine
        hotkeysOffItem.isHidden = s.hotkeysEnabled
        explainItem.isHidden = !items.explain
        statusSeparator.isHidden = status.isHidden && hotkeysOffItem.isHidden && explainItem.isHidden
        snapItem.isHidden = !items.snapSubmenu
        columnsItem.isHidden = !items.columnsSubmenu
        actionsSeparator.isHidden = snapItem.isHidden && columnsItem.isHidden
        // Always available: routes to setup until Accessibility is granted, then to Settings.
        settingsItem.title = granted ? "Settings…" : "Finish Setup…"
        shortcutsItem.isHidden = !items.shortcuts
        undoItem.isHidden = !items.undo
        for entry in [explainItem, snapItem, columnsItem, shortcutsItem, undoItem] { entry.isEnabled = granted }
        // A waiting update shows its item even when hidden in settings, so the cue can reach the person;
        // clicking it brings Sparkle's alert forward.
        checkItem.title = updateWaiting ? "Update Available…" : "Check for Updates…"
        checkItem.isHidden = !items.checkForUpdates && !updateWaiting
        // Not gated on Accessibility: updating is how a broken build gets fixed. Greyed only while a check runs.
        checkItem.isEnabled = updates.canCheckForUpdates
        // Read each time the menu opens, so a hotkey changed in Settings › Shortcuts shows straight away.
        // Global hotkeys off: the menu doesn't show them either, or they'd seem to work only while the menu is open.
        let keys = items.shortcutKeys && s.hotkeysEnabled
        explainItem.showShortcut(for: .explain, in: s.hotkeys, visible: keys)
        undoItem.showShortcut(for: .undo, in: s.hotkeys, visible: keys)
        settingsItem.showShortcut(for: .openSettings, in: s.hotkeys, visible: keys, fallback: (",", .command))
        showShortcuts(in: snapItem.submenu)
        // The front window's display is an Accessibility query (up to 0.3 s on a slow app). Until it answers,
        // the last display's counts must not stay clickable: they would run against whichever display is current now.
        columnsLookup?.cancel()
        guard granted, items.columnsSubmenu else { return }
        showColumnsNote("Finding Front Window…")
        columnsLookup = Task { [weak self] in
            let display = await self?.currentDisplay()
            guard !Task.isCancelled else { return }
            self?.showColumns(for: display)
        }
    }

    /// Only the counts `display` allows, its current count ticked. With no window there is nothing to act on.
    private func showColumns(for display: DisplayContext?) {
        guard let display else { return showColumnsNote("No Window in Front") }
        let entries = ColumnsMenu.entries(range: display.range.minCols...display.range.maxCols,
                                          current: display.profile.columns)
        let menu = Self.submenu(entries.map { ($0.title, .columns($0.change, display: .current)) },
                                target: self, separatorsAfter: [1])
        for (item, entry) in zip(menu.items.filter { !$0.isSeparatorItem }, entries) {
            item.isEnabled = entry.enabled
            item.state = entry.checked ? .on : .off
        }
        columnsItem.submenu = menu
        showShortcuts(in: menu)
    }

    /// A Columns submenu holding one greyed line, so nothing in it can be chosen.
    private func showColumnsNote(_ title: String) {
        let menu = NSMenu()
        let note = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        columnsItem.submenu = menu
    }

    private func showShortcuts(in menu: NSMenu?) {
        let s = model.settings
        for entry in menu?.items ?? [] {
            entry.showShortcut(for: (entry.representedObject as? CommandBox)?.command, in: s.hotkeys,
                               visible: s.menuBarItems.shortcutKeys)
        }
    }

    private func updateIcon() {
        item.button?.image = accessibilityGranted
            // Paused hotkeys badge the chosen picture rather than replace it, so the picker always shows its effect;
            // the trigger itself still works.
            ? icon.image(paused: !hotkeysOn, updateWaiting: updateWaiting)
            : NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Tessera needs permission")?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
    }

    /// A submenu whose items run commands. Each item carries its command; `separatorsAfter` splits the list into groups.
    private static func submenu(_ entries: [(String, Command)], target: StatusItemController, separatorsAfter: Set<Int> = []) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false   // else AppKit re-enables the Columns steps greyed at the ends of the range
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = CommandBox(entry.1)
            menu.addItem(item)
            if separatorsAfter.contains(index) { menu.addItem(.separator()) }
        }
        return menu
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        run(box.command)
    }

    @objc private func openSettings() { presenter()?.showSettings() }
    @objc private func openShortcuts() { presenter()?.showSettings(pane: .shortcuts) }
    @objc private func openAbout() { presenter()?.showSettings(pane: .about) }
    @objc private func explain() { run(.explain) }
    @objc private func undoLastMove() { run(.undo) }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
}

/// `Command` is a Swift enum; menu items carry objects.
private final class CommandBox: NSObject {
    let command: Command
    init(_ command: Command) { self.command = command }
}
