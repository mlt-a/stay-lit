import Foundation
import Testing
@testable import StayLitCore

/// A model with a pretend Mac without battery, a pretend thermal state and a double for the
/// notification.
@MainActor
private struct Rig {
    let system: FakeSystem
    let thermal: FakeThermalMonitor
    let notifier = FakeSleepRestoreNotifier()
    let time = ManualTimeSource()
    let model: AppModel

    init(
        sleepDisabled: Bool = false,
        thermal: FakeThermalMonitor = FakeThermalMonitor(.nominal),
        guardEnabled: Bool = true
    ) {
        system = FakeSystem(sleepDisabled: sleepDisabled, authorized: true)
        self.thermal = thermal
        model = makeModel(system, thermal: thermal, notifier: notifier, temperatureGuardEnabled: guardEnabled, time: time)
    }

    /// Starts watching and waits for the first reading to end.
    func start() async {
        model.startMonitoring()
        await settle { model.authorization != nil && !model.isBusy }
    }
}

@MainActor
struct TemperatureGuardModelTests {
    // MARK: Firing

    @Test(arguments: [ProcessInfo.ThermalState.serious, .critical])
    func heatingUpAllowsSleepAndTellsTheUser(state: ProcessInfo.ThermalState) async {
        let rig = Rig()
        rig.model.setBlockDuration(.oneHour)
        await rig.model.setSleepDisabled(true)
        await rig.time.waitForSleeper()
        await rig.start()
        #expect(rig.model.isSleepDisabled)

        rig.thermal.send(state)
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(!rig.model.isSleepDisabled)
        #expect(!rig.system.withState(\.isSleepDisabled))
        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.notifier.notifications == [.highTemperature])
        #expect(rig.model.lastAutomaticRestore == .highTemperature)
        #expect(rig.model.restoreDeadline == nil)
        #expect(rig.time.sleeperCount == 0)
        #expect(rig.model.error == nil)
    }

    @Test func aMacAlreadyHotAtLaunchWithSleepBlockedIsHandledAtOnce() async {
        let rig = Rig(sleepDisabled: true, thermal: FakeThermalMonitor(.serious))

        await rig.start()
        await settle { !rig.model.isSleepDisabled }

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.highTemperature])
    }

    @Test func sleepBlockedElsewhereWhileTheMacIsHotIsUndoneAtTheNextRefresh() async {
        let rig = Rig(thermal: FakeThermalMonitor(.serious))
        await rig.start()
        #expect(rig.system.withState(\.writes) == 0)

        rig.system.withState { $0.isSleepDisabled = true }
        await rig.model.refresh()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.notifier.notifications == [.highTemperature])
    }

    // MARK: Staying quiet

    @Test func aFairStateDoesNothing() async {
        let rig = Rig(sleepDisabled: true)
        await rig.start()

        rig.thermal.send(.fair)
        await letQueuedWorkRun()

        #expect(rig.model.isSleepDisabled)
        #expect(!rig.model.isTooHot)
        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.notifier.notifications.isEmpty)
        #expect(rig.model.lastAutomaticRestore == nil)
    }

    @Test func aDisabledGuardDoesNothing() async {
        let rig = Rig(guardEnabled: false)
        await rig.start()

        rig.thermal.send(.critical)
        await letQueuedWorkRun()
        #expect(rig.model.sleepControl == .available)

        await rig.model.setSleepDisabled(true)
        await letQueuedWorkRun()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.notifier.notifications.isEmpty)
    }

    @Test func theTemperatureFlagChangesOnlyWhenItFlips() async {
        let rig = Rig()
        await rig.start()

        let steps: [(sent: ProcessInfo.ThermalState, flips: Bool)] = [
            (.fair, false), (.nominal, false), (.serious, true), (.critical, false),
        ]
        for (sent, flips) in steps {
            let changed = flagChanges { _ = rig.model.isTooHot }
            rig.thermal.send(sent)
            if flips { await settle { changed.isRaised } } else { await letQueuedWorkRun() }
            #expect(changed.isRaised == flips, "after sending \(sent.rawValue)")
        }
    }

    // MARK: The switch

    @Test func blockingSleepIsRefusedByTheModelWhileTheMacIsHot() async {
        let rig = Rig(thermal: FakeThermalMonitor(.serious))
        // The guard is known before the first check ends.
        #expect(rig.model.sleepControl == .blockedByTemperatureGuard)

        await rig.model.setSleepDisabled(true)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.model.error == nil)
        #expect(!rig.model.isBusy)
    }

    @Test func blockingSleepIsAllowedJustBelowTheThreshold() async {
        let rig = Rig(thermal: FakeThermalMonitor(.fair))
        #expect(rig.model.sleepControl == .authorizationUnknown)

        await rig.model.setSleepDisabled(true)

        #expect(rig.model.isSleepDisabled)
    }

    @Test func theGuardStateStaysWhileAnActionRuns() async {
        let rig = Rig(thermal: FakeThermalMonitor(.serious))
        await rig.start()
        let gate = Gate()
        rig.system.withState { $0.writeGate = gate }

        let allow = Task { await rig.model.setSleepDisabled(false) }
        await gate.waitUntilArrived()
        #expect(rig.model.isBusy)
        #expect(rig.model.sleepControl == .blockedByTemperatureGuard)

        await gate.open()
        await allow.value
    }

    @Test func allowingSleepIsNeverRefused() async {
        let rig = Rig(sleepDisabled: true)
        await rig.model.refresh()

        rig.thermal.send(.critical)
        await rig.model.setSleepDisabled(false)

        #expect(!rig.model.isSleepDisabled)
    }

    @Test func coolingDownUnblocksTheSwitch() async {
        let rig = Rig(thermal: FakeThermalMonitor(.serious))
        await rig.start()
        #expect(rig.model.sleepControl == .blockedByTemperatureGuard)

        rig.thermal.send(.fair)
        await settle { rig.model.sleepControl == .available }
        await rig.model.setSleepDisabled(true)

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
    }

    @Test func coolingDownKeepsTheMessage() async {
        let rig = Rig(sleepDisabled: true, thermal: FakeThermalMonitor(.serious))
        await rig.start()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }
        #expect(rig.model.lastAutomaticRestore == .highTemperature)

        rig.thermal.send(.fair)
        await settle { !rig.model.isTooHot }
        await letQueuedWorkRun()

        #expect(rig.model.lastAutomaticRestore == .highTemperature)
        #expect(!rig.model.isSleepDisabled)
    }

    @Test func theNextActionOfTheUserClearsTheMessage() async {
        let rig = Rig(sleepDisabled: true, thermal: FakeThermalMonitor(.serious))
        await rig.start()
        await settle { rig.model.lastAutomaticRestore != nil }
        #expect(rig.model.lastAutomaticRestore == .highTemperature)

        await rig.model.setTemperatureGuardEnabled(false)

        #expect(rig.model.lastAutomaticRestore == nil)
    }

    @Test func blockingSleepAgainAfterCoolingDownClearsTheMessage() async {
        let rig = Rig(sleepDisabled: true, thermal: FakeThermalMonitor(.serious))
        await rig.start()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }
        rig.thermal.send(.fair)
        await settle { rig.model.sleepControl == .available }
        #expect(rig.model.lastAutomaticRestore == .highTemperature)

        await rig.model.setSleepDisabled(true)

        #expect(rig.model.isSleepDisabled)
        #expect(rig.model.lastAutomaticRestore == nil)
    }

    // MARK: The setting

    @Test func turningTheSettingBackOnActsAtOnceWhenTheMacIsHot() async {
        let saved = SavedSettings()
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        let model = makeModel(
            system,
            thermal: FakeThermalMonitor(.serious),
            temperatureGuardEnabled: false,
            onTemperatureGuardChange: saved.save
        )
        await model.refresh()
        #expect(model.isSleepDisabled)

        await model.setTemperatureGuardEnabled(true)

        #expect(model.isTemperatureGuardEnabled)
        #expect(saved.values == [true])
        #expect(!model.isSleepDisabled)
        #expect(model.lastAutomaticRestore == .highTemperature)
    }

    @Test func turningTheSettingOffUnblocksTheSwitchAndHandsOverTheChoice() async {
        let saved = SavedSettings()
        let model = makeModel(
            FakeSystem(authorized: true), thermal: FakeThermalMonitor(.serious), onTemperatureGuardChange: saved.save
        )
        #expect(model.sleepControl == .blockedByTemperatureGuard)

        await model.setTemperatureGuardEnabled(false)
        #expect(model.sleepControl == .available)
        #expect(saved.values == [false])

        await model.setSleepDisabled(true)
        #expect(model.isSleepDisabled)
    }

    @Test func theModelStartsFromTheStoredSetting() {
        #expect(!makeModel(temperatureGuardEnabled: false).isTemperatureGuardEnabled)
        #expect(makeModel(temperatureGuardEnabled: true).isTemperatureGuardEnabled)
    }

    // MARK: Reading the state at each refresh

    @Test func aRefreshAppliesAThermalStateTheStreamNeverSent() async {
        let rig = Rig(sleepDisabled: true)
        await rig.start()
        #expect(rig.model.isSleepDisabled)

        rig.thermal.changeWithoutEvent(.serious)
        await rig.model.refresh()

        #expect(rig.model.isTooHot)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.highTemperature])
    }

    @Test func thePeriodicRefreshAppliesItToo() async {
        let rig = Rig(sleepDisabled: true)
        await rig.start()
        // The first refresh queues its guard check after its reading, and the periodic refresh
        // skips its turn while anything is queued.
        await letQueuedWorkRun()

        rig.thermal.changeWithoutEvent(.critical)
        await rig.model.refreshPeriodically()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.highTemperature])
    }

    @Test func aRefreshKeepsTheHighTemperatureNewsOnceCool() async {
        let rig = Rig(sleepDisabled: true, thermal: FakeThermalMonitor(.serious))
        await rig.start()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }

        rig.thermal.changeWithoutEvent(.nominal)
        await rig.model.refresh()

        #expect(!rig.model.isTooHot)
        #expect(rig.model.lastAutomaticRestore == .highTemperature)
    }

    @Test func aStreamThatEndedAtOnceDoesNotBreakTheModel() async {
        let rig = Rig(sleepDisabled: true, thermal: FakeThermalMonitor(.nominal, streamEnds: true))
        await rig.start()
        #expect(rig.model.isSleepDisabled)

        rig.thermal.changeWithoutEvent(.serious)
        await rig.model.refresh()

        #expect(rig.model.isTooHot)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.highTemperature])
        #expect(rig.model.error == nil)

        await rig.model.setSleepDisabled(true)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.model.sleepControl == .blockedByTemperatureGuard)
    }

    // MARK: Failure

    /// The guard fails once, with sleep still blocked.
    private func failedRig() async -> (Rig, AppModelError) {
        let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        let rig = Rig()
        await rig.model.setSleepDisabled(true)
        await rig.start()
        rig.system.withState { $0.writeFailure = failure }
        rig.thermal.send(.serious)
        await settle { rig.model.actionError != nil && !rig.model.isBusy }
        // The first refresh may still be about to check the guard: let it end before the test acts.
        await letQueuedWorkRun()
        rig.system.withState { $0.writeFailure = nil }
        return (rig, .sleepControl(failure))
    }

    @Test func aFailedResetShowsOneErrorAndIsNotRetriedAtEveryEvent() async {
        let (rig, failure) = await failedRig()
        #expect(rig.model.actionError == failure)
        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.notifier.notifications.isEmpty)
        #expect(rig.model.lastAutomaticRestore == nil)

        rig.thermal.send(.critical)
        await letQueuedWorkRun()
        rig.thermal.send(.serious)
        await letQueuedWorkRun()
        await rig.model.refresh()

        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.model.actionError == failure)
        #expect(rig.model.isSleepDisabled)
    }

    @Test func anActionOfTheUserLetsTheGuardTryAgain() async {
        let (rig, _) = await failedRig()

        rig.model.setBlockDuration(.oneHour)
        rig.thermal.send(.critical)
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.notifier.notifications == [.highTemperature])
    }

    @Test func readingSleepAllowedLetsTheGuardTryAgain() async {
        let (rig, _) = await failedRig()

        rig.system.withState { $0.isSleepDisabled = false }
        await rig.model.refresh()
        rig.system.withState { $0.isSleepDisabled = true }
        await rig.model.refresh()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.notifier.notifications == [.highTemperature])
    }

    @Test func turningTheGuardOnAgainLetsItTryAtOnce() async {
        let (rig, _) = await failedRig()

        await rig.model.setTemperatureGuardEnabled(true)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.model.lastAutomaticRestore == .highTemperature)
    }

    // MARK: Quitting

    @Test func aThermalEventAfterTheQuitDoesNothing() async {
        let saved = SavedSettings()
        let system = FakeSystem(authorized: true)
        let thermal = FakeThermalMonitor(.nominal)
        let model = makeModel(system, thermal: thermal, onTemperatureGuardChange: saved.save)
        await model.setSleepDisabled(true)
        model.startMonitoring()
        await settle { model.authorization != nil && !model.isBusy }
        // The reset at quit fails silently: the model still believes sleep is blocked, so
        // only the quit stops the guard.
        system.withState { $0.writeFailure = SleepControlError.authorizationMissing }
        await model.allowSleepBeforeQuitting()
        let writes = system.withState(\.writes)

        thermal.send(.critical)
        await letQueuedWorkRun()
        await model.setTemperatureGuardEnabled(false)

        #expect(system.withState(\.writes) == writes)
        #expect(!model.isTooHot)
        #expect(model.isTemperatureGuardEnabled)
        #expect(saved.values.isEmpty)
    }
}
