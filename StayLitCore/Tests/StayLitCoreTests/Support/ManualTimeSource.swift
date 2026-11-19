import Foundation
@testable import StayLitCore

/// A clock the test moves by hand: `sleep` returns only when `advance` reaches its wake time.
final class ManualTimeSource: TimeSource, @unchecked Sendable {
    private struct Sleeper {
        var wakeTime: Date
        var continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current: Date
    private var sleepers: [UUID: Sleeper] = [:]
    private var watchers: [CheckedContinuation<Void, Never>] = []

    init(start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    /// How many waits are pending.
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                register(continuation, id: id, duration: duration)
            }
        } onCancel: {
            cancelSleeper(id)
        }
    }

    private func register(_ continuation: CheckedContinuation<Void, any Error>, id: UUID, duration: Duration) {
        var toWake: [CheckedContinuation<Void, Never>] = []
        var cancelled = false
        lock.withLock {
            // The cancellation handler may have run before this point.
            if Task.isCancelled {
                cancelled = true
            } else {
                sleepers[id] = Sleeper(wakeTime: current.addingTimeInterval(duration / .seconds(1)), continuation: continuation)
                toWake = watchers
                watchers.removeAll()
            }
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
        toWake.forEach { $0.resume() }
    }

    private func cancelSleeper(_ id: UUID) {
        let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
        sleeper?.continuation.resume(throwing: CancellationError())
    }

    /// Returns once at least one wait is pending.
    func waitForSleeper() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if sleepers.isEmpty { watchers.append(continuation) }
                return !sleepers.isEmpty
            }
            if ready { continuation.resume() }
        }
    }

    /// Moves time forward and wakes every wait that is due.
    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            current = current.addingTimeInterval(duration / .seconds(1))
            let dueIDs = sleepers.filter { $0.value.wakeTime <= current }.keys
            return dueIDs.compactMap { sleepers.removeValue(forKey: $0) }
        }
        due.forEach { $0.continuation.resume() }
    }
}
