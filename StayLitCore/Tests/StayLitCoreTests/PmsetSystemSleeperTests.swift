import Testing
@testable import StayLitCore

struct PmsetSystemSleeperTests {
    @Test func runsPmsetSleepnowWithoutSudo() async throws {
        let runner = FakeCommandRunner([.success(CommandResult(exitCode: 0))])

        try await PmsetSystemSleeper(runner: runner).sleepNow()

        #expect(runner.calls == [.init(executable: "/usr/bin/pmset", arguments: ["sleepnow"])])
    }

    @Test func aNonZeroExitIsCommandFailed() async {
        let runner = FakeCommandRunner([
            .success(CommandResult(exitCode: 1, standardError: "pmset: boom\n")),
        ])

        await #expect(
            throws: SleepControlError.commandFailed(
                command: "/usr/bin/pmset sleepnow",
                exitCode: 1,
                message: "pmset: boom"
            )
        ) {
            try await PmsetSystemSleeper(runner: runner).sleepNow()
        }
    }

    @Test func anUnstartableCommandIsLaunchFailed() async {
        let runner = FakeCommandRunner([.failure(.sudoLaunchFailed)])

        await #expect(throws: CommandRunnerError.sudoLaunchFailed) {
            try await PmsetSystemSleeper(runner: runner).sleepNow()
        }
    }
}
