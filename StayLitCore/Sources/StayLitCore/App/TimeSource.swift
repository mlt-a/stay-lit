import Foundation

/// The model's view of time: the date to compute a deadline from, and the wait until it.
/// Injected so tests move time by hand instead of waiting.
public protocol TimeSource: Sendable {
    var now: Date { get }
    /// Returns after `duration`. Throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// The real time. Its wait keeps counting while the Mac sleeps, which is harmless here:
/// the timer only runs while sleep is blocked.
public struct SystemTimeSource: TimeSource {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
