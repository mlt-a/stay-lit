import Foundation
@testable import StayLitCore

/// A pretend Mac: one sleep setting and one sudoers rule, behind the protocols the model uses.
/// Writes need the rule, as with the real `sudo -n`. Never runs a command.
final class FakeSystem: SleepControlling, SudoersAuthorizing, @unchecked Sendable {
    struct State {
        var isSleepDisabled = false
        var isAuthorized = false
        /// Fails the next calls of that kind instead of changing anything.
        var writeFailure: (any Error)?
        var readFailure: (any Error)?
        var installFailure: (any Error)?
        /// The install script succeeds, but sudo ignores the rule.
        var installSucceedsWithoutAuthorizing = false
        /// Fails the removal before it changes anything (the dialog was cancelled).
        var removeFailure: (any Error)?
        /// Fails the removal after it removed the rule, as the real script does when `pmset` fails.
        var removeFailureAfterRemovingRule: (any Error)?
        var statusFailure: (any Error)?
        /// Holds the next sleep read, after it read the state: what it returns is then stale.
        var readGate: Gate?
        /// Holds the next write, before it changes anything.
        var writeGate: Gate?
        var sleepReads = 0
        var statusReads = 0
        var writes = 0
        var installs = 0
        var removals = 0
    }

    private let lock = NSLock()
    private var state: State

    init(sleepDisabled: Bool = false, authorized: Bool = false) {
        state = State(isSleepDisabled: sleepDisabled, isAuthorized: authorized)
    }

    /// Changes the pretend Mac, or reads it.
    func withState<T>(_ body: (inout State) -> T) -> T {
        lock.withLock { body(&state) }
    }

    var ruleText: String { "fake rule\n" }

    func isSleepDisabled() async throws -> Bool {
        let (reading, gate) = lock.withLock {
            state.sleepReads += 1
            defer { state.readGate = nil }
            let reading: Result<Bool, any Error> = state.readFailure.map { .failure($0) } ?? .success(state.isSleepDisabled)
            return (reading, state.readGate)
        }
        await gate?.pass()
        return try reading.get()
    }

    func setSleepDisabled(_ disabled: Bool) async throws -> Bool {
        let gate = lock.withLock {
            defer { state.writeGate = nil }
            return state.writeGate
        }
        await gate?.pass()
        return try lock.withLock {
            state.writes += 1
            if let failure = state.writeFailure { throw failure }
            guard state.isAuthorized else { throw SleepControlError.authorizationMissing }
            state.isSleepDisabled = disabled
            return state.isSleepDisabled
        }
    }

    func status() async throws -> AuthorizationStatus {
        try lock.withLock {
            state.statusReads += 1
            if let failure = state.statusFailure { throw failure }
            return state.isAuthorized ? .authorized : .notAuthorized
        }
    }

    func install() async throws {
        try lock.withLock {
            state.installs += 1
            if let failure = state.installFailure { throw failure }
            if !state.installSucceedsWithoutAuthorizing { state.isAuthorized = true }
        }
    }

    func remove() async throws {
        try lock.withLock {
            state.removals += 1
            if let failure = state.removeFailure { throw failure }
            if let failure = state.removeFailureAfterRemovingRule {
                state.isAuthorized = false
                throw failure
            }
            state.isSleepDisabled = false
            state.isAuthorized = false
        }
    }
}

final class FakeLaunchAtLogin: LaunchAtLoginControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var current = LaunchAtLoginStatus.disabled
    private var failure: (any Error)?
    private var reads = 0

    var status: LaunchAtLoginStatus {
        lock.withLock {
            reads += 1
            return current
        }
    }

    /// How many times `status` was read.
    var statusReads: Int { lock.withLock { reads } }

    func failNextChange(with error: any Error) {
        lock.withLock { failure = error }
    }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            if let failure { throw failure }
            current = enabled ? .enabled : .disabled
        }
    }
}
