import Foundation

/// Watches the thermal state of the Mac. The model reads it on the main actor; the app target
/// composes the real implementation, tests use a double.
@MainActor
public protocol ThermalMonitoring {
    /// Read from the system every time.
    var state: ProcessInfo.ThermalState { get }

    /// A new stream each call: it yields the state after every change until the consumer stops.
    /// Subscribe before reading `state`, so no change falls between the two.
    func changes() -> AsyncStream<ProcessInfo.ThermalState>
}
