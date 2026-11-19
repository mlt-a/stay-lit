import Foundation
import Testing
@testable import StayLitCore

struct ClaudeGuardTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func isNotDueBeforeAnyRecord() {
        #expect(!ClaudeGuardTracker().isDue(at: at(10_000)))
    }

    @Test func isNotArmedWithoutWorkSeen() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.idle, at: at(0))

        #expect(!tracker.isDue(at: at(10_000)))
    }

    @Test func isNotDueWhileWorking() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.working, at: at(0))
        tracker.record(.working, at: at(10_000))

        #expect(!tracker.isDue(at: at(10_000)))
    }

    @Test func isDueAfterOneMinuteIdle() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.working, at: at(0))
        tracker.record(.idle, at: at(10))

        #expect(!tracker.isDue(at: at(69)))
        #expect(tracker.isDue(at: at(70)))
    }

    @Test func waitsTenMinutesWhenASessionIsWaiting() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.working, at: at(0))
        tracker.record(.waiting, at: at(10))

        #expect(!tracker.isDue(at: at(609)))
        #expect(tracker.isDue(at: at(610)))
    }

    @Test func aWaitingSessionThatEndsCountsFromTheLastWork() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.working, at: at(0))
        tracker.record(.waiting, at: at(10))
        tracker.record(.idle, at: at(300))

        #expect(tracker.isDue(at: at(300)))
    }

    @Test func workResumingRestartsTheCount() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.working, at: at(0))
        tracker.record(.idle, at: at(10))
        tracker.record(.working, at: at(50))
        tracker.record(.idle, at: at(60))

        #expect(!tracker.isDue(at: at(119)))
        #expect(tracker.isDue(at: at(120)))
    }

    @Test func resetDisarmsTheTracker() {
        var tracker = ClaudeGuardTracker()
        tracker.record(.working, at: at(0))
        tracker.record(.idle, at: at(10))
        tracker.reset()
        tracker.record(.idle, at: at(20))

        #expect(!tracker.isDue(at: at(10_000)))
    }
}
