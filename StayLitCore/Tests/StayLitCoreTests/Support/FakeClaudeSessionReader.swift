@testable import StayLitCore

/// Sessions the test sets by hand. `value` stands for one session in that state, which is all
/// the guard tests need.
final class FakeClaudeSessionReader: ClaudeSessionReading, Sendable {
    private let current: LockedValue<ClaudeSessionCounts>

    init(_ activity: ClaudeActivity = .idle) {
        current = LockedValue(ClaudeSessionCounts([activity]))
    }

    init(counts: ClaudeSessionCounts) {
        current = LockedValue(counts)
    }

    var value: ClaudeActivity {
        get { current.value.activity }
        set { current.value = ClaudeSessionCounts([newValue]) }
    }

    var counts: ClaudeSessionCounts {
        get { current.value }
        set { current.value = newValue }
    }

    func sessions() async -> ClaudeSessionCounts { counts }
}
