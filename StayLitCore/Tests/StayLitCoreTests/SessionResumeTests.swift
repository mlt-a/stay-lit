import Foundation
import Testing
@testable import StayLitCore

/// A model with a pretend Mac, battery, thermal state, Claude Code, lid and session,
/// sleep chosen for an hour, and a clock the test moves by hand.
@MainActor
private struct Rig {
    let system = FakeSystem(authorized: true)
    let power = FakePowerMonitor(.onBattery(50))
    let thermal = FakeThermalMonitor(.nominal)
    let claude = FakeClaudeSessionReader(.working)
    let lid = FakeLidReader(isClosed: true)
    let sleeper = FakeSystemSleeper()
    let session = FakeSessionMonitor()
    let time = ManualTimeSource()
    let model: AppModel
    let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")

    init() {
        model = makeModel(
            system, power: power, thermal: thermal, session: session, claudeSessions: claude, lid: lid,
            systemSleeper: sleeper, blockDuration: .oneHour, time: time
        )
    }

    /// The user blocks sleep, then the model starts watching.
    func blockSleep() async {
        await model.setSleepDisabled(true)
        await time.waitForSleeper()
        await model.startAndAwaitFirstReading()
    }

    /// Sleep blocked, then the app allows it again by itself for `reason`.
    func restore(_ reason: Reason) async {
        await blockSleep()
        switch reason {
        case .timer:
            time.advance(by: .seconds(3600))
        case .lowBattery:
            power.send(.onBattery(19))
        case .highTemperature:
            thermal.send(.serious)
        case .claudeFinished:
            claude.value = .idle
            await model.refresh()
            time.advance(by: .seconds(60))
            await model.refresh()
        }
        await settle { !model.isSleepDisabled && !model.isBusy }
        // The guard check queued after the restore: let it end before the test acts.
        await letQueuedWorkRun()
        #expect(!model.isSleepDisabled)
        #expect(system.withState(\.writes) == 2)
    }

    /// The user is back, and nothing should come of it: let the event go through before checking.
    func resumeQuietly() async {
        session.send(.resumed)
        await letQueuedWorkRun()
    }

    /// The user is back, and sleep should be blocked again.
    func resumeAndWaitForTheBlock() async {
        session.send(.resumed)
        await waitForTheBlock()
    }

    func waitForTheBlock() async {
        await settle { model.isSleepDisabled && !model.isBusy }
        await letQueuedWorkRun()
    }

    /// Blocked again by the app: the pretend Mac agrees and the timer runs for the chosen hour.
    func expectBlockedAgain(writes: Int = 3, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(model.isSleepDisabled, sourceLocation: sourceLocation)
        #expect(system.withState(\.isSleepDisabled), sourceLocation: sourceLocation)
        #expect(system.withState(\.writes) == writes, sourceLocation: sourceLocation)
        #expect(model.restoreDeadline == time.now.addingTimeInterval(3600), sourceLocation: sourceLocation)
        #expect(model.lastAutomaticRestore == nil, sourceLocation: sourceLocation)
        #expect(model.error == nil, sourceLocation: sourceLocation)
    }

    func expectStillAllowed(writes: Int = 2, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!model.isSleepDisabled, sourceLocation: sourceLocation)
        #expect(system.withState(\.writes) == writes, sourceLocation: sourceLocation)
        #expect(model.restoreDeadline == nil, sourceLocation: sourceLocation)
    }
}

/// What made the app allow sleep again, as `Rig.restore` causes it.
private enum Reason: CaseIterable {
    case timer
    case lowBattery
    case highTemperature
    case claudeFinished
}

/// How the user takes over after an automatic restore.
private enum UserTakeover: CaseIterable {
    /// No reading sees sleep blocked: only the user's switch drops the intent.
    case turnOff
    case turnOnThenOff

    @MainActor func apply(to model: AppModel) async {
        if self == .turnOnThenOff { await model.setSleepDisabled(true) }
        await model.setSleepDisabled(false)
    }

    var writes: Int { self == .turnOff ? 1 : 2 }
}

@MainActor
struct SessionResumeTests {
    // MARK: Blocking again

    @Test(arguments: Reason.allCases)
    private func theUserBackAfterAnAutomaticRestoreBlocksSleepAgain(reason: Reason) async {
        let rig = Rig()
        await rig.restore(reason)
        // The guard clears while the user is away: that alone does not block again.
        switch reason {
        case .lowBattery: rig.power.send(.onACPower(19))
        case .highTemperature: rig.thermal.send(.nominal)
        case .timer, .claudeFinished: break
        }
        await letQueuedWorkRun()
        rig.expectStillAllowed()

        await rig.resumeAndWaitForTheBlock()

        rig.expectBlockedAgain()
        #expect(rig.sleeper.sleepNowCount == (reason == .claudeFinished ? 1 : 0))
    }

    @Test func theUserBackWithoutAnAutomaticRestoreChangesNothing() async {
        let rig = Rig()
        await rig.model.startAndAwaitFirstReading()

        await rig.resumeQuietly()

        #expect(!rig.model.isSleepDisabled)
        #expect(rig.system.withState(\.writes) == 0)
    }

    @Test(arguments: UserTakeover.allCases)
    private func theUserTakingOverDropsTheBlockToCome(takeover: UserTakeover) async {
        let rig = Rig()
        await rig.restore(.timer)
        await takeover.apply(to: rig.model)

        await rig.resumeQuietly()

        rig.expectStillAllowed(writes: 2 + takeover.writes)
    }

    @Test func removingTheRuleDropsTheBlockToCome() async {
        let rig = Rig()
        await rig.restore(.timer)
        await rig.model.removeAuthorization()
        await rig.model.installAuthorization()
        #expect(rig.model.authorization == .authorized)

        await rig.resumeQuietly()
        await rig.model.refresh()

        rig.expectStillAllowed()
    }

    @Test func aResumeDuringTheRestoreWriteCounts() async {
        let rig = Rig()
        await rig.blockSleep()
        let gate = Gate()
        rig.system.withState { $0.writeGate = gate }
        rig.time.advance(by: .seconds(3600))
        await gate.waitUntilArrived()

        // The Mac slept and woke unlocked before the restore's write returned.
        rig.session.send(.resumed)
        await letQueuedWorkRun()
        await gate.open()
        await rig.waitForTheBlock()

        rig.expectBlockedAgain()
    }

    // MARK: Waiting for the guards

    @Test func aLowBatteryWaitsForTheCharger() async {
        let rig = Rig()
        await rig.restore(.lowBattery)

        await rig.resumeQuietly()
        rig.expectStillAllowed()
        #expect(rig.model.sleepControl == .blockedByBatteryGuard)

        rig.power.send(.onACPower(19))
        await rig.waitForTheBlock()

        rig.expectBlockedAgain()
    }

    @Test func aHotMacWaitsToCoolDown() async {
        let rig = Rig()
        await rig.restore(.highTemperature)

        await rig.resumeQuietly()
        rig.expectStillAllowed()
        #expect(rig.model.sleepControl == .blockedByTemperatureGuard)

        rig.thermal.send(.nominal)
        await rig.waitForTheBlock()

        rig.expectBlockedAgain()
    }

    @Test func aRefreshBlocksOnceTheGuardClearedWithoutAnEvent() async {
        let rig = Rig()
        await rig.restore(.lowBattery)
        await rig.resumeQuietly()

        rig.power.changeWithoutEvent(.onACPower(19))
        await rig.model.refresh()
        await rig.waitForTheBlock()

        rig.expectBlockedAgain()
    }

    @Test func aNewSleepWaitsForTheUserAgain() async {
        let rig = Rig()
        await rig.restore(.lowBattery)
        await rig.resumeQuietly()

        // The lid closes, then the charger comes in the dark.
        rig.session.send(.sleeping)
        await letQueuedWorkRun()
        rig.power.send(.onACPower(19))
        await letQueuedWorkRun()
        await rig.model.refreshPeriodically()
        await letQueuedWorkRun()
        rig.expectStillAllowed()

        await rig.resumeAndWaitForTheBlock()

        rig.expectBlockedAgain()
    }

    @Test func aMissingRuleKeepsSleepAllowedWithoutAnError() async {
        let rig = Rig()
        await rig.restore(.timer)
        // The rule goes away elsewhere: the next reading finds it missing.
        rig.system.withState { $0.isAuthorized = false }
        await rig.model.refresh()
        #expect(rig.model.authorization == .notAuthorized)

        await rig.resumeQuietly()

        rig.expectStillAllowed()
        #expect(rig.model.error == nil)
    }

    // MARK: Tried once

    @Test func aFailedBlockShowsOneErrorAndIsNotRetried() async {
        let rig = Rig()
        await rig.restore(.timer)
        rig.system.withState { $0.writeFailure = rig.failure }

        rig.session.send(.resumed)
        await settle { rig.model.actionError != nil && !rig.model.isBusy }
        await letQueuedWorkRun()

        #expect(rig.model.actionError == .sleepControl(rig.failure))
        rig.expectStillAllowed(writes: 3)

        rig.system.withState { $0.writeFailure = nil }
        rig.model.dismissError()
        await rig.resumeQuietly()
        await rig.model.refresh()

        rig.expectStillAllowed(writes: 3)
        #expect(rig.model.error == nil)
    }

    // MARK: Dropping the intent

    @Test func sleepBlockedElsewhereDropsTheBlockToCome() async {
        let rig = Rig()
        await rig.restore(.timer)

        // A terminal blocks sleep, then allows it again: the model only hears of it by reading.
        rig.system.withState { $0.isSleepDisabled = true }
        await rig.model.refresh()
        #expect(rig.model.isSleepDisabled)
        rig.system.withState { $0.isSleepDisabled = false }
        await rig.model.refresh()

        await rig.resumeQuietly()

        rig.expectStillAllowed()
    }

    // MARK: Only the user coming back

    @Test func aRefreshAloneNeverBlocksAgain() async {
        let rig = Rig()
        await rig.restore(.timer)

        await rig.model.refresh()
        await rig.model.refreshPeriodically()
        await letQueuedWorkRun()

        rig.expectStillAllowed()
    }

    @Test func aResumeBeforeTheRestoreDoesNotCount() async {
        let rig = Rig()
        await rig.blockSleep()
        await rig.resumeQuietly()
        #expect(rig.system.withState(\.writes) == 1)

        rig.time.advance(by: .seconds(3600))
        await settle { !rig.model.isSleepDisabled && !rig.model.isBusy }
        await letQueuedWorkRun()
        await rig.model.refresh()
        await letQueuedWorkRun()

        rig.expectStillAllowed()
    }

    @Test func aResumeWhileQuittingIsIgnored() async {
        let rig = Rig()
        await rig.restore(.timer)

        await rig.model.allowSleepBeforeQuitting()
        await rig.resumeQuietly()

        rig.expectStillAllowed(writes: 3)
    }
}
