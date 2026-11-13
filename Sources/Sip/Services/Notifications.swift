import AppKit
import Observation
import UserNotifications

/// Wraps UNUserNotificationCenter: permission, the reminder category, its actions, and delivery.
@MainActor
@Observable
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let categoryID = "SIP_REMINDER"
    static let logActionID = "LOG_FIRST_VESSEL"
    static let snoozeActionID = "SNOOZE"
    private static let reminderID = "sip.reminder"

    enum Action: Sendable { case logFirstVessel, snooze }

    enum Permission: Sendable {
        /// Not checked yet, or running outside an app bundle.
        case unknown
        case notDetermined
        case allowed
        /// Denied, or allowed with the alert style set to None. Either way reminders arrive silently.
        case off
    }

    @ObservationIgnored var onAction: ((Action) -> Void)?
    var permission: Permission = .unknown

    /// UNUserNotificationCenter crashes outside a bundled app (e.g. `swift run`), so do nothing there.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure(firstVessel: Vessel?) {
        guard let center else { return }
        center.delegate = self
        registerCategory(firstVessel: firstVessel)
    }

    func registerCategory(firstVessel: Vessel?) {
        guard let center else { return }
        var actions: [UNNotificationAction] = []
        if let vessel = firstVessel {
            actions.append(UNNotificationAction(identifier: Self.logActionID, title: "Log \(vessel.name)"))
        }
        actions.append(UNNotificationAction(identifier: Self.snoozeActionID, title: "Snooze 30 min"))
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshPermission()
        return granted
    }

    func refreshPermission() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        permission = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional: settings.alertStyle == .none ? .off : .allowed
        default: .off
        }
    }

    /// Asks for permission if macOS hasn't asked yet; otherwise opens Sip's page in System Settings,
    /// since apps can't ask again after being turned down.
    func turnOn() {
        switch permission {
        case .notDetermined:
            Task { _ = await requestAuthorization() }
        default:
            let id = Bundle.main.bundleIdentifier ?? ""
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func sendReminder(totalML: Int, goalML: Int) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time for a drink"
        content.body = "You're at \(Volume.litres(totalML)) of \(Volume.litres(goalML)) L."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        // Reusing the identifier replaces any earlier reminder rather than stacking them.
        let request = UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: nil)
        center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action: Action? = switch response.actionIdentifier {
        case Self.logActionID: .logFirstVessel
        case Self.snoozeActionID: .snooze
        default: nil
        }
        guard let action else { return }
        await MainActor.run { self.onAction?(action) }
    }
}
