import Foundation
import Testing
@testable import StayLitCore

/// A model with a pretend Mac, a pretend battery, a pretend thermal state and a clock the test
/// moves by hand.
@MainActor
private struct Rig {
    let system: FakeSystem
    let power: FakePowerMonitor
    let thermal: FakeThermalMonitor
    let notifier = FakeSleepRestoreNotifier()
    let claude = FakeClaudeSessionReader(.working)
    let lid = FakeLidReader(isClosed: true)
    let sleeper = FakeSystemSleeper()
    let time = ManualTimeSource()
    let model: AppModel
    let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")

    init(
        sleepDisabled: Bool = false,
        power: FakePowerMonitor = FakePowerMonitor(.onBattery(50)),
        thermal: FakeThermalMonitor = FakeThermalMonitor(.nominal),
        batteryGuardEnabled: Bool = true
    ) {
        system = FakeSystem(sleepDisabled: sleepDisabled, authorized: true)
        self.power = power
        self.thermal = thermal
        model = makeModel(
            system, power: power, thermal: thermal, claudeSessions: claude, lid: lid, systemSleeper: sleeper,
            notifier: notifier, batteryGuardEnabled: batteryGuardEnabled, time: time
        )
    }

    /// Sleep blocked for an hour, then the deadline passes while the write fails.
    func failTheDeadline() async {
        model.setBlockDuration(.oneHour)
        await model.setSleepDisabled(true)
        await time.waitForSleeper()
        await model.startAndAwaitFirstReading()
        system.withState { $0.writeFailure = failure }
        time.advance(by: .seconds(3600))
        await settle { model.actionError != nil && !model.isBusy && model.restoreDeadline == nil }
        system.withState { $0.writeFailure = nil }
    }

    /// Sleep blocked, then a guard fires while the write fails. `armingTheTimer` first chooses an
    /// hour, so the deadline can come next.
    func failTheGuard(_ trigger: Trigger = .lowBattery, armingTheTimer: Bool = false) async {
        if armingTheTimer { model.setBlockDuration(.oneHour) }
        await model.setSleepDisabled(true)
        if armingTheTimer { await time.waitForSleeper() }
        await model.startAndAwaitFirstReading()
        system.withState { $0.writeFailure = failure }
        fire(trigger)
        await settle { model.actionError != nil && !model.isBusy }
        // The first refresh may still be about to check the guard: let it end before the test acts.
        await letQueuedWorkRun()
        system.withState { $0.writeFailure = nil }
    }

    func fire(_ trigger: Trigger) {
        switch trigger {
        case .deadline: time.advance(by: .seconds(3600))
        case .lowBattery: power.send(.onBattery(19))
        case .highTemperature: thermal.send(.serious)
        }
    }
}

/// What makes the app allow sleep again by itself, as `Rig.fire` sends it.
private enum Trigger {
    case deadline
    case lowBattery
    case highTemperature

    var reason: RestoreReason {
        switch self {
        case .deadline: .timer
        case .lowBattery: .lowBattery(percent: 19)
        case .highTemperature: .highTemperature
        }
    }
}

/// An action of the user that touches sleep or a guard.
private enum SleepOrGuardChange: CaseIterable {
    case turnSleepOff
    case chooseDuration
    case turnGuardOff
    case turnTemperatureGuardOff

    @MainActor func apply(to model: AppModel) async {
        switch self {
        case .turnSleepOff: await model.setSleepDisabled(false)
        case .chooseDuration: model.setBlockDuration(.oneHour)
        case .turnGuardOff: await model.setBatteryGuardEnabled(false)
        case .turnTemperatureGuardOff: await model.setTemperatureGuardEnabled(false)
        }
    }
}

@MainActor
struct AutomaticRestoreTests {
    // MARK: One failure per kind of reason

    @Test(arguments: [
        (Trigger.deadline, Trigger.lowBattery), (.lowBattery, .deadline),
        (.deadline, .highTemperature), (.highTemperature, .deadline),
        (.lowBattery, .highTemperature), (.highTemperature, .lowBattery),
    ])
    private func aFailedRestoreDoesNotStopAnotherKind(failed: Trigger, next: Trigger) async {
        let rig = Rig()
        if failed == .deadline {
            await rig.failTheDeadline()
        } else {
            await rig.failTheGuard(failed, armingTheTimer: next == .deadline)
        }
        #expect(rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 2)

        rig.fire(next)
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.model.lastAutomaticRestore == next.reason)
        #expect(rig.notifier.notifications == [next.reason])
    }

    @Test func aFailedGuardIsNotRetriedByTheGuard() async {
        let rig = Rig()
        await rig.failTheGuard()

        rig.power.send(.onBattery(18))
        await letQueuedWorkRun()
        await rig.model.refresh()

        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.model.isSleepDisabled)
    }

    // MARK: Allowing restores again

    @Test func choosingADurationLetsTheGuardTryAgain() async {
        let rig = Rig()
        await rig.failTheGuard()

        rig.model.setBlockDuration(.oneHour)
        rig.power.send(.onBattery(16))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(rig.system.withState(\.writes) == 3)
    }

    @Test func turningTheGuardOnAgainLetsItTryAtOnce() async {
        let rig = Rig()
        await rig.failTheGuard()

        await rig.model.setBatteryGuardEnabled(true)

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 3)
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 19))
    }

    @Test func blockingSleepAgainLetsTheDeadlineTryAgain() async {
        let rig = Rig()
        await rig.failTheDeadline()

        await rig.model.setSleepDisabled(true)
        await rig.time.waitForSleeper()
        rig.time.advance(by: .seconds(3600))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 4)
        #expect(rig.notifier.notifications == [.timer])
    }

    @Test(arguments: [Trigger.lowBattery, .highTemperature], SleepOrGuardChange.allCases)
    private func anActionOnSleepOrTheGuardClearsTheLastAutomaticRestore(
        trigger: Trigger, change: SleepOrGuardChange
    ) async {
        let rig = Rig(sleepDisabled: true)
        await rig.model.startAndAwaitFirstReading()
        rig.fire(trigger)
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }
        #expect(rig.model.lastAutomaticRestore == trigger.reason)

        await change.apply(to: rig.model)

        #expect(rig.model.lastAutomaticRestore == nil)
    }

    // MARK: Both guards at once

    // The battery is left out: plugging in already clears its news, so no reading is needed.
    @Test(arguments: [Trigger.deadline, .highTemperature])
    private func sleepBlockedAgainElsewhereClearsTheLastAutomaticRestore(trigger: Trigger) async {
        let rig = Rig()
        rig.model.setBlockDuration(.oneHour)
        await rig.model.setSleepDisabled(true)
        await rig.time.waitForSleeper()
        await rig.model.startAndAwaitFirstReading()
        rig.fire(trigger)
        await settle { rig.model.lastAutomaticRestore == trigger.reason && !rig.model.isBusy }
        rig.thermal.send(.nominal)
        await letQueuedWorkRun()
        #expect(rig.model.lastAutomaticRestore == trigger.reason)

        // A terminal blocks sleep: the model never hears of it but from the next reading.
        rig.system.withState { $0.isSleepDisabled = true }
        await rig.model.refresh()

        #expect(rig.model.isSleepDisabled)
        #expect(rig.model.lastAutomaticRestore == nil)
    }

    @Test func aLowBatteryAndAHotMacRestoreSleepOnceForTheBattery() async {
        let rig = Rig(
            sleepDisabled: true, power: FakePowerMonitor(.onBattery(10)), thermal: FakeThermalMonitor(.serious)
        )

        await rig.model.startAndAwaitFirstReading()
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }
        // No second write for the temperature: let any later check run before counting.
        await letQueuedWorkRun()

        #expect(rig.system.withState(\.writes) == 1)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 10)])
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)
    }

    // MARK: The Claude guard comes last

    /// Claude Code finished a minute ago, the lid is closed, and `trigger` applies at the same time.
    /// `changeWithoutEvent` lets the next refresh find both, as it would after a missed event.
    @Test(arguments: [Trigger.lowBattery, .highTemperature])
    private func anotherGuardWinsOverTheClaudeGuard(trigger: Trigger) async {
        let rig = Rig(sleepDisabled: true)
        await rig.model.startAndAwaitFirstReading()
        rig.claude.value = .idle
        await rig.model.refresh()
        rig.time.advance(by: .seconds(60))
        switch trigger {
        case .lowBattery: rig.power.changeWithoutEvent(.onBattery(10))
        case .highTemperature: rig.thermal.changeWithoutEvent(.serious)
        case .deadline: break
        }

        await rig.model.refresh()
        await letQueuedWorkRun()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 1)
        let reason: RestoreReason = trigger == .lowBattery ? .lowBattery(percent: 10) : .highTemperature
        #expect(rig.notifier.notifications == [reason])
        #expect(rig.model.lastAutomaticRestore == reason)
        #expect(rig.sleeper.sleepNowCount == 0)
    }

    @Test func theBatteryGuardCaptionComesBeforeTheTemperature() async {
        let rig = Rig(power: FakePowerMonitor(.onBattery(10)), thermal: FakeThermalMonitor(.critical))
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)

        await rig.model.setBatteryGuardEnabled(false)
        #expect(rig.model.sleepControl == .blockedByTemperatureGuard)

        await rig.model.setSleepDisabled(true)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
    }

    @Test func pluggingInKeepsTheTemperatureNews() async {
        let rig = Rig(
            sleepDisabled: true,
            power: FakePowerMonitor(.onBattery(10)),
            thermal: FakeThermalMonitor(.serious),
            batteryGuardEnabled: false
        )
        await rig.model.startAndAwaitFirstReading()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }
        #expect(rig.model.lastAutomaticRestore == .highTemperature)

        rig.power.send(.onACPower(10))
        // Nothing should change: let the event go through before checking.
        await letQueuedWorkRun()

        #expect(rig.model.lastAutomaticRestore == .highTemperature)
    }

    @Test func coolingDownKeepsTheBatteryNews() async {
        let rig = Rig(
            sleepDisabled: true, power: FakePowerMonitor(.onBattery(10)), thermal: FakeThermalMonitor(.serious)
        )
        await rig.model.startAndAwaitFirstReading()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))

        rig.thermal.send(.nominal)
        // Nothing should change: let the event go through before checking.
        await letQueuedWorkRun()

        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))
    }

    // MARK: Other actions leave both alone

    @Test func theLoginItemDoesNotLetAFailedRestoreTryAgain() async {
        let rig = Rig()
        await rig.failTheGuard()

        await rig.model.setLaunchAtLogin(true)
        rig.power.send(.onBattery(16))
        await letQueuedWorkRun()

        #expect(rig.system.withState(\.writes) == 2)
        #expect(rig.model.isSleepDisabled)
    }

    @Test func theLoginItemAndTheAuthorizationKeepTheLastAutomaticRestore() async {
        let rig = Rig(sleepDisabled: true, power: FakePowerMonitor(.onBattery(10)))
        await rig.model.startAndAwaitFirstReading()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }

        await rig.model.setLaunchAtLogin(true)
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))
        await rig.model.installAuthorization()
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))
        await rig.model.removeAuthorization()
        #expect(rig.model.lastAutomaticRestore == .lowBattery(percent: 10))
    }

    // MARK: Reading the battery at each refresh

    @Test func aRefreshAppliesABatteryStateTheStreamNeverSent() async {
        let rig = Rig(sleepDisabled: true)
        await rig.model.startAndAwaitFirstReading()
        #expect(rig.model.isSleepDisabled)

        rig.power.changeWithoutEvent(.onBattery(10))
        await rig.model.refresh()

        #expect(rig.model.isBatteryLow)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 10)])
    }

    @Test func thePeriodicRefreshAppliesItToo() async {
        let rig = Rig(sleepDisabled: true)
        await rig.model.startAndAwaitFirstReading()
        // The first refresh queues its guard check after its reading, and the periodic refresh
        // skips its turn while anything is queued.
        await letQueuedWorkRun()

        rig.power.changeWithoutEvent(.onBattery(10))
        await rig.model.refreshPeriodically()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 10)])
    }

    @Test func thePeriodicRefreshStaysLightWhileItReadsTheBattery() async {
        let loginItem = FakeLaunchAtLogin()
        let system = FakeSystem(authorized: true)
        let power = FakePowerMonitor(nil)
        let model = makeModel(system, launchAtLogin: loginItem, power: power)
        let loginReadsBefore = loginItem.statusReads
        #expect(!model.hasBattery)

        power.changeWithoutEvent(.onBattery(30))
        await model.refreshPeriodically()

        #expect(model.hasBattery)
        #expect(system.withState(\.sleepReads) == 1)
        #expect(system.withState(\.statusReads) == 0)
        #expect(loginItem.statusReads == loginReadsBefore)
    }

    @Test func aRefreshForgetsTheLowBatteryNewsOnceOffBattery() async {
        let rig = Rig(sleepDisabled: true, power: FakePowerMonitor(.onBattery(10)))
        await rig.model.startAndAwaitFirstReading()
        await settle { rig.model.lastAutomaticRestore != nil && !rig.model.isBusy }

        rig.power.changeWithoutEvent(.onACPower(10))
        await rig.model.refresh()

        #expect(rig.model.lastAutomaticRestore == nil)
    }

    @Test func aStreamThatEndedAtOnceDoesNotBreakTheModel() async {
        let rig = Rig(sleepDisabled: true, power: FakePowerMonitor(.onBattery(50), streamEnds: true))
        await rig.model.startAndAwaitFirstReading()
        #expect(rig.model.hasBattery)
        #expect(rig.model.isSleepDisabled)

        rig.power.changeWithoutEvent(.onBattery(10))
        await rig.model.refresh()

        #expect(rig.model.isBatteryLow)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.notifier.notifications == [.lowBattery(percent: 10)])
        #expect(rig.model.error == nil)

        await rig.model.setSleepDisabled(true)
        #expect(!rig.model.isSleepDisabled)
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)
    }
}
