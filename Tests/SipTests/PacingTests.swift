import Foundation
import Testing
@testable import Sip

/// Fixed calendar so tests don't depend on the machine's time zone.
let testCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Australia/Sydney")!
    c.locale = Locale(identifier: "en_AU")
    return c
}()

/// A time on day `day` of November 2026 (the 9th is a Monday, the 14th a Saturday).
func on(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// A time on Monday 9 November 2026.
func at(_ hour: Int, _ minute: Int = 0) -> Date { on(9, hour, minute) }

@Suite("Recommendation")
struct RecommendationTests {
    @Test func defaultHours() {
        // 8 h → 2300 × 0.5 = 1150
        #expect(Pacing.recommendedGoal(workMinutes: 8 * 60) == 1150)
    }

    @Test func roundsToNearest50() {
        // 7.5 h → 1078.125 → 1100
        #expect(Pacing.recommendedGoal(workMinutes: 450) == 1100)
        // 7 h → 1006.25 → 1000
        #expect(Pacing.recommendedGoal(workMinutes: 420) == 1000)
        // 9.5 h → 1365.625 → 1350
        #expect(Pacing.recommendedGoal(workMinutes: 570) == 1350)
    }

    @Test func clampsToRange() {
        #expect(Pacing.recommendedGoal(workMinutes: 60) == 500)
        #expect(Pacing.recommendedGoal(workMinutes: 0) == 500)
        #expect(Pacing.recommendedGoal(workMinutes: 16 * 60) == 2000)
        #expect(Pacing.recommendedGoal(workMinutes: 24 * 60) == 2000)
    }

    @Test func changesWithSettingsHours() {
        var s = UserSettings()
        let before = s.recommendedGoalML
        s.endTime = TimeOfDay(hour: 18, minute: 30)
        #expect(s.recommendedGoalML > before)
    }
}

@Suite("Expected by now")
struct ExpectedTests {
    let start = TimeOfDay(hour: 8, minute: 30)
    let end = TimeOfDay(hour: 16, minute: 30)

    func expected(_ hour: Int, _ minute: Int = 0) -> Int {
        Pacing.expected(goalML: 1500, start: start, end: end, nowMinutes: Double(hour * 60 + minute))
    }

    @Test func beforeStartIsZero() {
        #expect(expected(7) == 0)
        #expect(expected(8, 29) == 0)
        #expect(expected(8, 30) == 0)
    }

    @Test func midDayIsLinear() {
        // Ramp is 8:30 → 16:00 (450 min). 12:15 is halfway.
        #expect(expected(12, 15) == 750)
        #expect(expected(10, 0) == 300)
    }

    @Test func lastThirtyMinutesIsFullGoal() {
        #expect(expected(16, 0) == 1500)
        #expect(expected(16, 15) == 1500)
    }

    @Test func afterEndIsFullGoal() {
        #expect(expected(18) == 1500)
    }

    @Test func behindThreshold() {
        #expect(Pacing.isBehind(expectedML: 700, actualML: 500))
        #expect(!Pacing.isBehind(expectedML: 699, actualML: 500))
        #expect(!Pacing.isBehind(expectedML: 500, actualML: 900))
    }

    @Test func tinyWorkWindowDoesNotDivideByZero() {
        let e = Pacing.expected(goalML: 1000, start: TimeOfDay(hour: 9, minute: 0),
                                end: TimeOfDay(hour: 9, minute: 20), nowMinutes: 545)
        #expect(e == 1000)
    }
}

@Suite("Reminder decisions")
struct ReminderPolicyTests {
    /// A context that would remind: Monday 12:15, nothing drunk, present, no history.
    func context(_ now: Date = at(12, 15)) -> ReminderContext {
        var settings = UserSettings()
        settings.goalML = 1500
        return ReminderContext(
            now: now, calendar: testCalendar, settings: settings, isExcludedDay: false,
            totalTodayML: 0, goalTodayML: 1500, lastDrinkAt: nil, lastReminderAt: nil,
            snoozeUntil: nil, isPresent: true)
    }

    @Test func baselineReminds() {
        #expect(ReminderPolicy.decide(context()) == .remind)
    }

    @Test func notWorkDay() {
        #expect(ReminderPolicy.decide(context(on(14, 12))) == .suppressed(.notWorkDay)) // Saturday
    }

    @Test func excludedDay() {
        var c = context()
        c.isExcludedDay = true
        #expect(ReminderPolicy.decide(c) == .suppressed(.excludedDay))
    }

    @Test func outsideWorkHours() {
        #expect(ReminderPolicy.decide(context(at(7))) == .suppressed(.outsideWorkHours))
        #expect(ReminderPolicy.decide(context(at(17))) == .suppressed(.outsideWorkHours))
    }

    @Test func invalidHoursNeverRemind() {
        var c = context()
        c.settings.endTime = TimeOfDay(hour: 8, minute: 0)
        #expect(ReminderPolicy.decide(c) == .suppressed(.outsideWorkHours))
    }

    @Test func finalWindow() {
        #expect(ReminderPolicy.decide(context(at(16, 10))) == .suppressed(.finalWindow))
    }

    @Test func goalMet() {
        var c = context()
        c.totalTodayML = 1500
        #expect(ReminderPolicy.decide(c) == .suppressed(.goalMet))
    }

    @Test func onPace() {
        var c = context() // expected 750 at 12:15
        c.totalTodayML = 551
        #expect(ReminderPolicy.decide(c) == .suppressed(.onPace))
        c.totalTodayML = 550
        #expect(ReminderPolicy.decide(c) == .remind)
    }

    @Test func recentDrink() {
        var c = context()
        c.lastDrinkAt = at(12, 0)
        #expect(ReminderPolicy.decide(c) == .suppressed(.recentDrink))
        c.lastDrinkAt = at(11, 55)
        #expect(ReminderPolicy.decide(c) == .remind)
    }

    @Test func tooSoonAfterLastReminder() {
        var c = context()
        c.lastReminderAt = at(11, 31)
        #expect(ReminderPolicy.decide(c) == .suppressed(.tooSoon))
        c.lastReminderAt = at(11, 30)
        #expect(ReminderPolicy.decide(c) == .remind)
    }

    @Test func snoozeSuppressesThenAllows() {
        var c = context()
        c.lastReminderAt = at(12, 0)
        c.snoozeUntil = at(12, 30)
        #expect(ReminderPolicy.decide(c) == .suppressed(.snoozed))
        // Once the snooze ends it fires even though the 45-min interval hasn't passed.
        c.now = at(12, 30)
        #expect(ReminderPolicy.decide(c) == .remind)
    }

    @Test func away() {
        var c = context()
        c.isPresent = false
        #expect(ReminderPolicy.decide(c) == .suppressed(.away))
    }

    @Test func returnSetsTenMinuteGrace() {
        let now = at(13)
        let last = ReminderPolicy.lastReminderAfterReturn(now: now, intervalMinutes: 45, existing: at(9))
        #expect(last == at(12, 25))
        var c = context(now)
        c.lastReminderAt = last
        #expect(ReminderPolicy.decide(c) == .suppressed(.tooSoon))
        c.now = at(13, 10)
        #expect(ReminderPolicy.decide(c) == .remind)
    }

    @Test func returnKeepsMoreRecentReminder() {
        let last = ReminderPolicy.lastReminderAfterReturn(now: at(13, 2), intervalMinutes: 45, existing: at(13))
        #expect(last == at(13))
    }
}
