/// What Claude Code is doing, read from the `status` and `bridgeSessionId` of its session
/// registry files.
public enum ClaudeActivity: Sendable, Equatable {
    /// Busy, or driven through Remote Control.
    case working
    /// Blocked on a permission or a question.
    case waiting
    /// Back to the prompt.
    case idle

    /// A missing or unknown status counts as work: a new Claude Code release may add values,
    /// and a wrong guess must keep the Mac awake rather than put it to sleep.
    public init(status: String?, bridgeSessionId: String? = nil) {
        // `bridgeSessionId` is set while Remote Control is on. The user drives the session from
        // another device, often with the lid closed: between two messages it is idle, but sleep
        // would cut the link.
        if bridgeSessionId?.isEmpty == false {
            self = .working
            return
        }
        switch status {
        case "idle": self = .idle
        case "waiting": self = .waiting
        default: self = .working
        }
    }
}
