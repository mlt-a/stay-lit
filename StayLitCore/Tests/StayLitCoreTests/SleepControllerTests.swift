import Foundation
import Testing
@testable import StayLitCore

private func pmsetReport(sleepDisabled: Bool) -> CommandResult {
    CommandResult(exitCode: 0, standardOutput: sleepDisabled ? " SleepDisabled\t\t1\n" : " sleep 1\n")
}

struct SleepControllerTests {
    @Test func readsStateFromPmset() async throws {
        let runner = FakeCommandRunner([.success(pmsetReport(sleepDisabled: true))])
        let controller = SleepController(runner: runner)

        #expect(try await controller.isSleepDisabled())
        #expect(runner.calls == [.init(executable: "/usr/bin/pmset", arguments: ["-g"])])
    }

    @Test(arguments: [true, false])
    func setsStateThroughSudoThenReadsItBack(disabled: Bool) async throws {
        let runner = FakeCommandRunner([
            .success(CommandResult(exitCode: 0)),
            .success(pmsetReport(sleepDisabled: disabled)),
        ])
        let controller = SleepController(runner: runner)

        let state = try await controller.setSleepDisabled(disabled)

        #expect(state == disabled)
        #expect(runner.calls == [
            .init(
                executable: "/usr/bin/sudo",
                arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]
            ),
            .init(executable: "/usr/bin/pmset", arguments: ["-g"]),
        ])
    }

    @Test func reportsStateFromPmsetNotFromTheRequest() async throws {
        let runner = FakeCommandRunner([
            .success(CommandResult(exitCode: 0)),
            .success(pmsetReport(sleepDisabled: false)),
        ])

        #expect(try await SleepController(runner: runner).setSleepDisabled(true) == false)
    }

    @Test func missingPasswordMeansAuthorizationMissing() async {
        let runner = FakeCommandRunner([
            .success(.sudoPasswordRequired),
        ])

        await #expect(throws: SleepControlError.authorizationMissing) {
            try await SleepController(runner: runner).setSleepDisabled(true)
        }
        #expect(runner.calls.count == 1)
    }

    @Test func anyOtherFailureIsCommandFailed() async {
        let runner = FakeCommandRunner([
            .success(CommandResult(exitCode: 2, standardError: "pmset: boom\n")),
        ])

        await #expect(
            throws: SleepControlError.commandFailed(
                command: "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1",
                exitCode: 2,
                message: "pmset: boom"
            )
        ) {
            try await SleepController(runner: runner).setSleepDisabled(true)
        }
    }

    @Test func failedReadIsCommandFailed() async {
        let runner = FakeCommandRunner([.success(CommandResult(exitCode: 1, standardError: "nope"))])

        await #expect(
            throws: SleepControlError.commandFailed(command: "/usr/bin/pmset -g", exitCode: 1, message: "nope")
        ) {
            try await SleepController(runner: runner).isSleepDisabled()
        }
    }

    @Test func unstartableCommandIsLaunchFailed() async {
        let runner = FakeCommandRunner([.failure(.sudoLaunchFailed)])

        await #expect(throws: CommandRunnerError.sudoLaunchFailed) {
            try await SleepController(runner: runner).setSleepDisabled(false)
        }
    }
}
