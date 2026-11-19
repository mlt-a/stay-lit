import Foundation
import Testing
@testable import StayLitCore

/// A model with a pretend Mac whose sleep is blocked, a pretend Claude Code, a lid, a double for
/// putting the Mac to sleep and a clock the test moves by hand.
@MainActor
private struct Rig {
    let system: FakeSystem
    let claude: FakeClaudeSessionReader
    let lid: FakeLidReader
    let sleeper: FakeSystemSleeper
    let notifier = FakeSleepRestoreNotifier()
    let time = ManualTimeSource()
    let model: AppModel

    init(
        sleepDisabled: Bool = true,
        claude: ClaudeActivity = .working,
        lidClosed: Bool = true,
        sleeper: FakeSystemSleeper = FakeSystemSleeper(),
        guardEnabled: Bool = true,
        onGuardChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        system = FakeSystem(sleepDisabled: sleepDisabled, authorized: true)
        self.claude = FakeClaudeSessionReader(claude)
        lid = FakeLidReader(isClosed: lidClosed)
        self.sleeper = sleeper
        model = makeModel(
            system,
            claudeSessions: self.claude,
            lid: lid,
            systemSleeper: sleeper,
            notifier: notifier,
            claudeGuardEnabled: guardEnabled,
            onClaudeGuardChange: onGuardChange,
            time: time
        )
    }

    /// Claude stops working at the current time, as the next refresh sees it.
    func claudeStops(_ activity: ClaudeActivity = .idle) async {
        claude.value = activity
        await model.refresh()
    }

    /// Lets time pass, then reads again: the guard only acts at a refresh.
    func refresh(after seconds: Int) async {
        time.advance(by: .seconds(seconds))
        await model.refresh()
        await letQueuedWorkRun()
    }

    /// Nothing happened: sleep still blocked, nothing told, the Mac not put to sleep.
    func expectQuiet(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(model.isSleepDisabled, sourceLocation: sourceLocation)
        #expect(system.withState(\.writes) == 0, sourceLocation: sourceLocation)
        #expect(notifier.notifications.isEmpty, sourceLocation: sourceLocation)
        #expect(sleeper.sleepNowCount == 0, sourceLocation: sourceLocation)
        #expect(model.lastAutomaticRestore == nil, sourceLocation: sourceLocation)
    }
}

@MainActor
struct ClaudeGuardModelTests {
    // MARK: Firing

    @Test func aMinuteWithoutWorkAndTheLidClosedAllowsSleepAndSleepsTheMac() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()

        await rig.refresh(after: 60)

        #expect(!rig.model.isSleepDisabled)
        #expect(!rig.system.withState(\.isSleepDisabled))
        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.notifier.notifications == [.claudeFinished])
        #expect(rig.model.lastAutomaticRestore == .claudeFinished)
        #expect(rig.sleeper.sleepNowCount == 1)
        #expect(rig.model.error == nil)
    }

    @Test func itWaitsTheFullMinute() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()

        await rig.refresh(after: 59)

        rig.expectQuiet()
    }

    @Test func thePeriodicRefreshActsToo() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()
        rig.time.advance(by: .seconds(60))

        await rig.model.refreshPeriodically()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.sleeper.sleepNowCount == 1)
    }

    @Test func aSessionWaitingForAnAnswerGetsTenMinutes() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops(.waiting)

        await rig.refresh(after: 599)
        rig.expectQuiet()

        await rig.refresh(after: 1)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.model.lastAutomaticRestore == .claudeFinished)
        #expect(rig.sleeper.sleepNowCount == 1)
    }

    // MARK: Staying quiet

    @Test func anOpenLidDoesNothingUntilItCloses() async {
        let rig = Rig(lidClosed: false)
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()

        await rig.refresh(after: 120)
        rig.expectQuiet()

        rig.lid.isClosed = true
        await rig.model.refresh()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.claudeFinished])
        #expect(rig.sleeper.sleepNowCount == 1)
    }

    @Test func withoutSeeingWorkNothingHappens() async {
        let rig = Rig(claude: .idle)
        await rig.model.startAndAwaitFirstReading()

        await rig.refresh(after: 3600)

        rig.expectQuiet()
    }

    @Test func aDisabledGuardDoesNothing() async {
        let rig = Rig(guardEnabled: false)
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()

        await rig.refresh(after: 3600)

        rig.expectQuiet()
    }

    @Test func claudeStillWorkingKeepsTheMacAwake() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()

        await rig.refresh(after: 3600)

        rig.expectQuiet()
    }

    @Test func claudeWorkingAgainStartsTheMinuteOver() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()
        await rig.refresh(after: 30)

        rig.claude.value = .working
        await rig.refresh(after: 10)
        await rig.claudeStops()
        await rig.refresh(after: 59)

        rig.expectQuiet()
    }

    @Test func nothingHappensWhileSleepIsAllowed() async {
        let rig = Rig(sleepDisabled: false)
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()

        await rig.refresh(after: 3600)

        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.notifier.notifications.isEmpty)
        #expect(rig.sleeper.sleepNowCount == 0)
    }

    // MARK: Failures

    @Test func aFailedWriteDoesNotPutTheMacToSleepAndIsNotRetried() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()
        let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        rig.system.withState { $0.writeFailure = failure }

        await rig.refresh(after: 60)

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.model.error == .sleepControl(failure))
        #expect(rig.model.lastAutomaticRestore == nil)
        #expect(rig.notifier.notifications.isEmpty)
        #expect(rig.sleeper.sleepNowCount == 0)

        await rig.refresh(after: 60)
        await rig.model.refreshPeriodically()

        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.sleeper.sleepNowCount == 0)
    }

    @Test func aFailedSleepNowKeepsSleepAllowedAndShowsTheError() async {
        let failure = SleepControlError.commandFailed(command: "pmset sleepnow", exitCode: 1, message: "nope")
        let rig = Rig(sleeper: FakeSystemSleeper(error: failure))
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()

        await rig.refresh(after: 60)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.model.lastAutomaticRestore == .claudeFinished)
        #expect(rig.notifier.notifications == [.claudeFinished])
        #expect(rig.sleeper.sleepNowCount == 1)
        #expect(rig.model.error == .sleepNowFailed(cause: .sleepControl(failure)))

        await rig.refresh(after: 60)

        #expect(rig.sleeper.sleepNowCount == 1)
        #expect(rig.system.withState(\.writes) == 1)
    }

    // MARK: Starting over

    @Test func aNewBlockNeedsToSeeClaudeWorkAgain() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()
        await rig.refresh(after: 60)
        #expect(rig.sleeper.sleepNowCount == 1)

        await rig.model.setSleepDisabled(true)
        await rig.refresh(after: 120)

        #expect(rig.model.isSleepDisabled)
        #expect(rig.sleeper.sleepNowCount == 1)

        rig.claude.value = .working
        await rig.model.refresh()
        await rig.claudeStops()
        await rig.refresh(after: 60)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.sleeper.sleepNowCount == 2)
    }

    @Test func turningTheGuardOffAndOnStartsUnarmed() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()
        await rig.model.setClaudeGuardEnabled(false)
        await rig.model.setClaudeGuardEnabled(true)
        await rig.claudeStops()

        await rig.refresh(after: 3600)

        rig.expectQuiet()
    }

    // MARK: The setting

    @Test func theSettingIsHandedOverOnlyWhenItChanges() async {
        let changes = Changes()
        let rig = Rig(guardEnabled: false) { changes.values.append($0) }
        #expect(!rig.model.isClaudeGuardEnabled)

        await rig.model.setClaudeGuardEnabled(false)
        await rig.model.setClaudeGuardEnabled(true)
        await rig.model.setClaudeGuardEnabled(true)
        await rig.model.setClaudeGuardEnabled(false)

        #expect(changes.values == [true, false])
        #expect(!rig.model.isClaudeGuardEnabled)
    }

    @Test func turningTheGuardOnActsOnNothingAtOnce() async {
        let rig = Rig(guardEnabled: false)
        await rig.model.startAndAwaitFirstReading()
        await rig.claudeStops()
        await rig.refresh(after: 3600)

        await rig.model.setClaudeGuardEnabled(true)
        await letQueuedWorkRun()

        rig.expectQuiet()
    }
}

/// What the setting callback received, in order.
@MainActor
private final class Changes {
    var values: [Bool] = []
}
