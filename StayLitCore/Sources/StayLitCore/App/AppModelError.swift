/// What went wrong, in terms the interface can turn into a message.
/// The core carries no user-facing text: the app target translates each case.
/// A cancelled password dialog is not an error, so no case stands for it.
public enum AppModelError: Error, Equatable, Sendable {
    /// Reading or changing the sleep setting failed.
    case sleepControl(SleepControlError)
    /// The root script that installs or removes the sudoers rule ran and failed.
    case authorizationScriptFailed(exitCode: Int32, message: String)
    /// A command could not be started.
    case commandLaunch(CommandRunnerError)
    /// The authorization is gone, but turning sleep back on failed on the way:
    /// sleep may still be blocked. `cause` is the failure of the removal.
    indirect case removedWithSleepPossiblyBlocked(cause: AppModelError)
    /// The rule was written, but `sudo` does not accept it: the status still reads as not
    /// authorized after a successful install.
    case ruleInstalledButNotAccepted
    /// Sleep was turned back on, but putting the Mac to sleep failed.
    indirect case sleepNowFailed(cause: AppModelError)
    /// Changing the launch at login registration failed.
    case launchAtLogin(message: String)
    /// The lid closed while sleep was blocked, but the session could not be locked.
    case screenLockUnavailable
    /// A failure of a kind the core does not know.
    case unexpected(message: String)

    /// The one translation from what the system threw. `nil` when the user cancelled the
    /// password dialog: they chose it, there is nothing to show.
    init?(_ error: any Error) {
        switch error {
        // Already translated by the model (`sleepNowFailed`): it must pass `perform` unchanged.
        case let error as AppModelError: self = error
        case let error as SleepControlError: self = .sleepControl(error)
        case AuthorizationError.cancelledByUser: return nil
        case AuthorizationError.scriptFailed(let exitCode, let message):
            self = .authorizationScriptFailed(exitCode: exitCode, message: message)
        case let error as CommandRunnerError: self = .commandLaunch(error)
        case ScreenLockError.unavailable: self = .screenLockUnavailable
        case let error as LaunchAtLoginFailure: self = .launchAtLogin(message: error.message)
        default: self = .unexpected(message: error.localizedDescription)
        }
    }
}

/// Wraps the error the login item registration threw, so the translation knows where it
/// comes from: the system's own error types say nothing about it.
struct LaunchAtLoginFailure: Error {
    let message: String
}
