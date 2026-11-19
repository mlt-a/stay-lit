import Foundation

/// Reads and changes the `disablesleep` power setting.
public protocol SleepControlling: Sendable {
    /// The current state, read from `pmset -g`.
    /// Throws `SleepControlError.commandFailed` or `CommandRunnerError.launchFailed`.
    func isSleepDisabled() async throws -> Bool

    /// Sets the state, then reads it back and returns what `pmset -g` reports.
    /// Throws `SleepControlError.authorizationMissing` when the sudoers rule is not installed,
    /// `SleepControlError.commandFailed` when a command fails, and
    /// `CommandRunnerError.launchFailed` when a command cannot be started.
    @discardableResult
    func setSleepDisabled(_ disabled: Bool) async throws -> Bool
}

public struct SleepController: SleepControlling {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func isSleepDisabled() async throws -> Bool {
        let result = try await runner.run(Executables.pmset, arguments: ["-g"])
        try result.requireSuccess(executable: Executables.pmset, arguments: ["-g"])
        return PmsetOutput.isSleepDisabled(in: result.standardOutput)
    }

    @discardableResult
    public func setSleepDisabled(_ disabled: Bool) async throws -> Bool {
        // `-n` makes sudo fail instead of waiting for a password nobody can type.
        let arguments = ["-n", Executables.pmset] + PmsetCommand.setSleepDisabledArguments(disabled)
        let result = try await runner.run(Executables.sudo, arguments: arguments)
        // Checked before the generic failure: it is the one error the user can fix.
        if SudoOutput.requiresPassword(result) {
            throw SleepControlError.authorizationMissing
        }
        try result.requireSuccess(executable: Executables.sudo, arguments: arguments)
        return try await isSleepDisabled()
    }
}
