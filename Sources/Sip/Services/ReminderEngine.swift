import Foundation

/// Ticks every 60 s and asks `ReminderPolicy` whether to nudge the user.
@MainActor
final class ReminderEngine {
    struct Reminder: Equatable, Sendable {
        var totalML: Int
        var goalML: Int
    }

    private let store: Store
    private let isPresent: () -> Bool
    private let send: (Reminder) -> Void
    private var timer: Timer?

    private(set) var lastReminderAt: Date?
    private(set) var snoozeUntil: Date?
    private(set) var lastDecision: ReminderDecision?

    init(store: Store, isPresent: @escaping () -> Bool, send: @escaping (Reminder) -> Void) {
        self.store = store
        self.isPresent = isPresent
        self.send = send
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        store.refreshDay()
        let context = ReminderContext(
            now: store.now(),
            calendar: store.calendar,
            settings: store.settings,
            isExcludedDay: store.isTodayExcluded,
            totalTodayML: store.todayTotal,
            goalTodayML: store.todayGoal,
            lastDrinkAt: store.lastDrinkAt,
            lastReminderAt: lastReminderAt,
            snoozeUntil: snoozeUntil,
            isPresent: isPresent()
        )
        let decision = ReminderPolicy.decide(context)
        lastDecision = decision
        guard decision == .remind else { return }
        lastReminderAt = context.now
        snoozeUntil = nil
        send(Reminder(totalML: context.totalTodayML, goalML: context.goalTodayML))
    }

    func snooze() {
        snoozeUntil = store.now().addingTimeInterval(Double(Pacing.snoozeMinutes * 60))
    }

    /// Called on unlock or wake. Never catch up on reminders missed while away.
    func userReturned() {
        lastReminderAt = ReminderPolicy.lastReminderAfterReturn(
            now: store.now(),
            intervalMinutes: store.settings.reminderIntervalMinutes,
            existing: lastReminderAt
        )
    }
}
