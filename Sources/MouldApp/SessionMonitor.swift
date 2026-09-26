import AppKit
import MouldCore

/// Watches for lock screen, screensaver, display sleep, system sleep and fast user switching.
@MainActor
final class SessionMonitor {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(onReset: @escaping @MainActor (ResetTrigger) -> Void) {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        for trigger in ResetTrigger.allCases {
            let pairs: [(NotificationCenter, String?)] = [
                (distributed, trigger.distributedNotificationName),
                (workspace, trigger.workspaceNotificationName),
            ]
            for case let (center, name?) in pairs {
                let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { onReset(trigger) }
                }
                tokens.append((center, token))
            }
        }
    }

    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }
}
