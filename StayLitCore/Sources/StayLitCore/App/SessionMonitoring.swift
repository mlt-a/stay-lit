/// Tells when the Mac goes to sleep and when the user is back after it. The app target composes
/// the real implementation, tests use a double.
@MainActor
public protocol SessionMonitoring {
    /// A new stream each call: it yields every event until the consumer stops.
    func events() -> AsyncStream<SessionEvent>
}

public enum SessionEvent: Sendable {
    /// The system is about to sleep.
    case sleeping
    /// The user is back after a wake: the first unlock after it, or the wake itself when the
    /// screen is not locked.
    case resumed
}
