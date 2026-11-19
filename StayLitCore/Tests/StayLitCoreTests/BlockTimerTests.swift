import Foundation
import Testing
@testable import StayLitCore

@MainActor
struct BlockTimerTests {
    private let hour = Duration.seconds(3600)

    @Test func theDeadlineAllowsSleepAgain() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        let start = time.now
        model.setBlockDuration(.oneHour)

        await model.setSleepDisabled(true)
        await time.waitForSleeper()
        #expect(model.restoreDeadline == start.addingTimeInterval(3600))

        time.advance(by: .seconds(3599))
        await letQueuedWorkRun()
        #expect(model.isSleepDisabled)
        #expect(system.withState(\.writes) == 1)

        time.advance(by: .seconds(1))
        await settle { !model.isSleepDisabled && !model.isBusy }

        #expect(!model.isSleepDisabled)
        #expect(system.withState(\.writes) == 2)
        #expect(model.restoreDeadline == nil)
        #expect(model.error == nil)
        #expect(!model.isBusy)
    }

    @Test func untilTurnedOffArmsNothing() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)

        await model.setSleepDisabled(true)

        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
    }

    @Test func aFiniteDurationChosenWhileSleepIsAllowedArmsNothingUntilTheBlock() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)

        model.setBlockDuration(.fourHours)
        await model.refresh()
        #expect(model.blockDuration == .fourHours)
        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)

        await model.setSleepDisabled(true)
        #expect(model.restoreDeadline == time.now.addingTimeInterval(4 * 3600))
        await time.waitForSleeper()
        #expect(time.sleeperCount == 1)
    }

    @Test func turningSleepBackOnCancelsTheTimer() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        await model.setSleepDisabled(false)
        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)

        time.advance(by: hour * 2)
        await letQueuedWorkRun()
        #expect(system.withState(\.writes) == 2)
    }

    @Test func aChangeMadeOutsideTheAppCancelsTheTimerAtTheNextRefresh() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        system.withState { $0.isSleepDisabled = false }
        await model.refresh()

        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
        time.advance(by: hour * 2)
        await letQueuedWorkRun()
        #expect(system.withState(\.writes) == 1)
    }

    @Test func losingTheAuthorizationCancelsTheTimer() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        // The rule disappears while sleep stays blocked: the reset could not be written.
        system.withState { $0.isAuthorized = false }
        await model.refresh()

        #expect(model.isSleepDisabled)
        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
    }

    @Test func removingTheAuthorizationCancelsTheTimer() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        await model.removeAuthorization()

        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
    }

    @Test func changingTheDurationWhileBlockedRestartsThenRemovesTheTimer() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        time.advance(by: .seconds(1800))
        model.setBlockDuration(.twoHours)
        #expect(model.restoreDeadline == time.now.addingTimeInterval(2 * 3600))
        #expect(time.sleeperCount == 0)
        await time.waitForSleeper()
        #expect(time.sleeperCount == 1)

        // The first deadline passes without effect.
        time.advance(by: .seconds(1800))
        await letQueuedWorkRun()
        #expect(model.isSleepDisabled)
        #expect(system.withState(\.writes) == 1)

        // Two hours after the change: the new deadline.
        time.advance(by: .seconds(1.5 * 3600))
        await settle { !model.isSleepDisabled && !model.isBusy }
        #expect(!model.isSleepDisabled)
        #expect(system.withState(\.writes) == 2)
    }

    @Test func choosingUntilTurnedOffWhileBlockedRemovesTheTimer() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        model.setBlockDuration(.untilTurnedOff)

        #expect(model.isSleepDisabled)
        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
        time.advance(by: hour * 2)
        await letQueuedWorkRun()
        #expect(model.isSleepDisabled)
        #expect(system.withState(\.writes) == 1)
    }

    @Test func aResetQueuedBehindAnOperationIsIgnoredWhenTheTimerWasRestarted() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        // A refresh holds the queue while the deadline passes.
        let gate = Gate()
        system.withState { $0.readGate = gate }
        let refresh = Task { await model.refresh() }
        await gate.waitUntilArrived()
        time.advance(by: hour)
        // The reset waits behind the refresh. It does not count as busy until it has its turn.
        await letQueuedWorkRun()
        #expect(!model.isBusy)
        model.setBlockDuration(.twoHours)

        await gate.open()
        await refresh.value
        await letQueuedWorkRun()

        #expect(!model.isBusy)
        #expect(model.isSleepDisabled)
        #expect(system.withState(\.writes) == 1)
        #expect(model.restoreDeadline != nil)
    }

    @Test func aStaleDeadlineLeavesTheErrorAndTheBusyStateAlone() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()
        system.withState { $0.installFailure = AuthorizationError.scriptFailed(exitCode: 1, message: "boom") }
        await model.installAuthorization()
        #expect(model.actionError != nil)

        let busyChanged = flagChanges { _ = model.isBusy }

        // The wait ends, then the timer restarts before the task that queues the reset runs.
        time.advance(by: hour)
        model.setBlockDuration(.twoHours)
        await letQueuedWorkRun()

        #expect(model.actionError != nil)
        #expect(!busyChanged.isRaised)
        #expect(system.withState(\.writes) == 1)
    }

    @Test func aFailedResetShowsAnActionErrorAndIsNotRetried() async {
        let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()
        system.withState { $0.writeFailure = failure }

        time.advance(by: hour)
        await settle { model.actionError != nil && !model.isBusy && model.restoreDeadline == nil }

        #expect(model.actionError == .sleepControl(failure))
        #expect(model.isSleepDisabled)
        // The deadline passed: it does not stay on screen, and nothing waits for it again.
        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
        #expect(model.lastAutomaticRestore == nil)

        system.withState { $0.writeFailure = nil }
        time.advance(by: hour * 4)
        await letQueuedWorkRun()
        await model.refresh()
        #expect(system.withState(\.writes) == 2)
        #expect(model.isSleepDisabled)
    }

    @Test func theDeadlineIsTheLastAutomaticRestoreUntilTheUserActs() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let power = FakePowerMonitor(.onBattery(80))
        let notifier = FakeSleepRestoreNotifier()
        let model = makeModel(system, power: power, notifier: notifier, time: time)
        model.startMonitoring()
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()
        #expect(model.lastAutomaticRestore == nil)

        time.advance(by: hour)
        await settle { model.lastAutomaticRestore != nil && !model.isBusy }
        #expect(model.lastAutomaticRestore == .timer)
        #expect(notifier.notifications == [.timer])

        // Only the low battery news goes away with the charger.
        power.send(.onACPower(80))
        await letQueuedWorkRun()
        #expect(model.lastAutomaticRestore == .timer)

        model.setBlockDuration(.twoHours)
        #expect(model.lastAutomaticRestore == nil)
    }

    @Test func quittingCancelsTheTimerAndNothingRearmsIt() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()

        await model.allowSleepBeforeQuitting()
        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
        #expect(system.withState(\.writes) == 2)

        model.setBlockDuration(.twoHours)
        #expect(model.restoreDeadline == nil)
        time.advance(by: hour * 4)
        await letQueuedWorkRun()
        #expect(system.withState(\.writes) == 2)
    }

    @Test func aToggleThatEndsAfterTheQuitDoesNotArmTheTimer() async {
        let system = FakeSystem(authorized: true)
        let time = ManualTimeSource()
        let model = makeModel(system, time: time)
        model.setBlockDuration(.oneHour)
        let gate = Gate()
        system.withState { $0.writeGate = gate }

        let toggle = Task { await model.setSleepDisabled(true) }
        await gate.waitUntilArrived()
        let quit = Task { await model.allowSleepBeforeQuitting() }
        await gate.open()
        await toggle.value
        await quit.value

        #expect(model.restoreDeadline == nil)
        #expect(time.sleeperCount == 0)
    }

    @Test(arguments: [
        (BlockDuration.untilTurnedOff, nil),
        (.oneHour, Duration.seconds(3600)),
        (.twoHours, .seconds(7200)),
        (.fourHours, .seconds(14400)),
    ])
    func theChoicesCarryTheirInterval(duration: BlockDuration, interval: Duration?) {
        #expect(duration.interval == interval)
        #expect(BlockDuration.allCases.contains(duration))
    }
}
