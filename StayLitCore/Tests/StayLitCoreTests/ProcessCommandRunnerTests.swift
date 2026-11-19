import Testing
@testable import StayLitCore

/// Only harmless, read-only system tools run here.
struct ProcessCommandRunnerTests {
    private let runner = ProcessCommandRunner()

    @Test func capturesStandardOutputAndExitCode() async throws {
        let result = try await runner.run("/bin/echo", arguments: ["hello world", "$HOME; ls"])

        #expect(result == CommandResult(exitCode: 0, standardOutput: "hello world $HOME; ls\n"))
    }

    @Test func capturesStandardErrorAndFailureCode() async throws {
        let result = try await runner.run("/bin/ls", arguments: ["/staylit-no-such-path"])

        #expect(!result.isSuccess)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("No such file"))
    }

    @Test func missingExecutableThrowsLaunchFailed() async {
        await #expect(throws: CommandRunnerError.self) {
            try await runner.run("/staylit/no-such-tool", arguments: [])
        }
    }
}
