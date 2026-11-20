import Foundation
import Testing
@testable import StayLitCore

/// A model whose sleep is blocked and whose lid is closed, with a clock the test moves by hand.
/// The run with the lid closed starts at the first reading, so every duration counts from the start.
@MainActor
private struct Rig {
    let system = FakeSystem(sleepDisabled: true, authorized: true)
    let claude: FakeClaudeSessionReader
    let lid: FakeLidReader
    let sleeper = FakeSystemSleeper()
    let time = ManualTimeSource()
    let model: AppModel

    init(lidClosed: Bool = true, claude: ClaudeActivity = .idle) {
        self.claude = FakeClaudeSessionReader(claude)
        lid = FakeLidReader(isClosed: lidClosed)
        model = makeModel(system, claudeSessions: self.claude, lid: lid, systemSleeper: sleeper, time: time)
    }

    /// Lets time pass, then reads again.
    func refresh(after seconds: Int) async {
        time.advance(by: .seconds(seconds))
        await model.refresh()
        await letQueuedWorkRun()
    }

    /// Starts watching and rides 90 s with the lid closed, enough for a run to be worth reporting.
    func startAndRun() async {
        await model.startAndAwaitFirstReading()
        await refresh(after: 90)
    }

    func openTheLid(after seconds: Int = 30) async {
        lid.isClosed = false
        await refresh(after: seconds)
    }

    /// Lets `seconds` pass in readings a minute apart: a longer silence would mean the Mac slept.
    func ride(_ seconds: Int) async {
        for _ in 0..<(seconds / 60) { await refresh(after: 60) }
    }
}

private let commandFailure = SleepControlError.commandFailed(command: "pmset", exitCode: 1, message: "boom")

/// An action of the user that ends the run without a report.
private enum UserEnd: CaseIterable {
    case allowSleep
    case removeAuthorization

    @MainActor func apply(to model: AppModel) async {
        switch self {
        case .allowSleep: await model.setSleepDisabled(false)
        case .removeAuthorization: await model.removeAuthorization()
        }
    }
}

@MainActor
struct LidClosedReportModelTests {
    // MARK: Reports

    @Test func theTimerEndingAfterAnHourReportsTheRun() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        rig.model.setBlockDuration(.oneHour)
        await rig.time.waitForSleeper()
        await rig.ride(3540)

        rig.time.advance(by: .seconds(60))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(3600), end: .restored(.timer)))
        #expect(rig.model.lastAutomaticRestore == .timer)
    }

    @Test func theClaudeGuardReportsTheRun() async {
        let rig = Rig(claude: .working)
        await rig.model.startAndAwaitFirstReading()
        await rig.refresh(after: 30)
        rig.claude.value = .idle
        await rig.model.refresh()

        await rig.refresh(after: 60)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.sleeper.sleepNowCount == 1)
        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(90), end: .restored(.claudeFinished)))
    }

    @Test func openingTheLidWithSleepStillBlockedReportsTheWholeTime() async {
        let rig = Rig()
        await rig.startAndRun()

        await rig.openTheLid()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(120), end: .lidOpened))
    }

    @Test func thePeriodicRefreshFeedsTheRunToo() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        // The first refresh may still be queued: the periodic one skips a busy queue.
        await letQueuedWorkRun()
        rig.time.advance(by: .seconds(90))
        rig.lid.isClosed = false

        await rig.model.refreshPeriodically()

        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(90), end: .lidOpened))
    }

    @Test func sleepAllowedOutsideTheAppReportsTheRun() async {
        let rig = Rig()
        await rig.startAndRun()

        rig.system.withState { $0.isSleepDisabled = false }
        await rig.refresh(after: 30)

        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(120), end: .sleepAllowedElsewhere))
    }

    // MARK: No report

    @Test func aRunWithoutTheLidClosedReportsNothing() async {
        let rig = Rig(lidClosed: false)
        await rig.model.startAndAwaitFirstReading()

        await rig.ride(300)

        #expect(rig.model.lastLidClosedReport == nil)
    }

    @Test func aShortRunReportsNothingAndKeepsTheLastReport() async {
        let rig = Rig()
        await rig.startAndRun()
        await rig.openTheLid()
        let first = rig.model.lastLidClosedReport
        #expect(first != nil)

        rig.lid.isClosed = true
        await rig.refresh(after: 10)
        await rig.openTheLid()

        #expect(rig.model.lastLidClosedReport == first)
    }

    @Test func aFailedReadingNeitherFeedsNorEndsTheRun() async {
        let rig = Rig()
        await rig.startAndRun()
        rig.system.withState { $0.readFailure = commandFailure }

        await rig.openTheLid()
        #expect(rig.model.lastLidClosedReport == nil)

        rig.system.withState { $0.readFailure = nil }
        await rig.refresh(after: 30)

        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(150), end: .lidOpened))
    }

    @Test func aLongSeriesOfFailedReadingsIsNotTakenForASleep() async {
        let rig = Rig()
        await rig.startAndRun()
        rig.system.withState { $0.readFailure = commandFailure }
        // Five minutes of failures, well over the sleep gap, with a reading every 30 s.
        for _ in 0..<10 { await rig.refresh(after: 30) }

        rig.system.withState { $0.readFailure = nil }
        rig.lid.isClosed = false
        await rig.refresh(after: 30)

        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(420), end: .lidOpened))
    }

    @Test func anAutomaticRestoreWithoutARunReplacesTheLastReport() async {
        let rig = Rig()
        await rig.startAndRun()
        await rig.openTheLid()
        #expect(rig.model.lastLidClosedReport != nil)

        rig.model.setBlockDuration(.oneHour)
        await rig.time.waitForSleeper()
        rig.time.advance(by: .seconds(3600))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(rig.model.lastAutomaticRestore == .timer)
        #expect(rig.model.lastLidClosedReport == nil)
    }

    // MARK: The user ends the run

    @Test(arguments: UserEnd.allCases)
    private func theUserEndingTheRunReportsNothing(_ end: UserEnd) async {
        let rig = Rig()
        await rig.startAndRun()

        await end.apply(to: rig.model)
        await rig.refresh(after: 30)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.model.lastLidClosedReport == nil)
    }

    @Test func aRefusedWriteLeavesTheRunGoing() async {
        let rig = Rig()
        await rig.startAndRun()
        rig.system.withState { $0.writeFailure = commandFailure }

        await rig.model.setSleepDisabled(false)
        await rig.openTheLid()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.model.lastLidClosedReport == LidClosedReport(duration: .seconds(120), end: .lidOpened))
    }
}
