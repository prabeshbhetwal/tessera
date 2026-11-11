/// Every setting the Settings search can find, in sidebar order. The anchor (the title unless given) is the
/// literal the app tags that row with; `SettingsCatalogTests` checks each one is tagged in Tessera/UI.
public enum SettingsCatalog {
    public typealias E = SettingsEntry

    public static let entries: [SettingsEntry] = general + ring + shortcuts + cycles + excludedApps + displays + splits
        + overlay + motion + updates + about

    static let general: [E] = [
        E("general", "App", "Launch at login", ["start automatically open when mac starts"]),
        E("general", "App", "Light or dark", anchor: "Appearance", ["light dark mode match system look theme windows"]),
        E("general", "App", "Understand searches with Apple Intelligence", anchor: "Apple Intelligence search",
          ["settings search on device model smart ai"]),
        E("general", "Menu bar", "Show the menu bar icon", ["status item top bar"]),
        E("general", "Menu bar", "Icon", ["menu bar symbol glyph picture"]),
        E("general", "Menu bar", "Show each item's shortcut", ["menu hotkey key equivalents"]),
        E("general", "Menu items", "Status line (how to snap)", ["menu hint"]),
        E("general", "Menu items", "What Just Happened?", ["menu explain last action"]),
        E("general", "Menu items", "Snap Front Window submenu", ["menu"]),
        E("general", "Menu items", "Columns submenu", ["menu"]),
        E("general", "Menu items", "Shortcuts…", ["menu item"]),
        E("general", "Menu items", "Undo Last Move", ["menu revert"]),
        E("general", "Menu items", "Check for Updates…", ["menu item"]),
        E("general", "Messages", "Show messages", ["hud confirmation after snapping"]),
        E("general", "Messages", "Position", ["message hud where"]),
        E("general", "Messages", "Stays for", ["message hud how long seconds time"]),
        E("general", "Tips", "Show tips on their own", ["tips coach onboarding"]),
        E("general", "Tips", "Dim the screen behind tips", ["tips darken"]),
        E("general", "Tips", "Show Tips Again", ["tips reset seen"]),
        E("general", "Advanced", "Advanced",
          ["export import backup settings file json cli terminal command line tool install"]),
        E("general", "", "Restore Defaults", ["reset general"]),
    ]

    static let excludedApps: [E] = [
        E("excludedApps", "Apps", "Excluded apps", anchor: "Apps",
          ["exclude ignore app turn off for app disable in app conflict own shortcuts add running app choose"]),
        E("excludedApps", "", "Restore Defaults", ["reset excluded apps"]),
    ]

    static let shortcuts: [E] = [
        E("shortcuts", "Hotkeys", "Use global hotkeys", ["keyboard shortcuts on"]),
        E("shortcuts", "Hotkeys", "Add Hotkey", ["hotkeys list new keyboard shortcut record bind keys"]),
        E("shortcuts", "Ring keyboard", "Navigate the open ring with the keyboard", ["arrow keys"]),
        E("shortcuts", "Ring keyboard", "Announce the selection with VoiceOver", ["accessibility speak"]),
        E("shortcuts", "", "Restore Defaults", ["reset shortcuts hotkeys"]),
    ]

    static let cycles: [E] = [
        E("cycles", "Cycles", "Cycles", anchor: nil, ["sequence repeat press step through layouts rotate"]),
        E("cycles", "", "Restore Defaults", ["reset cycles"]),
    ]

    static let splits: [E] = [
        E("splits", "Learning", "Learn from my adjustments", ["remember resize learned layout"]),
        E("splits", "Learning", "Resize neighbours to fill the display", ["reflow resize other windows apps adjacent"]),
        E("splits", "Learning", "Fill the space when a window closes", ["app closes quit empty gap fill"]),
        E("splits", "Learning", "When a window is minimised", ["minimise minimize dock restore retile gap empty space"]),
        E("splits", "Learning", "When a window closes but its app keeps running",
          ["close button red dock still running background app retile gap empty space wispr slack"]),
        E("splits", "Learning", "Make room when a window opens", ["new window opens tile automatically fit in"]),
        E("splits", "Learning", "Make room on", ["new window which displays tiled remembered split"]),
        E("splits", "Learning", "Wait before tiling a new app",
          ["delay seconds timer brief quick open wispr finder new window tile later"]),
        E("splits", "Learning", "Restore last order", ["window order arrangement"]),
        E("splits", "Learning", "Empty space when order changes", ["gap placement follows neighbour"]),
        E("splits", "Learned splits", "Forget All…", ["clear delete learned splits manage display monitor remembered layouts"]),
        E("splits", "", "Restore Defaults", ["reset splits"]),
    ]

    static let displays: [E] = [
        E("displays", "This display", "Columns", ["column count rows how many columns grid portrait"]),
        E("displays", "This display", "Gap",
          ["space between windows tiled apps no gap touching spacing gutter remove gap"]),
        E("displays", "This display", "Padding", ["margin screen edge around border inset"]),
        E("displays", "New displays", "Gap for new displays", anchor: "New displays gap",
          ["default space between windows other monitors"]),
        E("displays", "New displays", "Padding for new displays", anchor: "New displays padding",
          ["default margin screen edge other monitors"]),
        E("displays", "Column sizing", "Minimum column width", ["narrow smallest column"]),
        E("displays", "Column sizing", "Ideal column width", ["preferred column"]),
        E("displays", "Column sizing", "Maximum column width", ["widest column"]),
        E("displays", "Column sizing", "Minimum row height", ["shortest row"]),
        E("displays", "Column sizing", "Column limit", ["most columns maximum count"]),
        E("displays", "", "Restore Defaults", ["reset displays"]),
    ]

    static let ring: [E] = [
        E("ring", "Trigger", "Chord", ["trigger keys hold open ring modifier record activate"]),
        E("ring", "Gestures", "Directions: flick towards a layout", ["flick gesture direction"]),
        E("ring", "Gestures", "Pointing: a longer move picks a column of the grid", ["point gesture column"]),
        E("ring", "Gestures", "Click while pointing to span several columns", ["span multiple columns click"]),
        E("ring", "Gestures", "Scroll while holding to change the column count", ["scroll wheel trackpad columns"]),
        E("ring", "Gestures", "Press and release without moving to tile all windows", ["tap tile all tile evenly"]),
        E("ring", "Directions", "What each direction does", anchor: "Directions", ["wedge layout per direction assign"]),
        E("ring", "Size and zones", "Radius", ["ring size bigger smaller"]),
        E("ring", "Size and zones", "Thickness", ["ring width thick thin"]),
        E("ring", "Size and zones", "Point threshold", ["pointing distance where pointing begins"]),
        E("ring", "Size and zones", "Top band", ["zone top"]),
        E("ring", "Size and zones", "Bottom band", ["zone bottom"]),
        E("ring", "", "Restore Defaults", ["reset ring trigger gestures"]),
    ]

    static let overlay: [E] = [
        E("overlay", "", "Show on Screen", ["preview ring test try"]),
        E("overlay", "", "Preview Shortcut", ["preview confirmation test message"]),
        E("overlay", "Theme", "Theme", ["colour scheme preset look save custom appearance"]),
        E("overlay", "Ring", "Show the ring", ["ring visible circle hidden invisible"]),
        E("overlay", "Ring", "Action name and input hints", ["ring label caption"]),
        E("overlay", "Ring", "Layout icons", ["ring icon style"]),
        E("overlay", "Ring", "Dashed circle where pointing begins", ["boundary dashed line"]),
        E("overlay", "Ring", "Frosted background", ["blur glass vibrancy"]),
        E("overlay", "Grid and hints", "Grid lines while picking a column", ["grid lines"]),
        E("overlay", "Grid and hints", "Number the grid's columns", ["column numbers"]),
        E("overlay", "Grid and hints", "Show \u{201C}click to add columns\u{201D} the first few times", anchor: "Pointing hint",
          ["hint click add columns"]),
        E("overlay", "Ring colours", "Ring", ["ring colour fill"]),
        E("overlay", "Ring colours", "Ring tint", ["ring colour strength"]),
        E("overlay", "Ring colours", "Lines and icons", ["stroke colour"]),
        E("overlay", "Ring colours", "Selected layout", ["accent highlight colour"]),
        E("overlay", "Ring colours", "Grid", ["grid colour"]),
        E("overlay", "Preview and label colours", "Snap preview", ["preview colour"]),
        E("overlay", "Preview and label colours", "Label", ["label colour"]),
        E("overlay", "Preview and label colours", "Label text", ["label text colour"]),
        E("overlay", "Preview and label colours", "Outline of the current frame", ["outline colour"]),
        E("overlay", "Preview and label colours", "Dimming", ["dim colour"]),
        E("overlay", "Preview", "Fill the preview with", ["preview style fill"]),
        E("overlay", "Preview", "Fill opacity", ["preview transparency"]),
        E("overlay", "Preview", "Border width", ["preview outline stroke thickness"]),
        E("overlay", "Preview", "Match the window's corner radius", ["rounded corners"]),
        E("overlay", "Preview", "Corner radius", ["rounded corners round"]),
        E("overlay", "Label", "Show a label on the preview", ["preview label"]),
        E("overlay", "Label", "Size in points", ["label dimensions"]),
        E("overlay", "Label", "Slot name", ["label"]),
        E("overlay", "Label", "Position", ["label where centre bottom"]),
        E("overlay", "Around the preview", "Dim the windows the preview covers", ["dim neighbours darken"]),
        E("overlay", "Around the preview", "Dim strength", ["dim amount darkness"]),
        E("overlay", "Around the preview", "Outline where the window is now (dashed)", ["current frame outline dashed"]),
        E("overlay", "", "Restore Defaults", ["reset appearance overlay look"]),
    ]

    static let motion: [E] = [
        E("motion", "Snap speed", "Speed", ["snap animation how fast windows move instant"]),
        E("motion", "Snap speed", "Duration", ["snap animation time seconds"]),
        E("motion", "Preview morph", "Animate the preview between selections", ["morph preview animation"]),
        E("motion", "Preview morph", "Spring response", ["preview animation bounce"]),
        E("motion", "", "Restore Defaults", ["reset motion"]),
    ]

    static let updates: [E] = [
        E("updates", "Updates", "Last checked", ["update when last time"]),
        E("updates", "Updates", "Check Now", ["update now latest version new"]),
        E("updates", "Automatic updates", "Check for updates automatically", ["auto update"]),
        E("updates", "Automatic updates", "Frequency", ["update how often daily weekly"]),
        E("updates", "Automatic updates", "Download and install automatically", ["auto update install"]),
        E("updates", "Automatic updates", "Include beta versions", ["beta prerelease early"]),
        E("updates", "", "Restore Defaults", ["reset updates"]),
    ]

    static let about: [E] = [
        E("about", "About", "About Tessera", anchor: nil, ["version copy licence website links credits"]),
    ]
}
