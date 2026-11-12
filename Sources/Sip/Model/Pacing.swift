import Foundation

/// Pure pacing and reminder logic. No side effects, no clocks — everything is passed in.
enum Pacing {
    static let behindThresholdML = 200
    /// The goal should be reached this long before the end of the work day; no reminders in this window.
    static let finalWindowMinutes = 30
    static let recentDrinkMinutes = 20
    static let returnGraceMinutes = 10
    static let snoozeMinutes = 30

    // MARK: Recommendation

    /// 2300 ml × (workHours / 16), rounded to the nearest 50 ml and clamped to 500–2000 ml.
    static func recommendedGoal(workMinutes: Int) -> Int {
        let raw = 2300.0 * (Double(workMinutes) / 60.0) / 16.0
        let rounded = Int((raw / 50.0).rounded()) * 50
        return min(2000, max(500, rounded))
    }

    // MARK: Expected intake

    /// Linear ramp from 0 at `start` to `goal` at `end − 30 min`; 0 before start, the full goal after.
    static func expected(goalML: Int, start: TimeOfDay, end: TimeOfDay, nowMinutes: Double) -> Int {
        let startM = Double(start.minutesSinceMidnight)
        let rampEnd = Double(end.minutesSinceMidnight - finalWindowMinutes)
        if nowMinutes < startM { return 0 }
        if nowMinutes >= rampEnd || rampEnd <= startM { return goalML }
        let fraction = (nowMinutes - startM) / (rampEnd - startM)
        return Int((Double(goalML) * fraction).rounded())
    }

    static func expected(goalML: Int, settings: UserSettings, now: Date, calendar: Calendar) -> Int {
        expected(goalML: goalML, start: settings.startTime, end: settings.endTime,
                 nowMinutes: minutesSinceMidnight(now, calendar: calendar))
    }

    static func isBehind(expectedML: Int, actualML: Int) -> Bool {
        expectedML - actualML >= behindThresholdML
    }

    static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date)) / 60
    }
}

// MARK: - Reminder decisions

struct ReminderContext: Sendable {
    var now: Date
    var calendar: Calendar
    var settings: UserSettings
    var isExcludedDay: Bool
    var totalTodayML: Int
    var goalTodayML: Int
    var lastDrinkAt: Date?
    var lastReminderAt: Date?
    var snoozeUntil: Date?
    var isPresent: Bool
}

enum ReminderDecision: Equatable, Sendable {
    case remind
    case suppressed(Reason)

    enum Reason: Equatable, Sendable {
        case notWorkDay, excludedDay, outsideWorkHours, finalWindow, goalMet, onPace
        case recentDrink, tooSoon, snoozed, away
    }
}

enum ReminderPolicy {
    static func decide(_ c: ReminderContext) -> ReminderDecision {
        let s = c.settings
        guard s.workDays.contains(Weekday(of: c.now, calendar: c.calendar)) else { return .suppressed(.notWorkDay) }
        guard !c.isExcludedDay else { return .suppressed(.excludedDay) }

        let nowM = Pacing.minutesSinceMidnight(c.now, calendar: c.calendar)
        let startM = Double(s.startTime.minutesSinceMidnight)
        let endM = Double(s.endTime.minutesSinceMidnight)
        guard s.hasValidHours, nowM >= startM, nowM < endM else { return .suppressed(.outsideWorkHours) }
        guard nowM < endM - Double(Pacing.finalWindowMinutes) else { return .suppressed(.finalWindow) }

        guard c.totalTodayML < c.goalTodayML else { return .suppressed(.goalMet) }
        let expected = Pacing.expected(goalML: c.goalTodayML, start: s.startTime, end: s.endTime, nowMinutes: nowM)
        guard Pacing.isBehind(expectedML: expected, actualML: c.totalTodayML) else { return .suppressed(.onPace) }

        if let last = c.lastDrinkAt, c.now.timeIntervalSince(last) < Double(Pacing.recentDrinkMinutes * 60) {
            return .suppressed(.recentDrink)
        }

        if let snooze = c.snoozeUntil {
            // An expired snooze is its own trigger; the interval doesn't apply on top of it.
            if c.now < snooze { return .suppressed(.snoozed) }
        } else if let last = c.lastReminderAt,
                  c.now.timeIntervalSince(last) < Double(s.reminderIntervalMinutes * 60) {
            return .suppressed(.tooSoon)
        }

        guard c.isPresent else { return .suppressed(.away) }
        return .remind
    }

    /// When the user comes back (unlock or wake), don't catch up on missed reminders: pretend the last
    /// one was sent such that the next becomes possible ~10 minutes from now.
    static func lastReminderAfterReturn(now: Date, intervalMinutes: Int, existing: Date?) -> Date {
        let shifted = now.addingTimeInterval(Double((Pacing.returnGraceMinutes - intervalMinutes) * 60))
        guard let existing else { return shifted }
        return max(existing, shifted)
    }
}
