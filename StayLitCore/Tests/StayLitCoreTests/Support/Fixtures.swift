@testable import StayLitCore

extension CommandResult {
    static let sudoPasswordRequired = CommandResult(exitCode: 1, standardError: "sudo: a password is required\n")
}

extension CommandRunnerError {
    static let sudoLaunchFailed = CommandRunnerError.launchFailed(
        executable: "/usr/bin/sudo",
        reason: "no such file"
    )
}
