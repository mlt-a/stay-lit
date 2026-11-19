/// Puts the Mac to sleep now. The app target composes the real implementation, tests use a double.
public protocol SystemSleeping: Sendable {
    /// Throws `SleepControlError.commandFailed` when the command fails and
    /// `CommandRunnerError.launchFailed` when it cannot be started.
    func sleepNow() async throws
}

/// `pmset sleepnow`. It needs no `sudo`: any user may put the Mac to sleep.
public struct PmsetSystemSleeper: SystemSleeping {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func sleepNow() async throws {
        let arguments = PmsetCommand.sleepNowArguments
        let result = try await runner.run(Executables.pmset, arguments: arguments)
        try result.requireSuccess(executable: Executables.pmset, arguments: arguments)
    }
}
