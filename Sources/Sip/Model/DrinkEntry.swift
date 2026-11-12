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
    /// "1.2", "0.75", "2" — litres with one or two decimals as needed.
    static func litres(_ ml: Int) -> String {
        let litres = Double(ml) / 1000
        return litres.formatted(.number.precision(.fractionLength(1...2)))
    }

    static func ml(_ ml: Int) -> String { "\(ml) ml" }
}
