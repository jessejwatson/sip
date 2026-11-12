import AppKit

/// Tracks whether the user is at the machine: screen unlocked and awake.
@MainActor
final class PresenceMonitor {
    private(set) var isLocked = false
    private(set) var isAsleep = false
    var isPresent: Bool { !isLocked && !isAsleep }

    /// Called when the user becomes present again after being away.
    var onReturn: (() -> Void)?

    /// Only mutated on the main actor; read once more in deinit.
    nonisolated(unsafe) private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter

        observe(distributed, "com.apple.screenIsLocked") { $0.isLocked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.isLocked = false }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.isAsleep = false }
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ update: @escaping @MainActor (PresenceMonitor) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasPresent = self.isPresent
                update(self)
                if !wasPresent, self.isPresent { self.onReturn?() }
            }
        }
        tokens.append((center, token))
    }

    deinit {
        for (center, token) in tokens { center.removeObserver(token) }
    }
}
