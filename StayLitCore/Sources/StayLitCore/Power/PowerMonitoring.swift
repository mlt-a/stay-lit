/// Watches the battery. The model reads it on the main actor; the app target composes the
/// real implementation, tests use a double.
@MainActor
public protocol PowerMonitoring {
    /// Read from the system every time. `nil` when the Mac has no battery.
    var state: PowerState? { get }

    /// A new stream each call: it yields the state after every change until the consumer stops.
    /// Subscribe before reading `state`, so no change falls between the two.
    func changes() -> AsyncStream<PowerState?>
}
