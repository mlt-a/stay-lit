/// Builds the AppleScript source that `osascript` runs to get administrator rights.
enum AppleScript {
    /// macOS shows its own password dialog, with `prompt` as its message, then runs the script
    /// as root with `/bin/sh`.
    static func runAsAdministrator(_ shellScript: String, prompt: String) -> String {
        "do shell script \(stringLiteral(shellScript)) with prompt \(stringLiteral(prompt))"
            + " with administrator privileges"
    }

    /// An AppleScript string literal: backslashes first, so the ones added for quotes stay single.
    static func stringLiteral(_ value: String) -> String {
        let escaped = value
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
