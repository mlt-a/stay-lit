import Foundation

public enum AuthorizationStatus: Sendable, Equatable {
    /// The rule is installed: `sudo -n` runs the two pmset commands without a password.
    case authorized
    /// `sudo -n` cannot run the two pmset commands right now. The rule may be missing,
    /// incomplete, or unusable because sudo itself fails: this means "not usable",
    /// not "not installed".
    case notAuthorized
}

public enum AuthorizationError: Error, Equatable, Sendable {
    /// The user closed the password dialog. Nothing changed and nothing needs to be shown.
    case cancelledByUser
    /// The root script ran and failed. Nothing was installed.
    case scriptFailed(exitCode: Int32, message: String)
}

/// Installs and removes the sudoers rule that lets the app toggle sleep without a password.
public protocol SudoersAuthorizing: Sendable {
    /// The exact rule `install()` writes, to show the user beforehand.
    var ruleText: String { get }

    /// Throws `CommandRunnerError.launchFailed` when `sudo` cannot be started.
    func status() async throws -> AuthorizationStatus

    /// Asks for an administrator password once, then installs the rule.
    /// Throws `AuthorizationError` when the dialog is cancelled or the script fails,
    /// and `CommandRunnerError.launchFailed` when `osascript` cannot be started.
    func install() async throws

    /// Asks for an administrator password, turns sleep back on, then removes the rule.
    /// Throws the same errors as `install()`.
    func remove() async throws
}

/// The messages of the macOS password dialog, one per operation.
/// Each says what the app is about to do. The app target provides them, localized.
public struct AuthorizationPrompts: Sendable, Equatable {
    public var install: String
    public var remove: String

    public init(install: String, remove: String) {
        self.install = install
        self.remove = remove
    }
}

public struct SudoersAuthorizer: SudoersAuthorizing {
    private let prompts: AuthorizationPrompts
    private let runner: any CommandRunning
    private let userID: uid_t
    private let ruleFileExists: @Sendable () -> Bool

    public init(
        prompts: AuthorizationPrompts,
        runner: any CommandRunning = ProcessCommandRunner(),
        userID: uid_t = getuid()
    ) {
        self.init(prompts: prompts, runner: runner, userID: userID) {
            FileManager.default.fileExists(atPath: SudoersRule.path(forUserID: userID))
        }
    }

    init(
        prompts: AuthorizationPrompts,
        runner: any CommandRunning,
        userID: uid_t,
        ruleFileExists: @escaping @Sendable () -> Bool
    ) {
        self.prompts = prompts
        self.runner = runner
        self.userID = userID
        self.ruleFileExists = ruleFileExists
    }

    public var ruleText: String {
        SudoersRule.text(forUserID: userID)
    }

    public func status() async throws -> AuthorizationStatus {
        // sudo alone could say yes without our rule: an admin with any other NOPASSWD rule
        // can list without a password, and `%admin ALL=(ALL) ALL` permits pmset.
        guard ruleFileExists() else { return .notAuthorized }
        // Exit code 0 only if the command is permitted. `-n` fails instead of prompting.
        // Both forms must pass: the app needs `disablesleep 1` to turn sleep off and `0` to restore it.
        async let turnOn = runner.run(Executables.sudo, arguments: Self.sudoListArguments(disabled: true))
        async let turnOff = runner.run(Executables.sudo, arguments: Self.sudoListArguments(disabled: false))
        let results = try await [turnOn, turnOff]
        return results.allSatisfy(\.isSuccess) ? .authorized : .notAuthorized
    }

    private static func sudoListArguments(disabled: Bool) -> [String] {
        ["-n", "-l", Executables.pmset] + PmsetCommand.setSleepDisabledArguments(disabled)
    }

    public func install() async throws {
        try await runAsAdministrator(SudoersRule.installScript(forUserID: userID), prompt: prompts.install)
    }

    public func remove() async throws {
        try await runAsAdministrator(SudoersRule.removeScript(forUserID: userID), prompt: prompts.remove)
    }

    private func runAsAdministrator(_ shellScript: String, prompt: String) async throws {
        let result = try await runner.run(
            Executables.osascript,
            arguments: ["-e", AppleScript.runAsAdministrator(shellScript, prompt: prompt)]
        )
        guard !result.isSuccess else { return }
        if OsascriptOutput.userCancelled(result) {
            throw AuthorizationError.cancelledByUser
        }
        throw OsascriptOutput.scriptFailure(result)
    }
}
