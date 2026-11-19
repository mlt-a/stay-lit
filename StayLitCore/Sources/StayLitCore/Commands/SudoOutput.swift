import Foundation

enum SudoOutput {
    /// Whether `sudo -n` refused to run because it would need a password.
    static func requiresPassword(_ result: CommandResult) -> Bool {
        result.standardError.localizedCaseInsensitiveContains("a password is required")
    }
}
