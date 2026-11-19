public enum SleepControlError: Error, Equatable, Sendable {
    /// `sudo` asked for a password: the sudoers rule is not installed.
    case authorizationMissing
    /// A command ran and failed.
    case commandFailed(command: String, exitCode: Int32, message: String)
}
