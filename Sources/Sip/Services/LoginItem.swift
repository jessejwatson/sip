import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Sip: failed to update login item: \(error)")
        }
    }
}
