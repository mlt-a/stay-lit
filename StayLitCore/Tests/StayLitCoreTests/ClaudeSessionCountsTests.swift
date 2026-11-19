import Testing
@testable import StayLitCore

struct ClaudeSessionCountsTests {
    @Test func noSessionHasNoCountAndIsIdle() {
        #expect(ClaudeSessionCounts.none == ClaudeSessionCounts(working: 0, waiting: 0))
        #expect(ClaudeSessionCounts.none.activity == .idle)
    }

    @Test func workingAndWaitingSessionsAreCounted() {
        let counts = ClaudeSessionCounts([.working, .idle, .waiting, .working, .idle, .idle])

        #expect(counts == ClaudeSessionCounts(working: 2, waiting: 1))
    }

    @Test(arguments: [
        ([ClaudeActivity](), ClaudeActivity.idle),
        ([.idle, .idle], .idle),
        ([.idle, .waiting], .waiting),
        ([.waiting, .idle, .waiting], .waiting),
        ([.idle, .waiting, .working], .working),
        ([.working, .idle], .working),
    ])
    func theMostActiveSessionWins(activities: [ClaudeActivity], expected: ClaudeActivity) {
        #expect(ClaudeSessionCounts(activities).activity == expected)
    }

    @Test(arguments: [
        (ClaudeSessionCounts.none, false, ClaudeSessionSummary.noneWorking(waiting: 0)),
        (.none, true, .noneWorking(waiting: 0)),
        (ClaudeSessionCounts(waiting: 2), false, .noneWorking(waiting: 2)),
        (ClaudeSessionCounts(waiting: 2), true, .noneWorking(waiting: 2)),
        (ClaudeSessionCounts(working: 3, waiting: 1), true, .keptAwake(working: 3, waiting: 1)),
        (ClaudeSessionCounts(working: 1), true, .keptAwake(working: 1, waiting: 0)),
        (ClaudeSessionCounts(working: 3, waiting: 1), false, .pausedOnClose(working: 3)),
        (ClaudeSessionCounts(working: 1), false, .pausedOnClose(working: 1)),
    ])
    func workingSessionsWarnOnlyWhileTheMacWouldSleep(
        counts: ClaudeSessionCounts,
        isSleepBlocked: Bool,
        expected: ClaudeSessionSummary
    ) {
        #expect(counts.summary(isSleepBlocked: isSleepBlocked) == expected)
    }
}
