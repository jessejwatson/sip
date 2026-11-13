#if DEBUG
import AppKit
import SwiftUI

/// Renders the popover offscreen to PNGs for UI review, using throwaway seeded data.
/// Usage: SIP_SNAPSHOT_DIR=/some/dir swift run Sip
@MainActor
enum Snapshot {
    static func run(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scenario in Scenario.allCases {
            let model = scenario.makeModel()
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = MenuContent()
                    .environment(model)
                    .environment(model.store)
                render(view, appearance: appearance,
                       to: directory.appendingPathComponent("menu-\(scenario)-\(suffix).png"))
            }
        }
        let model = Scenario.empty.makeModel()
        let settingsModel = Scenario.onTrack.makeModel()
        settingsModel.notifications.permission = .off
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(OnboardingView().environment(model).environment(model.store), appearance: appearance,
                   to: directory.appendingPathComponent("onboarding-\(suffix).png"))
            render(SettingsView().environment(settingsModel).environment(settingsModel.store), appearance: appearance,
                   to: directory.appendingPathComponent("settings-\(suffix).png"))
        }
    }

    enum Scenario: String, CaseIterable, CustomStringConvertible {
        case behind, onTrack, met, empty, leave
        var description: String { rawValue }

        @MainActor func makeModel() -> AppModel {
            let calendar = Calendar.current
            var clock = calendar.date(bySettingHour: 13, minute: 10, second: 0, of: Self.lastMonday)!
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SipSnapshot-\(UUID())")
            let defaults = UserDefaults(suiteName: dir.lastPathComponent)!
            let store = Store(defaults: defaults, directory: dir, calendar: calendar, now: { clock })

            var settings = UserSettings()
            settings.hasOnboarded = self != .empty
            settings.goalML = 1500
            settings.vessels = [Vessel(name: "Bottle", amountML: 750), Vessel(name: "Cup", amountML: 250)]
            store.settings = settings

            // Previous week: a mix of met, partial and empty days.
            for (offset, amount) in [(-7, 1500), (-6, 750), (-5, 1500), (-4, 0), (-3, 1750)] where amount > 0 {
                clock = calendar.date(byAdding: .day, value: offset, to: clock)!
                store.log(amount)
                clock = calendar.date(byAdding: .day, value: -offset, to: clock)!
            }
            let today: Int = switch self {
            case .behind: 250
            case .onTrack: 1000
            case .met: 1500
            case .empty: 0
            case .leave: 500
            }
            if today > 0 { store.log(today) }
            if self == .leave { store.setExcluded(true, on: store.today) }
            store.refreshDay()
            let model = AppModel(store: store)
            // Show the warning states: notifications turned off.
            if self == .behind { model.notifications.permission = .off }
            return model
        }

        private static var lastMonday: Date {
            let cal = Calendar.current
            var date = cal.startOfDay(for: Date())
            while cal.component(.weekday, from: date) != 2 { date = cal.date(byAdding: .day, value: -1, to: date)! }
            return date
        }
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
#endif
