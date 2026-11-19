import Testing
@testable import StayLitCore

private func authorizer(
    _ runner: FakeCommandRunner,
    ruleFileExists: Bool = true
) -> SudoersAuthorizer {
    SudoersAuthorizer(prompts: prompts, runner: runner, userID: 501) { ruleFileExists }
}

private let prompts = AuthorizationPrompts(
    install: "Stay Lit will install its rule.",
    remove: "Stay Lit will remove its rule."
)

private func sudoListCall(_ state: String) -> FakeCommandRunner.Call {
    .init(executable: "/usr/bin/sudo", arguments: ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", state])
}

private let cancelled = CommandResult(
    exitCode: 1,
    standardError: "0:200: execution error: User canceled. (-128)\n"
)

struct SudoersAuthorizerTests {
    @Test func ruleTextIsTheRuleForTheUser() {
        #expect(authorizer(FakeCommandRunner([])).ruleText == SudoersRule.text(forUserID: 501))
    }

    // MARK: Status

    /// Replies to each `sudo -n -l` form by its state, whatever order the two run in.
    private func sudoListRunner(
        permitting permitted: Set<String>
    ) -> FakeCommandRunner {
        FakeCommandRunner { call in
            permitted.contains(call.arguments.last ?? "")
                ? .success(CommandResult(exitCode: 0))
                : .success(.sudoPasswordRequired)
        }
    }

    private func sortedCalls(_ runner: FakeCommandRunner) -> [FakeCommandRunner.Call] {
        runner.calls.sorted { $0.arguments.last ?? "" < $1.arguments.last ?? "" }
    }

    @Test func authorizedWhenTheFileExistsAndSudoPermitsBothCommands() async throws {
        let runner = sudoListRunner(permitting: ["0", "1"])

        #expect(try await authorizer(runner).status() == .authorized)
        #expect(sortedCalls(runner) == [sudoListCall("0"), sudoListCall("1")])
    }

    @Test(arguments: [["0"], ["1"], []] as [Set<String>])
    func notAuthorizedWhenSudoDoesNotPermitBothCommands(permitted: Set<String>) async throws {
        let runner = sudoListRunner(permitting: permitted)

        #expect(try await authorizer(runner).status() == .notAuthorized)
        #expect(sortedCalls(runner) == [sudoListCall("0"), sudoListCall("1")])
    }

    @Test func notAuthorizedWithoutTheFileEvenIfSudoWouldPermit() async throws {
        let runner = FakeCommandRunner([])

        #expect(try await authorizer(runner, ruleFileExists: false).status() == .notAuthorized)
        #expect(runner.calls.isEmpty)
    }

    @Test func statusReportsAnUnstartableSudo() async {
        let runner = FakeCommandRunner { _ in .failure(.sudoLaunchFailed) }

        await #expect(throws: CommandRunnerError.sudoLaunchFailed) {
            try await authorizer(runner).status()
        }
    }

    // MARK: Install and remove

    @Test func installRunsTheInstallScriptAsAdministrator() async throws {
        let runner = FakeCommandRunner([.success(CommandResult(exitCode: 0))])

        try await authorizer(runner, ruleFileExists: false).install()

        #expect(runner.calls == [
            .init(
                executable: "/usr/bin/osascript",
                arguments: ["-e", AppleScript.runAsAdministrator(SudoersRule.installScript(forUserID: 501), prompt: prompts.install)]
            ),
        ])
    }

    @Test func removeRunsTheRemoveScriptAsAdministrator() async throws {
        let runner = FakeCommandRunner([.success(CommandResult(exitCode: 0))])

        try await authorizer(runner).remove()

        #expect(runner.calls == [
            .init(
                executable: "/usr/bin/osascript",
                arguments: [
                    "-e",
                    "do shell script \"/usr/bin/pmset -a disablesleep 0; status=$?;"
                        + " /bin/rm -f /etc/sudoers.d/staylit-501; exit $status\""
                        + " with prompt \"\(prompts.remove)\" with administrator privileges",
                ]
            ),
        ])
    }

    @Test func removeReportsAPmsetFailureEvenThoughTheRuleIsGone() async {
        // The root script exits with pmset's status, which osascript reports as the error number.
        let runner = FakeCommandRunner([
            .success(CommandResult(exitCode: 1, standardError: "0:300: execution error: pmset: failed (71)\n")),
        ])

        await #expect(throws: AuthorizationError.scriptFailed(exitCode: 71, message: "pmset: failed")) {
            try await authorizer(runner).remove()
        }
    }

    @Test func cancellingThePasswordDialogIsCancelledByUser() async {
        let runner = FakeCommandRunner([.success(cancelled), .success(cancelled)])
        let authorizer = authorizer(runner)

        await #expect(throws: AuthorizationError.cancelledByUser) { try await authorizer.install() }
        await #expect(throws: AuthorizationError.cancelledByUser) { try await authorizer.remove() }
    }

    @Test func aCancelMarkerInTheMiddleOfTheMessageIsNotACancel() {
        let result = CommandResult(
            exitCode: 1,
            standardError: "0:300: execution error: failed after (-128) retries (1)\n"
        )

        #expect(!OsascriptOutput.userCancelled(result))
        #expect(OsascriptOutput.userCancelled(cancelled))
    }

    @Test func aFailingScriptIsScriptFailed() async {
        let runner = FakeCommandRunner([
            .success(CommandResult(
                exitCode: 1,
                standardError: "0:300: execution error: /etc/sudoers.d/staylit-501.tmp:2: syntax error (1)\n"
            )),
        ])

        await #expect(
            throws: AuthorizationError.scriptFailed(
                exitCode: 1,
                message: "/etc/sudoers.d/staylit-501.tmp:2: syntax error"
            )
        ) {
            try await authorizer(runner).install()
        }
    }

    @Test func installReportsAnUnstartableOsascript() async {
        let runner = FakeCommandRunner([
            .failure(.launchFailed(executable: "/usr/bin/osascript", reason: "no such file")),
        ])

        await #expect(
            throws: CommandRunnerError.launchFailed(executable: "/usr/bin/osascript", reason: "no such file")
        ) {
            try await authorizer(runner).install()
        }
    }
}

struct ScriptFailureTests {
    @Test(arguments: [
        // Prefix and suffix removed, N becomes the exit code.
        ("0:300: execution error: syntax error (2)\n", Int32(2), "syntax error"),
        // Several lines and parentheses inside the text are kept.
        ("12:34: execution error: line one\nline two (x) (3)", Int32(3), "line one\nline two (x)"),
        // Not in the osascript form: kept as it is, with osascript's exit code.
        ("something else\n", Int32(1), "something else"),
        ("0:300: execution error: no suffix", Int32(1), "0:300: execution error: no suffix"),
        ("syntax error (2)", Int32(1), "syntax error (2)"),
    ])
    func cleansTheMessage(standardError: String, exitCode: Int32, message: String) {
        #expect(
            OsascriptOutput.scriptFailure(CommandResult(exitCode: 1, standardError: standardError))
                == .scriptFailed(exitCode: exitCode, message: message)
        )
    }
}
