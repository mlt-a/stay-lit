enum PmsetCommand {
    static let sleepNowArguments = ["sleepnow"]

    /// The arguments that turn sleep off (`true`) or back on (`false`).
    /// The sudoers rule, the root script and the app all derive their command from here,
    /// so the rule always permits exactly what the app runs.
    static func setSleepDisabledArguments(_ disabled: Bool) -> [String] {
        ["-a", "disablesleep", disabled ? "1" : "0"]
    }
}
