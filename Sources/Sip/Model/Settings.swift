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

    var workMinutes: Int { max(0, endTime.minutesSinceMidnight - startTime.minutesSinceMidnight) }
    var hasValidHours: Bool { endTime > startTime }
    var recommendedGoalML: Int { Pacing.recommendedGoal(workMinutes: workMinutes) }
}
