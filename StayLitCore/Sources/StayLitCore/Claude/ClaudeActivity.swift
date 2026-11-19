/// What Claude Code is doing, read from the `status` of its session registry files.
public enum ClaudeActivity: Sendable, Equatable {
    /// Busy.
    case working
    /// Blocked on a permission or a question.
    case waiting
    /// Back to the prompt.
    case idle

    /// A missing or unknown status counts as work: a new Claude Code release may add values,
    /// and a wrong guess must keep the Mac awake rather than put it to sleep.
    public init(status: String?) {
        switch status {
        case "idle": self = .idle
        case "waiting": self = .waiting
        default: self = .working
        }
    }
}
