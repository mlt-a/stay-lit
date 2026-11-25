@testable import StayLitCore

/// The Mac going to sleep and the user coming back, when the test says so: `send` tells every
/// subscriber.
@MainActor
final class FakeSessionMonitor: SessionMonitoring {
    private var continuations: [AsyncStream<SessionEvent>.Continuation] = []

    func events() -> AsyncStream<SessionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        continuations.append(continuation)
        return stream
    }

    func send(_ event: SessionEvent) {
        continuations.forEach { $0.yield(event) }
    }
}
