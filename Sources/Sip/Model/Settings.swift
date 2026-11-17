import Foundation

/// Matches `Calendar.component(.weekday, from:)`: 1 = Sunday … 7 = Saturday.
enum Weekday: Int, Codable, CaseIterable, Sendable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// Monday-first ordering for display.
    static let displayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    var initial: String { String(shortName.prefix(1)) }

    init(of date: Date, calendar: Calendar) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }
}

struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// This time on the same calendar day as `day`.
    func date(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

/// How volumes are shown and entered. Amounts are always stored in millilitres.
enum VolumeUnit: String, Codable, CaseIterable, Sendable {
    case ml, oz

    static let mlPerOz = 29.5735

    /// Fluid ounces where the region uses US customary units, millilitres everywhere else.
    static func automatic(for locale: Locale = .current) -> VolumeUnit {
        locale.measurementSystem == .us ? .oz : .ml
    }

    /// Step for goal steppers and sliders.
    var goalStep: Double { self == .ml ? 50 : 1 }
    var goalRange: ClosedRange<Double> { self == .ml ? 250...5000 : 8...170 }
    var goalSliderRange: ClosedRange<Double> { self == .ml ? 250...4000 : 8...135 }

    /// A millilitre amount in this unit.
    func value(_ ml: Int) -> Double { self == .ml ? Double(ml) : Double(ml) / Self.mlPerOz }

    /// An amount in this unit, in whole millilitres.
    func millilitres(_ value: Double) -> Int { Int((self == .ml ? value : value * Self.mlPerOz).rounded()) }
}

struct Vessel: Codable, Sendable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amountML: Int
}

/// User preferences, persisted to UserDefaults as one Codable blob.
struct UserSettings: Codable, Sendable, Equatable {
    var workDays: Set<Weekday> = Weekday.weekdays
    var startTime = TimeOfDay(hour: 8, minute: 30)
    var endTime = TimeOfDay(hour: 16, minute: 30)
    var goalML: Int = 1150
    var vessels: [Vessel] = [Vessel(name: "Bottle", amountML: 750)]
    var reminderIntervalMinutes: Int = 45
    var hasOnboarded = false
    /// nil follows the region. Optional so settings saved before this existed still decode.
    var volumeUnit: VolumeUnit?

    var workMinutes: Int { max(0, endTime.minutesSinceMidnight - startTime.minutesSinceMidnight) }
    var hasValidHours: Bool { endTime > startTime }
    var recommendedGoalML: Int { Pacing.recommendedGoal(workMinutes: workMinutes) }
    var unit: VolumeUnit { volumeUnit ?? .automatic() }

    /// Puts a vessel where the target vessel is, shifting the others along.
    mutating func moveVessel(_ id: Vessel.ID, to targetID: Vessel.ID) {
        guard id != targetID,
              let from = vessels.firstIndex(where: { $0.id == id }),
              let to = vessels.firstIndex(where: { $0.id == targetID }) else { return }
        vessels.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }
}
