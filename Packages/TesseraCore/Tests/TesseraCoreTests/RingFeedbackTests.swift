import Foundation
import Testing
@testable import TesseraCore

@Suite struct RingFeedbackTests {
    private func feedback(_ selection: Selection = .none, ring: RingSettings = .default,
                          keyboard: Bool = false, keys: Bool = true, tap: Bool = false,
                          cancelling: Bool = false) -> RingFeedback {
        .make(selection: selection, ring: ring, keyboard: keyboard,
              keyboardEnabled: keys, tapToTile: tap, cancelling: cancelling)
    }

    @Test func selectionNamesTheMappedAction() {
        for action in WindowAction.allCases {
            #expect(feedback(.wedge(index: 0, action: action)).title == action.displayName)
        }
    }

    @Test func keyboardSpanUsesOneBasedColumnsAndBand() {
        let id = DisplayID(vendor: 1, model: 1, serial: 1, uuid: nil)
        let value = feedback(.span(display: id, span: ColumnSpan(columns: 1...3, band: .top)), keyboard: true)
        #expect(value.title == "Columns 2–4 · top")
        #expect(value.hint.contains("↵ Apply"))
        #expect(value.hint.contains("esc Cancel"))
    }

    @Test func returningToCentreCancelsInsteadOfAdvertisingTiling() {
        #expect(feedback(tap: true, cancelling: true).title == "Release to tile all windows")
        #expect(feedback(tap: false, cancelling: true).title == "Release here to cancel")
    }

    @Test func disabledGesturesAreNeverSuggested() {
        var ring = RingSettings.default
        ring.directions = false
        #expect(!feedback(ring: ring).hint.contains("Flick"))
        ring.pointing = false
        #expect(feedback(ring: ring).hint.contains("← →"))
        #expect(feedback(ring: ring, keys: false).hint.contains("Enable a gesture"))
    }

    @Test func mouseSelectionOffersReleaseInsteadOfReturn() {
        let value = feedback(.wedge(index: 2, action: .rightHalf))
        #expect(value.hint == "Release to snap")
    }

    @Test func olderSettingsGainActionLabelsThroughMigration() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TesseraSettings.defaults)) as! [String: Any]
        var ring = object["ring"] as! [String: Any]
        ring["showActionLabels"] = nil
        object["ring"] = ring
        let data = try JSONSerialization.data(withJSONObject: object)
        let migrated = try SettingsMigration.migrate(data)
        let settings = try JSONDecoder().decode(TesseraSettings.self, from: migrated.data)
        #expect(settings.ring.showActionLabels)
    }
}
