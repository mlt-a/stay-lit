import Foundation

/// Reads the thermal state from `ProcessInfo` and listens to its change notification.
@MainActor
public final class ProcessInfoThermalMonitor: ThermalMonitoring {
    public init() {}

    public var state: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }

    public func changes() -> AsyncStream<ProcessInfo.ThermalState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ProcessInfo.ThermalState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        // No queue: the block runs on the posting thread, not the main thread. It only reads
        // `ProcessInfo` and yields, and both are safe from any thread.
        let observer = ObserverToken(
            NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(ProcessInfo.processInfo.thermalState)
            }
        )
        // The consumer stopped (its task ended or was cancelled): stop observing.
        continuation.onTermination = { _ in
            NotificationCenter.default.removeObserver(observer.value)
        }
        return stream
    }
}

/// `addObserver` returns a token that is not `Sendable`, but `removeObserver` accepts it
/// from any thread, and the termination handler is the only place that touches it.
private final class ObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}
