import Foundation
import Observation

enum DayStatus: Equatable, Sendable {
    case met, partial, none, off
}

@MainActor
@Observable
final class Store {
    static let bundleID = "com.jessejwatson.sip"
    private static let settingsKey = "settings"

    var settings: UserSettings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            // Today's result follows the current goal; past days keep their snapshot.
            if settings.goalML != oldValue.goalML, history.dailyGoals[key(for: today)] != nil {
                history.dailyGoals[key(for: today)] = settings.goalML
                saveHistory()
            }
            onSettingsChange?(oldValue, settings)
        }
    }

    private(set) var history: History
    /// Start of the current local day. Updated by `refreshDay()` so views re-render at midnight.
    private(set) var today: Date

    @ObservationIgnored var onSettingsChange: ((UserSettings, UserSettings) -> Void)?
    @ObservationIgnored private(set) var lastSaveError: Error?

    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let historyURL: URL

    init(
        defaults: UserDefaults = .standard,
        directory: URL = Store.defaultDirectory,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.historyURL = directory.appendingPathComponent("history.json")
        self.calendar = calendar
        self.now = now
        self.today = calendar.startOfDay(for: now())

        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            settings = decoded
        } else {
            settings = UserSettings()
        }

        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? Self.decoder.decode(History.self, from: data) {
            history = decoded
        } else {
            history = History()
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // MARK: Day handling

    func refreshDay() {
        let start = calendar.startOfDay(for: now())
        if start != today { today = start }
    }

    func key(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func entries(on day: Date) -> [DrinkEntry] {
        history.entries.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
    }

    func total(on day: Date) -> Int {
        entries(on: day).reduce(0) { $0 + $1.amountML }
    }

    /// The goal that applied on `day`: today uses the current goal, past days their snapshot.
    func goal(on day: Date) -> Int {
        if calendar.isDate(day, inSameDayAs: today) { return settings.goalML }
        return history.dailyGoals[key(for: day)] ?? settings.goalML
    }

    func isExcluded(_ day: Date) -> Bool { history.excludedDays.contains(key(for: day)) }

    func isWorkDay(_ day: Date) -> Bool { settings.workDays.contains(Weekday(of: day, calendar: calendar)) }

    func status(on day: Date) -> DayStatus {
        if !isWorkDay(day) || isExcluded(day) { return .off }
        let total = total(on: day)
        if total == 0 { return .none }
        return total >= goal(on: day) ? .met : .partial
    }

    // MARK: Today

    var todayTotal: Int { total(on: today) }
    var todayGoal: Int { goal(on: today) }
    var todayEntries: [DrinkEntry] { entries(on: today) }
    var isTodayExcluded: Bool { isExcluded(today) }
    var isTodayOff: Bool { !isWorkDay(today) || isTodayExcluded }
    var todayFraction: Double {
        todayGoal > 0 ? Double(todayTotal) / Double(todayGoal) : 0
    }
    var lastDrinkAt: Date? { history.entries.map(\.timestamp).max() }

    // MARK: Mutations

    func log(_ amountML: Int) {
        guard amountML > 0 else { return }
        refreshDay()
        let timestamp = now()
        history.entries.append(DrinkEntry(timestamp: timestamp, amountML: amountML))
        history.dailyGoals[key(for: timestamp)] = settings.goalML
        saveHistory()
    }

    func undoLast() {
        refreshDay()
        guard let last = todayEntries.max(by: { $0.timestamp < $1.timestamp }) else { return }
        history.entries.removeAll { $0.id == last.id }
        saveHistory()
    }

    func setExcluded(_ excluded: Bool, on day: Date) {
        let k = key(for: day)
        if excluded { history.excludedDays.insert(k) } else { history.excludedDays.remove(k) }
        saveHistory()
    }

    func resetAll() {
        history = History()
        settings = UserSettings()
        saveHistory()
    }

    // MARK: Export

    func csv() -> String {
        var lines = ["date,time,amount_ml"]
        for entry in history.entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let c = calendar.dateComponents([.hour, .minute, .second], from: entry.timestamp)
            let time = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            lines.append("\(key(for: entry.timestamp)),\(time),\(entry.amountML)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    private func saveHistory() {
        do {
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(history).write(to: historyURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = error
            NSLog("Sip: failed to save history: \(error)")
        }
    }
}
