import Foundation

/// The timing rule of the Claude guard. The model feeds it the activity at every refresh and
/// asks whether it is time to act.
public struct ClaudeGuardTracker: Sendable, Equatable {
    /// No session works and none waits.
    public static let idleDelay: TimeInterval = 60
    /// A session is blocked on a question: give the user time to answer.
    public static let waitingDelay: TimeInterval = 600

    private enum State: Sendable, Equatable {
        /// No work seen yet since the sleep block began: blocking sleep for another reason
        /// must not trigger the guard.
        case unarmed
        case working
        /// Nothing works since `since`; `waiting` when a session is blocked on a question.
        case stopped(since: Date, waiting: Bool)
    }

    private var state = State.unarmed

    public init() {}

    public mutating func record(_ activity: ClaudeActivity, at date: Date) {
        let waiting = activity == .waiting
        switch (activity, state) {
        case (.working, _):
            state = .working
        case (_, .unarmed):
            break
        case (_, .working):
            state = .stopped(since: date, waiting: waiting)
        case (_, .stopped(let since, _)):
            state = .stopped(since: since, waiting: waiting)
        }
    }

    public mutating func reset() {
        state = .unarmed
    }

    public func isDue(at date: Date) -> Bool {
        guard case .stopped(let since, let waiting) = state else { return false }
        return date.timeIntervalSince(since) >= (waiting ? Self.waitingDelay : Self.idleDelay)
    }
}
