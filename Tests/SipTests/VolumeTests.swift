import Foundation
import SwiftUI
import Testing
@testable import Sip

@Suite("Volume")
struct VolumeTests {
    @Test func automaticUnitFollowsRegion() {
        #expect(VolumeUnit.automatic(for: Locale(identifier: "en_US")) == .oz)
        #expect(VolumeUnit.automatic(for: Locale(identifier: "en_AU")) == .ml)
        #expect(VolumeUnit.automatic(for: Locale(identifier: "en_GB")) == .ml)
    }

    @Test func formatting() {
        #expect(Volume.amount(250, in: .ml) == "250 ml")
        #expect(Volume.amount(500, in: .oz) == "16.9 oz")
        #expect(Volume.amount(237, in: .oz) == "8 oz")
        #expect(Volume.total(1150, in: .ml) == "1.15 L")
        #expect(Volume.total(1150, in: .oz) == "39 oz")
    }

    @Test func ouncesRoundTrip() {
        #expect(VolumeUnit.oz.millilitres(16.9) == 500)
        #expect(VolumeUnit.oz.millilitres(VolumeUnit.oz.value(750)) == 750)
        #expect(VolumeUnit.ml.millilitres(250) == 250)
    }

    @MainActor
    @Test func goalBindingSnapsToWholeOunces() {
        var goal = 1150
        let binding = Binding(get: { goal }, set: { goal = $0 }).goal(in: .oz)
        #expect(binding.wrappedValue == 39)
        binding.wrappedValue = 40
        #expect(goal == 1183)
    }

    @Test func settingsSavedBeforeUnitsStillDecode() throws {
        var old = UserSettings()
        old.goalML = 1800
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "volumeUnit")
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.goalML == 1800)
        #expect(decoded.volumeUnit == nil)
    }
}
