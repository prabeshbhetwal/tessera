import Foundation
import Testing
@testable import TesseraCore

@Suite struct UpdateSettingsTests {
    @Test func intervalSeconds() {
        #expect(UpdateInterval.daily.seconds == 86_400)
        #expect(UpdateInterval.weekly.seconds == 604_800)
        #expect(UpdateInterval.fortnightly.seconds == 1_209_600)
        #expect(UpdateInterval.monthly.seconds == 2_592_000)
        #expect(UpdateInterval.allCases.map(\.displayName) == ["Daily", "Weekly", "Fortnightly", "Monthly"])
    }

    @Test func defaults() {
        let u = TesseraSettings.defaults.updates
        #expect(u == UpdateSettings())
        #expect(u.checkAutomatically)
        #expect(u.interval == .weekly)
        #expect(!u.installAutomatically)
        #expect(!u.includeBetas)
    }

    @Test func channels() {
        var u = UpdateSettings()
        #expect(u.allowedChannels == [])
        u.includeBetas = true
        #expect(u.allowedChannels == ["beta"])
        #expect(u.allowedChannels == [UpdateSettings.betaChannel])
    }

    /// A file written before updates existed must load with defaults, not be quarantined.
    @Test func oldFileGainsUpdates() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        object["updates"] = nil
        let migrated = try SettingsMigration.migrate(JSONSerialization.data(withJSONObject: object))
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: migrated.data)
        #expect(decoded == TesseraSettings.defaults)
        #expect(throws: Never.self) { try SettingsValidation.validate(decoded) }
    }

    /// A file written before the menu bar's Check for Updates item could be hidden must show it, not be quarantined.
    @Test func oldFileShowsCheckForUpdatesItem() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        var items = object["menuBarItems"] as! [String: Any]
        items["checkForUpdates"] = nil
        object["menuBarItems"] = items
        let migrated = try SettingsMigration.migrate(JSONSerialization.data(withJSONObject: object))
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: migrated.data)
        #expect(decoded.menuBarItems.checkForUpdates)
        #expect(decoded == TesseraSettings.defaults)
        #expect(throws: Never.self) { try SettingsValidation.validate(decoded) }
    }

    @Test func roundTrips() throws {
        var s = TesseraSettings.defaults
        s.updates.checkAutomatically = false
        s.updates.interval = .monthly
        s.updates.installAutomatically = true
        s.updates.includeBetas = true
        let decoded = try JSONDecoder().decode(TesseraSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        #expect(decoded.updates.interval == .monthly)
    }
}
