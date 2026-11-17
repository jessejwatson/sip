import Foundation

struct DrinkEntry: Codable, Sendable, Hashable, Identifiable {
    var id = UUID()
    var timestamp: Date
    var amountML: Int
}

/// Everything stored in history.json.
struct History: Codable, Sendable, Equatable {
    var entries: [DrinkEntry] = []
    /// `yyyy-MM-dd` keys for days marked as leave or sick.
    var excludedDays: Set<String> = []
    /// Goal in effect on each day something was logged, keyed by `yyyy-MM-dd`.
    var dailyGoals: [String: Int] = [:]
}

/// Volume formatting shared by the menu, notifications and onboarding.
enum Volume {
    /// "1.2 L" or "41 oz", for totals and goals.
    static func total(_ ml: Int, in unit: VolumeUnit) -> String {
        "\(totalValue(ml, in: unit)) \(unit == .ml ? "L" : "oz")"
    }

    /// "1.2", "0.75", "2" litres with one or two decimals as needed, or whole ounces.
    static func totalValue(_ ml: Int, in unit: VolumeUnit) -> String {
        switch unit {
        case .ml: (Double(ml) / 1000).formatted(.number.precision(.fractionLength(1...2)))
        case .oz: unit.value(ml).formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// "250 ml" or "16.9 oz", for single drinks.
    static func amount(_ ml: Int, in unit: VolumeUnit) -> String {
        switch unit {
        case .ml: "\(ml) ml"
        case .oz: "\(unit.value(ml).formatted(.number.precision(.fractionLength(0...1)))) oz"
        }
    }
}
