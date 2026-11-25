import StayLitCore
import UserNotifications

/// Posts the guards' notifications through the system notification center.
/// The end of a timer posts nothing: the user chose the duration. A refusal costs nothing:
/// the window shows the same news.
nonisolated struct UserNotificationSleepRestoreNotifier: SleepRestoreNotifying {
    /// Asks for the right to notify, only while the user has not answered yet. Returns at once.
    /// Called when the user turns a guard on and when the status window opens with one on,
    /// never at launch; the first notification also asks.
    func requestPermission() {
        Task { _ = await Self.isAllowedToNotify() }
    }

    func notifySleepRestored(_ reason: RestoreReason) {
        let identifier: String
        let body: String
        switch reason {
        case .timer:
            return
        case .lowBattery(let percent):
            identifier = "low-battery"
            body = "The battery is at \(percent)%, so Stay Lit allowed sleep again. Plug in the charger and it turns back on when you use the Mac."
        case .highTemperature:
            identifier = "high-temperature"
            body = "The Mac is too hot, so Stay Lit allowed sleep again."
        case .claudeFinished:
            identifier = "claude-finished"
            body = "Claude Code has finished, so Stay Lit allowed sleep again."
        }
        Task {
            guard await Self.isAllowedToNotify() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Sleep turned back on"
            content.body = body
            // Same identifier per guard: a second notification replaces the first instead of piling up.
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Asks the first time only: the system remembers the answer.
    private static func isAllowedToNotify() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert])) ?? false
        default:
            return false
        }
    }
}
