import Observation
import Synchronization
@testable import StayLitCore

/// Lets queued work run until `condition` holds. The fakes only suspend at gates, so yielding is
/// enough: no real time passes.
@MainActor
func settle(until condition: () -> Bool) async {
    for _ in 0..<1000 {
        if condition() { return }
        await Task.yield()
    }
}

/// Lets queued work run, for a test that checks something did not happen.
@MainActor
func letQueuedWorkRun() async {
    for _ in 0..<100 { await Task.yield() }
}

extension AppModel {
    /// Starts watching and waits for the first reading to end. The authorization is set before
    /// the Claude sessions are read, so waiting for it is not enough: `refresh()` is queued behind
    /// the first reading and returns once it has ended.
    func startAndAwaitFirstReading() async {
        startMonitoring()
        await refresh()
    }
}

/// Set once, from any thread: observation callbacks are `@Sendable`.
final class Flag: Sendable {
    private let value = Atomic(false)

    var isRaised: Bool { value.load(ordering: .relaxed) }

    func raise() { value.store(true, ordering: .relaxed) }
}

/// Raises the returned flag when anything `read` touches changes.
@MainActor
func flagChanges(of read: () -> Void) -> Flag {
    let changed = Flag()
    withObservationTracking(read) { changed.raise() }
    return changed
}
