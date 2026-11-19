import Foundation
import Testing
@testable import StayLitCore

struct LidClosedRunTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A tracker whose run began at `at(0)`, with a reading every 30 s up to `seen`.
    private func runningTracker(seen: TimeInterval = 0) -> LidClosedRunTracker {
        var tracker = LidClosedRunTracker()
        _ = tracker.record(lidClosed: true, sleepBlocked: true, at: at(0))
        for seconds in stride(from: 30, through: seen, by: 30) {
            _ = tracker.record(lidClosed: true, sleepBlocked: true, at: at(seconds))
        }
        return tracker
    }

    @Test(arguments: [(lidClosed: true, sleepBlocked: false), (lidClosed: false, sleepBlocked: true)])
    func startsNoRunWithoutBlockOrWithTheLidOpen(lidClosed: Bool, sleepBlocked: Bool) {
        var tracker = LidClosedRunTracker()
        _ = tracker.record(lidClosed: lidClosed, sleepBlocked: sleepBlocked, at: at(0))

        #expect(tracker.restored(.timer, at: at(600)) == nil)
    }

    @Test func aRunStartingIsNotReportedYet() {
        var tracker = LidClosedRunTracker()

        #expect(tracker.record(lidClosed: true, sleepBlocked: true, at: at(0)) == nil)
    }

    @Test func restoreEndsTheRunWithItsReason() {
        var tracker = runningTracker(seen: 570)

        #expect(tracker.restored(.timer, at: at(600)) == LidClosedReport(duration: .seconds(600), end: .restored(.timer)))
    }

    @Test func restoreKeepsTheReasonDetails() {
        var tracker = runningTracker(seen: 270)

        #expect(tracker.restored(.lowBattery(percent: 8), at: at(300))?.end == .restored(.lowBattery(percent: 8)))
    }

    @Test func aRestoreAfterAGapEndsTheRunAsASleepAtTheLastReadingSeen() {
        var tracker = runningTracker(seen: 300)

        #expect(tracker.restored(.timer, at: at(10_000)) == LidClosedReport(duration: .seconds(300), end: .macSlept))
        #expect(tracker.isRunning == false)
    }

    @Test func aRestoreAfterExactlyTheLimitKeepsItsReason() {
        var tracker = runningTracker(seen: 300)

        #expect(tracker.restored(.timer, at: at(420)) == LidClosedReport(duration: .seconds(420), end: .restored(.timer)))
    }

    @Test func restoreWithoutRunGivesNothing() {
        var tracker = LidClosedRunTracker()

        #expect(tracker.restored(.timer, at: at(600)) == nil)
    }

    @Test(arguments: [
        (lidClosed: false, sleepBlocked: true, end: LidClosedReport.End.lidOpened),
        (lidClosed: true, sleepBlocked: false, end: .sleepAllowedElsewhere),
        // Sleep allowed wins over the lid opening.
        (lidClosed: false, sleepBlocked: false, end: .sleepAllowedElsewhere),
    ])
    func aReadingThatBreaksTheConditionsEndsTheRun(lidClosed: Bool, sleepBlocked: Bool, end: LidClosedReport.End) {
        var tracker = runningTracker(seen: 570)

        #expect(
            tracker.record(lidClosed: lidClosed, sleepBlocked: sleepBlocked, at: at(600))
                == LidClosedReport(duration: .seconds(600), end: end)
        )
    }

    @Test func aGapEndsTheRunAtTheLastReadingSeen() {
        var tracker = runningTracker(seen: 300)

        #expect(
            tracker.record(lidClosed: true, sleepBlocked: true, at: at(10_000))
                == LidClosedReport(duration: .seconds(300), end: .macSlept)
        )
    }

    @Test func aGapOfExactlyTheLimitKeepsTheRun() {
        var tracker = runningTracker(seen: 300)

        #expect(tracker.record(lidClosed: true, sleepBlocked: true, at: at(420)) == nil)
        #expect(tracker.restored(.timer, at: at(430))?.duration == .seconds(430))
    }

    @Test func aGapJustOverTheLimitEndsTheRun() {
        var tracker = runningTracker(seen: 300)

        #expect(tracker.record(lidClosed: true, sleepBlocked: true, at: at(421))?.end == .macSlept)
    }

    @Test(arguments: [(lidClosed: true, duration: Duration.seconds(100)), (lidClosed: false, duration: nil)])
    func theReadingAfterAGapStartsANewRunOnlyWhenTheLidIsStillClosed(lidClosed: Bool, duration: Duration?) {
        var tracker = runningTracker(seen: 300)
        _ = tracker.record(lidClosed: lidClosed, sleepBlocked: true, at: at(10_000))

        #expect(tracker.restored(.timer, at: at(10_100))?.duration == duration)
    }

    @Test func awakeProofsKeepTheRunAcrossALongSeriesOfFailedReadings() {
        var tracker = runningTracker(seen: 60)
        for seconds in stride(from: 90.0, through: 330.0, by: 30.0) { tracker.sawAwake(at: at(seconds)) }

        #expect(
            tracker.record(lidClosed: false, sleepBlocked: true, at: at(360))
                == LidClosedReport(duration: .seconds(360), end: .lidOpened)
        )
    }

    @Test func awakeProofsAfterAGapDoNotHideTheSleep() {
        var tracker = runningTracker(seen: 300)
        tracker.sawAwake(at: at(10_000))

        #expect(
            tracker.record(lidClosed: true, sleepBlocked: true, at: at(10_030))
                == LidClosedReport(duration: .seconds(300), end: .macSlept)
        )
    }

    @Test func anAwakeProofNeitherStartsNorEndsARun() {
        var tracker = LidClosedRunTracker()
        tracker.sawAwake(at: at(0))

        #expect(tracker.isRunning == false)
        #expect(tracker.restored(.timer, at: at(600)) == nil)
    }

    @Test func aShortGapRunGivesNoReport() {
        var tracker = runningTracker(seen: 30)

        #expect(tracker.record(lidClosed: true, sleepBlocked: true, at: at(10_000)) == nil)
    }

    @Test(arguments: [(seconds: 59.0, duration: nil), (seconds: 60.0, duration: Duration.seconds(60))])
    func aRunNeedsAMinuteToGiveAReport(seconds: TimeInterval, duration: Duration?) {
        var tracker = runningTracker()

        #expect(tracker.restored(.timer, at: at(seconds))?.duration == duration)
    }

    @Test func aShortLidOpenedRunGivesNoReport() {
        var tracker = runningTracker()

        #expect(tracker.record(lidClosed: false, sleepBlocked: true, at: at(30)) == nil)
    }

    @Test func cancelDropsTheRunWithoutReport() {
        var tracker = runningTracker(seen: 570)
        tracker.cancel()

        #expect(tracker.restored(.timer, at: at(600)) == nil)
        #expect(tracker.record(lidClosed: false, sleepBlocked: true, at: at(610)) == nil)
    }

    @Test func aRunCanStartAgainAfterItEnded() {
        var tracker = runningTracker()
        _ = tracker.restored(.timer, at: at(300))
        _ = tracker.record(lidClosed: true, sleepBlocked: true, at: at(400))

        #expect(tracker.restored(.highTemperature, at: at(500))?.duration == .seconds(100))
    }
}
