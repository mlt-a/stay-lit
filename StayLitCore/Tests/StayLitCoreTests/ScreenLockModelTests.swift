import Testing
@testable import StayLitCore

/// A model that took its first reading, with a clock the test moves by hand. Sleep is blocked
/// and the lid open unless the test says otherwise.
@MainActor
private struct Rig {
    let system: FakeSystem
    let lid: FakeLidReader
    let locker: FakeScreenLocker
    let time = ManualTimeSource()
    let model: AppModel

    init(lidClosed: Bool = false, sleepBlocked: Bool = true, lockFails: Bool = false) async {
        system = FakeSystem(sleepDisabled: sleepBlocked, authorized: true)
        lid = FakeLidReader(isClosed: lidClosed)
        locker = FakeScreenLocker(fails: lockFails)
        model = makeModel(system, lid: lid, screenLocker: locker, time: time)
        await model.startAndAwaitFirstReading()
    }

    /// Lets ten seconds pass, then reads again: the pace of the periodic refresh.
    func refresh() async {
        time.advance(by: .seconds(10))
        await model.refresh()
        await letQueuedWorkRun()
    }

    func closeTheLid() async {
        lid.isClosed = true
        await refresh()
    }

    func openTheLid() async {
        lid.isClosed = false
        await refresh()
    }
}

@MainActor
struct ScreenLockModelTests {
    @Test func closingTheLidWithSleepBlockedLocksTheScreenOnce() async {
        let rig = await Rig()
        await rig.closeTheLid()
        #expect(rig.locker.lockCount == 1)
        #expect(rig.model.error == nil)
    }

    @Test func aLidThatStaysClosedDoesNotLockAgain() async {
        let rig = await Rig()
        await rig.closeTheLid()
        await rig.refresh()
        await rig.refresh()
        #expect(rig.locker.lockCount == 1)
    }

    @Test func closingTheLidAgainLocksASecondTime() async {
        let rig = await Rig()
        await rig.closeTheLid()
        await rig.openTheLid()
        await rig.closeTheLid()
        #expect(rig.locker.lockCount == 2)
    }

    @Test func aLidAlreadyClosedAtTheFirstReadingDoesNotLock() async {
        let rig = await Rig(lidClosed: true)
        await rig.refresh()
        #expect(rig.locker.lockCount == 0)
    }

    @Test func aLidClosedWhileSleepWasAllowedDoesNotLockWhenSleepIsBlocked() async {
        let rig = await Rig(sleepBlocked: false)
        await rig.closeTheLid()
        rig.system.withState { $0.isSleepDisabled = true }
        await rig.refresh()
        await rig.refresh()
        #expect(rig.locker.lockCount == 0)
    }

    @Test func aFailedLockShowsAnErrorThatDismissingClears() async {
        let rig = await Rig(lockFails: true)
        await rig.closeTheLid()
        #expect(rig.locker.lockCount == 1)
        #expect(rig.model.error == .screenLockUnavailable)
        rig.model.dismissError()
        #expect(rig.model.error == nil)
    }

    @Test func aSuccessfulLockAfterAFailureClearsTheError() async {
        let rig = await Rig(lockFails: true)
        await rig.closeTheLid()
        #expect(rig.model.error == .screenLockUnavailable)
        rig.locker.fails = false
        await rig.openTheLid()
        await rig.closeTheLid()
        #expect(rig.locker.lockCount == 2)
        #expect(rig.model.error == nil)
    }

    @Test func aLidClosedWhileAnOperationHoldsTheQueueLocksOnce() async {
        let rig = await Rig()
        let gate = Gate()
        rig.system.withState { $0.writeGate = gate }
        let toggle = Task { await rig.model.setSleepDisabled(true) }
        await gate.waitUntilArrived()

        rig.lid.isClosed = true
        await rig.model.refreshPeriodically()
        #expect(rig.locker.lockCount == 1)

        await gate.open()
        await toggle.value
        await rig.refresh()
        #expect(rig.locker.lockCount == 1)
    }

    @Test func sleepAllowedThenBlockedAgainWithTheLidOpenLocksWhenTheLidCloses() async {
        let rig = await Rig()
        rig.system.withState { $0.isSleepDisabled = false }
        await rig.refresh()
        rig.system.withState { $0.isSleepDisabled = true }
        await rig.refresh()
        await rig.closeTheLid()
        #expect(rig.locker.lockCount == 1)
    }

    @Test func aFailedSleepReadingBetweenOpenAndClosedDoesNotForgetTheOpenLid() async {
        let rig = await Rig()
        rig.system.withState { $0.readFailure = SleepControlError.commandFailed(command: "pmset -g", exitCode: 1, message: "nope") }
        await rig.closeTheLid()
        #expect(rig.locker.lockCount == 0)

        rig.system.withState { $0.readFailure = nil }
        await rig.refresh()
        #expect(rig.locker.lockCount == 1)
    }

    @Test func dismissingAnotherErrorKeepsAScreenLockErrorHiddenBehindIt() async {
        let rig = await Rig(lockFails: true)
        await rig.closeTheLid()
        let failure = SleepControlError.commandFailed(command: "pmset -g", exitCode: 1, message: "nope")
        rig.system.withState { $0.readFailure = failure }
        await rig.refresh()
        #expect(rig.model.error == .sleepControl(failure))

        rig.model.dismissError()
        #expect(rig.model.error == .screenLockUnavailable)
        rig.model.dismissError()
        #expect(rig.model.error == nil)
    }
}
