/// How many Claude Code sessions work and wait, one count per session. Idle sessions are not
/// counted: nothing reads them.
public struct ClaudeSessionCounts: Sendable, Equatable {
    public var working: Int
    public var waiting: Int

    /// No session.
    public static let none = ClaudeSessionCounts()

    public init(working: Int = 0, waiting: Int = 0) {
        self.working = working
        self.waiting = waiting
    }

    public init(_ activities: some Sequence<ClaudeActivity>) {
        self.init()
        for activity in activities {
            switch activity {
            case .working: working += 1
            case .waiting: waiting += 1
            case .idle: break
            }
        }
    }

    /// The most active state wins: `working`, then `waiting`, then `idle`. No session is `idle`.
    public var activity: ClaudeActivity {
        if working > 0 { .working } else if waiting > 0 { .waiting } else { .idle }
    }

    /// What the window says about the sessions. Working sessions are a warning while the Mac
    /// would sleep: closing the lid now pauses them.
    public func summary(isSleepBlocked: Bool) -> ClaudeSessionSummary {
        if working == 0 {
            .noneWorking(waiting: waiting)
        } else if isSleepBlocked {
            .keptAwake(working: working, waiting: waiting)
        } else {
            .pausedOnClose(working: working)
        }
    }
}

/// The line about the Claude Code sessions, without its words or colors.
public enum ClaudeSessionSummary: Sendable, Equatable {
    /// No session works. Some may wait.
    case noneWorking(waiting: Int)
    /// Sessions work and sleep is blocked: the Mac stays awake for them.
    case keptAwake(working: Int, waiting: Int)
    /// Sessions work while the Mac would sleep: closing the lid pauses them.
    case pausedOnClose(working: Int)
}
