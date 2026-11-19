import Foundation
import Testing
@testable import StayLitCore

/// A model with a pretend Mac, a pretend battery and a double for the notification.
@MainActor
private struct Rig {
    let system: FakeSystem
    let power: FakePowerMonitor
    let notifier = FakeSleepRestoreNotifier()
    let time = ManualTimeSource()
    let model: AppModel

    init(sleepDisabled: Bool = false, battery: PowerState? = .onBattery(50), guardEnabled: Bool = true) {
        system = FakeSystem(sleepDisabled: sleepDisabled, authorized: true)
        power = FakePowerMonitor(battery)
        model = makeModel(system, power: power, notifier: notifier, batteryGuardEnabled: guardEnabled, time: time)
    }

    /// Starts watching and waits for the first reading to end.
    func start() async {
        model.startMonitoring()
        await settle { model.authorization != nil && !model.isBusy }
    }
}

@MainActor
struct BatteryGuardModelTests {
    // MARK: Firing

    @Test func fallingToTheThresholdOnBatteryAllowsSleepAndTellsTheUser() async {
        let rig = Rig()
        rig.model.setBlockDuration(.oneHour)
        await rig.model.setSleepDisabled(true)
        await rig.time.waitForSleeper()
        await rig.start()
        #expect(rig.model.isSleepDisabled)

        rig.power.send(.onBattery(20))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(!rig.model.isSleepDisabled)
        #expect(!rig.system.withState(\.isSleepDisabled))
        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 20)])
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 20))
        #expect(rig.model.restoreDeadline == nil)
        #expect(rig.time.sleeperCount == 0)
        #expect(rig.model.error == nil)
    }

    @Test func aBatteryAlreadyLowAtLaunchWithSleepBlockedIsHandledAtOnce() async {
        let rig = Rig(sleepDisabled: true, battery: .onBattery(10))

        await rig.start()
        await settle { !rig.model.isSleepDisabled }

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 10)])
    }

    @Test func sleepBlockedElsewhereWhileTheBatteryIsLowIsUndoneAtTheNextRefresh() async {
        let rig = Rig(battery: .onBattery(15))
        await rig.start()
        #expect(rig.system.withState(\.writes) == 0)

        rig.system.withState { $0.isSleepDisabled = true }
        await rig.model.refresh()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 15)])
    }

    // MARK: Staying quiet

    @Test func theSamePercentOnTheChargerDoesNothing() async {
        let rig = Rig(sleepDisabled: true)
        await rig.start()

        rig.power.send(.onACPower(10))
        await letQueuedWorkRun()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.notifier.notifications.isEmpty)
        #expect(rig.model.lastAutomaticRestore == nil)
    }

    @Test func aPercentAboveTheThresholdDoesNothing() async {
        let rig = Rig(sleepDisabled: true)
        await rig.start()

        rig.power.send(.onBattery(21))
        await letQueuedWorkRun()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
    }

    @Test func aDisabledGuardDoesNothing() async {
        let rig = Rig(guardEnabled: false)
        await rig.start()

        rig.power.send(.onBattery(5))
        await letQueuedWorkRun()
        #expect(rig.model.sleepControl == .available)

        await rig.model.setSleepDisabled(true)
        await letQueuedWorkRun()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.notifier.notifications.isEmpty)
    }

    @Test func aMacWithoutABatteryHidesTheSettingAndDoesNothing() async {
        let rig = Rig(sleepDisabled: true, battery: nil)
        #expect(!rig.model.hasBattery)
        await rig.start()

        rig.power.send(nil)
        await letQueuedWorkRun()

        #expect(!rig.model.hasBattery)
        #expect(!rig.model.isBatteryLow)
        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.notifier.notifications.isEmpty)
        #expect(rig.model.sleepControl == .available)
    }

    @Test func aMacWithABatteryShowsTheSetting() {
        #expect(Rig().model.hasBattery)
    }

    @Test func theBatteryFlagsChangeOnlyWhenTheyFlip() async {
        let rig = Rig(battery: .onBattery(50))
        await rig.start()

        let unchanged = flagChanges {
            _ = rig.model.hasBattery
            _ = rig.model.isBatteryLow
        }
        rig.power.send(.onBattery(49))
        rig.power.send(.onBattery(21))
        await letQueuedWorkRun()
        #expect(!unchanged.isRaised)

        let crossed = flagChanges { _ = rig.model.isBatteryLow }
        rig.power.send(.onBattery(20))
        await settle { rig.model.isBatteryLow }
        #expect(crossed.isRaised)
        #expect(rig.model.hasBattery)
    }

    // MARK: The switch

    @Test func blockingSleepIsRefusedByTheModelBelowTheThreshold() async {
        let rig = Rig(battery: .onBattery(20))
        // The guard is known before the first check ends.
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)

        await rig.model.setSleepDisabled(true)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.model.error == nil)
        #expect(!rig.model.isBusy)
    }

    @Test func blockingSleepIsAllowedJustAboveTheThreshold() async {
        let rig = Rig(battery: .onBattery(21))
        #expect(rig.model.sleepControl == .authorizationUnknown)

        await rig.model.setSleepDisabled(true)

        #expect(rig.model.isSleepDisabled)
    }

    @Test func theGuardStateStaysWhileAnActionRuns() async {
        let rig = Rig(battery: .onBattery(10))
        await rig.start()
        let gate = Gate()
        rig.system.withState { $0.writeGate = gate }

        let allow = Task { await rig.model.setSleepDisabled(false) }
        await gate.waitUntilArrived()
        #expect(rig.model.isBusy)
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)

        await gate.open()
        await allow.value
    }

    @Test func allowingSleepIsNeverRefused() async {
        let rig = Rig(sleepDisabled: true, battery: .onBattery(50))
        await rig.model.refresh()

        rig.power.send(.onBattery(10))
        await rig.model.setSleepDisabled(false)

        #expect(!rig.model.isSleepDisabled)
    }

    @Test func pluggingInUnblocksTheSwitch() async {
        let rig = Rig(battery: .onBattery(15))
        await rig.start()
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)

        rig.power.send(.onACPower(15))
        await settle { rig.model.sleepControl == .available }
        await rig.model.setSleepDisabled(true)

        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
    }

    @Test func pluggingInClearsTheMessage() async {
        let rig = Rig(sleepDisabled: true, battery: .onBattery(10))
        await rig.start()
        await settle { rig.model.lastAutomaticRestore != nil }
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))

        rig.power.send(.onACPower(10))
        await settle { rig.model.lastAutomaticRestore == nil }

        #expect(rig.model.lastAutomaticRestore == nil)
        #expect(!rig.model.isSleepDisabled)
    }

    @Test func theNextActionOfTheUserClearsTheMessage() async {
        let rig = Rig(sleepDisabled: true, battery: .onBattery(10))
        await rig.start()
        await settle { rig.model.lastAutomaticRestore != nil }
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))

        await rig.model.setBatteryGuardEnabled(false)

        #expect(rig.model.lastAutomaticRestore == nil)
    }

    // MARK: The setting

    @Test func turningTheSettingBackOnActsAtOnceWhenTheBatteryIsLow() async {
        let saved = SavedSettings()
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        let model = makeModel(
            system, power: FakePowerMonitor(.onBattery(10)), batteryGuardEnabled: false, onBatteryGuardChange: saved.save
        )
        await model.refresh()
        #expect(model.isSleepDisabled)

        await model.setBatteryGuardEnabled(true)

        #expect(model.isBatteryGuardEnabled)
        #expect(saved.values == [true])
        #expect(!model.isSleepDisabled)
        #expect(model.lastAutomaticRestore == .lowBattery(percent: 10))
    }

    @Test func turningTheSettingOffUnblocksTheSwitchAndHandsOverTheChoice() async {
        let saved = SavedSettings()
        let model = makeModel(
            FakeSystem(authorized: true), power: FakePowerMonitor(.onBattery(10)), onBatteryGuardChange: saved.save
        )
        #expect(model.sleepControl == .blockedByBatteryGuard)

        await model.setBatteryGuardEnabled(false)
        #expect(model.sleepControl == .available)
        #expect(saved.values == [false])

        await model.setSleepDisabled(true)
        #expect(model.isSleepDisabled)
    }

    @Test func theModelStartsFromTheStoredSetting() {
        #expect(!makeModel(batteryGuardEnabled: false).isBatteryGuardEnabled)
        #expect(makeModel(batteryGuardEnabled: true).isBatteryGuardEnabled)
    }

    // MARK: Failure

    /// The guard fails once, with sleep still blocked.
    private func failedRig() async -> (Rig, AppModelError) {
        let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        let rig = Rig()
        await rig.model.setSleepDisabled(true)
        await rig.start()
        rig.system.withState { $0.writeFailure = failure }
        rig.power.send(.onBattery(19))
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

        rig.power.send(.onBattery(18))
        await letQueuedWorkRun()
        rig.power.send(.onBattery(17))
        await letQueuedWorkRun()
        await rig.model.refresh()

        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.model.actionError == failure)
        #expect(rig.model.isSleepDisabled)
    }

    @Test func anActionOfTheUserLetsTheGuardTryAgain() async {
        let (rig, _) = await failedRig()

        rig.model.setBlockDuration(.oneHour)
        rig.power.send(.onBattery(16))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 16)])
    }

    @Test func readingSleepAllowedLetsTheGuardTryAgain() async {
        let (rig, _) = await failedRig()

        rig.system.withState { $0.isSleepDisabled = false }
        await rig.model.refresh()
        rig.system.withState { $0.isSleepDisabled = true }
        await rig.model.refresh()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 19)])
    }

    @Test func aRestoreThatNoLongerAppliesInTheQueueLeavesTheWindowAlone() async {
        let rig = Rig(sleepDisabled: true)
        await rig.start()
        rig.system.withState { $0.installFailure = AuthorizationError.scriptFailed(exitCode: 1, message: "boom") }
        await rig.model.installAuthorization()
        let shown = rig.model.actionError
        #expect(shown != nil)

        // A refresh reads "allowed", made elsewhere, and holds the queue before it says so.
        let gate = Gate()
        rig.system.withState {
            $0.isSleepDisabled = false
            $0.readGate = gate
        }
        let refresh = Task { await rig.model.refresh() }
        await gate.waitUntilArrived()
        let busyChanged = flagChanges { _ = rig.model.isBusy }
        // The guard's restore waits behind the refresh, with sleep still blocked as far as it knows.
        rig.power.send(.onBattery(10))
        await letQueuedWorkRun()

        await gate.open()
        await refresh.value
        await letQueuedWorkRun()

        #expect(!busyChanged.isRaised)
        #expect(rig.model.actionError == shown)
        #expect(rig.system.withState(\.writes) == 0)
        #expect(rig.notifier.notifications.isEmpty)
    }

    // MARK: Quitting

    @Test func aPowerEventAfterTheQuitDoesNothing() async {
        let saved = SavedSettings()
        let system = FakeSystem(authorized: true)
        let power = FakePowerMonitor(.onBattery(50))
        let model = makeModel(system, power: power, onBatteryGuardChange: saved.save)
        await model.setSleepDisabled(true)
        model.startMonitoring()
        await settle { model.authorization != nil && !model.isBusy }
        // The reset at quit fails silently: the model still believes sleep is blocked, so
        // only the quit stops the guard.
        system.withState { $0.writeFailure = SleepControlError.authorizationMissing }
        await model.allowSleepBeforeQuitting()
        let writes = system.withState(\.writes)

        power.send(.onBattery(5))
        await letQueuedWorkRun()
        await model.setBatteryGuardEnabled(false)

        #expect(system.withState(\.writes) == writes)
        #expect(!model.isBatteryLow)
        #expect(model.isBatteryGuardEnabled)
        #expect(saved.values.isEmpty)
    }
}
