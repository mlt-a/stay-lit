import Foundation

enum OsascriptOutput {
    /// Whether `osascript` stopped because the user cancelled the password dialog.
    /// -128 is AppleScript's "User canceled." error; the number does not depend on the language.
    /// Only the end of stderr counts: the same text inside a script's own message is not a cancel.
    static func userCancelled(_ result: CommandResult) -> Bool {
        result.trimmedStandardError.hasSuffix("(-128)")
    }

    /// Turns osascript's `0:300: execution error: <text> (N)` into `<text>` and the script's own
    /// exit code N. Any other stderr is kept as it is, with osascript's exit code.
    static func scriptFailure(_ result: CommandResult) -> AuthorizationError {
        let message = result.trimmedStandardError
        guard let match = message.wholeMatch(of: /(?s)\d+:\d+: execution error: (.*) \((-?\d+)\)/),
              let exitCode = Int32(match.2)
        else {
            return .scriptFailed(exitCode: result.exitCode, message: message)
        }
        return .scriptFailed(exitCode: exitCode, message: String(match.1))
    }
}
