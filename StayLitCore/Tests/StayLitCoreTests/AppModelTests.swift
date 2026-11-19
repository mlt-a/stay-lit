import Foundation
import Testing
@testable import StayLitCore

@MainActor
struct AppModelTests {
    // MARK: Toggle

    @Test func toggleSucceedsWithTheAuthorization() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)

        await model.setSleepDisabled(true)

        #expect(model.isSleepDisabled)
        #expect(model.authorization == .authorized)
        #expect(model.error == nil)
        #expect(!model.isBusy)

        await model.setSleepDisabled(false)
        #expect(!model.isSleepDisabled)
    }

    @Test func toggleWithoutTheAuthorizationShowsThePanelAndNoError() async {
        let system = FakeSystem(authorized: false)
        let model = makeModel(system)

        await model.setSleepDisabled(true)

        #expect(model.authorization == .notAuthorized)
        #expect(model.error == nil)
        #expect(!model.isSleepDisabled)
    }

    @Test func aRefusedWriteWithAnyMessageShowsThePanelWhenTheRuleIsNotUsable() async {
        // A non-admin account does not get "a password is required".
        let system = FakeSystem(authorized: false)
        system.withState {
            $0.writeFailure = SleepControlError.commandFailed(
                command: "sudo", exitCode: 1, message: "user is not in the sudoers file"
            )
        }
        let model = makeModel(system)

        await model.setSleepDisabled(true)

        #expect(model.authorization == .notAuthorized)
        #expect(model.error == nil)
    }

    @Test func aFailedWriteWithTheRuleInPlaceShowsTheError() async {
        let failure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        let system = FakeSystem(authorized: true)
        system.withState { $0.writeFailure = failure }
        let model = makeModel(system)

        await model.setSleepDisabled(true)

        #expect(model.authorization == .authorized)
        #expect(model.error == .sleepControl(failure))
    }

    @Test func anUnstartableCommandShowsTheErrorEvenWithoutTheRule() async {
        let failure = CommandRunnerError.sudoLaunchFailed
        let system = FakeSystem(authorized: false)
        system.withState {
            $0.writeFailure = failure
            $0.statusFailure = failure
        }
        let model = makeModel(system)

        await model.setSleepDisabled(true)

        #expect(model.error == .commandLaunch(failure))
    }

    @Test func theNextActionClearsTheError() async {
        let system = FakeSystem(authorized: true)
        system.withState { $0.writeFailure = SleepControlError.commandFailed(command: "x", exitCode: 1, message: "") }
        let model = makeModel(system)
        await model.setSleepDisabled(true)
        #expect(model.error != nil)

        system.withState { $0.writeFailure = nil }
        await model.setSleepDisabled(true)

        #expect(model.error == nil)
        #expect(model.isSleepDisabled)
    }

    // MARK: Authorization

    @Test func installThenToggle() async {
        let system = FakeSystem(authorized: false)
        let model = makeModel(system)
        await model.refresh()
        #expect(model.authorization == .notAuthorized)

        await model.installAuthorization()
        #expect(model.authorization == .authorized)
        #expect(model.error == nil)
        #expect(system.withState(\.installs) == 1)

        await model.setSleepDisabled(true)
        #expect(model.isSleepDisabled)
        #expect(model.error == nil)
    }

    @Test func cancellingTheInstallDialogShowsNothing() async {
        let system = FakeSystem(authorized: false)
        system.withState { $0.installFailure = AuthorizationError.cancelledByUser }
        let model = makeModel(system)

        await model.installAuthorization()

        #expect(model.actionError == nil)
        #expect(model.refreshError == nil)
        #expect(!model.isBusy)
    }

    @Test func aFailedInstallShowsTheError() async {
        let failure = AuthorizationError.scriptFailed(exitCode: 1, message: "syntax error")
        let system = FakeSystem(authorized: false)
        system.withState { $0.installFailure = failure }
        let model = makeModel(system)

        await model.installAuthorization()

        #expect(model.error == .authorizationScriptFailed(exitCode: 1, message: "syntax error"))
        #expect(model.authorization == .notAuthorized)
    }

    @Test func removeTurnsSleepBackOnAndShowsThePanel() async {
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        let model = makeModel(system)
        await model.refresh()
        #expect(model.isSleepDisabled)

        await model.removeAuthorization()

        #expect(model.authorization == .notAuthorized)
        #expect(!model.isSleepDisabled)
        #expect(model.error == nil)
        #expect(system.withState(\.removals) == 1)
    }

    @Test func cancellingTheRemoveDialogChangesNothing() async {
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        system.withState { $0.removeFailure = AuthorizationError.cancelledByUser }
        let model = makeModel(system)
        await model.refresh()

        await model.removeAuthorization()

        #expect(model.actionError == nil)
        #expect(model.refreshError == nil)
        #expect(model.authorization == .authorized)
        #expect(model.isSleepDisabled)
        #expect(!model.isBusy)
    }

    @Test func aRemovalThatFailedOnPmsetWarnsThatSleepMayStayBlocked() async {
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        system.withState {
            $0.removeFailureAfterRemovingRule = AuthorizationError.scriptFailed(exitCode: 71, message: "pmset failed")
        }
        let model = makeModel(system)
        await model.refresh()

        await model.removeAuthorization()

        // The rule is gone and the state was read again: sleep is still blocked.
        #expect(model.authorization == .notAuthorized)
        #expect(model.isSleepDisabled)
        #expect(model.error == .removedWithSleepPossiblyBlocked(
            cause: .authorizationScriptFailed(exitCode: 71, message: "pmset failed")
        ))
    }

    @Test func aRemovalThatFailedBeforeRemovingTheRuleShowsTheScriptFailure() async {
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        system.withState { $0.removeFailure = AuthorizationError.scriptFailed(exitCode: 1, message: "denied") }
        let model = makeModel(system)

        await model.removeAuthorization()

        #expect(model.authorization == .authorized)
        #expect(model.error == .authorizationScriptFailed(exitCode: 1, message: "denied"))
    }

    // MARK: Refresh

    @Test func refreshSeesAChangeMadeOutsideTheApp() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        await model.refresh()
        #expect(!model.isSleepDisabled)

        system.withState { $0.isSleepDisabled = true }
        await model.refresh()
        #expect(model.isSleepDisabled)

        system.withState { $0.isSleepDisabled = false }
        await model.refresh()
        #expect(!model.isSleepDisabled)
    }

    @Test func refreshSeesTheRuleAppearOrDisappear() async {
        let system = FakeSystem(authorized: false)
        let model = makeModel(system)
        #expect(model.authorization == nil)

        await model.refresh()
        #expect(model.authorization == .notAuthorized)

        system.withState { $0.isAuthorized = true }
        await model.refresh()
        #expect(model.authorization == .authorized)
    }

    @Test func aFailingRefreshShowsAnErrorAndTheNextGoodOneClearsIt() async {
        let failure = SleepControlError.commandFailed(command: "pmset -g", exitCode: 1, message: "nope")
        let system = FakeSystem(authorized: true)
        system.withState { $0.readFailure = failure }
        let model = makeModel(system)

        await model.refresh()
        #expect(model.error == .sleepControl(failure))

        system.withState { $0.readFailure = nil }
        await model.refresh()
        #expect(model.error == nil)
    }

    @Test func anActionErrorSurvivesASuccessfulRefresh() async {
        let actionFailure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        let system = FakeSystem(authorized: true)
        system.withState { $0.writeFailure = actionFailure }
        let model = makeModel(system)
        await model.setSleepDisabled(true)

        await model.refresh()
        await model.refreshPeriodically()

        #expect(model.actionError == .sleepControl(actionFailure))
        #expect(model.refreshError == nil)
        #expect(model.error == .sleepControl(actionFailure))
    }

    @Test func anActionErrorWinsOverARefreshErrorAndDismissingClearsBoth() async {
        let actionFailure = SleepControlError.commandFailed(command: "pmset", exitCode: 2, message: "boom")
        let readFailure = SleepControlError.commandFailed(command: "pmset -g", exitCode: 1, message: "nope")
        let system = FakeSystem(authorized: true)
        system.withState { $0.writeFailure = actionFailure }
        let model = makeModel(system)
        await model.setSleepDisabled(true)

        system.withState { $0.readFailure = readFailure }
        await model.refresh()
        #expect(model.refreshError == .sleepControl(readFailure))
        #expect(model.error == .sleepControl(actionFailure))

        model.dismissError()
        #expect(model.actionError == nil)
        #expect(model.refreshError == nil)
        #expect(model.error == nil)
    }

    @Test func theNextActionClearsOnlyTheActionError() async {
        let readFailure = SleepControlError.commandFailed(command: "pmset -g", exitCode: 1, message: "nope")
        let system = FakeSystem(authorized: true)
        system.withState { $0.writeFailure = SleepControlError.commandFailed(command: "x", exitCode: 1, message: "") }
        let model = makeModel(system)
        await model.setSleepDisabled(true)
        #expect(model.actionError != nil)

        system.withState {
            $0.writeFailure = nil
            $0.readFailure = readFailure
        }
        await model.setSleepDisabled(true)

        #expect(model.actionError == nil)
        #expect(model.error == .sleepControl(readFailure))
    }

    @Test func thePeriodicRefreshReadsTheSleepStateOnly() async {
        let system = FakeSystem(authorized: true)
        let loginItem = FakeLaunchAtLogin()
        let model = makeModel(system, launchAtLogin: loginItem)
        let loginReadsBefore = loginItem.statusReads

        system.withState { $0.isSleepDisabled = true }
        await model.refreshPeriodically()

        #expect(model.isSleepDisabled)
        #expect(system.withState(\.sleepReads) == 1)
        #expect(system.withState(\.statusReads) == 0)
        #expect(loginItem.statusReads == loginReadsBefore)
    }

    @Test func theFullRefreshReadsEverything() async {
        let system = FakeSystem(authorized: true)
        let loginItem = FakeLaunchAtLogin()
        let model = makeModel(system, launchAtLogin: loginItem)
        let loginReadsBefore = loginItem.statusReads

        await model.refresh()

        #expect(system.withState(\.sleepReads) == 1)
        #expect(system.withState(\.statusReads) == 1)
        #expect(loginItem.statusReads == loginReadsBefore + 1)
    }

    @Test func aRefreshThatReadsDuringAnActionCannotOverwriteItsResult() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        let gate = Gate()
        system.withState { $0.readGate = gate }

        // The refresh reads "allowed", then is held before it writes what it read.
        let refresh = Task { await model.refresh() }
        await gate.waitUntilArrived()
        let toggle = Task { await model.setSleepDisabled(true) }
        // Lets the toggle run now if it were not queued behind the refresh.
        await letQueuedWorkRun()
        #expect(system.withState(\.writes) == 0)
        #expect(model.isBusy)

        await gate.open()
        await refresh.value
        await toggle.value

        #expect(system.withState(\.writes) == 1)
        #expect(model.isSleepDisabled)
        #expect(!model.isBusy)
    }

    @Test func aPeriodicRefreshIsDroppedWhileAnActionRuns() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        let gate = Gate()
        system.withState { $0.writeGate = gate }

        let toggle = Task { await model.setSleepDisabled(true) }
        await gate.waitUntilArrived()
        await model.refreshPeriodically()
        #expect(system.withState(\.sleepReads) == 0)

        await gate.open()
        await toggle.value
        // Only the read that follows the action.
        #expect(system.withState(\.sleepReads) == 1)
        #expect(model.isSleepDisabled)
    }

    @Test func aRefreshDoesNotSetBusy() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        let gate = Gate()
        system.withState { $0.readGate = gate }

        let refresh = Task { await model.refresh() }
        await gate.waitUntilArrived()
        #expect(!model.isBusy)

        await gate.open()
        await refresh.value
    }

    @Test func aRefreshThatFindsNothingNewNotifiesNoObserver() async {
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        let model = makeModel(system)
        await model.refresh()

        let changed = flagChanges {
            _ = model.isSleepDisabled
            _ = model.authorization
            _ = model.launchAtLogin
            _ = model.error
            _ = model.isBusy
            _ = model.sleepControl
            _ = model.lastAutomaticRestore
        }
        await model.refresh()
        await model.refreshPeriodically()

        #expect(!changed.isRaised)
    }

    @Test func startingTheMonitoringTwiceIsSafe() {
        let model = makeModel()

        model.startMonitoring()
        model.startMonitoring()
    }

    // MARK: The switch

    @Test func theSwitchWaitsForTheFirstCheckThenForEachAction() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        #expect(model.sleepControl == .authorizationUnknown)

        await model.refresh()
        #expect(model.sleepControl == .available)

        let gate = Gate()
        system.withState { $0.writeGate = gate }
        let toggle = Task { await model.setSleepDisabled(true) }
        await gate.waitUntilArrived()
        #expect(model.sleepControl == .busy)

        await gate.open()
        await toggle.value
        #expect(model.sleepControl == .available)
    }

    // MARK: Unknown authorization status

    @Test func aStatusThatCannotBeReadKeepsThePreviousAuthorization() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        await model.refresh()

        system.withState { $0.statusFailure = CommandRunnerError.sudoLaunchFailed }
        await model.refresh()

        #expect(model.authorization == .authorized)
        #expect(model.refreshError == .commandLaunch(.sudoLaunchFailed))
    }

    @Test func aFailedRemovalWithAnUnreadableStatusShowsTheScriptFailure() async {
        let failure = AuthorizationError.scriptFailed(exitCode: 1, message: "denied")
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        let model = makeModel(system)
        await model.refresh()
        system.withState {
            $0.removeFailure = failure
            $0.statusFailure = CommandRunnerError.sudoLaunchFailed
        }

        await model.removeAuthorization()

        #expect(model.actionError == .authorizationScriptFailed(exitCode: 1, message: "denied"))
        #expect(model.authorization == .authorized)
    }

    @Test func aFailedWriteWithAnUnreadableStatusShowsTheWriteError() async {
        let system = FakeSystem(authorized: false)
        let model = makeModel(system)
        await model.refresh()
        #expect(model.authorization == .notAuthorized)
        system.withState { $0.statusFailure = CommandRunnerError.sudoLaunchFailed }

        await model.setSleepDisabled(true)

        // The status is unknown, so the model does not conclude that the rule is missing.
        #expect(model.actionError == .sleepControl(.authorizationMissing))
        #expect(model.authorization == .notAuthorized)
    }

    // MARK: Install outcome

    @Test func anInstalledRuleThatSudoRefusesIsExplained() async {
        let system = FakeSystem(authorized: false)
        system.withState { $0.installSucceedsWithoutAuthorizing = true }
        let model = makeModel(system)

        await model.installAuthorization()

        #expect(model.authorization == .notAuthorized)
        #expect(model.actionError == .ruleInstalledButNotAccepted)
    }

    @Test func anInstallFollowedByAnUnreadableStatusShowsTheReadingError() async {
        let system = FakeSystem(authorized: false)
        system.withState {
            $0.installSucceedsWithoutAuthorizing = true
            $0.statusFailure = CommandRunnerError.sudoLaunchFailed
        }
        let model = makeModel(system)

        await model.installAuthorization()

        #expect(model.actionError == nil)
        #expect(model.error == .commandLaunch(.sudoLaunchFailed))
    }

    // MARK: Quitting

    @Test func theQuitResetRunsAfterAnActionInFlight() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        let gate = Gate()
        system.withState { $0.writeGate = gate }

        let toggle = Task { await model.setSleepDisabled(true) }
        await gate.waitUntilArrived()
        let quit = Task { await model.allowSleepBeforeQuitting() }
        await letQueuedWorkRun()
        #expect(system.withState(\.writes) == 0)

        await gate.open()
        await toggle.value
        await quit.value

        #expect(system.withState(\.writes) == 2)
        #expect(system.withState(\.isSleepDisabled) == false)
    }

    @Test func theQuitResetIsTriedEvenWhenTheModelThinksSleepIsAllowed() async {
        let system = FakeSystem(sleepDisabled: true, authorized: true)
        let model = makeModel(system)
        #expect(!model.isSleepDisabled)

        await model.allowSleepBeforeQuitting()

        #expect(system.withState(\.writes) == 1)
        #expect(system.withState(\.isSleepDisabled) == false)
    }

    @Test func nothingRunsAfterQuitting() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        await model.allowSleepBeforeQuitting()
        let reads = system.withState(\.sleepReads)

        await model.setSleepDisabled(true)
        await model.installAuthorization()
        await model.setLaunchAtLogin(true)
        await model.refresh()
        await model.refreshPeriodically()

        #expect(system.withState(\.writes) == 1)
        #expect(system.withState(\.installs) == 0)
        #expect(system.withState(\.sleepReads) == reads)
        #expect(!system.withState(\.isSleepDisabled))
        #expect(!model.isBusy)
    }

    @Test func aSecondQuitWaitsForTheSameReset() async {
        let system = FakeSystem(authorized: true)
        let model = makeModel(system)
        let gate = Gate()
        system.withState { $0.writeGate = gate }

        let first = Task { await model.allowSleepBeforeQuitting() }
        await gate.waitUntilArrived()
        let second = Task { await model.allowSleepBeforeQuitting() }
        await gate.open()
        await first.value
        await second.value

        #expect(system.withState(\.writes) == 1)
    }

    @Test(arguments: [true, false])
    func aFailedQuitResetStillReturns(authorized: Bool) async {
        let system = FakeSystem(sleepDisabled: true, authorized: authorized)
        system.withState { $0.writeFailure = authorized ? CommandRunnerError.sudoLaunchFailed : nil }
        let model = makeModel(system)

        await model.allowSleepBeforeQuitting()

        #expect(system.withState(\.writes) == 1)
        #expect(model.error == nil)
    }

    // MARK: Errors

    @Test func cancellingThePasswordDialogTranslatesToNoError() {
        #expect(AppModelError(AuthorizationError.cancelledByUser) == nil)
        #expect(AppModelError(AuthorizationError.scriptFailed(exitCode: 3, message: "x"))
            == .authorizationScriptFailed(exitCode: 3, message: "x"))
        #expect(AppModelError(CommandRunnerError.sudoLaunchFailed) == .commandLaunch(.sudoLaunchFailed))
    }

    // MARK: Launch at login

    @Test func launchAtLoginFollowsTheSystemStatus() async {
        let loginItem = FakeLaunchAtLogin()
        let model = makeModel(FakeSystem(), launchAtLogin: loginItem)
        #expect(model.launchAtLogin == .disabled)

        await model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .enabled)
        #expect(model.error == nil)

        await model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin == .disabled)
    }

    @Test func aFailedLoginRegistrationShowsTheErrorAndKeepsTheSystemStatus() async {
        struct Refused: LocalizedError { var errorDescription: String? { "refused" } }
        let loginItem = FakeLaunchAtLogin()
        loginItem.failNextChange(with: Refused())
        let model = makeModel(FakeSystem(), launchAtLogin: loginItem)

        await model.setLaunchAtLogin(true)

        #expect(model.launchAtLogin == .disabled)
        #expect(model.error == .launchAtLogin(message: "refused"))
    }

    @Test(arguments: [
        (LaunchAtLoginStatus.enabled, true),
        (.requiresApproval, true),
        (.disabled, false),
        (.unavailable, false),
    ])
    func theLaunchAtLoginBoxIsCheckedWhenRegistered(status: LaunchAtLoginStatus, checked: Bool) {
        #expect(status.isRegistered == checked)
    }
}

// MARK: Claude sessions

@MainActor
struct ClaudeSessionsModelTests {
    @Test func theCountsAreEmptyBeforeTheFirstReading() {
        #expect(makeModel().claudeSessions == .none)
    }

    @Test func refreshPublishesTheCountsWithSleepAllowedAndTheGuardOff() async {
        let counts = ClaudeSessionCounts(working: 2, waiting: 1)
        let claude = FakeClaudeSessionReader(counts: counts)
        let model = makeModel(FakeSystem(sleepDisabled: false), claudeSessions: claude, claudeGuardEnabled: false)

        await model.refresh()

        #expect(model.claudeSessions == counts)

        claude.counts = ClaudeSessionCounts.none
        await model.refresh()

        #expect(model.claudeSessions == ClaudeSessionCounts.none)
    }

    @Test func aRefreshWithTheSameCountsDoesNotNotify() async {
        let claude = FakeClaudeSessionReader(counts: ClaudeSessionCounts(working: 1))
        let model = makeModel(FakeSystem(sleepDisabled: false), claudeSessions: claude)
        await model.refresh()

        let changed = flagChanges { _ = model.claudeSessions }
        await model.refresh()

        #expect(!changed.isRaised)
    }
}
