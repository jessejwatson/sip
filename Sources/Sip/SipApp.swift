import AppKit
import SwiftUI

@main
struct SipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(appDelegate.model)
                .environment(appDelegate.model.store)
        } label: {
            MenuBarIcon(store: appDelegate.model.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.model)
                .environment(appDelegate.model.store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { model.start() }
    }
}

/// Owns the long-lived services and wires them together.
@MainActor
@Observable
final class AppModel {
    let store: Store
    @ObservationIgnored let notifications = Notifications()
    @ObservationIgnored let presence = PresenceMonitor()
    @ObservationIgnored private(set) var engine: ReminderEngine!
    @ObservationIgnored private var onboardingWindow: NSWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: Store = Store()) {
        self.store = store
        engine = ReminderEngine(
            store: store,
            isPresent: { [presence] in presence.isPresent },
            send: { [notifications] in notifications.sendReminder(totalML: $0.totalML, goalML: $0.goalML) }
        )
    }

    func start() {
        notifications.configure(firstVessel: store.settings.vessels.first)
        notifications.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .logFirstVessel: self.logFirstVessel()
            case .snooze: self.engine.snooze()
            }
        }

        store.onSettingsChange = { [weak self] old, new in
            guard let self else { return }
            if old.vessels.first != new.vessels.first {
                self.notifications.registerCategory(firstVessel: new.vessels.first)
            }
            self.engine.tick()
        }

        presence.onReturn = { [weak self] in self?.engine.userReturned() }
        presence.start()

        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.refreshDay() }
            })
        }

        engine.start()

        if !store.settings.hasOnboarded { showOnboarding() }
    }

    func log(_ amountML: Int) {
        store.log(amountML)
    }

    func logFirstVessel() {
        guard let vessel = store.settings.vessels.first else { return }
        log(vessel.amountML)
    }

    func finishOnboarding(settings: UserSettings, launchAtLogin: Bool) {
        var settings = settings
        settings.hasOnboarded = true
        store.settings = settings
        LoginItem.setEnabled(launchAtLogin)
        onboardingWindow?.close()
        Task { _ = await notifications.requestAuthorization() }
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView().environment(self).environment(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to Sip"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        onboardingWindow?.center()
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func resetAllData() {
        store.resetAll()
        LoginItem.setEnabled(false)
        showOnboarding()
    }
}

struct MenuBarIcon: View {
    let store: Store

    var body: some View {
        Image(nsImage: Self.image(symbol: symbolName, dimmed: store.isTodayOff))
            .accessibilityLabel("Sip, \(Int((store.todayFraction * 100).rounded()))% of today's goal")
    }

    private var symbolName: String {
        if store.isTodayOff { return "drop" }
        let fraction = store.todayFraction
        if fraction >= 1 { return "drop.fill" }
        if fraction >= 0.34 { return "drop.halffull" }
        return "drop"
    }

    /// Menu bar labels ignore SwiftUI opacity, so dimming is baked into a template image's alpha.
    private static func image(symbol: String, dimmed: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "drop", accessibilityDescription: nil)
            ?? NSImage()
        guard dimmed else {
            base.isTemplate = true
            return base
        }
        let dimmedImage = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        dimmedImage.isTemplate = true
        return dimmedImage
    }
}
