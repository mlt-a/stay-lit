import Foundation

/// The sudoers rule Stay Lit installs, and the two scripts that run as root to add and remove it.
///
/// The only value that changes from one Mac to another is the user ID, an integer.
/// Nothing else that a user or another program controls ever reaches a root script.
public enum SudoersRule {
    /// One file per user, so a second account never overwrites or removes the first one's rule.
    /// The name has no dot: sudo skips files in `sudoers.d` whose name contains one.
    public static func path(forUserID userID: uid_t) -> String {
        "/etc/sudoers.d/staylit-\(userID)"
    }

    /// The dot keeps sudo from reading a file still being written as a rule.
    static func temporaryPath(forUserID userID: uid_t) -> String {
        path(forUserID: userID) + ".tmp"
    }

    /// The file content, as it is shown to the user before installing.
    public static func text(forUserID userID: uid_t) -> String {
        lines(forUserID: userID).joined(separator: "\n") + "\n"
    }

    /// A leading `#` followed by digits is a user ID in sudoers, not a comment.
    static func lines(forUserID userID: uid_t) -> [String] {
        let permitted = [false, true].map(pmsetCommandLine).joined(separator: ", ")
        return [
            "# Added by Stay Lit. Lets user \(userID) run these two pmset commands without a password.",
            "#\(userID) ALL=(root) NOPASSWD: \(permitted)",
        ]
    }

    private static func pmsetCommandLine(disabled: Bool) -> String {
        ([Executables.pmset] + PmsetCommand.setSleepDisabledArguments(disabled)).joined(separator: " ")
    }

    /// Writes the rule to the temporary file, validates it, gives it its final owner and
    /// mode, then renames it into place. `mv` within one directory is atomic, so sudo sees
    /// either no rule or the whole rule. Any failing step deletes the temporary file.
    static func installScript(forUserID userID: uid_t) -> String {
        let path = path(forUserID: userID)
        let temporaryPath = temporaryPath(forUserID: userID)
        let write = ([Executables.printf, shellQuoted("%s\\n")] + lines(forUserID: userID).map(shellQuoted))
            .joined(separator: " ")
        return "\(write) > \(temporaryPath)"
            + " && \(Executables.visudo) -cf \(temporaryPath)"
            + " && \(Executables.chown) root:wheel \(temporaryPath)"
            + " && \(Executables.chmod) 0440 \(temporaryPath)"
            + " && \(Executables.mv) -f \(temporaryPath) \(path)"
            + " || { \(Executables.rm) -f \(temporaryPath); exit 1; }"
    }

    /// Turns sleep back on, then deletes the rule. The rule goes even if pmset fails, because
    /// removing the authorization is what the user asked for. The script still exits with
    /// pmset's status, so the failure is reported.
    static func removeScript(forUserID userID: uid_t) -> String {
        "\(pmsetCommandLine(disabled: false)); status=$?; \(Executables.rm) -f \(path(forUserID: userID)); exit $status"
    }

    /// Wraps a value in single quotes for `/bin/sh`, where nothing inside is expanded.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\\''") + "'"
    }
}
