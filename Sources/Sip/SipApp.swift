import AppKit
import SwiftUI

@main
struct SipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar panel and every window are managed by AppModel. SwiftUI needs a scene, and an
        // empty Settings scene opens a blank window at launch, so use a menu bar extra that's never shown.
        MenuBarExtra("Sip", systemImage: "drop", isInserted: .constant(false)) { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            #if DEBUG
            if let dir = ProcessInfo.processInfo.environment["SIP_SNAPSHOT_DIR"] {
                Snapshot.run(to: URL(fileURLWithPath: dir))
                exit(0)
            }
            #endif
            model.start()
        }
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
    @ObservationIgnored private var statusItem: StatusItemController?
    @ObservationIgnored private var onboardingWindow: NSWindow?
    @ObservationIgnored private var settingsWindow: NSWindow?
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
        statusItem = StatusItemController(model: self)

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
            onboardingWindow = makeWindow(title: "Welcome to Sip", content: OnboardingView())
        }
        present(onboardingWindow)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Sip Settings", content: SettingsView())
        }
        present(settingsWindow)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let host = NSHostingController(rootView: content.environment(self).environment(store))
        // Size the window to the SwiftUI content, and follow it if the content changes size.
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        statusItem?.close()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func resetAllData() {
        store.resetAll()
        LoginItem.setEnabled(false)
        showOnboarding()
    }
}
