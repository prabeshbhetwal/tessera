import AppKit
import Combine
import TesseraCore

/// The menu bar item, in AppKit.
///
/// SwiftUI's `MenuBarExtra` rebuilt its menu from observed state and dropped every item that read that
/// state once it changed after launch, leaving only Quit; its `isInserted` binding also once looped and
/// froze the app. An `NSStatusItem` whose menu is refreshed each time it opens has neither problem.
///
/// The icon and the optional items come from settings (General › Menu bar); Settings… and Quit always show.
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

    private let model: SettingsModel
    private let presenter: () -> WindowPresenter?
    private let run: (Command) -> Void
    private let updates: UpdateService
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var icon: MenuBarIcon = .grid
    private let status = NSMenuItem()
    private let statusSeparator = NSMenuItem.separator()
    private let snapItem = NSMenuItem(title: "Snap Front Window", action: nil, keyEquivalent: "")
    private let columnsItem = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
    private let actionsSeparator = NSMenuItem.separator()
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let shortcutsItem = NSMenuItem(title: "Shortcuts…", action: #selector(openShortcuts), keyEquivalent: "")
    private let undoItem = NSMenuItem(title: "Undo Last Move", action: #selector(undoLastMove), keyEquivalent: "")
    private let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")

    init(model: SettingsModel, updates: UpdateService, presenter: @escaping () -> WindowPresenter?,
         run: @escaping (Command) -> Void) {
        self.model = model
        self.updates = updates
        self.presenter = presenter
        self.run = run
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        status.isEnabled = false
        for entry in [settingsItem, shortcutsItem, undoItem, checkItem] { entry.target = self }
        snapItem.submenu = Self.submenu(
            [("Tile All Windows", .tileWindows(display: .current)), ("Remember Split", .rememberSplit(display: .current))]
                + WindowAction.allCases.map { action in (action.displayName, .apply(.action(action), display: .current)) },
            target: self, separatorAfter: 1)
        columnsItem.submenu = Self.submenu(
            [("One More Column", .columns(.delta(1), display: .current)),
             ("One Fewer Column", .columns(.delta(-1), display: .current))]
                + (2...8).map { ("\($0) Columns", .columns(.set($0), display: .current)) },
            target: self, separatorAfter: 1)
        let quit = NSMenuItem(title: "Quit Tessera", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for entry in [status, statusSeparator, snapItem, columnsItem, actionsSeparator,
                      settingsItem, shortcutsItem, undoItem, checkItem, .separator(), quit] {
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
        statusSeparator.isHidden = status.isHidden
        snapItem.isHidden = !items.snapSubmenu
        columnsItem.isHidden = !items.columnsSubmenu
        actionsSeparator.isHidden = snapItem.isHidden && columnsItem.isHidden
        // Always available: routes to setup until Accessibility is granted, then to Settings.
        settingsItem.title = granted ? "Settings…" : "Finish Setup…"
        shortcutsItem.isHidden = !items.shortcuts
        undoItem.isHidden = !items.undo
        for entry in [snapItem, columnsItem, shortcutsItem, undoItem] { entry.isEnabled = granted }
        // A waiting update shows its item even when hidden in settings, so the cue can reach the person;
        // clicking it brings Sparkle's alert forward.
        checkItem.title = updateWaiting ? "Update Available…" : "Check for Updates…"
        checkItem.isHidden = !items.checkForUpdates && !updateWaiting
        // Not gated on Accessibility: updating is how a broken build gets fixed. Greyed only while a check runs.
        checkItem.isEnabled = updates.canCheckForUpdates
    }

    private func updateIcon() {
        let image: NSImage?
        if accessibilityGranted {
            image = updateWaiting
                ? Self.badged(symbol: icon.rawValue)
                : NSImage(systemSymbolName: icon.rawValue, accessibilityDescription: "Tessera")
            image?.isTemplate = true
        } else {
            image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Tessera needs permission")?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
        }
        item.button?.image = image
    }

    /// The menu bar symbol with a dot at its top-right corner, cut out of the symbol so it reads on its own.
    /// Drawn in one colour, so it stays a template image that follows light and dark menu bars.
    private static func badged(symbol: String) -> NSImage? {
        guard let size = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.size else { return nil }
        // AppKit may run the handler on any thread, so it captures only the symbol name.
        let image = NSImage(size: size, flipped: false) { @Sendable rect in
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.draw(in: rect)
            let diameter = rect.height * 0.45
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.accessibilityDescription = "Tessera — update available"
        return image
    }

    /// A submenu whose items run commands. Each item carries its command; `separatorAfter` splits the list.
    private static func submenu(_ entries: [(String, Command)], target: StatusItemController, separatorAfter: Int? = nil) -> NSMenu {
        let menu = NSMenu()
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = CommandBox(entry.1)
            menu.addItem(item)
            if index == separatorAfter { menu.addItem(.separator()) }
        }
        return menu
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        run(box.command)
    }

    @objc private func openSettings() { presenter()?.showSettings() }
    @objc private func openShortcuts() { presenter()?.showSettings(pane: .shortcuts) }
    @objc private func undoLastMove() { run(.undo) }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
}

/// `Command` is a Swift enum; menu items carry objects.
private final class CommandBox: NSObject {
    let command: Command
    init(_ command: Command) { self.command = command }
}
