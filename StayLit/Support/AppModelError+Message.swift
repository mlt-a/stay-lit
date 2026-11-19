import StayLitCore

extension AppModelError {
    /// The text shown for the error. The core only says what happened.
    var message: String {
        switch self {
        case .sleepControl(.authorizationMissing):
            "Stay Lit is not authorized to change the sleep setting yet."
        case .sleepControl(.commandFailed(_, let exitCode, let message)) where message.isEmpty:
            "A command failed with code \(exitCode)."
        case .sleepControl(.commandFailed(_, let exitCode, let message)):
            "A command failed with code \(exitCode): \(message)"
        case .authorizationScriptFailed(_, let message):
            "The authorization could not be changed: \(message)"
        case .commandLaunch(.launchFailed(let executable, let reason)):
            "Could not start \(executable): \(reason)"
        case .removedWithSleepPossiblyBlocked(.authorizationScriptFailed(_, let detail)):
            "The authorization was removed, but turning sleep back on failed, so sleep may still be blocked. \(detail)"
        case .removedWithSleepPossiblyBlocked(let cause):
            "The authorization was removed, but turning sleep back on failed, so sleep may still be blocked. \(cause.message)"
        case .ruleInstalledButNotAccepted:
            "The rule was installed, but sudo does not accept it. Check that /etc/sudoers includes /etc/sudoers.d."
        case .sleepNowFailed(let cause):
            "Sleep was turned back on, but the Mac could not be put to sleep. \(cause.message)"
        case .launchAtLogin(let message):
            "Launch at login could not be changed: \(message)"
        case .screenLockUnavailable:
            "The screen could not be locked when the lid closed."
        case .unexpected(let message):
            "Something went wrong: \(message)"
        }
    }
}
