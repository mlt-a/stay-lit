/// Tells the user, outside the window, that the app allowed sleep again by itself.
/// The core carries no text: the app target words the notification, and chooses which reasons
/// deserve one.
///
/// Returns at once and never fails: the model does not wait for the user, and a refused
/// notification changes nothing (the window shows the same news).
@MainActor
public protocol SleepRestoreNotifying {
    func notifySleepRestored(_ reason: RestoreReason)
}
