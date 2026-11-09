import os
import ServiceManagement
import SwiftUI
import TesseraCore

struct GeneralPane: View {
    @Bindable var model: SettingsModel
    @State private var loginError: String?
    /// Read once per appearance; `SMAppService.status` is IPC and must never run in `body`.
    @State private var loginNeedsApproval = false
    @State private var recordingChord = false

    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "settings-ui")

    var body: some View {
        Form {
            Section {
                KeycapRow(keys: ModifierKey.names(model.settings.trigger.keyCodes), prominent: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                ChordRecorder(chord: $model.settings.trigger, recording: $recordingChord)
            } header: {
                Text("Trigger")
            } footer: {
                Footer(recordingChord
                    ? "Hold the modifier keys you want, then release them. Esc cancels."
                    : model.settings.trigger.keyCodes.count == 1
                        ? "A single-key chord opens the ring every time you press that key."
                        : "Hold these keys to open the ring; release to snap. Click the chord to record a new one, or select it and press Delete for the default.")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError { Callout(.warning, loginError) { loginItemsButton } }
                if loginNeedsApproval {
                    Callout(.warning, "Approve Tessera in System Settings › General › Login Items.") { loginItemsButton }
                }
                AppearancePicker(selection: $model.settings.appearance)
            } header: {
                Text("App")
            } footer: {
                Footer("Light or dark applies to Tessera's windows. Match System follows macOS. The ring has its own colours in Ring and Overlay.")
            }

            Section {
                Toggle("Show the menu bar icon", isOn: $model.settings.showMenuBarIcon)
                LabeledContent("Icon") {
                    Picker("Icon", selection: $model.settings.menuBarIcon) {
                        ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                            Image(nsImage: icon.image())
                                .accessibilityLabel(icon.displayName)
                                .help(icon.displayName)
                                .tag(icon)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!model.settings.showMenuBarIcon)
                Toggle("Show each item's shortcut", isOn: $model.settings.menuBarItems.shortcutKeys)
                    .disabled(!model.settings.showMenuBarIcon)
            } header: {
                Text("Menu bar")
            } footer: {
                if !model.settings.showMenuBarIcon {
                    Footer("With the icon hidden, open Tessera from Finder or Spotlight to reach Settings.")
                } else if !model.settings.hotkeysEnabled {
                    Footer("Hotkeys are off, so the icon carries a pause badge. Turn them back on in Shortcuts.")
                }
            }

            Section {
                Toggle("Status line (how to snap)", isOn: $model.settings.menuBarItems.statusLine)
                Toggle("What Just Happened?", isOn: $model.settings.menuBarItems.explain)
                Toggle("Snap Front Window submenu", isOn: $model.settings.menuBarItems.snapSubmenu)
                Toggle("Columns submenu", isOn: $model.settings.menuBarItems.columnsSubmenu)
                Toggle("Shortcuts…", isOn: $model.settings.menuBarItems.shortcuts)
                Toggle("Undo Last Move", isOn: $model.settings.menuBarItems.undo)
                Toggle("Check for Updates…", isOn: $model.settings.menuBarItems.checkForUpdates)
            } header: {
                Text("Menu items")
            } footer: {
                Footer("Choose what the menu shows. Settings… and Quit are always there.")
            }
            .disabled(!model.settings.showMenuBarIcon)

            Section {
                Toggle("Show messages", isOn: $model.settings.showHUD)
                Group {
                    Picker("Position", selection: $model.settings.hudPosition) {
                        ForEach(HUDPosition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    SliderRow(title: "Stays for", value: $model.settings.hudSeconds, range: 0.5...5, step: 0.1,
                              format: { String(format: "%.1f s", $0) })
                }
                .disabled(!model.settings.showHUD)
            } header: {
                Text("Messages")
            } footer: {
                Footer("Shortcut confirmations and short results such as \u{201C}5 columns\u{201D}, shown on the screen under the mouse.")
            }

            HelpSection(model: model)

            AdvancedSection(model: model)

            ResetSection {
                model.settings.trigger = .default
                model.settings.showMenuBarIcon = true
                model.settings.showHUD = true
                model.settings.hudPosition = .bottom
                model.settings.hudSeconds = TesseraSettings.defaults.hudSeconds
                model.settings.menuBarIcon = .tiles
                model.settings.menuBarItems = MenuBarItems()
                model.settings.appearance = .system
                model.settings.help.autoShow = true
                model.settings.help.dimScreen = true
                if model.settings.launchAtLogin { setLaunchAtLogin(false) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The system owns the truth: the user may have removed Tessera from Login Items.
            let status = SMAppService.mainApp.status
            loginNeedsApproval = status == .requiresApproval
            if status == .enabled || status == .notRegistered { model.settings.launchAtLogin = status == .enabled }
        }
    }

    private var loginItemsButton: some View {
        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            .controlSize(.small)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.settings.launchAtLogin = on
            loginError = nil
            loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        } catch {
            Self.log.error("Login item change failed: \(error.localizedDescription, privacy: .private)")
            loginError = "Couldn't change the login item. Try again, or check Login Items in System Settings."
        }
    }
}

#Preview {
    GeneralPane(model: SettingsModel())
}
