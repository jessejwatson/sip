import Foundation
import Testing
@testable import Sip

@MainActor
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(minutes: Int) { now = now.addingTimeInterval(Double(minutes * 60)) }
}

@MainActor
func makeStore(clock: TestClock, directory: URL? = nil) -> (Store, URL) {
    let dir = directory ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("SipTests-\(UUID().uuidString)", isDirectory: true)
    let suite = "SipTests-\(dir.lastPathComponent)"
    let store = Store(defaults: UserDefaults(suiteName: suite)!, directory: dir,
                      calendar: testCalendar, now: { clock.now })
    return (store, dir)
}

@MainActor
@Suite("Store")
struct StoreTests {
    @Test func todayTotalAndUndo() {
        let clock = TestClock(at(10))
        let (store, _) = makeStore(clock: clock)
        store.log(750)
        clock.advance(minutes: 30)
        store.log(250)
        #expect(store.todayTotal == 1000)
        store.undoLast()
        #expect(store.todayTotal == 750)
        store.log(0)
        store.log(-5)
        #expect(store.todayEntries.count == 1)
    }

    @Test func rolloverAcrossMidnight() {
        let clock = TestClock(on(9, 23, 50))
        let (store, _) = makeStore(clock: clock)
        store.log(500)
        #expect(store.todayTotal == 500)
        clock.advance(minutes: 20)
        store.refreshDay()
        #expect(store.todayTotal == 0)
        #expect(store.todayEntries.isEmpty)
        #expect(store.total(on: on(9, 12)) == 500)
        // Undo after midnight only affects the new day.
        store.undoLast()
        #expect(store.total(on: on(9, 12)) == 500)
    }

    @Test func excludedDays() {
        let clock = TestClock(at(10))
        let (store, _) = makeStore(clock: clock)
        #expect(!store.isTodayOff)
        store.setExcluded(true, on: store.today)
        #expect(store.isTodayExcluded)
        #expect(store.status(on: store.today) == .off)
        store.setExcluded(false, on: store.today)
        #expect(!store.isTodayExcluded)
        #expect(store.status(on: on(14, 10)) == .off) // Saturday
    }

    @Test func goalSnapshotsProtectPastDays() {
        let clock = TestClock(on(9, 10))
        let (store, _) = makeStore(clock: clock)
        store.settings.goalML = 1000
        store.log(1000)
        #expect(store.status(on: on(9, 12)) == .met)

        // Next day: raise the goal. Monday still counts as met.
        clock.now = on(10, 10)
        store.refreshDay()
        store.settings.goalML = 2000
        #expect(store.goal(on: on(9, 12)) == 1000)
        #expect(store.status(on: on(9, 12)) == .met)
        #expect(store.todayGoal == 2000)

        store.log(500)
        #expect(store.status(on: store.today) == .partial)
        // Changing the goal later today updates today's snapshot.
        store.settings.goalML = 500
        #expect(store.history.dailyGoals["2026-11-10"] == 500)
        #expect(store.status(on: store.today) == .met)
        #expect(store.status(on: on(11, 12)) == .none)
    }

    @Test func persistsAcrossRelaunch() {
        let clock = TestClock(at(10))
        let (store, dir) = makeStore(clock: clock)
        store.log(600)
        store.setExcluded(true, on: on(11, 12))

        let reloaded = Store(defaults: UserDefaults(suiteName: "SipTests-\(dir.lastPathComponent)")!,
                             directory: dir, calendar: testCalendar, now: { clock.now })
        #expect(reloaded.todayTotal == 600)
        #expect(reloaded.isExcluded(on(11, 12)))
    }

    @Test func settingsPersist() {
        let clock = TestClock(at(10))
        let (store, dir) = makeStore(clock: clock)
        store.settings.goalML = 1750
        store.settings.hasOnboarded = true
        let reloaded = Store(defaults: UserDefaults(suiteName: "SipTests-\(dir.lastPathComponent)")!,
                             directory: dir, calendar: testCalendar, now: { clock.now })
        #expect(reloaded.settings.goalML == 1750)
        #expect(reloaded.settings.hasOnboarded)
    }

    @Test func csvOutput() {
        let clock = TestClock(on(10, 9, 5))
        let (store, _) = makeStore(clock: clock)
        store.log(250)
        clock.now = on(9, 14, 30) // earlier day, logged later: export is sorted
        store.log(750)
        #expect(store.csv() == """
            date,time,amount_ml
            2026-11-09,14:30:00,750
            2026-11-10,09:05:00,250

            """)
    }

    @Test func resetAll() {
        let clock = TestClock(at(10))
        let (store, _) = makeStore(clock: clock)
        store.settings.hasOnboarded = true
        store.log(500)
        store.resetAll()
        #expect(store.history == History())
        #expect(!store.settings.hasOnboarded)
    }
}

@MainActor
@Suite("Reminder engine")
struct ReminderEngineTests {
    final class Sent { var count = 0 }

    func makeEngine(clock: TestClock, present: @escaping () -> Bool = { true }) -> (Store, ReminderEngine, Sent) {
        let (store, _) = makeStore(clock: clock)
        store.settings.goalML = 1500
        let sent = Sent()
        let engine = ReminderEngine(store: store, isPresent: present, send: { _ in sent.count += 1 })
        return (store, engine, sent)
    }

    @Test func remindsAtMostOncePerInterval() {
        let clock = TestClock(at(11))
        let (_, engine, sent) = makeEngine(clock: clock)
        for _ in 0..<90 {
            engine.tick()
            clock.advance(minutes: 1)
        }
        // Ticks cover 11:00–12:29: reminders at 11:00 and 11:45 only.
        #expect(sent.count == 2)
    }

    @Test func noBurstAfterUnlock() {
        let clock = TestClock(at(9))
        var present = false
        let (_, engine, sent) = makeEngine(clock: clock, present: { present })
        // Away for three hours while falling far behind.
        for _ in 0..<180 {
            engine.tick()
            clock.advance(minutes: 1)
        }
        #expect(sent.count == 0)

        present = true
        engine.userReturned()
        for _ in 0..<10 {
            engine.tick()
            clock.advance(minutes: 1)
        }
        #expect(sent.count == 0)
        engine.tick() // 10 minutes after return
        #expect(sent.count == 1)
        for _ in 0..<30 {
            clock.advance(minutes: 1)
            engine.tick()
        }
        #expect(sent.count == 1)
    }

    @Test func snoozeDelaysThirtyMinutes() {
        let clock = TestClock(at(11))
        let (_, engine, sent) = makeEngine(clock: clock)
        engine.tick()
        #expect(sent.count == 1)
        clock.advance(minutes: 2)
        engine.snooze()
        for _ in 0..<29 {
            clock.advance(minutes: 1)
            engine.tick()
        }
        #expect(sent.count == 1)
        clock.advance(minutes: 1)
        engine.tick()
        #expect(sent.count == 2)
    }

    @Test func loggingStopsReminders() {
        let clock = TestClock(at(11))
        let (store, engine, sent) = makeEngine(clock: clock)
        store.log(1500)
        for _ in 0..<120 {
            engine.tick()
            clock.advance(minutes: 1)
        }
        #expect(sent.count == 0)
    }
}

@Suite("Vessel order")
struct VesselOrderTests {
    private func settings() -> UserSettings {
        var s = UserSettings()
        s.vessels = ["A", "B", "C"].map { Vessel(name: $0, amountML: 250) }
        return s
    }

    private func names(_ s: UserSettings) -> [String] { s.vessels.map(\.name) }

    @Test func dragDownTakesTargetsPlace() {
        var s = settings()
        s.moveVessel(s.vessels[0].id, to: s.vessels[2].id)
        #expect(names(s) == ["B", "C", "A"])
    }

    @Test func dragUpTakesTargetsPlace() {
        var s = settings()
        s.moveVessel(s.vessels[2].id, to: s.vessels[0].id)
        #expect(names(s) == ["C", "A", "B"])
    }

    @Test func dropOnItselfOrUnknownDoesNothing() {
        var s = settings()
        s.moveVessel(s.vessels[1].id, to: s.vessels[1].id)
        s.moveVessel(UUID(), to: s.vessels[0].id)
        #expect(names(s) == ["A", "B", "C"])
    }
}
