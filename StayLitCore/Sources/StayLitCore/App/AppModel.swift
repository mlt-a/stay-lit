import Foundation
import Observation

/// Everything the status window shows, and everything it can ask for.
///
/// It owns no system call: sleep, authorization, login registration, the battery, the thermal
/// state, the Claude Code sessions, the lid, going to sleep and notifications come in as
/// protocols, so tests run it against doubles. The displayed state always comes from the system
/// (`pmset -g`, `sudo -n -l`, the login item status, IOKit, `ProcessInfo`), never from what the
/// model last asked for.
///
/// Every operation waits its turn in one queue, never at the same time as another: a refresh
/// cannot read the state while an action changes it, then write back what it read. The app also
/// allows sleep again by itself, when the chosen duration ends, the battery runs low, the Mac
/// gets too hot or Claude Code has finished with the lid closed (`RestoreReason`): that goes
/// through the same queue, as one more action. The last one also puts the Mac to sleep, inside
/// that action.
@MainActor
@Observable
public final class AppModel {
    /// Whether `pmset -g` reports sleep as blocked.
    public private(set) var isSleepDisabled = false
    /// `nil` until the first check ends.
    public private(set) var authorization: AuthorizationStatus?
    public private(set) var launchAtLogin: LaunchAtLoginStatus
    /// How long the next block lasts, and the one in progress when a deadline is armed.
    public private(set) var blockDuration = BlockDuration.untilTurnedOff
    /// The "Battery guard" setting.
    public private(set) var isBatteryGuardEnabled: Bool
    /// The Mac has a battery: the guard setting only makes sense then.
    public private(set) var hasBattery: Bool
    /// The Mac runs on battery, at or below `BatteryGuard.threshold`.
    public private(set) var isBatteryLow: Bool
    /// The "Temperature guard" setting.
    public private(set) var isTemperatureGuardEnabled: Bool
    /// The thermal state is `.serious` or more (`TemperatureGuard`).
    public private(set) var isTooHot: Bool
    /// The "Claude guard" setting.
    public private(set) var isClaudeGuardEnabled: Bool
    /// Why the app last allowed sleep again by itself, while nothing happened since. Cleared when
    /// the user changes sleep, the duration or a guard, when a reading shows sleep blocked, and
    /// for `.lowBattery` when the Mac is no longer on battery. `.highTemperature` stays after the
    /// Mac cools down: a Mac that went to sleep cools, and the window must still explain on wake-up
    /// why sleep is allowed.
    public private(set) var lastAutomaticRestore: RestoreReason?
    /// The last run with the lid closed and sleep blocked that lasted long enough, and why it
    /// ended. A new report replaces it, and so does an automatic restore that leaves none. Only
    /// that and `dismissLidClosedReport()` clear it. Memory only.
    /// Fed by every successful reading of the sleep state, which also reads the lid. It carries the
    /// reason of an automatic restore, so the window shows it instead of `lastAutomaticRestore`.
    public private(set) var lastLidClosedReport: LidClosedReport?
    /// The failure of the last action. Cleared by the next action and by `dismissError()`.
    public private(set) var actionError: AppModelError?
    /// The failure of the last refresh. Each refresh replaces it, so it goes away by itself.
    public private(set) var refreshError: AppModelError?
    /// The last attempt to lock the screen when the lid closed failed. Apart from `actionError`:
    /// `perform` overwrites that one after every action. A successful lock clears it, and so does
    /// `dismissError()` when it is the error shown: dismissing another error leaves it, still unseen.
    public private(set) var screenLockError: AppModelError?

    /// When the app allows sleep again by itself. `nil` when no timer runs. Memory only.
    public var restoreDeadline: Date? { restoreTimer.deadline }

    /// The failure to show. An action error wins: the user asked for that action.
    public var error: AppModelError? { actionError ?? refreshError ?? screenLockError }

    /// What to say about the last block that ended by itself, if anything.
    public var blockEndNotice: BlockEndNotice? {
        BlockEndNotice(report: lastLidClosedReport, restore: lastAutomaticRestore)
    }

    /// An action of the user is waiting or running (including the password dialog):
    /// the controls are disabled. Refreshes leave it alone.
    public var isBusy: Bool { pendingActions > 0 }

    /// Whether the "Block sleep" switch can be used. A guard comes first, so its caption stays
    /// put while an action runs.
    public var sleepControl: SleepControlState {
        if let blockingGuard {
            blockingGuard
        } else if authorization == nil {
            .authorizationUnknown
        } else if isBusy {
            .busy
        } else {
            .available
        }
    }

    /// What the Claude Code sessions do, as of the last refresh. Read whether sleep is blocked
    /// or not, and whether the Claude guard is on or not.
    public private(set) var claudeSessions = ClaudeSessionCounts.none

    /// The exact sudoers rule that "install" writes, to show before asking.
    public var authorizationRuleText: String { authorizer.ruleText }

    @ObservationIgnored private let sleepController: any SleepControlling
    @ObservationIgnored private let authorizer: any SudoersAuthorizing
    @ObservationIgnored private let loginItem: any LaunchAtLoginControlling
    @ObservationIgnored private let powerMonitor: any PowerMonitoring
    @ObservationIgnored private let thermalMonitor: any ThermalMonitoring
    @ObservationIgnored private let claudeSessionReader: any ClaudeSessionReading
    @ObservationIgnored private let lid: any LidReading
    @ObservationIgnored private let systemSleeper: any SystemSleeping
    @ObservationIgnored private let screenLocker: any ScreenLocking
    @ObservationIgnored private let notifier: any SleepRestoreNotifying
    @ObservationIgnored private let onBatteryGuardChange: @MainActor (Bool) -> Void
    @ObservationIgnored private let onTemperatureGuardChange: @MainActor (Bool) -> Void
    @ObservationIgnored private let onClaudeGuardChange: @MainActor (Bool) -> Void
    @ObservationIgnored private let timeSource: any TimeSource
    @ObservationIgnored private let restoreTimer: RestoreTimer
    @ObservationIgnored private let refreshInterval: Duration
    /// The latest battery reading. `nil` on a Mac without battery. Not observed: the window only
    /// needs `hasBattery` and `isBatteryLow`, which change far less often than the percent.
    @ObservationIgnored private var power: PowerState?
    @ObservationIgnored private var monitoring: Task<Void, Never>?
    @ObservationIgnored private var powerMonitoring: Task<Void, Never>?
    @ObservationIgnored private var thermalMonitoring: Task<Void, Never>?
    /// What the Claude guard saw since sleep was blocked. Kept empty while sleep is allowed or the
    /// guard is off, so each block starts unarmed.
    @ObservationIgnored private var claudeTracker = ClaudeGuardTracker()
    /// The run with the lid closed in progress, if any. Fed by every sleep reading.
    @ObservationIgnored private var lidRunTracker = LidClosedRunTracker()
    /// Whether the lid was closed at the last reading made with sleep blocked. `nil` when there is
    /// none, so the next one cannot count as the lid closing.
    @ObservationIgnored private var lidWasClosed: Bool?
    /// The last operation queued. The next one waits for it before it starts.
    @ObservationIgnored private var lastOperation: Task<Void, Never>?
    /// Operations queued or running, refreshes included.
    @ObservationIgnored private var pendingOperations = 0
    /// The kinds of automatic restore that failed, since when no reading saw sleep allowed and the
    /// user did not touch sleep or the guard. Without it, every power event would try again and
    /// show the same error. Per kind: a failed deadline does not stop the guard, nor the reverse.
    @ObservationIgnored private var failedRestoreKinds: Set<RestoreReason.Kind> = []
    /// Set once the app asked to quit. Every operation asked for afterwards is refused.
    @ObservationIgnored private var quitting: Task<Void, Never>?
    private var pendingActions = 0

    /// `isBatteryGuardEnabled`, `isTemperatureGuardEnabled` and `isClaudeGuardEnabled` are the
    /// stored settings; `onBatteryGuardChange`, `onTemperatureGuardChange` and
    /// `onClaudeGuardChange` store the user's new choice. The model keeps no storage of its own.
    /// `timeSource` is also the clock of the Claude guard.
    public init(
        sleepController: any SleepControlling,
        authorizer: any SudoersAuthorizing,
        launchAtLogin: any LaunchAtLoginControlling,
        powerMonitor: any PowerMonitoring,
        thermalMonitor: any ThermalMonitoring,
        claudeSessions: any ClaudeSessionReading,
        lid: any LidReading,
        systemSleeper: any SystemSleeping,
        screenLocker: any ScreenLocking,
        notifier: any SleepRestoreNotifying,
        isBatteryGuardEnabled: Bool,
        onBatteryGuardChange: @escaping @MainActor (Bool) -> Void,
        isTemperatureGuardEnabled: Bool,
        onTemperatureGuardChange: @escaping @MainActor (Bool) -> Void,
        isClaudeGuardEnabled: Bool,
        onClaudeGuardChange: @escaping @MainActor (Bool) -> Void,
        timeSource: any TimeSource = SystemTimeSource(),
        refreshInterval: Duration = .seconds(10)
    ) {
        self.sleepController = sleepController
        self.authorizer = authorizer
        self.loginItem = launchAtLogin
        self.powerMonitor = powerMonitor
        self.thermalMonitor = thermalMonitor
        self.claudeSessionReader = claudeSessions
        self.lid = lid
        self.systemSleeper = systemSleeper
        self.screenLocker = screenLocker
        self.notifier = notifier
        self.onBatteryGuardChange = onBatteryGuardChange
        self.onTemperatureGuardChange = onTemperatureGuardChange
        self.onClaudeGuardChange = onClaudeGuardChange
        self.timeSource = timeSource
        self.restoreTimer = RestoreTimer(timeSource: timeSource)
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin.status
        self.isBatteryGuardEnabled = isBatteryGuardEnabled
        let power = powerMonitor.state
        self.power = power
        self.hasBattery = power != nil
        self.isBatteryLow = BatteryGuard.isLow(power)
        self.isTemperatureGuardEnabled = isTemperatureGuardEnabled
        self.isTooHot = TemperatureGuard.isTooHot(thermalMonitor.state)
        self.isClaudeGuardEnabled = isClaudeGuardEnabled
    }

    // MARK: Refreshing

    /// Reads the whole state once, then the sleep state every `refreshInterval`, to see
    /// changes made elsewhere (a terminal, another account). Also follows the battery and the
    /// thermal state. Does nothing when it already runs.
    public func startMonitoring() {
        guard monitoring == nil else { return }
        // Subscribe, then read: a change between the two reaches the stream.
        let powerChanges = powerMonitor.changes()
        applyPower(powerMonitor.state)
        powerMonitoring = Task { [weak self] in
            for await power in powerChanges {
                guard let model = self else { return }
                await model.powerChanged(to: power)
            }
        }
        let thermalChanges = thermalMonitor.changes()
        applyThermal(thermalMonitor.state)
        thermalMonitoring = Task { [weak self] in
            for await state in thermalChanges {
                guard let model = self else { return }
                await model.thermalChanged(to: state)
            }
        }
        let interval = refreshInterval
        monitoring = Task { [weak self] in
            await self?.refresh()
            // `self` is only held while a refresh runs, so the loop never keeps the model alive.
            while true {
                // A cancelled sleep throws at once: stop instead of spinning.
                do { try await Task.sleep(for: interval) } catch { return }
                guard let model = self else { return }
                await model.refreshPeriodically()
            }
        }
    }

    /// Reads the battery, the thermal state, the sleep state, the authorization status, the
    /// login item status and the Claude Code sessions.
    public func refresh() async {
        await serialized { [self] in
            // An event a stream missed leaves the battery or the temperature stale: read them again.
            applyPower(powerMonitor.state)
            applyThermal(thermalMonitor.state)
            async let sessions = claudeSessionReader.sessions()
            apply(await readSystemState(.full))
            applyClaude(await sessions)
        }
        await restoreSleepIfAGuardApplies()
    }

    /// The periodic check: the battery and the thermal state, then the Claude Code sessions (no
    /// process) and the sleep state (one process), read together. The authorization and the
    /// login item change through the app, which reads them after each action. Skipped when an
    /// operation is queued or running: that one reads the state when it ends. The lid check for
    /// the lock is not skipped: an operation can hold the queue for as long as a password dialog
    /// stays open, and the lid would close unlocked meanwhile.
    func refreshPeriodically() async {
        guard pendingOperations == 0 else {
            // The last known state stands in for a reading: the queue is busy. The lid run is left
            // to the queue.
            if isSleepDisabled { lockIfLidJustClosed(lidClosed: lid.isLidClosed(), sleepBlocked: true) }
            return
        }
        await serialized { [self] in
            applyPower(powerMonitor.state)
            applyThermal(thermalMonitor.state)
            async let sessions = claudeSessionReader.sessions()
            apply(await readSystemState(.sleepOnly))
            applyClaude(await sessions)
        }
        await restoreSleepIfAGuardApplies()
    }

    // MARK: Actions

    /// Blocks (`true`) or allows (`false`) sleep. A refused write shows the authorization
    /// panel when the rule is not usable, and the error otherwise. Blocking arms the timer
    /// for the chosen duration.
    ///
    /// Blocking is refused, without a word, while `sleepControl` is `.blockedByBatteryGuard` or
    /// `.blockedByTemperatureGuard`: the caller reads the reason there.
    public func setSleepDisabled(_ disabled: Bool) async {
        await perform(
            changesSleepOrGuard: true,
            if: { [self] in !(disabled && blockingGuard != nil) }
        ) { [self, sleepController] in
            try await sleepController.setSleepDisabled(disabled)
            if disabled {
                // A new block: what the Claude guard saw during the last one does not count.
                claudeTracker.reset()
                armTimer()
            } else {
                // After the write: a refused one leaves the run going.
                lidRunTracker.cancel()
            }
        } explain: { outcome, state in
            // A password prompt is not the only way a write fails without the rule: an account
            // that is not an administrator gets another message. The authorization status decides.
            if case .failed(.sleepControl) = outcome, state.authorization == .notAuthorized { return nil }
            return outcome.failure
        }
        // The battery may have dropped, or the Mac heated up, while the write ran.
        if disabled { await restoreSleepIfAGuardApplies() }
    }

    /// Chooses how long the next block lasts. While sleep is blocked, the timer restarts from
    /// now for the new duration (or stops for "until turned off"); sleep itself is not touched.
    /// Nothing is armed while sleep is allowed.
    public func setBlockDuration(_ duration: BlockDuration) {
        guard duration != blockDuration else { return }
        allowAutomaticRestoresAgain()
        update(\.blockDuration, to: duration)
        if isSleepDisabled { armTimer() }
    }

    public func installAuthorization() async {
        await perform { [authorizer] in
            try await authorizer.install()
        } explain: { outcome, state in
            // The script succeeded, yet sudo ignores the rule: without a word, the window
            // would look as if nothing happened.
            if case .succeeded = outcome, state.authorization == .notAuthorized {
                return .ruleInstalledButNotAccepted
            }
            return outcome.failure
        }
    }

    /// Turns sleep back on and removes the sudoers rule.
    public func removeAuthorization() async {
        await perform { [self, authorizer] in
            try await authorizer.remove()
            // Removing the rule turns sleep back on: the user ended the run.
            lidRunTracker.cancel()
        } explain: { outcome, state in
            // The script removes the rule even when `pmset` fails: with the rule gone,
            // the failure means sleep may still be blocked.
            if case .failed(let failure) = outcome, case .authorizationScriptFailed = failure,
               state.authorization == .notAuthorized {
                return .removedWithSleepPossiblyBlocked(cause: failure)
            }
            return outcome.failure
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) async {
        await perform { [loginItem] in
            do {
                try loginItem.setEnabled(enabled)
            } catch {
                throw LaunchAtLoginFailure(message: error.localizedDescription)
            }
        }
    }

    /// Turns the battery guard on or off and hands the choice to `onBatteryGuardChange`.
    /// Acts at once when the battery is already low with sleep blocked.
    public func setBatteryGuardEnabled(_ enabled: Bool) async {
        await perform(changesSleepOrGuard: true) { [self] in
            guard enabled != isBatteryGuardEnabled else { return }
            isBatteryGuardEnabled = enabled
            onBatteryGuardChange(enabled)
        }
        await restoreSleepIfBatteryLow()
    }

    /// Turns the temperature guard on or off and hands the choice to `onTemperatureGuardChange`.
    /// Acts at once when the Mac is already too hot with sleep blocked.
    public func setTemperatureGuardEnabled(_ enabled: Bool) async {
        await perform(changesSleepOrGuard: true) { [self] in
            guard enabled != isTemperatureGuardEnabled else { return }
            isTemperatureGuardEnabled = enabled
            onTemperatureGuardChange(enabled)
        }
        await restoreSleepIfTooHot()
    }

    /// Turns the Claude guard on or off and hands the choice to `onClaudeGuardChange`. Nothing
    /// acts at once: the guard first has to see Claude Code work.
    public func setClaudeGuardEnabled(_ enabled: Bool) async {
        await perform(changesSleepOrGuard: true) { [self] in
            guard enabled != isClaudeGuardEnabled else { return }
            isClaudeGuardEnabled = enabled
            // A guard turned off and on again before the next refresh would keep what it saw
            // earlier: no refresh ran in between to reset the tracker.
            claudeTracker.reset()
            onClaudeGuardChange(enabled)
        }
    }

    public func dismissLidClosedReport() {
        update(\.lastLidClosedReport, to: nil)
    }

    public func dismissError() {
        let screenLockErrorWasShown = actionError == nil && refreshError == nil
        update(\.actionError, to: nil)
        update(\.refreshError, to: nil)
        if screenLockErrorWasShown { update(\.screenLockError, to: nil) }
    }

    // MARK: Quitting

    /// Turns sleep back on before the app quits, after every operation already queued, so a
    /// write still in flight cannot block sleep again afterwards. Always tried, whatever the
    /// model last read, and never fails. From the first call on, every other operation is
    /// refused; a second call waits for the same reset.
    /// Without a usable rule the reset fails silently. A crash or a kill never comes here:
    /// sleep then stays as it was.
    public func allowSleepBeforeQuitting() async {
        if let quitting { return await quitting.value }
        monitoring?.cancel()
        powerMonitoring?.cancel()
        thermalMonitoring?.cancel()
        restoreTimer.disarm()
        let reset = Task { [self, sleepController] in
            await enqueue {
                _ = try? await sleepController.setSleepDisabled(false)
            }
        }
        quitting = reset
        await reset.value
    }

    // MARK: Private

    /// What one reading of the system found. A `nil` field was not read, or could not be:
    /// a `nil` authorization means the status is unknown, not that the rule is missing.
    private struct SystemState {
        var isSleepDisabled: Bool?
        var authorization: AuthorizationStatus?
        var launchAtLogin: LaunchAtLoginStatus?
        var failure: AppModelError?
    }

    private enum ReadingScope {
        case full
        case sleepOnly
    }

    private func readSystemState(_ scope: ReadingScope) async -> SystemState {
        var state = SystemState()
        guard scope == .full else {
            do {
                state.isSleepDisabled = try await sleepController.isSleepDisabled()
            } catch {
                state.failure = AppModelError(error)
            }
            return state
        }

        async let sleepDisabled = sleepController.isSleepDisabled()
        async let authorization = authorizer.status()
        state.launchAtLogin = loginItem.status
        do {
            state.isSleepDisabled = try await sleepDisabled
        } catch {
            state.failure = AppModelError(error)
        }
        do {
            state.authorization = try await authorization
        } catch {
            state.failure = state.failure ?? AppModelError(error)
        }
        return state
    }

    private func apply(_ state: SystemState) {
        if let value = state.isSleepDisabled { update(\.isSleepDisabled, to: value) }
        // Sleep blocked again, by anyone: "sleep allowed again" would contradict the reading.
        if state.isSleepDisabled == true { update(\.lastAutomaticRestore, to: nil) }
        if let value = state.authorization { update(\.authorization, to: value) }
        if let value = state.launchAtLogin { update(\.launchAtLogin, to: value) }
        update(\.refreshError, to: state.failure)
        // A failed reading says nothing about the lid run, but it proves the Mac is awake:
        // a long series of failures must not look like a sleep.
        if let sleepDisabled = state.isSleepDisabled {
            trackLidRun(sleepBlocked: sleepDisabled)
        } else {
            lidRunTracker.sawAwake(at: timeSource.now)
        }
        // Sleep is allowed, whoever allowed it: a later automatic restore may be tried.
        if state.isSleepDisabled == false {
            failedRestoreKinds.removeAll()
            // Whoever blocks sleep next starts the Claude guard over, even without a refresh in
            // between.
            claudeTracker.reset()
        }
        // Sleep allowed, or no rule left to turn it back on: the timer has no purpose.
        // The one place that stops it, quitting aside.
        if state.isSleepDisabled == false || state.authorization == .notAuthorized {
            restoreTimer.disarm()
        }
    }

    private func trackLidRun(sleepBlocked: Bool) {
        // With sleep allowed and no run going, the lid cannot change anything: skip the IORegistry read.
        let lidClosed = sleepBlocked || lidRunTracker.isRunning ? lid.isLidClosed() : nil
        if let lidClosed {
            keep(lidRunTracker.record(lidClosed: lidClosed, sleepBlocked: sleepBlocked, at: timeSource.now))
        }
        lockIfLidJustClosed(lidClosed: lidClosed, sleepBlocked: sleepBlocked)
    }

    /// The one place that writes `lidWasClosed`. Only a lid seen open and then closed, with sleep
    /// blocked, locks: a lid already closed (external display) or a block started with the lid
    /// closed does not.
    private func lockIfLidJustClosed(lidClosed: Bool?, sleepBlocked: Bool) {
        if sleepBlocked, lidWasClosed == false, lidClosed == true { lockScreenForClosedLid() }
        // Only a reading made with sleep blocked counts for the next one.
        lidWasClosed = sleepBlocked ? lidClosed : nil
    }

    private func lockScreenForClosedLid() {
        do {
            try screenLocker.lockScreen()
            update(\.screenLockError, to: nil)
        } catch {
            update(\.screenLockError, to: AppModelError(error))
        }
    }

    /// A report replaces the last one. No report leaves it: the window still shows the last run.
    private func keep(_ report: LidClosedReport?) {
        if let report { update(\.lastLidClosedReport, to: report) }
    }

    /// The user changed sleep or a guard: the last automatic restore is old news, and a
    /// failed one may be tried again. Other actions (login item, authorization) leave both alone.
    private func allowAutomaticRestoresAgain() {
        update(\.lastAutomaticRestore, to: nil)
        failedRestoreKinds.removeAll()
    }

    // MARK: Automatic restore

    /// The one way the app allows sleep again by itself: an action of its own, so it waits its
    /// turn in the queue. `reasons` are asked in order once the restore has its turn: the first
    /// that applies, of a kind not failed yet, wins. When none does, nothing on screen changes,
    /// not even the busy state.
    /// A failure is shown once, as an action error: no restore of that kind is tried again until
    /// a reading sees sleep allowed or the user changes sleep or a guard.
    private func restoreSleepAutomatically(_ reasons: [@MainActor () -> RestoreReason?]) async {
        await perform(.automatic, given: { [self] () -> RestoreReason? in
            guard isSleepDisabled else { return nil }
            return reasons.lazy.compactMap { $0() }.first { !failedRestoreKinds.contains($0.kind) }
        }) { [self] reason in
            do {
                try await sleepController.setSleepDisabled(false)
            } catch {
                failedRestoreKinds.insert(reason.kind)
                throw error
            }
            update(\.lastAutomaticRestore, to: reason)
            // Replaced even by nothing: an older report would hide this restore's notice.
            update(\.lastLidClosedReport, to: lidRunTracker.restored(reason, at: timeSource.now))
            // The charger may have been plugged in while the write ran.
            forgetLowBatteryRestoreOffBattery()
            notifier.notifySleepRestored(reason)
            // Last, and outside the write's `do`: sleep is allowed whatever happens here, so a
            // failure must neither count as a failed restore nor undo `lastAutomaticRestore`.
            if reason.followsWithSystemSleep { try await sleepNow() }
        }
    }

    private func sleepNow() async throws {
        do {
            try await systemSleeper.sleepNow()
        } catch {
            // Whatever it threw, even a command that could not start: sleep is allowed anyway.
            throw AppModelError.sleepNowFailed(cause: AppModelError(error) ?? .unexpected(message: error.localizedDescription))
        }
    }

    /// Starts the timer from now for `blockDuration`, replacing the running one, or stops it
    /// for "until turned off". Nothing is armed once the app is quitting.
    private func armTimer() {
        guard quitting == nil else { return }
        restoreTimer.arm(for: blockDuration.interval) { [weak self] deadline in
            guard let self else { return }
            // A timer restarted or stopped since has another deadline, or none.
            await restoreSleepAutomatically([{ self.restoreTimer.deadline == deadline ? .timer : nil }])
        }
    }

    /// The guard that keeps sleep allowed, if any: blocking would be undone at once. The battery
    /// goes first, here and in `restoreSleepIfAGuardApplies`: when both apply, its caption and its
    /// reason are the ones shown. The Claude guard never blocks: it only acts once sleep is blocked.
    private var blockingGuard: SleepControlState? {
        guard !isSleepDisabled else { return nil }
        if isBatteryGuardEnabled && isBatteryLow { return .blockedByBatteryGuard }
        if isTemperatureGuardEnabled && isTooHot { return .blockedByTemperatureGuard }
        return nil
    }

    /// Called after every reading and user action that may need a guard. The guards share one
    /// entry in the queue, so a periodic refresh never finds it busy between them. The Claude
    /// guard comes last: it is the only one that puts the Mac to sleep, so any other guard that
    /// applies wins and the Mac stays awake.
    private func restoreSleepIfAGuardApplies() async {
        await restoreSleepAutomatically([lowBatteryReason, highTemperatureReason, claudeFinishedReason])
    }

    /// Called after every power event and change of the battery guard.
    private func restoreSleepIfBatteryLow() async {
        await restoreSleepAutomatically([lowBatteryReason])
    }

    /// Called after every thermal event and change of the temperature guard.
    private func restoreSleepIfTooHot() async {
        await restoreSleepAutomatically([highTemperatureReason])
    }

    private func lowBatteryReason() -> RestoreReason? {
        guard isBatteryGuardEnabled, isBatteryLow, let power else { return nil }
        return .lowBattery(percent: power.percent)
    }

    private func highTemperatureReason() -> RestoreReason? {
        isTemperatureGuardEnabled && isTooHot ? .highTemperature : nil
    }

    /// The lid is read here, when the restore has its turn, not with the sessions: Claude may
    /// finish while the lid is open, and closing it later must act at the next refresh.
    private func claudeFinishedReason() -> RestoreReason? {
        guard isClaudeGuardEnabled,
              claudeTracker.isDue(at: timeSource.now),
              !failedRestoreKinds.contains(.claudeFinished),
              lid.isLidClosed()
        else { return nil }
        return .claudeFinished
    }

    /// Takes the one reading of the sessions per refresh, made while the sleep state was read.
    /// The same reading feeds the tracker while the guard is on and sleep is blocked; the tracker
    /// starts over otherwise. Called after `apply`: tracking needs the sleep state just read.
    private func applyClaude(_ sessions: ClaudeSessionCounts) {
        let tracking = isClaudeGuardEnabled && isSleepDisabled
        update(\.claudeSessions, to: sessions)
        if tracking {
            claudeTracker.record(sessions.activity, at: timeSource.now)
        } else {
            claudeTracker.reset()
        }
    }

    private func powerChanged(to power: PowerState?) async {
        guard quitting == nil else { return }
        applyPower(power)
        await restoreSleepIfBatteryLow()
    }

    /// The one way a battery reading enters the model, from an event or from a refresh.
    private func applyPower(_ power: PowerState?) {
        updatePower(power)
        forgetLowBatteryRestoreOffBattery()
    }

    /// The observed booleans change only when they flip, not with every percent.
    private func updatePower(_ power: PowerState?) {
        self.power = power
        update(\.hasBattery, to: power != nil)
        update(\.isBatteryLow, to: BatteryGuard.isLow(power))
    }

    /// News of a low battery is stale once the Mac no longer runs on it.
    private func forgetLowBatteryRestoreOffBattery() {
        if case .lowBattery = lastAutomaticRestore, power?.isOnBattery != true {
            update(\.lastAutomaticRestore, to: nil)
        }
    }

    private func thermalChanged(to state: ProcessInfo.ThermalState) async {
        guard quitting == nil else { return }
        applyThermal(state)
        await restoreSleepIfTooHot()
    }

    /// The one way a thermal reading enters the model, from an event or from a refresh.
    private func applyThermal(_ state: ProcessInfo.ThermalState) {
        update(\.isTooHot, to: TemperatureGuard.isTooHot(state))
    }

    // MARK: Queue

    private enum ActionOutcome {
        case succeeded
        case failed(AppModelError)

        var failure: AppModelError? {
            if case .failed(let failure) = self { failure } else { nil }
        }
    }

    private enum Initiator {
        /// Busy from the call: the controls wait for it.
        case user
        /// Busy only once its precondition holds: a dropped one leaves the window alone.
        case automatic
    }

    /// Runs an action in the queue, then reads the whole state. `precondition` is checked once
    /// the action has its turn: when it fails, nothing runs and nothing shown changes.
    /// `changesSleepOrGuard` marks the actions of the user that touch sleep or a guard:
    /// they allow automatic restores again.
    private func perform(
        _ initiator: Initiator = .user,
        changesSleepOrGuard: Bool = false,
        if precondition: @escaping @MainActor () -> Bool = { true },
        _ action: @escaping @MainActor () async throws -> Void,
        explain: @escaping @MainActor (ActionOutcome, SystemState) -> AppModelError? = { outcome, _ in outcome.failure }
    ) async {
        await perform(
            initiator,
            changesSleepOrGuard: changesSleepOrGuard,
            given: { precondition() ? () : nil },
            { _ in try await action() },
            explain: explain
        )
    }

    /// The same, when the action needs what the precondition found: `given` returns it, or
    /// `nil` to drop the action. `explain` turns the outcome into what to show, knowing the
    /// state read after it. A cancelled password dialog never reaches it.
    private func perform<Input>(
        _ initiator: Initiator,
        changesSleepOrGuard: Bool = false,
        given precondition: @escaping @MainActor () -> Input?,
        _ action: @escaping @MainActor (Input) async throws -> Void,
        explain: @escaping @MainActor (ActionOutcome, SystemState) -> AppModelError? = { outcome, _ in outcome.failure }
    ) async {
        guard quitting == nil else { return }
        if initiator == .user { pendingActions += 1 }
        await serialized { [self] in
            guard let input = precondition() else { return }
            switch initiator {
            case .user: if changesSleepOrGuard { allowAutomaticRestoresAgain() }
            case .automatic: pendingActions += 1
            }
            update(\.actionError, to: nil)
            var outcome: ActionOutcome? = .succeeded
            do {
                try await action(input)
            } catch {
                outcome = AppModelError(error).map { .failed($0) }
            }
            let state = await readSystemState(.full)
            apply(state)
            update(\.actionError, to: outcome.flatMap { explain($0, state) })
            if initiator == .automatic { pendingActions -= 1 }
        }
        if initiator == .user { pendingActions -= 1 }
    }

    /// Queues `operation` behind the last one and waits until it ends.
    /// Refused once the app is quitting.
    private func serialized(_ operation: @escaping @MainActor () async -> Void) async {
        guard quitting == nil else { return }
        await enqueue(operation)
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = lastOperation
        pendingOperations += 1
        let current = Task { [self] in
            await previous?.value
            await operation()
            pendingOperations -= 1
        }
        lastOperation = current
        await current.value
    }

    /// `@Observable` notifies on every write, even of an equal value: write only on change.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
