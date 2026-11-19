@testable import StayLitCore

/// Records what the model asked to tell the user. Never posts anything.
@MainActor
final class FakeSleepRestoreNotifier: SleepRestoreNotifying {
    /// Every reason, in order.
    private(set) var notifications: [RestoreReason] = []

    func notifySleepRestored(_ reason: RestoreReason) {
        notifications.append(reason)
    }
}
