import Foundation
import Observation

/// Waits until a deadline, then calls back once. Memory only: nothing survives a relaunch.
/// The callback decides what the deadline means; the timer only keeps time.
@MainActor
@Observable
final class RestoreTimer {
    /// When the callback runs. `nil` when nothing is armed.
    private(set) var deadline: Date?

    @ObservationIgnored private let timeSource: any TimeSource
    @ObservationIgnored private var task: Task<Void, Never>?

    init(timeSource: any TimeSource) {
        self.timeSource = timeSource
    }

    /// Replaces the running timer with one that ends `interval` from now and then calls
    /// `onDeadline` with its deadline. A `nil` interval only stops the running one.
    func arm(for interval: Duration?, onDeadline: @escaping @MainActor (Date) async -> Void) {
        disarm()
        guard let interval else { return }
        let deadline = timeSource.now.addingTimeInterval(interval / .seconds(1))
        self.deadline = deadline
        task = Task { [weak self, timeSource] in
            do {
                try await timeSource.sleep(for: interval)
                // A wait that ended just before `disarm` returns normally: cancelled means stopped.
                try Task.checkCancellation()
            } catch { return }
            await onDeadline(deadline)
            // The deadline passed, whatever came of it: it must not stay on screen. Re-armed
            // while the callback ran, the new deadline stays.
            guard let self, self.deadline == deadline else { return }
            self.deadline = nil
            self.task = nil
        }
    }

    /// The task holds the timer weakly: without this, a dropped timer would still call back.
    isolated deinit {
        task?.cancel()
    }

    func disarm() {
        task?.cancel()
        task = nil
        if deadline != nil { deadline = nil }
    }
}
