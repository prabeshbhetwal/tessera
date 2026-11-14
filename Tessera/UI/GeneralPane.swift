import os
import ServiceManagement
import SwiftUI
import TesseraCore

struct GeneralPane: View {
    @Bindable var model: SettingsModel
    @State private var loginError: String?
    /// Read once per appearance; `SMAppService.status` is IPC and must never run in `body`.
    @State private var loginNeedsApproval = false

    private static let log = Logger(subsystem: "com.prabeshbhetwal.Tessera", category: "settings-ui")
    /// The on-device model ships with macOS 26; earlier systems can never enable the assistant.
    private static let supportsAppleIntelligenceOS = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .settingAnchor("Launch at login")
                if let loginError { Callout(.warning, loginError) { loginItemsButton } }
                if loginNeedsApproval {
                    Callout(.warning, "Approve Tessera in System Settings › General › Login Items.") { loginItemsButton }
                }
                AppearancePicker(selection: $model.settings.appearance)
                    .settingAnchor("Appearance")
                Toggle("Understand searches with Apple Intelligence", isOn: $model.settings.searchUsesAppleIntelligence)
                    .disabled(!SettingsAssistant.isAvailable)
                    .settingAnchor("Apple Intelligence search")
            } header: {
                InfoHeader("App", info: "Light or dark changes Tessera’s own windows; the ring’s colours are in Appearance. "
                    + "Apple Intelligence lets Settings search understand a whole sentence. It runs on your Mac, and nothing leaves it.")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !SettingsAssistant.isAvailable {
                        Footer(Self.supportsAppleIntelligenceOS
                            ? "Needs Apple Intelligence, which is off or not ready on this Mac."
                            : "Needs macOS 26 or later with Apple Intelligence.")
                    }
                }
            }

            Section {
                Toggle("Show the menu bar icon", isOn: $model.settings.showMenuBarIcon).settingAnchor("Show the menu bar icon")
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
                .settingAnchor("Icon")
                Toggle("Show each item’s shortcut", isOn: $model.settings.menuBarItems.shortcutKeys).settingAnchor("Show each item’s shortcut")
                    .disabled(!model.settings.showMenuBarIcon)
            } header: {
                Text("Menu bar")
            } footer: {
                if !model.settings.showMenuBarIcon {
                    Footer("To get back here, open Tessera from Spotlight or Finder.")
                } else if !model.settings.hotkeysEnabled {
                    Footer("Shortcuts are paused, so the icon shows a pause badge. Turn them back on in Shortcuts.")
                }
            }

            Section {
                Toggle("Status line (how to snap)", isOn: $model.settings.menuBarItems.statusLine).settingAnchor("Status line (how to snap)")
                Toggle("What Just Happened?", isOn: $model.settings.menuBarItems.explain).settingAnchor("What Just Happened?")
                Toggle("Snap Front Window submenu", isOn: $model.settings.menuBarItems.snapSubmenu).settingAnchor("Snap Front Window submenu")
                Toggle("Columns submenu", isOn: $model.settings.menuBarItems.columnsSubmenu).settingAnchor("Columns submenu")
                Toggle("Shortcuts…", isOn: $model.settings.menuBarItems.shortcuts).settingAnchor("Shortcuts…")
                Toggle("Undo Last Move", isOn: $model.settings.menuBarItems.undo).settingAnchor("Undo Last Move")
                Toggle("Check for Updates…", isOn: $model.settings.menuBarItems.checkForUpdates).settingAnchor("Check for Updates…")
            } header: {
                InfoHeader("Menu items", info: "Choose what the menu bar menu shows. Settings… and Quit are always there.")
            }
            .disabled(!model.settings.showMenuBarIcon)

            Section {
                Toggle("Show messages", isOn: $model.settings.showHUD).settingAnchor("Show messages")
                Group {
                    Picker("Position", selection: $model.settings.hudPosition) {
                        ForEach(HUDPosition.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .settingAnchor("Position")
                    SliderRow(title: "Stays for", value: $model.settings.hudSeconds, range: 0.5...5, step: 0.1,
                              format: { String(format: "%.1f s", $0) })
                }
                .disabled(!model.settings.showHUD)
            } header: {
                InfoHeader("Messages", info: "Short notes such as \u{201C}5 columns\u{201D} that confirm what a shortcut did. They appear near the mouse.")
            }

            HelpSection(model: model)

            AdvancedSection(model: model)

            ResetSection {
                model.settings.showMenuBarIcon = true
                model.settings.showHUD = true
                model.settings.hudPosition = .bottom
                model.settings.hudSeconds = TesseraSettings.defaults.hudSeconds
                model.settings.menuBarIcon = .tiles
                model.settings.menuBarItems = MenuBarItems()
                model.settings.appearance = .system
                model.settings.searchUsesAppleIntelligence = TesseraSettings.defaults.searchUsesAppleIntelligence
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
            loginError = "Couldn’t change the login item. Try again, or check Login Items in System Settings."
        }
    }
}

#Preview {
    GeneralPane(model: SettingsModel())
}
