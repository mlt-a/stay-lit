/// Reads what the Claude Code sessions of this Mac are doing. The app target composes the
/// real implementation, tests use a double.
public protocol ClaudeSessionReading: Sendable {
    /// Read from the system every time. `.none` when there is no session. It reads files, so it
    /// never runs on the caller's actor, the main actor included.
    @concurrent func sessions() async -> ClaudeSessionCounts
}
