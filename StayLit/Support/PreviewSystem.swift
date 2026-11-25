#if DEBUG
import StayLitCore
import Synchronization
import SwiftUI

/// The window states shown by previews and by the `-demo <state>` launch argument, for
/// screenshots. Nothing in them runs a command.
enum DemoState: String, CaseIterable {
    /// Sleep allowed, no session.
    case asleep
    /// Sleep allowed, two sessions working.
    case asleepAgents
    /// Sleep blocked until turned off, no session.
    case lit
    /// Sleep blocked for 2 hours, three sessions working and one waiting.
    case litAgents
    /// The sudoers rule is missing.
    case unauthorized
    /// Sleep allowed after a lid-closed run that the battery guard ended at 18%.
    case report
    /// On battery at 15%: the battery guard keeps sleep allowed.
    case blockedBattery
    /// The Mac is too hot: the temperature guard keeps sleep allowed.
    case tooHot

    /// The state named by `-demo <state>`, if any.
    static var launchArgument: DemoState? {
        UserDefaults.standard.string(forKey: "demo").flatMap(DemoState.init(rawValue:))
    }
}

/// A Mac made of doubles, set in one `DemoState`. Sleep follows what the window asks, so the
/// switch still works; everything else changes only here.
final class DemoMac {
    let model: AppModel
    private let state: DemoState
    private let system: DemoSystem
    private let power: DemoPower

    init(_ state: DemoState) {
        self.state = state
        let sessions = switch state {
        case .asleepAgents: ClaudeSessionCounts(working: 2)
        case .litAgents: ClaudeSessionCounts(working: 3, waiting: 1)
        default: ClaudeSessionCounts.none
        }
        let system = DemoSystem(
            sleepDisabled: [.lit, .litAgents, .report].contains(state),
            authorized: state != .unauthorized,
            sessions: sessions,
            lidClosed: state == .report
        )
        let power = DemoPower(
            state: state == .blockedBattery
                ? PowerState(isOnBattery: true, percent: 15)
                : PowerState(isOnBattery: true, percent: 64)
        )
        self.system = system
        self.power = power
        model = AppModel(
            sleepController: system,
            authorizer: system,
            launchAtLogin: system,
            powerMonitor: power,
            thermalMonitor: DemoThermal(state: state == .tooHot ? .serious : .nominal),
            sessionMonitor: DemoSessionMonitor(),
            claudeSessions: system,
            lid: system,
            systemSleeper: system,
            screenLocker: system,
            notifier: system,
            isBatteryGuardEnabled: true,
            onBatteryGuardChange: { _ in },
            isTemperatureGuardEnabled: true,
            onTemperatureGuardChange: { _ in },
            isClaudeGuardEnabled: state == .litAgents || state == .asleepAgents,
            onClaudeGuardChange: { _ in },
            blockDuration: .untilTurnedOff,
            onBlockDurationChange: { _ in },
            timeSource: system
        )
    }

    /// Brings the model to the state, through its public actions only.
    func prepare() async {
        await model.refresh()
        switch state {
        case .litAgents:
            model.setBlockDuration(.twoHours)
        case .report:
            await runWithTheLidClosed(for: .seconds(5_400))
        case .asleep, .asleepAgents, .lit, .unauthorized, .blockedBattery, .tooHot:
            break
        }
    }

    /// Readings closer than the tracker's sleep gap, then the battery drops to 18% and the guard
    /// ends the run. The charger comes back afterwards, so only the report tells the story.
    private func runWithTheLidClosed(for duration: Duration) async {
        let step = Duration.seconds(LidClosedRunTracker.sleepGap / 2)
        var elapsed = Duration.zero
        while elapsed < duration {
            elapsed += step
            system.advanceClock(by: step)
            await model.refresh()
        }
        power.state = PowerState(isOnBattery: true, percent: 18)
        await model.refresh()
        power.state = PowerState(isOnBattery: false, percent: 18)
        system.openLid()
        system.resetClock()
        await model.refresh()
    }
}

/// Sleep, the rule, the login item, the sessions, the lid, the clock and the side effects.
/// Shared with the model's tasks, hence the lock.
private nonisolated final class DemoSystem: SleepControlling, SudoersAuthorizing, LaunchAtLoginControlling,
    ClaudeSessionReading, LidReading, SystemSleeping, ScreenLocking, TimeSource, SleepRestoreNotifying {
    private struct State {
        var sleepDisabled: Bool
        var authorized: Bool
        var sessions: ClaudeSessionCounts
        var lidClosed: Bool
        /// How far the demo clock runs ahead of the real one.
        var clockOffset: Duration = .zero
    }

    private let state: Mutex<State>

    init(sleepDisabled: Bool, authorized: Bool, sessions: ClaudeSessionCounts, lidClosed: Bool) {
        state = Mutex(State(sleepDisabled: sleepDisabled, authorized: authorized, sessions: sessions, lidClosed: lidClosed))
    }

    func advanceClock(by duration: Duration) { state.withLock { $0.clockOffset += duration } }
    func resetClock() { state.withLock { $0.clockOffset = .zero } }
    func openLid() { state.withLock { $0.lidClosed = false } }

    var ruleText: String { SudoersRule.text(forUserID: 501) }
    var status: LaunchAtLoginStatus { .disabled }
    var now: Date {
        let offset = state.withLock { $0.clockOffset }
        return Date.now.addingTimeInterval(TimeInterval(offset.components.seconds))
    }

    func isSleepDisabled() async throws -> Bool { state.withLock { $0.sleepDisabled } }
    func setSleepDisabled(_ disabled: Bool) async throws -> Bool {
        state.withLock { $0.sleepDisabled = disabled }
        return disabled
    }
    func status() async throws -> AuthorizationStatus {
        state.withLock { $0.authorized } ? .authorized : .notAuthorized
    }
    func install() async throws { state.withLock { $0.authorized = true } }
    func remove() async throws {
        state.withLock {
            $0.authorized = false
            $0.sleepDisabled = false
        }
    }
    func setEnabled(_ enabled: Bool) throws {}
    func sessions() async -> ClaudeSessionCounts { state.withLock { $0.sessions } }
    func isLidClosed() -> Bool { state.withLock { $0.lidClosed } }
    func sleepNow() async throws {}
    func lockScreen() throws {}
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
    func notifySleepRestored(_ reason: RestoreReason) {}
}

/// The battery, set by `DemoMac`. Events never come: the model reads it at each refresh.
private final class DemoPower: PowerMonitoring {
    var state: PowerState?

    init(state: PowerState?) {
        self.state = state
    }

    func changes() -> AsyncStream<PowerState?> { AsyncStream { _ in } }
}

/// A fixed thermal state. Apart from `DemoPower`: both protocols name their reading `state`,
/// with different types.
private struct DemoThermal: ThermalMonitoring {
    let state: ProcessInfo.ThermalState

    func changes() -> AsyncStream<ProcessInfo.ThermalState> { AsyncStream { _ in } }
}

/// The demo Mac never sleeps, so the user never comes back.
private struct DemoSessionMonitor: SessionMonitoring {
    func events() -> AsyncStream<SessionEvent> { AsyncStream { _ in } }
}

/// The status window in one demo state.
struct DemoStatusView: View {
    @State private var mac: DemoMac

    init(_ state: DemoState) {
        _mac = State(initialValue: DemoMac(state))
    }

    var body: some View {
        StatusView(model: mac.model)
            .task { await mac.prepare() }
    }
}

#Preview("Asleep") { DemoStatusView(.asleep) }
#Preview("Asleep, agents working") { DemoStatusView(.asleepAgents) }
#Preview("Lit") { DemoStatusView(.lit) }
#Preview("Lit, agents working") { DemoStatusView(.litAgents) }
#Preview("Not authorized") { DemoStatusView(.unauthorized) }
#Preview("Lid closed report") { DemoStatusView(.report) }
#Preview("Low battery") { DemoStatusView(.blockedBattery) }
#Preview("Too hot") { DemoStatusView(.tooHot) }
#endif
