import Foundation
@testable import StayLitCore

/// A thermal state the test drives by hand: `send` changes the state and tells every subscriber,
/// `changeWithoutEvent` changes it alone, as when the system misses an event.
@MainActor
final class FakeThermalMonitor: ThermalMonitoring {
    private(set) var state: ProcessInfo.ThermalState
    private var continuations: [AsyncStream<ProcessInfo.ThermalState>.Continuation] = []
    private let streamEnds: Bool

    /// `streamEnds`: every stream finishes at once, as when the system gives no event source.
    init(_ state: ProcessInfo.ThermalState = .nominal, streamEnds: Bool = false) {
        self.state = state
        self.streamEnds = streamEnds
    }

    func changes() -> AsyncStream<ProcessInfo.ThermalState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ProcessInfo.ThermalState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        if streamEnds {
            continuation.finish()
        } else {
            continuations.append(continuation)
        }
        return stream
    }

    func changeWithoutEvent(_ state: ProcessInfo.ThermalState) {
        self.state = state
    }

    func send(_ state: ProcessInfo.ThermalState) {
        self.state = state
        continuations.forEach { $0.yield(state) }
    }
}
